#!/usr/bin/env bash
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sensor="$skill_dir/scripts/check-sonar-new-code.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/sonar-new-code.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

# Keep tests independent of the caller's analysis context.
unset SONAR_PULL_REQUEST_KEY SONAR_PULL_REQUEST_BRANCH SONAR_PULL_REQUEST_BASE SONAR_BRANCH_NAME
export FAKE_WRITE_METADATA=1
export FAKE_TASK_RESPONSE='{"task":{"status":"SUCCESS","analysisId":"current-analysis"}}'
mkdir -p "$fixture/bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> maven.args' \
  'for arg in "$@"; do if [[ "$arg" == -Dsonar.scanner.metadataFilePath=* && ${FAKE_WRITE_METADATA:-0} == 1 ]]; then printf "ceTaskId=current-task\n" > "${arg#*=}"; fi; done' \
  'exit "${FAKE_MAVEN_STATUS:-0}"' \
  > "$fixture/mvnw"
chmod +x "$fixture/mvnw"
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ "$*" == *"/api/qualitygates/project_status?"* ]]; then if [[ "$*" == *"?analysisId=current-analysis" ]]; then printf "%s\n" "$FAKE_QUALITY_GATE_RESPONSE"; else printf "%s\n" "{\"projectStatus\":{\"status\":\"ERROR\"}}"; fi; elif [[ "$*" == *"/api/ce/task?"* ]]; then printf "%s\n" "$FAKE_TASK_RESPONSE"; else printf "%s\n" "$FAKE_MEASURES_RESPONSE"; fi' \
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
  FAKE_MEASURES_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","period":{"value":"85.5"}},{"metric":"new_bugs","period":{"value":"3"}},{"metric":"new_vulnerabilities","value":"0"},{"metric":"new_code_smells","value":"2"},{"metric":"new_security_hotspots","value":"0"},{"metric":"new_duplicated_lines_density","value":"0.0"}]}}' \
  "$sensor" > "$fixture/report.txt"
)

grep -Fq -- '-Dsonar.pullrequest.key=42' "$fixture/maven.args"
grep -Fq -- '-Dsonar.pullrequest.branch=feature/new-code' "$fixture/maven.args"
grep -Fq -- '-Dsonar.pullrequest.base=main' "$fixture/maven.args"
grep -Fq 'SonarQube Quality Gate: OK' "$fixture/report.txt"
grep -Fq 'New-code coverage: 85.50%' "$fixture/report.txt"
grep -Fq 'New bugs: 3' "$fixture/report.txt"

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
  FAKE_MEASURES_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","periods":[{"index":1,"value":"80"}]},{"metric":"new_bugs","value":"0"},{"metric":"new_vulnerabilities","value":"0"},{"metric":"new_code_smells","value":"0"},{"metric":"new_security_hotspots","value":"0"},{"metric":"new_duplicated_lines_density","value":"0"}]}}' \
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
  FAKE_MEASURES_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","periods":[{"index":1,"value":"80"}]},{"metric":"new_bugs","period":{}},{"metric":"new_vulnerabilities","periods":[]},{"metric":"new_code_smells"}]}}' \
  "$sensor" > "$partial_report"
)
grep -Fq 'New vulnerabilities: N/A' "$partial_report"
grep -Fq 'New bugs: N/A' "$partial_report"
grep -Fq 'New code smells: N/A' "$partial_report"
grep -Fq 'New-code coverage: 80.00%' "$partial_report"

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
  FAKE_MEASURES_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","periods":[{"index":1,"value":"80"}]},{"metric":"new_bugs","period":{}},{"metric":"new_vulnerabilities","periods":[]},{"metric":"new_code_smells"}]}}' \
  "$sensor"
)
grep -Fq -- '-Dsonar.branch.name=feature/git-fallback' "$fallback_fixture/maven.args"

printf 'PASS: pull-request and branch analysis contexts are sent to SonarQube.\n'

# Nonzero scanner exits must report only a completed analysis with a failed gate.
for scenario in failed-gate scanner-failure pending-task failed-task; do
  result=0
  (
    cd "$fixture"
    export PATH="$fixture/bin:$PATH"
    export SONAR_HOST_URL=https://sonar.example.test SONAR_TOKEN=test-token
    export SONAR_PROJECT_KEY=service-key SONAR_BRANCH_NAME=feature/new-code
    export FAKE_MAVEN_STATUS=7 FAKE_WRITE_METADATA=1
    export FAKE_QUALITY_GATE_RESPONSE='{"projectStatus":{"status":"ERROR"}}'
    export FAKE_TASK_RESPONSE='{"task":{"status":"SUCCESS","analysisId":"current-analysis"}}'
    export FAKE_MEASURES_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","period":{"value":"85.5"}},{"metric":"new_bugs","period":{"value":"3"}}]}}'
    case "$scenario" in
      scanner-failure) export FAKE_WRITE_METADATA=0 ;;
      pending-task) export FAKE_TASK_RESPONSE='{"task":{"status":"IN_PROGRESS"}}' ;;
      failed-task) export FAKE_TASK_RESPONSE='{"task":{"status":"FAILED"}}' ;;
    esac
    "$sensor"
  ) > "$fixture/$scenario.txt" 2>&1 || result=$?
  [[ $result -ne 0 ]]
  if [[ $scenario == failed-gate ]]; then
    grep -Fq 'SonarQube Quality Gate: ERROR' "$fixture/$scenario.txt"
    grep -Fq 'New-code coverage: 85.50%' "$fixture/$scenario.txt"
    grep -Fq 'New bugs: 3' "$fixture/$scenario.txt"
  else
    [[ $result -eq 7 ]]
    if grep -Fq 'New-code coverage:' "$fixture/$scenario.txt"; then
      printf 'FAIL: scanner failure produced a metrics report\n' >&2
      exit 1
    fi
  fi
done
printf 'PASS: failed gates report metrics; scanner failures retain their exit status.\n'

# Every nonempty proper subset of the PR tuple must fail before Maven runs,
# even when an explicit branch or a Git fallback is available.
for branch_mode in explicit fallback; do
  for mask in 2 4 6 1 3 5; do
    case_dir="$fallback_fixture/partial-$branch_mode-$mask"
    mkdir -p "$case_dir"
    cp "$fixture/mvnw" "$case_dir/mvnw"
    result=0
    (
      cd "$case_dir"
      export PATH="$fixture/bin:$PATH"
      export SONAR_HOST_URL=https://sonar.example.test SONAR_TOKEN=test-token
      export SONAR_PROJECT_KEY=service-key
      export FAKE_QUALITY_GATE_RESPONSE='{"projectStatus":{"status":"OK"}}'
      export FAKE_MEASURES_RESPONSE='{"component":{"measures":[]}}'
      if [[ $branch_mode == explicit ]]; then export SONAR_BRANCH_NAME=feature/new-code; fi
      if (( mask & 1 )); then export SONAR_PULL_REQUEST_KEY=42; fi
      if (( mask & 2 )); then export SONAR_PULL_REQUEST_BRANCH=feature/new-code; fi
      if (( mask & 4 )); then export SONAR_PULL_REQUEST_BASE=main; fi
      "$sensor"
    ) > "$case_dir/report.txt" 2>&1 || result=$?
    [[ $result -ne 0 ]]
    [[ ! -e "$case_dir/maven.args" ]]
    grep -Fq 'requires SONAR_PULL_REQUEST_KEY, SONAR_PULL_REQUEST_BRANCH, and SONAR_PULL_REQUEST_BASE' "$case_dir/report.txt"
  done
done
printf 'PASS: all incomplete PR tuples are rejected before scanning.\n'
