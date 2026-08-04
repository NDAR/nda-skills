#!/usr/bin/env bash
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
verifier="$skill_dir/scripts/verify-java-service.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/java-spring-verification.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

make_fixture() {
  local name=$1
  local covered=$2
  local missed=$3
  local directory="$fixture/$name"

  mkdir -p "$directory/target/site/jacoco"
  printf '<report><counter type="LINE" missed="%s" covered="%s"/></report>\n' \
    "$missed" "$covered" > "$directory/target/site/jacoco/jacoco.xml"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> maven.args' \
    > "$directory/mvnw"
  chmod +x "$directory/mvnw"
  printf '%s\n' "$directory"
}

passing_fixture=$(make_fixture passing 8 2)
(
  cd "$passing_fixture"
  "$verifier"
)
test "$(<"$passing_fixture/maven.args")" = 'clean verify'

sonar_fixture=$(make_fixture sonar-success 9 1)
mkdir -p "$sonar_fixture/bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$FAKE_SONAR_RESPONSE"' \
  > "$sonar_fixture/bin/curl"
chmod +x "$sonar_fixture/bin/curl"
(
  cd "$sonar_fixture"
  PATH="$sonar_fixture/bin:$PATH" \
  SONAR_HOST_URL=https://sonar.example.test \
  SONAR_TOKEN=test-token \
  SONAR_PROJECT_KEY=service-key \
  FAKE_SONAR_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","value":"80.0"},{"metric":"new_bugs","value":"0"}]}}' \
  "$verifier"
)
grep -Fq 'clean verify' "$sonar_fixture/maven.args"
grep -Fq 'sonar-maven-plugin:sonar' "$sonar_fixture/maven.args"
grep -Fq -- '-Dsonar.qualitygate.wait=true' "$sonar_fixture/maven.args"

root_counter_fixture=$(make_fixture root-counter-coverage 7 3)
printf '%s\n' '<report><counter type="LINE" missed="3" covered="7"/><package><counter type="LINE" missed="0" covered="100"/></package></report>' \
  > "$root_counter_fixture/target/site/jacoco/jacoco.xml"
if (
  cd "$root_counter_fixture"
  "$verifier"
); then
  printf 'Expected root JaCoCo coverage below 80%% to fail despite nested counters.\n' >&2
  exit 1
fi

sonar_bug_fixture=$(make_fixture sonar-new-bug 9 1)
mkdir -p "$sonar_bug_fixture/bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$FAKE_SONAR_RESPONSE"' \
  > "$sonar_bug_fixture/bin/curl"
chmod +x "$sonar_bug_fixture/bin/curl"
if (
  cd "$sonar_bug_fixture"
  PATH="$sonar_bug_fixture/bin:$PATH" \
  SONAR_HOST_URL=https://sonar.example.test \
  SONAR_TOKEN=test-token \
  SONAR_PROJECT_KEY=service-key \
  FAKE_SONAR_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","value":"90.0"},{"metric":"new_bugs","value":"1"}]}}' \
  "$verifier"
); then
  printf 'Expected a new SonarQube bug to fail verification.\n' >&2
  exit 1
fi

sonar_coverage_fixture=$(make_fixture sonar-new-coverage 9 1)
mkdir -p "$sonar_coverage_fixture/bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$FAKE_SONAR_RESPONSE"' \
  > "$sonar_coverage_fixture/bin/curl"
chmod +x "$sonar_coverage_fixture/bin/curl"
if (
  cd "$sonar_coverage_fixture"
  PATH="$sonar_coverage_fixture/bin:$PATH" \
  SONAR_HOST_URL=https://sonar.example.test \
  SONAR_TOKEN=test-token \
  SONAR_PROJECT_KEY=service-key \
  FAKE_SONAR_RESPONSE='{"component":{"measures":[{"metric":"new_coverage","value":"79.9"},{"metric":"new_bugs","value":"0"}]}}' \
  "$verifier"
); then
  printf 'Expected SonarQube new-code coverage below 80%% to fail verification.\n' >&2
  exit 1
fi

failing_fixture=$(make_fixture coverage-failure 7 3)
if (
  cd "$failing_fixture"
  "$verifier"
); then
  printf 'Expected coverage below 80%% to fail.\n' >&2
  exit 1
fi

if (
  cd "$passing_fixture"
  SONAR_HOST_URL=https://sonar.example.test "$verifier"
); then
  printf 'Expected partial SonarQube configuration to fail verification.\n' >&2
  exit 1
fi

if (
  cd "$passing_fixture"
  SONAR_REQUIRED=true "$verifier"
); then
  printf 'Expected required SonarQube configuration to fail when absent.\n' >&2
  exit 1
fi

if (
  cd "$passing_fixture"
  COVERAGE_MINIMUM=79 "$verifier"
); then
  printf 'Expected a coverage threshold below 80%% to be rejected.\n' >&2
  exit 1
fi

if (
  cd "$passing_fixture"
  COVERAGE_MINIMUM=nan "$verifier"
); then
  printf 'Expected a non-finite coverage threshold to be rejected.\n' >&2
  exit 1
fi

printf 'PASS: Maven, JaCoCo, and required-SonarQube checks are enforced.\n'
