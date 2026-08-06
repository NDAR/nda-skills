#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'SonarQube new-code sensor failed: %s\n' "$*" >&2
  exit 1
}

for variable in SONAR_HOST_URL SONAR_TOKEN SONAR_PROJECT_KEY; do
  [[ -n ${!variable:-} ]] || fail "Set $variable."
done

if [[ -n ${SONAR_PULL_REQUEST_KEY:-} ]]; then
  [[ -n ${SONAR_PULL_REQUEST_BRANCH:-} && -n ${SONAR_PULL_REQUEST_BASE:-} ]] \
    || fail 'SONAR_PULL_REQUEST_KEY requires SONAR_PULL_REQUEST_BRANCH and SONAR_PULL_REQUEST_BASE.'
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

"${maven[@]}" org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
  "-Dsonar.host.url=$SONAR_HOST_URL" \
  "-Dsonar.projectKey=$SONAR_PROJECT_KEY" \
  -Dsonar.qualitygate.wait=true \
  "${sonar_context[@]}"

command -v curl >/dev/null 2>&1 || fail 'curl is required to read SonarQube results.'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required to format SonarQube results.'

encode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

sonar_url=${SONAR_HOST_URL%/}
project_key=$(encode "$SONAR_PROJECT_KEY")
encoded_context=$(encode "$context_value")
authorization=(--header "Authorization: Bearer $SONAR_TOKEN")

quality_gate=$(curl --fail-with-body --silent --show-error "${authorization[@]}" \
  "$sonar_url/api/qualitygates/project_status?projectKey=$project_key&$context_parameter=$encoded_context")
measures=$(curl --fail-with-body --silent --show-error "${authorization[@]}" \
  "$sonar_url/api/measures/component?component=$project_key&metricKeys=new_coverage%2Cnew_bugs%2Cnew_vulnerabilities%2Cnew_code_smells%2Cnew_security_hotspots%2Cnew_duplicated_lines_density&$context_parameter=$encoded_context")

python3 - "$quality_gate" "$measures" <<'PY'
import json
import sys

quality_gate = json.loads(sys.argv[1])
measures_payload = json.loads(sys.argv[2])
status = quality_gate.get("projectStatus", {}).get("status")
if not status:
    raise SystemExit("SonarQube new-code sensor failed: Quality Gate status was not returned.")

measure_values = {
    item["metric"]: item.get("value", "0")
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
