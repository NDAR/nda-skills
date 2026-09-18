#!/usr/bin/env python3
"""Report stable updates for directly declared versions in a Maven project."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import NamedTuple, Sequence


MAVEN_NAMESPACE = "http://maven.apache.org/POM/4.0.0"
PROPERTY_REFERENCE = re.compile(r"^\$\{([^}]+)}$")
UPDATE_LINE = re.compile(r"^\s*([^\s:]+:[^\s:]+)\s+(?:\.{2,}\s+)?(\S+)\s+->\s+(\S+)\s*$")
VERSIONS_PLUGIN = "org.codehaus.mojo:versions-maven-plugin:2.21.0"
IGNORED_PRERELEASES = (
    r"(?i).*[.-](alpha|beta|milestone|rc|cr|m|preview|ea)[.-]?[0-9]*.*,(?i).*SNAPSHOT.*"
)
PRERELEASE_QUALIFIER = re.compile(
    r"(?i)(?:^|[._-])(?:alpha|beta|milestone|rc|cr|m|preview|ea)(?:[._-]?\d*)?(?:$|[._-])|snapshot"
)


class VersionedArtifact(NamedTuple):
    coordinate: str
    current_version: str


class UpdateCheck(NamedTuple):
    updates: dict[str, str]
    error: str | None = None


class RenderedReport(NamedTuple):
    text: str
    complete: bool
    outdated: bool


def _text(element: ET.Element | None) -> str | None:
    if element is None or element.text is None:
        return None
    value = element.text.strip()
    return value or None


def _properties(root: ET.Element, namespace: dict[str, str]) -> dict[str, str | None]:
    return {
        child.tag.rsplit("}", 1)[-1]: _text(child)
        for child in root.findall("m:properties/*", namespace)
    }


def _resolve_version(version: str | None, properties: dict[str, str | None]) -> str | None:
    if version is None:
        return None
    reference = PROPERTY_REFERENCE.fullmatch(version)
    return properties.get(reference.group(1)) if reference else version


def _artifact(
    element: ET.Element | None,
    namespace: dict[str, str],
    properties: dict[str, str | None],
    default_group_id: str | None = None,
) -> VersionedArtifact | None:
    if element is None:
        return None
    group_id = _text(element.find("m:groupId", namespace)) or default_group_id
    artifact_id = _text(element.find("m:artifactId", namespace))
    version = _resolve_version(_text(element.find("m:version", namespace)), properties)
    if not group_id or not artifact_id or not version:
        return None
    return VersionedArtifact(f"{group_id}:{artifact_id}", version)


def _parse_maven_pom(pom_path: Path) -> ET.Element:
    root = ET.parse(pom_path).getroot()
    if root.tag != f"{{{MAVEN_NAMESPACE}}}project":
        raise ET.ParseError("Maven POM namespace is missing or unsupported")
    return root


def discover_explicit_dependencies(pom_path: Path) -> list[VersionedArtifact]:
    root = _parse_maven_pom(pom_path)
    namespace = {"m": MAVEN_NAMESPACE}
    properties = _properties(root, namespace)
    dependencies: list[VersionedArtifact] = []

    for dependency in root.findall("m:dependencies/m:dependency", namespace):
        artifact = _artifact(dependency, namespace, properties)
        if artifact:
            dependencies.append(artifact)
    return dependencies


def build_includes(dependencies: Sequence[VersionedArtifact]) -> str:
    return ",".join(dependency.coordinate for dependency in dependencies)


def discover_explicit_parent(pom_path: Path) -> VersionedArtifact | None:
    root = _parse_maven_pom(pom_path)
    namespace = {"m": MAVEN_NAMESPACE}
    return _artifact(root.find("m:parent", namespace), namespace, _properties(root, namespace))


def discover_explicit_plugins(pom_path: Path) -> list[VersionedArtifact]:
    root = _parse_maven_pom(pom_path)
    namespace = {"m": MAVEN_NAMESPACE}
    properties = _properties(root, namespace)
    plugins = []
    for plugin in root.findall("m:build/m:plugins/m:plugin", namespace):
        artifact = _artifact(plugin, namespace, properties, "org.apache.maven.plugins")
        if artifact:
            plugins.append(artifact)
    return plugins


def render_inventory(project: Path) -> str:
    pom_path = project / "pom.xml"
    parent = discover_explicit_parent(pom_path)
    dependencies = discover_explicit_dependencies(pom_path)
    plugins = discover_explicit_plugins(pom_path)
    lines = [
        "# Maven Version Inventory",
        "",
        "Scope: direct root-POM declarations only; profile, dependency-management, and plugin-management entries are excluded.",
        "",
    ]
    if parent:
        lines.extend(["## Parent", *_render_table(("Artifact", "Current"), [(parent.coordinate, parent.current_version)]), ""])
    lines.extend(["## Explicit dependencies"])
    lines.extend(_render_table(("Artifact", "Current"), [(item.coordinate, item.current_version) for item in dependencies]))
    lines.extend(["", "## Explicit build plugins"])
    lines.extend(_render_table(("Artifact", "Current"), [(item.coordinate, item.current_version) for item in plugins]))
    lines.extend(["", "## Generated dependency include filter", f"-Dincludes={build_includes(dependencies)}"])
    return "\n".join(lines) + "\n"


def _render_table(headers: Sequence[str], rows: Sequence[Sequence[str]]) -> list[str]:
    if not rows:
        return ["None"]
    return [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
        *("| " + " | ".join(row) + " |" for row in rows),
    ]


def _version_key(version: str) -> tuple[tuple[int, int | str], ...]:
    """Return a comparison key for the stable Maven versions this script reports.

    Maven's compatibility sections can list a fallback version that is older
    than the version declared in the POM.  The Versions Plugin does not expose
    a machine-readable flag for that distinction, so use a deliberately small
    natural-order comparison to discard those fallbacks.  ``Final``, ``GA``,
    and ``RELEASE`` are packaging labels rather than version increments.
    """
    normalized = re.sub(r"(?i)(?:[.-](?:final|ga|release))+$", "", version)
    tokens = re.findall(r"\d+|[A-Za-z]+", normalized)
    return tuple(
        (1, int(token)) if token.isdigit() else (0, token.lower()) for token in tokens
    )


def _strip_final_label(version: str) -> str:
    return re.sub(r"(?i)(?:[.-](?:final|ga|release))+$", "", version)


def _is_stable(version: str) -> bool:
    return not PRERELEASE_QUALIFIER.search(version)


def _is_newer(candidate: str, current: str) -> bool:
    candidate_prerelease = PRERELEASE_QUALIFIER.search(candidate)
    current_prerelease = PRERELEASE_QUALIFIER.search(current)
    if candidate_prerelease is None and current_prerelease is not None:
        candidate_base = _strip_final_label(candidate).rstrip("._-")
        current_base = current[: current_prerelease.start()].rstrip("._-")
        if candidate_base.casefold() == current_base.casefold():
            return True
    return _version_key(candidate) > _version_key(current)


def _run_update_check(
    project: Path,
    artifacts: Sequence[VersionedArtifact],
    maven_command: str,
    goal: str,
    update_heading: str,
    no_updates_marker: str,
    extra_arguments: Sequence[str] = (),
    scan_compatibility_sections: bool = False,
) -> UpdateCheck:
    if not artifacts:
        return UpdateCheck({})

    with tempfile.TemporaryDirectory(prefix="check-pom-updates-") as directory:
        output_file = Path(directory, "updates.txt")
        command = [
            maven_command,
            "-N",
            "-B",
            "-ntp",
            f"{VERSIONS_PLUGIN}:{goal}",
            "-DallowSnapshots=false",
            f"-Dmaven.version.ignore={IGNORED_PRERELEASES}",
            f"-Dversions.outputFile={output_file}",
            "-Dversions.overwriteOutput=true",
            "-Dversions.logOutput=false",
            "-Dversions.outputLineWidth=10000",
            *extra_arguments,
        ]
        result = subprocess.run(command, cwd=project, check=False, capture_output=True, text=True)
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip() or "Maven update check failed"
            return UpdateCheck({}, re.sub(r"\s+", " ", detail))
        if not output_file.exists():
            return UpdateCheck({}, "Maven update report was not created")
        report = output_file.read_text(encoding="utf-8")

    current_versions = {artifact.coordinate: artifact.current_version for artifact in artifacts}
    explicit_coordinates = set(current_versions)
    updates: dict[str, str] = {}
    report_lines = report.splitlines()
    if scan_compatibility_sections:
        for line in report_lines:
            match = UPDATE_LINE.match(line)
            if not match or match.group(1) not in explicit_coordinates:
                continue
            coordinate, _reported_current, candidate = match.groups()
            if not _is_stable(candidate) or not _is_newer(candidate, current_versions[coordinate]):
                continue
            previous = updates.get(coordinate)
            if previous is None or _is_newer(candidate, previous):
                updates[coordinate] = candidate
        if updates or no_updates_marker in report:
            return UpdateCheck(updates)
    try:
        heading_index = next(
            index for index, line in enumerate(report_lines) if line.strip() == update_heading
        )
    except StopIteration:
        if no_updates_marker in report:
            return UpdateCheck({})
        return UpdateCheck({}, "Unrecognized Maven update report")
    for line in report_lines[heading_index + 1 :]:
        if not line.strip():
            break
        match = UPDATE_LINE.match(line)
        if (
            match
            and match.group(1) in explicit_coordinates
            and _is_stable(match.group(3))
            and _is_newer(match.group(3), current_versions[match.group(1)])
        ):
            updates[match.group(1)] = match.group(3)
    return UpdateCheck(updates)


def find_dependency_updates(
    project: Path,
    dependencies: Sequence[VersionedArtifact],
    maven_command: str,
) -> UpdateCheck:
    includes = build_includes(dependencies)
    arguments = [
        f"-Dincludes={includes}",
        f"-DdependencyIncludes={includes}",
        "-DprocessDependencyManagement=false",
        "-DprocessPluginDependencies=false",
        "-DshowVersionless=false",
    ]
    return _run_update_check(
        project,
        dependencies,
        maven_command,
        "display-dependency-updates",
        "The following dependencies in Dependencies have newer versions:",
        "No dependencies in Dependencies have newer versions.",
        arguments,
    )


def render_dependency_report(project: Path, maven_command: str) -> RenderedReport:
    pom_path = project / "pom.xml"
    parent = discover_explicit_parent(pom_path)
    dependencies = discover_explicit_dependencies(pom_path)
    plugins = discover_explicit_plugins(pom_path)
    dependency_check = find_dependency_updates(project, dependencies, maven_command)
    parent_check = _run_update_check(
        project,
        [parent] if parent else [],
        maven_command,
        "display-parent-updates",
        "The parent project has a newer version:",
        "The parent project is the latest version:",
    )
    plugin_check = _run_update_check(
        project,
        plugins,
        maven_command,
        "display-plugin-updates",
        "The following plugin updates are available:",
        "All plugins with a version specified are using the latest versions.",
        scan_compatibility_sections=True,
    )

    outdated = [dependency for dependency in dependencies if dependency.coordinate in dependency_check.updates]
    current = (
        [dependency for dependency in dependencies if dependency.coordinate not in dependency_check.updates]
        if not dependency_check.error
        else []
    )
    outdated_plugins = [plugin for plugin in plugins if plugin.coordinate in plugin_check.updates]
    current_plugins = (
        [plugin for plugin in plugins if plugin.coordinate not in plugin_check.updates]
        if not plugin_check.error
        else []
    )
    lines = [
        "# Maven Version Update Report",
        "",
        f"Project: `{project}`",
        "",
        "Scope: direct root-POM declarations only; profile, dependency-management, and plugin-management entries are excluded.",
        "",
        "## Parent",
    ]
    if parent:
        parent_update = parent_check.updates.get(parent.coordinate)
        lines.extend(
            _render_table(
                ("Artifact", "Current", "Latest stable"),
                [(parent.coordinate, parent.current_version, parent_update or parent.current_version)],
            )
        )
    else:
        lines.append("None")
    lines.extend(["", "## Outdated dependencies"])
    lines.extend(
        _render_table(
            ("Artifact", "Current", "Latest stable"),
            [
                (dependency.coordinate, dependency.current_version, dependency_check.updates[dependency.coordinate])
                for dependency in outdated
            ],
        )
    )
    lines.extend(["", "## Current dependencies"])
    lines.extend(_render_table(("Artifact", "Current"), [(dependency.coordinate, dependency.current_version) for dependency in current]))
    lines.extend(["", "## Outdated build plugins"])
    lines.extend(
        _render_table(
            ("Artifact", "Current", "Latest stable"),
            [
                (plugin.coordinate, plugin.current_version, plugin_check.updates[plugin.coordinate])
                for plugin in outdated_plugins
            ],
        )
    )
    lines.extend(["", "## Current build plugins"])
    lines.extend(_render_table(("Artifact", "Current"), [(plugin.coordinate, plugin.current_version) for plugin in current_plugins]))

    unresolved = [
        ("Parent", parent_check.error),
        ("Dependencies", dependency_check.error),
        ("Build plugins", plugin_check.error),
    ]
    unresolved = [(label, error) for label, error in unresolved if error]
    lines.extend(["", "## Unresolved checks"])
    lines.extend(_render_table(("Category", "Error"), unresolved))
    has_updates = bool(
        dependency_check.updates or parent_check.updates or plugin_check.updates
    )
    return RenderedReport("\n".join(lines) + "\n", not unresolved, has_updates)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project",
        type=Path,
        default=Path.cwd(),
        help="Maven project directory (default: current working directory)",
    )
    parser.add_argument("--inventory-only", action="store_true", help="Print discovered explicit versions")
    parser.add_argument("--maven-command", default="mvn", help="Maven executable to invoke")
    parser.add_argument("--output", type=Path, help="Write Markdown to this file instead of standard output")
    parser.add_argument(
        "--fail-on-outdated",
        action="store_true",
        help="Exit 1 when an update is available (default: report only)",
    )
    arguments = parser.parse_args()
    project = arguments.project.resolve()
    pom_path = project / "pom.xml"
    if not pom_path.is_file():
        print(f"error: pom.xml not found in {project}", file=sys.stderr)
        return 2
    try:
        if arguments.inventory_only:
            output = render_inventory(project)
            exit_code = 0
        else:
            report = render_dependency_report(project, arguments.maven_command)
            output = report.text
            if not report.complete:
                exit_code = 2
            elif arguments.fail_on_outdated and report.outdated:
                exit_code = 1
            else:
                exit_code = 0
        if arguments.output:
            arguments.output.write_text(output, encoding="utf-8")
        else:
            print(output, end="")
        return exit_code
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
