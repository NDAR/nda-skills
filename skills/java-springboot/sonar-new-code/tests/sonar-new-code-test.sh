#!/usr/bin/env bash
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sensor="$skill_dir/scripts/check-sonar-new-code.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/sonar-new-code.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> maven.args' \
  > "$fixture/mvnw"
chmod +x "$fixture/mvnw"
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ "$*" == *"/api/qualitygates/project_status?"* ]]; then printf "%s\n" "$FAKE_QUALITY_GATE_RESPONSE"; else printf "%s\n" "$FAKE_MEASURES_RESPONSE"; fi' \
  > "$fixture/bin/curl"
chmod +x "$fixture/bin/curl"

(
  cd "$fixture"
  PATH="$fixture/bin:$PATH" \
  SONAR_HOST_URL=https://sonar.example.test \
  SONAR_TOKEN=test-token \
  SONAR_PROJECT_KEY=service-key \
  SONAR_PULL_REQUEST_KEY=42 \
  SONAR_PULL_REQUEST_BRANCH=feature/new-code \
  SONAR_PULL_REQUEST_BASE=main \
  FAKE_QUALITY_GATE_RESPONSE='{"projectStatus":{"status":"OK"}}' \
  FAKE_MEASURES_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","value":"85.5"},{"metric":"new_bugs","value":"0"},{"metric":"new_vulnerabilities","value":"0"},{"metric":"new_code_smells","value":"2"},{"metric":"new_security_hotspots","value":"0"},{"metric":"new_duplicated_lines_density","value":"0.0"}]}}' \
  "$sensor" > "$fixture/report.txt"
)

grep -Fq -- '-Dsonar.pullrequest.key=42' "$fixture/maven.args"
grep -Fq -- '-Dsonar.pullrequest.branch=feature/new-code' "$fixture/maven.args"
grep -Fq -- '-Dsonar.pullrequest.base=main' "$fixture/maven.args"
grep -Fq 'SonarQube Quality Gate: OK' "$fixture/report.txt"
grep -Fq 'New-code coverage: 85.50%' "$fixture/report.txt"
grep -Fq 'New bugs: 0' "$fixture/report.txt"

branch_fixture=$(mktemp -d "${TMPDIR:-/tmp}/sonar-new-code-branch.XXXXXX")
trap 'rm -rf "$fixture" "$branch_fixture"' EXIT
mkdir -p "$branch_fixture/bin"
cp "$fixture/mvnw" "$branch_fixture/mvnw"
cp "$fixture/bin/curl" "$branch_fixture/bin/curl"
chmod +x "$branch_fixture/mvnw" "$branch_fixture/bin/curl"
(
  cd "$branch_fixture"
  PATH="$branch_fixture/bin:$PATH" \
  SONAR_HOST_URL=https://sonar.example.test \
  SONAR_TOKEN=test-token \
  SONAR_PROJECT_KEY=service-key \
  SONAR_BRANCH_NAME=feature/new-code \
  FAKE_QUALITY_GATE_RESPONSE='{"projectStatus":{"status":"OK"}}' \
  FAKE_MEASURES_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","value":"80"},{"metric":"new_bugs","value":"0"},{"metric":"new_vulnerabilities","value":"0"},{"metric":"new_code_smells","value":"0"},{"metric":"new_security_hotspots","value":"0"},{"metric":"new_duplicated_lines_density","value":"0"}]}}' \
  "$sensor"
)
grep -Fq -- '-Dsonar.branch.name=feature/new-code' "$branch_fixture/maven.args"

partial_report="$branch_fixture/partial-report.txt"
(
  cd "$branch_fixture"
  PATH="$branch_fixture/bin:$PATH" \
  SONAR_HOST_URL=https://sonar.example.test \
  SONAR_TOKEN=test-token \
  SONAR_PROJECT_KEY=service-key \
  SONAR_BRANCH_NAME=feature/new-code \
  FAKE_QUALITY_GATE_RESPONSE='{"projectStatus":{"status":"OK"}}' \
  FAKE_MEASURES_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","value":"80"},{"metric":"new_bugs","value":"0"}]}}' \
  "$sensor" > "$partial_report"
)
grep -Fq 'New vulnerabilities: N/A' "$partial_report"

fallback_fixture=$(mktemp -d "${TMPDIR:-/tmp}/sonar-new-code-fallback.XXXXXX")
trap 'rm -rf "$fixture" "$branch_fixture" "$fallback_fixture"' EXIT
mkdir -p "$fallback_fixture/bin"
cp "$fixture/mvnw" "$fallback_fixture/mvnw"
cp "$fixture/bin/curl" "$fallback_fixture/bin/curl"
chmod +x "$fallback_fixture/mvnw" "$fallback_fixture/bin/curl"
git -C "$fallback_fixture" init --quiet --initial-branch=feature/git-fallback
(
  cd "$fallback_fixture"
  PATH="$fallback_fixture/bin:$PATH" \
  SONAR_HOST_URL=https://sonar.example.test \
  SONAR_TOKEN=test-token \
  SONAR_PROJECT_KEY=service-key \
  FAKE_QUALITY_GATE_RESPONSE='{"projectStatus":{"status":"OK"}}' \
  FAKE_MEASURES_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","value":"80"},{"metric":"new_bugs","value":"0"}]}}' \
  "$sensor"
)
grep -Fq -- '-Dsonar.branch.name=feature/git-fallback' "$fallback_fixture/maven.args"

printf 'PASS: pull-request and branch analysis contexts are sent to SonarQube.\n'
