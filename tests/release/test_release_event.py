"""Exercise promotion event handling against real, temporary Git history."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PromotionEventTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.git('init', '-b', 'main')
        self.git('config', 'user.email', 'ci@example.invalid')
        self.git('config', 'user.name', 'Release test')
        (self.directory / 'source').mkdir()
        (self.directory / 'source/a').write_text('base')
        self.git('add', '.')
        self.git('commit', '-m', 'Initial')
        self.base = self.git('rev-parse', 'HEAD')
        self.git('checkout', '-b', 'dev')
        (self.directory / 'source/a').write_text('changed')
        self.git('commit', '-am', 'Change source')
        self.head = self.git('rev-parse', 'HEAD')
        self.manifest = {'components': [{'name': 'example', 'kind': 'source', 'paths': ['source/'], 'context': '.', 'baseline': '0.0.0'}], 'shared_paths': []}
        (self.directory / 'manifest.json').write_text(json.dumps(self.manifest))
        self.event = {'pull_request': {'number': 1, 'html_url': 'https://example.invalid/pr/1',
            'base': {'ref': 'main', 'sha': self.base, 'repo': {'full_name': 'example/repo'}},
            'head': {'ref': 'dev', 'sha': self.head, 'repo': {'full_name': 'example/repo'}},
            'labels': [{'name': 'release=minor'}], 'merged': False}}

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.directory), *args], text=True, stderr=subprocess.DEVNULL).strip()

    def execute(self):
        (self.directory / 'event.json').write_text(json.dumps(self.event))
        environment = os.environ.copy()
        environment.pop('GITHUB_OUTPUT', None)
        return subprocess.run(['python3', str(ROOT / '.github/scripts/release_plan.py'), '--event', 'event.json', '--manifest', 'manifest.json'],
                              cwd=self.directory, env=environment, capture_output=True, text=True)

    def test_preview_and_merged_plan_use_same_increment(self):
        self.assertEqual(self.execute().returncode, 0)
        self.git('checkout', 'main')
        self.git('merge', '--no-ff', 'dev', '-m', 'Promotion')
        self.event['pull_request'].update(merged=True, merge_commit_sha=self.git('rev-parse', 'HEAD'))
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads((self.directory / 'release-plan.json').read_text())
        self.assertEqual(plan['components'][0]['version'], '0.1.0')
        self.git('tag', 'example/v0.1.0')
        self.assertEqual(self.execute().returncode, 0)
        self.assertEqual(json.loads((self.directory / 'release-plan.json').read_text())['components'][0]['version'], '0.1.0')

    def test_squashed_promotion_rejected(self):
        self.git('checkout', 'main')
        self.git('merge', '--squash', 'dev')
        self.git('commit', '-m', 'Squashed promotion')
        self.event['pull_request'].update(merged=True, merge_commit_sha=self.git('rev-parse', 'HEAD'))
        result = self.execute()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('require a merge commit', result.stderr)

    def test_fork_promotion_and_incorrect_checkout_rejected(self):
        self.event['pull_request']['head']['repo']['full_name'] = 'fork/repo'
        self.assertNotEqual(self.execute().returncode, 0)
        self.event['pull_request']['head']['repo']['full_name'] = 'example/repo'
        self.git('checkout', 'main')
        self.assertNotEqual(self.execute().returncode, 0)


if __name__ == '__main__':
    unittest.main()
