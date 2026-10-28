#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'SonarQube new-code sensor failed: %s\n' "$*" >&2
  exit 1
}

for variable in SONAR_HOST_URL SONAR_TOKEN SONAR_PROJECT_KEY; do
  [[ -n ${!variable:-} ]] || fail "Set $variable."
done

if [[ -n ${SONAR_PULL_REQUEST_KEY:-} || -n ${SONAR_PULL_REQUEST_BRANCH:-} || -n ${SONAR_PULL_REQUEST_BASE:-} ]]; then
  [[ -n ${SONAR_PULL_REQUEST_KEY:-} && -n ${SONAR_PULL_REQUEST_BRANCH:-} && -n ${SONAR_PULL_REQUEST_BASE:-} ]] \
    || fail 'Pull-request analysis requires SONAR_PULL_REQUEST_KEY, SONAR_PULL_REQUEST_BRANCH, and SONAR_PULL_REQUEST_BASE.'
  sonar_context=(
    "-Dsonar.pullrequest.key=$SONAR_PULL_REQUEST_KEY"
    "-Dsonar.pullrequest.branch=$SONAR_PULL_REQUEST_BRANCH"
    "-Dsonar.pullrequest.base=$SONAR_PULL_REQUEST_BASE"
  )
  context_parameter=pullRequest
  context_value=$SONAR_PULL_REQUEST_KEY
elif [[ -n ${SONAR_BRANCH_NAME:-} ]]; then
  sonar_context=("-Dsonar.branch.name=$SONAR_BRANCH_NAME")
  context_parameter=branch
  context_value=$SONAR_BRANCH_NAME
else
  git_branch=$(git branch --show-current 2>/dev/null || true)
  [[ -n $git_branch ]] || fail 'Set a pull-request tuple or SONAR_BRANCH_NAME; no current Git branch is available.'
  sonar_context=("-Dsonar.branch.name=$git_branch")
  context_parameter=branch
  context_value=$git_branch
fi

if [[ -x ./mvnw ]]; then
  maven=(./mvnw)
else
  command -v mvn >/dev/null 2>&1 || fail 'Neither ./mvnw nor mvn is available.'
  maven=(mvn)
fi

# A unique metadata file prevents a previous scan from masking scanner failures.
scan_directory=$(mktemp -d "${TMPDIR:-/tmp}/sonar-new-code-scan.XXXXXX")
trap 'rm -rf "$scan_directory"' EXIT
scan_metadata="$scan_directory/report-task.txt"
scanner_status=0
"${maven[@]}" org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
  "-Dsonar.host.url=$SONAR_HOST_URL" \
  "-Dsonar.projectKey=$SONAR_PROJECT_KEY" \
  -Dsonar.qualitygate.wait=true \
  "-Dsonar.scanner.metadataFilePath=$scan_metadata" \
  "${sonar_context[@]}" || scanner_status=$?

if (( scanner_status != 0 )) && [[ ! -s $scan_metadata ]]; then
  exit "$scanner_status"
fi

command -v curl >/dev/null 2>&1 || fail 'curl is required to read SonarQube results.'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required to format SonarQube results.'

encode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

sonar_url=${SONAR_HOST_URL%/}
project_key=$(encode "$SONAR_PROJECT_KEY")
encoded_context=$(encode "$context_value")
# Read the header from stdin so the token is absent from curl's process arguments.
sonar_get() {
  curl --fail-with-body --silent --show-error --header @- "$1" \
    <<< "Authorization: Bearer $SONAR_TOKEN"
}

# Resolve the submitted analysis on every run, including successful scans.
# Project/context gate queries could return a concurrent scan's result.
result_status=$scanner_status
(( result_status != 0 )) || result_status=1
[[ -s $scan_metadata ]] || {
  printf 'SonarQube new-code sensor failed: Scanner metadata was not returned.\n' >&2
  exit "$result_status"
}
task_id=$(sed -n 's/^ceTaskId=//p' "$scan_metadata")
[[ -n $task_id ]] || exit "$result_status"
task=$(sonar_get "$sonar_url/api/ce/task?id=$(encode "$task_id")") || exit "$result_status"
analysis_id=$(python3 -c '
import json, sys
task = json.loads(sys.argv[1]).get("task", {})
if task.get("status") != "SUCCESS" or not task.get("analysisId"):
    raise SystemExit(1)
print(task["analysisId"])
' "$task") || exit "$result_status"
gate_query="analysisId=$(encode "$analysis_id")"

quality_gate=$(sonar_get "$sonar_url/api/qualitygates/project_status?$gate_query")
if (( scanner_status != 0 )); then
  # Only a failed gate explains a scanner failure that may still be reported.
  python3 -c 'import json, sys; sys.exit(json.loads(sys.argv[1]).get("projectStatus", {}).get("status") != "ERROR")' \
    "$quality_gate" || exit "$scanner_status"
fi
measures=$(sonar_get "$sonar_url/api/measures/component?component=$project_key&metricKeys=new_coverage%2Cnew_bugs%2Cnew_vulnerabilities%2Cnew_code_smells%2Cnew_security_hotspots%2Cnew_duplicated_lines_density&$context_parameter=$encoded_context")

python3 - "$quality_gate" "$measures" <<'PY'
import json
import sys

quality_gate = json.loads(sys.argv[1])
measures_payload = json.loads(sys.argv[2])
status = quality_gate.get("projectStatus", {}).get("status")
if not status:
    raise SystemExit("SonarQube new-code sensor failed: Quality Gate status was not returned.")

def measure_value(item):
    value = (item.get("period") or {}).get("value")
    if value is None:
        value = next((period["value"] for period in item.get("periods", [])
                      if period.get("index", 1) == 1 and period.get("value") is not None), None)
    return item.get("value") if value is None else value

measure_values = {
    item["metric"]: measure_value(item)
    for item in measures_payload.get("component", {}).get("measures", [])
}

def percent(metric):
    value = measure_values.get(metric)
    return "N/A" if value is None else f"{float(value):.2f}%"

def count(metric):
    value = measure_values.get(metric)
    return "N/A" if value is None else str(int(float(value)))

print(f"SonarQube Quality Gate: {status}")
print(f"New-code coverage: {percent('new_coverage')}")
print(f"New bugs: {count('new_bugs')}")
print(f"New vulnerabilities: {count('new_vulnerabilities')}")
print(f"New code smells: {count('new_code_smells')}")
print(f"New security hotspots: {count('new_security_hotspots')}")
print(f"New duplicated-lines density: {percent('new_duplicated_lines_density')}")
if status != "OK":
    raise SystemExit(1)
PY
