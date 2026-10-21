#!/usr/bin/env python3
"""Run explicit workspace checks and verify fresh LCOV and SonarQube evidence."""
import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request


def fail(message):
    raise ValueError(message)


def number(value, label, maximum=100):
    try:
        result = float(value)
    except (TypeError, ValueError):
        fail(f'{label} must be a finite number between 0 and {maximum}.')
    if not math.isfinite(result) or not 0 <= result <= maximum:
        fail(f'{label} must be a finite number between 0 and {maximum}.')
    return result


def run(command, label):
    print(f'Running {label}', flush=True)
    # Do not print commands: credentials belong in the environment, not logs.
    subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', command], check=True)


def fingerprint(path):
    if not path.exists():
        return None
    stat = path.stat()
    return stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns


def coverage(path):
    """Read DA records; merge repeated source/line entries without double counting."""
    lines = {}
    source = None
    record = {}
    summaries = {}
    for raw in path.read_text().splitlines():
        if raw.startswith('SF:'):
            if source is not None or not raw[3:].strip():
                fail(f'Malformed LCOV source record in {path}.')
            source, record, summaries = raw[3:], {}, {}
        elif raw.startswith('DA:'):
            if source is None:
                fail(f'LCOV line without source in {path}.')
            fields = raw[3:].split(',')
            line, hits = int(fields[0]), int(fields[1])
            if line <= 0 or hits < 0 or line in record:
                fail(f'Invalid LCOV line in {path}.')
            record[line] = hits > 0
        elif raw.startswith(('LF:', 'LH:')):
            key = raw[:2]
            if source is None or key in summaries:
                fail(f'Malformed LCOV summary in {path}.')
            summaries[key] = int(raw[3:])
        elif raw == 'end_of_record':
            if source is None:
                fail(f'Malformed LCOV record in {path}.')
            for key, actual in (('LF', len(record)), ('LH', sum(record.values()))):
                if key in summaries and summaries[key] != actual:
                    fail(f'Inconsistent LCOV {key} in {path}.')
            for line, hit in record.items():
                identity = (source, line)
                lines[identity] = lines.get(identity, False) or hit
            source = None
    if source is not None:
        fail(f'Unterminated LCOV record in {path}.')
    if not lines:
        fail(f'LCOV report {path} contains no executable lines.')
    return sum(lines.values()), len(lines)


def sonar_config():
    names = ('SONAR_HOST_URL', 'SONAR_TOKEN', 'SONAR_PROJECT_KEY')
    configured = [bool(os.environ.get(name)) for name in names]
    required = os.environ.get('SONAR_REQUIRED', 'false')
    if required not in ('true', 'false'):
        fail('SONAR_REQUIRED must be true or false.')
    if any(configured) and not all(configured):
        fail('Set all of SONAR_HOST_URL, SONAR_TOKEN, SONAR_PROJECT_KEY, or none.')
    context_names = ('SONAR_PULL_REQUEST_KEY', 'SONAR_PULL_REQUEST_BRANCH', 'SONAR_PULL_REQUEST_BASE')
    context = [os.environ.get(name, '') for name in context_names]
    if any(context) and not all(context):
        fail('Set all three SONAR_PULL_REQUEST_* context variables together.')
    branch = os.environ.get('SONAR_BRANCH_NAME', '')
    if branch and any(context):
        fail('Choose pull-request or branch analysis, not both.')
    if not all(configured):
        if required == 'true' or any(context) or branch:
            fail('SonarQube is required but connection variables are missing.')
        return None
    url = urllib.parse.urlsplit(os.environ['SONAR_HOST_URL'])
    if url.scheme not in ('https', 'http') or not url.hostname or url.username or url.password or url.query or url.fragment:
        fail('SONAR_HOST_URL must be an HTTP(S) server URL without credentials, query, or fragment.')
    if url.scheme == 'http' and url.hostname not in ('localhost', '127.0.0.1', '::1'):
        fail('Use HTTPS for remote SonarQube authentication.')
    timeout = number(os.environ.get('SONAR_QUALITY_GATE_TIMEOUT', '300'), 'Sonar timeout', 86400)
    if timeout <= 0 or not timeout.is_integer():
        fail('Sonar timeout must be a positive integer in seconds.')
    args = []
    if all(context):
        args = [f'-Dsonar.pullrequest.{key}={value}' for key, value in zip(('key', 'branch', 'base'), context)]
    elif branch:
        args = [f'-Dsonar.branch.name={branch}']
    return args, int(timeout)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the bearer token to a redirect destination.
        return None


def sonar_api(endpoint, params):
    url = os.environ['SONAR_HOST_URL'].rstrip('/') + endpoint + '?' + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + os.environ['SONAR_TOKEN']})
    opener = urllib.request.build_opener(NoRedirect)
    with opener.open(request, timeout=30) as response:
        return json.load(response)


def check_sonar(config, reports, minimum):
    context, timeout = config
    with tempfile.TemporaryDirectory(prefix='angular-sonar-') as directory:
        metadata = Path(directory) / 'report-task.txt'
        args = [os.environ.get('SONAR_SCANNER', 'sonar-scanner'),
                '-Dsonar.host.url=' + os.environ['SONAR_HOST_URL'],
                '-Dsonar.projectKey=' + os.environ['SONAR_PROJECT_KEY'],
                '-Dsonar.javascript.lcov.reportPaths=' + ','.join(str(p) for p in reports),
                '-Dsonar.scanner.metadataFilePath=' + str(metadata),
                '-Dsonar.qualitygate.wait=true', f'-Dsonar.qualitygate.timeout={timeout}', *context]
        print('Running SonarScanner and waiting for the Quality Gate.', flush=True)
        subprocess.run(args, check=True)
        if not metadata.is_file():
            fail('SonarScanner did not produce fresh task metadata.')
        values = dict(line.split('=', 1) for line in metadata.read_text().splitlines() if '=' in line)
        task_id = values.get('ceTaskId')
        if not task_id:
            fail('SonarScanner metadata has no ceTaskId.')
        task = sonar_api('/api/ce/task', {'id': task_id}).get('task', {})
        if task.get('status') != 'SUCCESS' or not task.get('analysisId'):
            fail('SonarQube task has no successful completed analysis.')
        gate = sonar_api('/api/qualitygates/project_status', {'analysisId': task['analysisId']}).get('projectStatus', {})
        if gate.get('status') != 'OK':
            fail('SonarQube Quality Gate did not pass.')
        conditions = {item['metricKey']: item.get('actualValue') for item in gate.get('conditions', [])}
        if any(conditions.get(key) is None for key in ('new_coverage', 'new_bugs')):
            fail('Quality Gate must return new_coverage and new_bugs conditions for this analysis.')
        new_coverage = number(conditions['new_coverage'], 'Sonar new-code coverage')
        bugs = number(conditions['new_bugs'], 'Sonar new bugs', sys.maxsize)
        print(f'SonarQube Quality Gate: OK; new-code coverage: {new_coverage:.2f}%; new bugs: {bugs:g}')
        if new_coverage < minimum or bugs != 0:
            fail('SonarQube new-code coverage or new-bug requirement failed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lcov', action='append', required=True, type=Path,
                        help='Expected LCOV report for a checked project; repeat for multiple projects.')
    args = parser.parse_args()
    reports = args.lcov
    if len({p.resolve() for p in reports}) != len(reports):
        fail('Specify each LCOV report once.')
    if any(',' in str(p) for p in reports):
        fail('LCOV paths cannot contain commas (SonarScanner uses a comma-separated list).')
    commands = {}
    for name in ('ANGULAR_LINT_CMD', 'ANGULAR_TEST_CMD', 'ANGULAR_BUILD_CMD'):
        command = os.environ.get(name, '').strip()
        if not command:
            fail(f'Set {name} to a repository-supported, non-watch command.')
        commands[name] = command
    minimum = number(os.environ.get('COVERAGE_MINIMUM', '80'), 'COVERAGE_MINIMUM')
    config = sonar_config()
    run(commands['ANGULAR_LINT_CMD'], 'Angular lint')
    before = {path: fingerprint(path) for path in reports}
    run(commands['ANGULAR_TEST_CMD'], 'Angular tests with coverage')
    for path in reports:
        after = fingerprint(path)
        if after is None or after == before[path]:
            fail(f'Expected fresh LCOV report from this test run: {path}.')
        covered, total = coverage(path)
        percentage = covered * 100 / total
        print(f'LCOV {path}: {percentage:.2f}% ({covered}/{total} lines); required: {minimum:.2f}%')
        if percentage < minimum:
            fail(f'Line coverage below {minimum:g}% in {path}.')
    run(commands['ANGULAR_BUILD_CMD'], 'Angular production build')
    if config is not None:
        check_sonar(config, reports, minimum)
        print('Verification passed: lint, tests, coverage, build, and SonarQube.')
    else:
        print('Local verification passed: lint, tests, coverage, build. SonarQube NOT RUN: connection variables absent; pending CI where required.')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(f'Verification failed: check exited with status {error.returncode}.', file=sys.stderr)
        sys.exit(1)
    except (ValueError, OSError, KeyError, IndexError) as error:
        # Remote payloads and command arguments must not expose credentials.
        message = str(error)
        token = os.environ.get('SONAR_TOKEN')
        if token:
            message = message.replace(token, '[REDACTED]')
        print(f'Verification failed: {message}', file=sys.stderr)
        sys.exit(1)
