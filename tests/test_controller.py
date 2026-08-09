from __future__ import annotations

import importlib.util
import json
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / 'skills' / 'mac-to-windows-testing' / 'scripts' / 'mac2win_test.py'
SPEC = importlib.util.spec_from_file_location('mac2win_test', MODULE_PATH)
assert SPEC and SPEC.loader
M2W = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M2W)


class ControllerTests(unittest.TestCase):
    def test_examples_parse_and_validate(self) -> None:
        for path in sorted((ROOT / 'examples').glob('*.yaml')):
            profile = M2W.load_profile(path)
            M2W.validate_profile(profile)

    def test_redacts_common_credentials_and_identity(self) -> None:
        value = 'password=hello token:abc 13812345678 test@example.com 192.168.1.9 C:\\Users\\Alice\\x'
        redacted = M2W.redact_text(value)
        self.assertNotIn('hello', redacted)
        self.assertNotIn('13812345678', redacted)
        self.assertNotIn('test@example.com', redacted)
        self.assertNotIn('192.168.1.9', redacted)
        self.assertNotIn('Alice', redacted)

    def test_finalize_requires_native_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run = pathlib.Path(temporary)
            result = {'runId': 'r1', 'status': 'PENDING_AI_REVIEW', 'visualConfidenceThreshold': 0.85, 'scenarios': []}
            review = {'runId': 'r1', 'status': 'PASS', 'confidence': 0.99, 'findings': []}
            M2W.dump_json(run / 'result.json', result)
            M2W.dump_json(run / 'review.json', review)
            final = M2W.finalize_result(run / 'result.json', run / 'review.json')
            self.assertEqual('BLOCKED', final['status'])
            self.assertEqual('BLOCKED_EVIDENCE_MISSING', final['blocker'])

    def test_finalize_passes_with_complete_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run = pathlib.Path(temporary)
            (run / 'screenshots').mkdir()
            (run / 'ui-trees').mkdir()
            (run / 'screenshots' / 'main.png').write_bytes(b'png')
            (run / 'ui-trees' / 'main.json').write_text('[]', encoding='utf-8')
            result = {'runId': 'r2', 'status': 'PENDING_AI_REVIEW', 'visualConfidenceThreshold': 0.85, 'scenarios': []}
            review = {'runId': 'r2', 'status': 'PASS', 'confidence': 0.95, 'findings': []}
            M2W.dump_json(run / 'result.json', result)
            M2W.dump_json(run / 'review.json', review)
            final = M2W.finalize_result(run / 'result.json', run / 'review.json')
            self.assertEqual('PASS', final['status'])

    def test_result_failure_cannot_be_overridden_by_visual_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run = pathlib.Path(temporary)
            M2W.dump_json(run / 'result.json', {'runId': 'r3', 'status': 'FAIL', 'scenarios': []})
            M2W.dump_json(run / 'review.json', {'runId': 'r3', 'status': 'PASS', 'confidence': 1, 'findings': []})
            final = M2W.finalize_result(run / 'result.json', run / 'review.json')
            self.assertEqual('FAIL', final['status'])

    def test_schemas_are_valid_json(self) -> None:
        for path in sorted((ROOT / 'schemas').glob('*.json')):
            self.assertIsInstance(json.loads(path.read_text(encoding='utf-8')), dict)


if __name__ == '__main__':
    unittest.main()
