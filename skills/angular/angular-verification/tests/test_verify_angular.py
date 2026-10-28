"""Run the real verifier against isolated workspaces and a local Sonar fixture."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'verify-angular.py'


def lcov(covered=8, total=10, source='src/app.ts'):
    return 'SF:' + source + '\n' + ''.join(
        f'DA:{line},{int(line <= covered)}\n' for line in range(1, total + 1)
    ) + f'LF:{total}\nLH:{covered}\nend_of_record\n'


class VerifyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(('SONAR_', 'ANGULAR_', 'COVERAGE_'))}
        self.env.update(ANGULAR_LINT_CMD='echo lint >> calls',
                        ANGULAR_TEST_CMD='cp fixture.lcov coverage.lcov; echo test >> calls',
                        ANGULAR_BUILD_CMD='echo build >> calls')
        (self.root / 'fixture.lcov').write_text(lcov())

    def run_check(self, ok=True, paths=('coverage.lcov',)):
        args = [sys.executable, str(SCRIPT)]
        for path in paths:
            args += ['--lcov', path]
        result = subprocess.run(args, cwd=self.root, env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode == 0, ok, result.stdout)
        return result.stdout

    def test_runs_all_checks_and_reports_coverage(self):
        self.assertIn('80.00%', self.run_check())
        self.assertEqual((self.root / 'calls').read_text(), 'lint\ntest\nbuild\n')

    def test_low_coverage_fails(self):
        (self.root / 'fixture.lcov').write_text(lcov(7))
        self.assertIn('below', self.run_check(False))

    def test_each_report_must_pass(self):
        (self.root / 'low.lcov').write_text(lcov(1, source='src/low.ts'))
        self.env['ANGULAR_TEST_CMD'] += '; cp low.lcov second.lcov'
        self.assertIn('below', self.run_check(False, ('coverage.lcov', 'second.lcov')))

    def test_stale_report_is_not_evidence(self):
        (self.root / 'coverage.lcov').write_text(lcov())
        self.env['ANGULAR_TEST_CMD'] = 'true'
        self.assertIn('fresh', self.run_check(False))

    def test_missing_report_fails(self):
        self.env['ANGULAR_TEST_CMD'] = 'true'
        self.assertIn('report', self.run_check(False))

    def test_empty_malformed_and_inconsistent_coverage_fail(self):
        for contents in ('', 'garbage', lcov(0, 0), lcov().replace('LH:8', 'LH:10'),
                         'SF:a.ts\nDA:1,-1\nend_of_record\n'):
            with self.subTest(contents=contents):
                (self.root / 'fixture.lcov').write_text(contents)
                self.run_check(False)

    def test_threshold_must_be_finite_and_in_range(self):
        for value in ('nan', 'inf', '-1', '101', 'bad'):
            with self.subTest(value=value):
                self.env['COVERAGE_MINIMUM'] = value
                self.run_check(False)

    def test_explicit_repository_threshold(self):
        self.env['COVERAGE_MINIMUM'] = '90'
        self.run_check(False)
        self.env['COVERAGE_MINIMUM'] = '75'
        self.run_check()

    def test_required_command_missing_fails_before_running(self):
        del self.env['ANGULAR_BUILD_CMD']
        self.run_check(False)
        self.assertFalse((self.root / 'calls').exists())

    def test_check_failure_stops_pipeline(self):
        self.env['ANGULAR_TEST_CMD'] = 'exit 9'
        self.run_check(False)
        self.assertEqual((self.root / 'calls').read_text(), 'lint\n')

    def test_partial_or_required_sonar_configuration_fails(self):
        self.env['SONAR_HOST_URL'] = 'http://localhost'
        self.run_check(False)
        del self.env['SONAR_HOST_URL']
        self.env['SONAR_REQUIRED'] = 'true'
        self.run_check(False)

    def sonar_fixture(self, status='OK', coverage='80', bugs='0', missing=False):
        responses = {
            '/api/ce/task': {'task': {'status': 'SUCCESS', 'analysisId': 'analysis-123'}},
            '/api/qualitygates/project_status': {'projectStatus': {
                'status': status, 'conditions': [] if missing else [
                    {'metricKey': 'new_coverage', 'actualValue': coverage},
                    {'metricKey': 'new_bugs', 'actualValue': bugs}]}}
        }
        requests = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append((self.path, self.headers.get('Authorization')))
                body = json.dumps(responses[self.path.split('?')[0]]).encode()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        scanner = self.root / 'sonar-scanner'
        scanner.write_text('#!' + sys.executable + '\n' + '''
import json, pathlib, sys
pathlib.Path('scanner-args.json').write_text(json.dumps(sys.argv[1:]))
for arg in sys.argv[1:]:
    if arg.startswith('-Dsonar.scanner.metadataFilePath='):
        pathlib.Path(arg.split('=', 1)[1]).write_text('ceTaskId=task-123\\n')
''')
        scanner.chmod(0o755)
        self.env.update(SONAR_HOST_URL=f'http://127.0.0.1:{server.server_port}',
                        SONAR_TOKEN='fixture-token', SONAR_PROJECT_KEY='angular-app',
                        SONAR_SCANNER=str(scanner))
        return requests

    def test_sonar_gate_is_tied_to_current_analysis_and_token_is_not_in_args(self):
        requests = self.sonar_fixture()
        self.env.update(SONAR_PULL_REQUEST_KEY='7', SONAR_PULL_REQUEST_BRANCH='feature',
                        SONAR_PULL_REQUEST_BASE='main')
        output = self.run_check()
        args = json.loads((self.root / 'scanner-args.json').read_text())
        self.assertIn('-Dsonar.qualitygate.wait=true', args)
        self.assertIn('-Dsonar.pullrequest.key=7', args)
        self.assertIn('-Dsonar.javascript.lcov.reportPaths=coverage.lcov', args)
        self.assertNotIn('fixture-token', str(args) + output)
        self.assertIn((' /api/qualitygates/project_status?analysisId=analysis-123'.strip(),
                       'Bearer fixture-token'), requests)

    def test_failed_gate_low_new_coverage_bugs_missing_or_nonfinite_metrics_fail(self):
        for params in ({'status': 'ERROR'}, {'coverage': '79'}, {'bugs': '1'},
                       {'missing': True}, {'coverage': 'NaN'}, {'bugs': '0.5'}):
            with self.subTest(params=params):
                self.sonar_fixture(**params)
                self.run_check(False)

    def test_invalid_sonar_context_fails(self):
        self.sonar_fixture()
        self.env['SONAR_PULL_REQUEST_BRANCH'] = 'feature'
        self.run_check(False)
        self.env.update(SONAR_PULL_REQUEST_KEY='7', SONAR_PULL_REQUEST_BASE='main',
                        SONAR_BRANCH_NAME='feature')
        self.run_check(False)


if __name__ == '__main__':
    unittest.main()
