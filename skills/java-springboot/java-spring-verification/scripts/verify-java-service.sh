#!/usr/bin/env bash
set -euo pipefail

coverage_minimum=${COVERAGE_MINIMUM:-80}
sonar_required=${SONAR_REQUIRED:-false}
sonar_timeout=${SONAR_QUALITY_GATE_TIMEOUT:-300}

fail() {
  printf 'Verification failed: %s\n' "$*" >&2
  exit 1
}

if [[ -x ./mvnw ]]; then
  maven=(./mvnw)
else
  command -v mvn >/dev/null 2>&1 || fail 'Neither ./mvnw nor mvn is available.'
  maven=(mvn)
fi

printf 'Running Maven verification: %s clean verify\n' "${maven[*]}"
"${maven[@]}" clean verify

command -v python3 >/dev/null 2>&1 || fail 'python3 is required to read JaCoCo and SonarQube reports.'
jacoco_reports=()
while IFS= read -r report; do
  jacoco_reports+=("$report")
done < <(find . -type f -path '*/target/site/jacoco/jacoco.xml' -print | sort)
(( ${#jacoco_reports[@]} > 0 )) || fail 'No JaCoCo XML report found under */target/site/jacoco/jacoco.xml.'

python3 - "$coverage_minimum" "${jacoco_reports[@]}" <<'PY'
import math
import sys
import xml.etree.ElementTree as ET

minimum = float(sys.argv[1])
if not math.isfinite(minimum) or minimum < 80:
    raise SystemExit("Verification failed: COVERAGE_MINIMUM must be a finite value of at least 80.")
covered = missed = 0
for path in sys.argv[2:]:
    for counter in ET.parse(path).getroot().findall("counter"):
        if counter.attrib.get("type") == "LINE":
            covered += int(counter.attrib["covered"])
            missed += int(counter.attrib["missed"])

total = covered + missed
if total == 0:
    raise SystemExit("Verification failed: JaCoCo reports contain no executable line coverage.")
coverage = covered * 100 / total
print(f"JaCoCo line coverage: {coverage:.2f}% ({covered}/{total} lines); required: {minimum:.2f}%")
if coverage < minimum:
    raise SystemExit(1)
PY

sonar_values=("${SONAR_HOST_URL:-}" "${SONAR_TOKEN:-}" "${SONAR_PROJECT_KEY:-}")
configured=0
for value in "${sonar_values[@]}"; do
  if [[ -n "$value" ]]; then
    ((configured += 1))
  fi
done
if (( configured != 0 && configured != 3 )); then
  fail 'Set all of SONAR_HOST_URL, SONAR_TOKEN, and SONAR_PROJECT_KEY, or set none of them.'
fi
if (( configured == 0 )); then
  [[ "$sonar_required" != true ]] || fail 'SonarQube is required but SONAR_HOST_URL, SONAR_TOKEN, and SONAR_PROJECT_KEY are not all set.'
  printf 'SonarQube verification skipped: connection variables are not configured.\n'
  exit 0
fi

if [[ -n ${SONAR_PULL_REQUEST_KEY:-} ]]; then
  [[ -n ${SONAR_PULL_REQUEST_BRANCH:-} && -n ${SONAR_PULL_REQUEST_BASE:-} ]] \
    || fail 'SONAR_PULL_REQUEST_KEY requires SONAR_PULL_REQUEST_BRANCH and SONAR_PULL_REQUEST_BASE.'
  sonar_context=(
    "-Dsonar.pullrequest.key=$SONAR_PULL_REQUEST_KEY"
    "-Dsonar.pullrequest.branch=$SONAR_PULL_REQUEST_BRANCH"
    "-Dsonar.pullrequest.base=$SONAR_PULL_REQUEST_BASE"
  )
  sonar_query="pullRequest=$SONAR_PULL_REQUEST_KEY"
elif [[ -n ${SONAR_BRANCH_NAME:-} ]]; then
  sonar_context=("-Dsonar.branch.name=$SONAR_BRANCH_NAME")
  sonar_query="branch=$SONAR_BRANCH_NAME"
else
  sonar_context=()
  sonar_query=''
fi

printf 'Running SonarQube analysis and waiting for the Quality Gate.\n'
sonar_command=(
  org.sonarsource.scanner.maven:sonar-maven-plugin:sonar
  "-Dsonar.host.url=$SONAR_HOST_URL"
  "-Dsonar.projectKey=$SONAR_PROJECT_KEY"
  -Dsonar.qualitygate.wait=true
  "-Dsonar.qualitygate.timeout=$sonar_timeout"
)
if (( ${#sonar_context[@]} > 0 )); then
  sonar_command+=("${sonar_context[@]}")
fi
"${maven[@]}" "${sonar_command[@]}"

command -v curl >/dev/null 2>&1 || fail 'curl is required to read SonarQube measures.'
sonar_url=${SONAR_HOST_URL%/}
encoded_project_key=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$SONAR_PROJECT_KEY")
encoded_context=''
if [[ -n "$sonar_query" ]]; then
  context_name=${sonar_query%%=*}
  context_value=${sonar_query#*=}
  encoded_context="&$context_name=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$context_value")"
fi

measures=$(curl --fail-with-body --silent --show-error \
  --header "Authorization: Bearer $SONAR_TOKEN" \
  "$sonar_url/api/measures/component?component=$encoded_project_key&metricKeys=new_coverage%2Cnew_bugs$encoded_context")

python3 -c '
import json
import math
import sys
minimum = float(sys.argv[1])
if not math.isfinite(minimum) or minimum < 80:
    raise SystemExit("Verification failed: COVERAGE_MINIMUM must be a finite value of at least 80.")
payload = json.loads(sys.argv[2])
measures = {item["metric"]: item.get("value") for item in payload.get("component", {}).get("measures", [])}
missing = [metric for metric in ("new_coverage", "new_bugs") if metric not in measures]
if missing:
    separator = chr(44) + chr(32)
    raise SystemExit(f"Verification failed: SonarQube did not return {separator.join(missing)}. Configure new-code analysis and a Quality Gate.")
new_coverage = float(measures["new_coverage"])
new_bugs = int(float(measures["new_bugs"]))
print(f"SonarQube new-code coverage: {new_coverage:.2f}%; required: {minimum:.2f}%")
print(f"SonarQube new bugs: {new_bugs}; required: 0")
if new_coverage < minimum or new_bugs != 0:
    raise SystemExit(1)
' "$coverage_minimum" "$measures"

printf 'Verification passed: Maven, JaCoCo, and SonarQube requirements are satisfied.\n'
