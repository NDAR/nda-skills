#!/usr/bin/env bash
set -euo pipefail

hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
checker="$hook_dir/scripts/check-pom-updates.py"

fixture=$(mktemp -d "${TMPDIR:-/tmp}/check-pom-updates-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

project="$fixture/project"
mkdir -p "$project"
cat > "$project/pom.xml" <<'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.example</groupId>
    <artifactId>parent</artifactId>
    <version>1.0.0</version>
  </parent>
  <groupId>com.example</groupId>
  <artifactId>sample</artifactId>
  <version>1.0.0</version>
</project>
POM

maven="$fixture/mvn"
cat > "$maven" <<'MAVEN'
#!/usr/bin/env bash
set -euo pipefail

output_file=""
non_recursive=false
for argument in "$@"; do
  case "$argument" in
    -N) non_recursive=true ;;
    -Dversions.outputFile=*) output_file=${argument#-Dversions.outputFile=} ;;
  esac
done

if [[ -z "$output_file" ]]; then
  printf 'missing Maven output file argument\n' >&2
  exit 70
fi

if [[ "$non_recursive" != true ]]; then
  printf '%s\n' 'Parent project is part of the reactor.' > "$output_file"
  exit 0
fi

printf '%s\n' 'The parent project has a newer version:' > "$output_file"
printf '%s\n' 'com.example:parent 1.0.0 -> 1.1.0' >> "$output_file"
MAVEN
chmod +x "$maven"

set +e
output=$(python3 "$checker" --project "$project" --maven-command "$maven" --fail-on-outdated 2>&1)
status=$?
set -e

if (( status != 1 )); then
  printf 'Expected an outdated version to exit 1, got %s.\n%s\n' "$status" "$output" >&2
  exit 1
fi
grep -Fq 'com.example:parent' <<<"$output"
grep -Fq '1.1.0' <<<"$output"

printf 'PASS: outdated direct parent versions cause a failing update check.\n'

# An aggregator can keep its own POM version-light while module POMs declare
# direct dependencies. Those declarations must still be checked and reported
# against their reactor-relative POM path.
reactor_project="$fixture/reactor-project"
mkdir -p "$reactor_project/service-module"
cat > "$reactor_project/pom.xml" <<'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>reactor</artifactId>
  <version>1.0.0</version>
  <modules>
    <module>service-module</module>
  </modules>
</project>
POM
cat > "$reactor_project/service-module/pom.xml" <<'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.example</groupId>
    <artifactId>reactor</artifactId>
    <version>1.0.0</version>
  </parent>
  <artifactId>service-module</artifactId>
  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>stale-library</artifactId>
      <version>1.0.0</version>
    </dependency>
  </dependencies>
</project>
POM

reactor_maven="$fixture/reactor-mvn"
cat > "$reactor_maven" <<'MAVEN'
#!/usr/bin/env bash
set -euo pipefail

output_file=""
goal=""
pom_file=""
while (( $# > 0 )); do
  argument=$1
  shift
  case "$argument" in
    -Dversions.outputFile=*) output_file=${argument#-Dversions.outputFile=} ;;
    -f|--file)
      if (( $# == 0 )); then
        printf 'missing Maven POM file argument\n' >&2
        exit 71
      fi
      pom_file=$1
      shift
      ;;
    -f=*|--file=*) pom_file=${argument#*=} ;;
    *:display-dependency-updates) goal=dependency ;;
    *:display-parent-updates) goal=parent ;;
    *:display-plugin-updates) goal=plugin ;;
  esac
done

if [[ -z "$output_file" ]]; then
  printf 'missing Maven output file argument\n' >&2
  exit 70
fi

if [[ -f "$PWD/custom-pom.xml" && "$pom_file" != "$PWD/custom-pom.xml" ]]; then
  printf 'expected Maven -f %s, got %s\n' "$PWD/custom-pom.xml" "${pom_file:-none}" >&2
  exit 72
fi

case "$goal" in
  dependency)
    printf '%s\n' 'The following dependencies in Dependencies have newer versions:' > "$output_file"
    printf '%s\n' 'com.example:stale-library 1.0.0 -> 2.0.0' >> "$output_file"
    ;;
  parent) printf '%s\n' 'The parent project is the latest version:' > "$output_file" ;;
  plugin) printf '%s\n' 'All plugins with a version specified are using the latest versions.' > "$output_file" ;;
esac
MAVEN
chmod +x "$reactor_maven"

set +e
reactor_output=$(python3 "$checker" --project "$reactor_project" --maven-command "$reactor_maven" --fail-on-outdated 2>&1)
reactor_status=$?
set -e
if (( reactor_status != 1 )); then
  printf 'Expected a stale module dependency to exit 1, got %s.\n%s\n' "$reactor_status" "$reactor_output" >&2
  exit 1
fi
grep -Fq 'service-module/pom.xml' <<<"$reactor_output"
grep -Fq 'com.example:stale-library' <<<"$reactor_output"
grep -Fq '2.0.0' <<<"$reactor_output"

printf 'PASS: reactor module dependencies are included in update checks.\n'

# An empty module declaration cannot identify a POM to check and must fail
# closed instead of making the reactor appear current.
invalid_reactor_project="$fixture/invalid-reactor-project"
mkdir -p "$invalid_reactor_project"
cat > "$invalid_reactor_project/pom.xml" <<'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>invalid-reactor</artifactId>
  <version>1.0.0</version>
  <modules>
    <module>   </module>
  </modules>
</project>
POM

set +e
invalid_reactor_output=$(python3 "$checker" --project "$invalid_reactor_project" --maven-command "$reactor_maven" --fail-on-outdated 2>&1)
invalid_reactor_status=$?
set -e
if (( invalid_reactor_status != 2 )); then
  printf 'Expected an empty reactor module declaration to exit 2, got %s.\n%s\n' "$invalid_reactor_status" "$invalid_reactor_output" >&2
  exit 1
fi
grep -Fq 'reactor module path is empty' <<<"$invalid_reactor_output"

printf 'PASS: empty reactor module declarations fail closed.\n'

# Maven reactor modules may be declared outside the aggregator directory. The
# report must preserve that path and return the stale-update status, not fail
# while formatting it.
external_fixture="$fixture/external-reactor"
external_reactor_project="$external_fixture/reactor"
external_module_project="$external_fixture/shared-module"
mkdir -p "$external_reactor_project" "$external_module_project"
cat > "$external_reactor_project/pom.xml" <<'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>external-reactor</artifactId>
  <version>1.0.0</version>
  <modules>
    <module>../shared-module</module>
  </modules>
</project>
POM
cat > "$external_module_project/pom.xml" <<'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>shared-module</artifactId>
  <version>1.0.0</version>
  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>stale-library</artifactId>
      <version>1.0.0</version>
    </dependency>
  </dependencies>
</project>
POM

set +e
external_reactor_output=$(python3 "$checker" --project "$external_reactor_project" --maven-command "$reactor_maven" --fail-on-outdated 2>&1)
external_reactor_status=$?
set -e
if (( external_reactor_status != 1 )); then
  printf 'Expected a stale external reactor module to exit 1, got %s.\n%s\n' "$external_reactor_status" "$external_reactor_output" >&2
  exit 1
fi
grep -Fq '../shared-module/pom.xml' <<<"$external_reactor_output"
grep -Fq 'com.example:stale-library' <<<"$external_reactor_output"

printf 'PASS: external reactor module paths are reported.\n'

# Maven also allows a module declaration to name its POM file directly rather
# than its directory. The checker must check that POM without adding another
# /pom.xml path segment.
file_module_reactor="$fixture/file-module-reactor"
file_module_child="$file_module_reactor/child"
mkdir -p "$file_module_child"
cat > "$file_module_reactor/pom.xml" <<'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>file-module-reactor</artifactId>
  <version>1.0.0</version>
  <modules>
    <module>child/custom-pom.xml</module>
  </modules>
</project>
POM
cat > "$file_module_child/custom-pom.xml" <<'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>custom-file-module</artifactId>
  <version>1.0.0</version>
  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>stale-library</artifactId>
      <version>1.0.0</version>
    </dependency>
  </dependencies>
</project>
POM

set +e
file_module_output=$(python3 "$checker" --project "$file_module_reactor" --maven-command "$reactor_maven" --fail-on-outdated 2>&1)
file_module_status=$?
set -e
if (( file_module_status != 1 )); then
  printf 'Expected a stale file-valued module to exit 1, got %s.\n%s\n' "$file_module_status" "$file_module_output" >&2
  exit 1
fi
grep -Fq 'child/custom-pom.xml' <<<"$file_module_output"
grep -Fq 'com.example:stale-library' <<<"$file_module_output"

printf 'PASS: file-valued reactor module paths are reported.\n'

# A POM without Maven's namespace cannot be safely interpreted as a Maven POM.
# It must fail instead of silently finding no version declarations.
unsupported_project="$fixture/unsupported-project"
mkdir -p "$unsupported_project"
cat > "$unsupported_project/pom.xml" <<'POM'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>unsupported</artifactId>
  <version>1.0.0</version>
</project>
POM

set +e
unsupported_output=$(python3 "$checker" --project "$unsupported_project" --inventory-only 2>&1)
unsupported_status=$?
set -e
if (( unsupported_status != 2 )); then
  printf 'Expected a POM without Maven namespace to fail with status 2, got %s.\n%s\n' "$unsupported_status" "$unsupported_output" >&2
  exit 1
fi
grep -Fq 'Maven POM namespace' <<<"$unsupported_output"

printf 'PASS: unsupported POM namespaces fail closed.\n'

# Any unexpected checker exception must remain a non-overridable error rather
# than sharing exit 1 with an available update.
set +e
unexpected_output=$(python3 - "$checker" "$project" 2>&1 <<'PY'
import importlib.util
import sys

checker_path, project = sys.argv[1:]
spec = importlib.util.spec_from_file_location("check_pom_updates", checker_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

def fail_unexpectedly(*_args):
    raise RuntimeError("simulated unexpected checker failure")

module.render_dependency_report = fail_unexpectedly
sys.argv = [checker_path, "--project", project]
raise SystemExit(module.main())
PY
)
unexpected_status=$?
set -e
if (( unexpected_status != 2 )); then
  printf 'Expected an unexpected checker exception to exit 2, got %s.\n%s\n' "$unexpected_status" "$unexpected_output" >&2
  exit 1
fi
grep -Fq 'simulated unexpected checker failure' <<<"$unexpected_output"

printf 'PASS: unexpected checker exceptions fail closed.\n'
