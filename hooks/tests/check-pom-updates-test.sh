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
