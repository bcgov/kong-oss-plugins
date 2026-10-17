import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('publish_releases', ROOT / '.github/scripts/publish_releases.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.old = Path.cwd()
        os.chdir(self.temp.name)
        self.sha = 'a' * 40
        self.component = {'name': 'example', 'kind': 'image', 'version': '0.1.0', 'tag': 'example/v0.1.0', 'previous': None, 'paths': ['source/']}
        Path('release-plan.json').write_text(json.dumps({'sha': self.sha, 'components': [self.component], 'url': 'https://example.invalid/pr/1'}))
        Path('release-assets').mkdir()
        self.receipt = {'component': 'example', 'revision': self.sha, 'digest': 'sha256:' + 'b' * 64, 'image': 'ghcr.io/example/example:v0.1.0'}
        self.write_receipt()

    def tearDown(self):
        os.chdir(self.old)
        self.temp.cleanup()

    def write_receipt(self):
        Path('release-assets/example.json').write_text(json.dumps(self.receipt))

    def test_mismatched_artifact_blocks_external_writes(self):
        for key, value in [('revision', 'wrong'), ('component', 'wrong'), ('digest', ''), ('image', 'ghcr.io/example/example:v9.0.0')]:
            with self.subTest(key=key):
                receipt = dict(self.receipt, **{key: value})
                Path('release-assets/example.json').write_text(json.dumps(receipt))
                with patch.object(publisher, 'api') as api:
                    with self.assertRaises(ValueError):
                        publisher.main()
                    api.assert_not_called()

    def test_existing_published_release_is_noop_only_for_same_commit(self):
        with patch.object(publisher.subprocess, 'check_output', return_value='Changes'), patch.object(publisher.subprocess, 'run') as command:
            with patch.object(publisher, 'api', side_effect=[[{'tag_name': self.component['tag'], 'draft': False}], {'sha': self.sha}]):
                publisher.main()
                command.assert_not_called()
            with patch.object(publisher, 'api', side_effect=[[{'tag_name': self.component['tag'], 'draft': False}], {'sha': 'wrong'}]):
                with self.assertRaises(ValueError):
                    publisher.main()

    def test_orphan_tag_collision_blocks_release_creation(self):
        with patch.object(publisher.subprocess, 'check_output', return_value='Changes'), patch.object(publisher, 'api', side_effect=[[], {'sha': 'wrong'}]) as api:
            with self.assertRaises(ValueError):
                publisher.main()
            self.assertEqual(api.call_count, 2)

    def test_upload_failure_leaves_release_draft(self):
        missing = urllib.error.HTTPError('https://example.invalid', 404, 'Not found', {}, None)
        calls = [[], missing, {'id': 1, 'target_commitish': self.sha}]
        with patch.object(publisher.subprocess, 'check_output', return_value='Changes'), patch.object(publisher.subprocess, 'run', side_effect=RuntimeError('upload failed')):
            with patch.object(publisher, 'api', side_effect=calls) as api:
                with self.assertRaises(RuntimeError):
                    publisher.main()
                self.assertEqual(api.call_count, 3)  # No PATCH to publish after the failure.


if __name__ == '__main__':
    unittest.main()
