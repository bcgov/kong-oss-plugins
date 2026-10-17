import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_plan', ROOT / '.github/scripts/release_plan.py')
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)


class ReleasePlanTests(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((ROOT / '.github/release/components.json').read_text())

    def test_increment_resets_lower_segments(self):
        for bump, expected in [('major', '3.0.0'), ('minor', '2.4.0'), ('patch', '2.3.5')]:
            self.assertEqual(planner.increment('2.3.4', bump), expected)

    def test_exactly_one_valid_label(self):
        for labels in [[], ['release=patch', 'release=minor'], ['release=banana']]:
            with self.assertRaises(ValueError):
                planner.release_bump(labels)
        self.assertEqual(planner.release_bump([{'name': 'release=minor'}, {'name': 'bug'}]), 'minor')

    def test_version_ledger_is_component_scoped_and_semver_sorted(self):
        component = {'name': 'example', 'baseline': '0.0.0'}
        tags = ['v9.0.0', 'example/v1.9.0', 'example/v1.10.0', 'other/v99.0.0', 'example/v2.0.0-rc.1']
        self.assertEqual(planner.version_for(component, tags, 'new', lambda _: 'old', 'patch'), ('1.10.1', 'example/v1.10.0'))

    def test_retry_retains_version_for_commit(self):
        component = {'name': 'example', 'baseline': '0.0.0'}
        tags = ['example/v1.0.0', 'example/v1.1.0']
        self.assertEqual(planner.version_for(component, tags, 'same', lambda t: 'same' if t.endswith('1.1.0') else 'old', 'minor'), ('1.1.0', 'example/v1.0.0'))

    def test_duplicate_release_versions_for_commit_rejected(self):
        with self.assertRaises(ValueError):
            planner.version_for({'name': 'example', 'baseline': '0.0.0'},
                                ['example/v1.0.0', 'example/v1.1.0'], 'same', lambda _: 'same', 'patch')

    def test_unrelated_files_do_not_release(self):
        result = planner.plan(self.manifest, ['notes/unrelated.md'], [], 'new', lambda _: 'old', 'patch')
        self.assertEqual(result['components'], [])

    def test_shared_workflow_releases_all_consumers(self):
        result = planner.plan(self.manifest, ['.github/workflows/release.yaml'], [], 'new', lambda _: 'old', 'patch')
        self.assertEqual(len(result['components']), len(self.manifest['components']))

    def test_component_source_changes_are_isolated(self):
        component = self.manifest['components'][0]
        result = planner.plan(self.manifest, [component['paths'][0] + '/changed'], [], 'new', lambda _: 'old', 'patch')
        self.assertEqual([c['name'] for c in result['components']], [component['name']])

    def test_edge_image_includes_chart(self):
        if not any(c['name'] == 'sdx-access-point' for c in self.manifest['components']):
            self.skipTest('No edge chart in this repository')
        result = planner.plan(self.manifest, ['sdx/image/Dockerfile'], [], 'new', lambda _: 'old', 'patch')
        self.assertEqual([c['name'] for c in result['components']], ['sdx-access-point', 'sdx-edge'])
        self.assertEqual(result['components'][1]['version'], '0.3.12')


if __name__ == '__main__':
    unittest.main()
