#!/usr/bin/env python3
"""Plan component releases without publishing; tags are the version ledger."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def increment(version, bump):
    parts = list(map(int, version.split('.')))
    index = {'major': 0, 'minor': 1, 'patch': 2}[bump]
    parts[index] += 1
    for i in range(index + 1, 3):
        parts[i] = 0
    return '.'.join(map(str, parts))


def release_bump(labels):
    labels = [x['name'] if isinstance(x, dict) else x for x in labels]
    values = [x for x in labels if x.startswith('release=')]
    if len(values) != 1 or values[0] not in ('release=major', 'release=minor', 'release=patch'):
        raise ValueError('Exactly one release=major, release=minor or release=patch label is required')
    return values[0].split('=')[1]


def version_for(component, tags, target, resolve, bump):
    prefix = component['name'] + '/v'
    versions = []
    for tag in tags:
        if tag.startswith(prefix) and re.fullmatch(r'\d+\.\d+\.\d+', tag[len(prefix):]):
            versions.append((tuple(map(int, tag[len(prefix):].split('.'))), tag))
    # Re-running the same promotion must retain its reserved/released version.
    same = [(v, tag) for v, tag in versions if resolve(tag) == target]
    if len(same) > 1:
        raise ValueError(f"Multiple versions for {component['name']} at {target}")
    previous = sorted((v, t) for v, t in versions if resolve(t) != target and (not same or v < same[0][0]))
    if same:
        version = '.'.join(map(str, same[0][0]))
    else:
        current = '.'.join(map(str, previous[-1][0])) if previous else component['baseline']
        version = increment(current, bump)
    return version, previous[-1][1] if previous else None


def affected(component, changed, shared):
    return any(any(p.startswith(root) for root in component['paths'] + shared) for p in changed)


def plan(manifest, changed, tags, target, resolve, bump):
    selected = [c for c in manifest['components'] if affected(c, changed, manifest['shared_paths'])]
    # A new edge image must also be packaged into a compatible chart release.
    if any(c['name'] == 'sdx-access-point' for c in selected):
        selected += [c for c in manifest['components'] if c['kind'] == 'chart' and c not in selected]
    result = []
    for component in selected:
        version, previous = version_for(component, tags, target, resolve, bump)
        item = dict(component, version=version, tag=f"{component['name']}/v{version}", previous=previous)
        item.setdefault('file', item['context'] + '/Dockerfile')
        result.append(item)
    return {'sha': target, 'components': result}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--event', default=os.environ.get('GITHUB_EVENT_PATH'))
    parser.add_argument('--manifest', default='.github/release/components.json')
    parser.add_argument('--output', default='release-plan.json')
    args = parser.parse_args()
    event = json.loads(Path(args.event).read_text())
    pr = event['pull_request']
    if pr['base']['ref'] != 'main' or pr['head']['ref'] != 'dev':
        raise ValueError('Only dev -> main promotion PRs may release')
    if pr['head']['repo']['full_name'] != pr['base']['repo']['full_name']:
        raise ValueError('Promotion must originate in this repository')
    bump = release_bump(pr['labels'])
    merged = pr.get('merged', False)
    target = pr['merge_commit_sha'] if merged else pr['head']['sha']
    if git('rev-parse', 'HEAD') != target:
        raise ValueError('Checkout must match the exact promotion head/merge commit')
    # The first parent of the merge is the exact pre-promotion main commit.
    # Reject squash/rebase promotions to keep dev/main ancestry and retry ranges reliable.
    if merged:
        parents = git('rev-list', '--parents', '-n', '1', target).split()[1:]
        if len(parents) != 2 or parents[1] != pr['head']['sha']:
            raise ValueError('dev -> main promotions require a merge commit (not squash/rebase)')
        base = parents[0]
    else:
        base = git('merge-base', pr['base']['sha'], target)
    changed = git('diff', '--name-only', base, target).splitlines()
    tags = git('tag', '--list').splitlines()
    result = plan(json.loads(Path(args.manifest).read_text()), changed, tags, target,
                  lambda t: git('rev-parse', t + '^{commit}'), bump)
    for component in result['components']:
        if component['previous']:
            subprocess.run(['git', 'merge-base', '--is-ancestor', component['previous'], target], check=True)
    result['pr'] = pr['number']
    result['url'] = pr['html_url']
    Path(args.output).write_text(json.dumps(result, indent=2) + '\n')
    images = [c for c in result['components'] if c['kind'] == 'image']
    charts = [c for c in result['components'] if c['kind'] == 'chart']
    outputs = {'images': json.dumps({'include': images}), 'has_images': str(bool(images)).lower(),
               'has_chart': str(bool(charts)).lower(), 'has_components': str(bool(result['components'])).lower(),
               'chart_version': charts[0]['version'] if charts else '',
               'edge_version': next((c['version'] for c in images if c['name'] == 'sdx-access-point'), '')}
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            for key, value in outputs.items():
                stream.write(f'{key}={value}\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
