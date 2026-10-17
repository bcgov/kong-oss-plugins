#!/usr/bin/env python3
"""Publish component release notes and verified receipts after artifact jobs succeed."""
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import urllib.error
import urllib.request


def api(path, payload=None, method=None):
    request = urllib.request.Request('https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY'] + path,
                                    data=json.dumps(payload).encode() if payload is not None else None,
                                    method=method,
                                    headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                                             'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def main():
    plan = json.loads(Path('release-plan.json').read_text())
    assets = Path('release-assets')
    assets.mkdir(exist_ok=True)
    for component in plan['components']:
        name, tag = component['name'], component['tag']
        files = []
        if component['kind'] == 'source':
            archive = assets / f"{name}-{component['version']}.tar.gz"
            subprocess.run(['git', 'archive', '--format=tar.gz', '--prefix=' + name + '/',
                            '-o', str(archive), plan['sha']], check=True)
            receipt = {'component': name, 'revision': plan['sha'],
                       'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}
            receipt_path = assets / (name + '.json')
            receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
            files.append(archive)
        else:
            receipt_path = assets / (name + '.json')
            receipt = json.loads(receipt_path.read_text())
            if receipt['revision'] != plan['sha'] or receipt['component'] != name:
                raise ValueError('Artifact identity differs from planned release')
            if not re.fullmatch(r'sha256:[0-9a-f]{64}', receipt.get('digest', '')):
                raise ValueError('Artifact digest is missing or invalid')
            if component['kind'] == 'image' and not receipt['image'].endswith(':v' + component['version']):
                raise ValueError('Artifact image version differs from planned release')
            if component['kind'] == 'chart':
                files.append(assets / f"{name}-{component['version']}.tgz")
        files.append(receipt_path)
        revision_range = (component['previous'] + '..' if component['previous'] else '') + plan['sha']
        changes = subprocess.check_output(['git', 'log', '--format=- %s (%h)', revision_range, '--',
                                           *component['paths']], text=True).strip()
        body = (f"Promotion: {plan['url']}\n\nSource commit: `{plan['sha']}`\n\n"
                f"## Changes\n{changes or 'Shared build/release dependency update.'}\n\n"
                f"## Artifact identity\n```json\n{json.dumps(receipt, indent=2)}\n```\n")
        # Draft releases are not returned by the public tag endpoint. Include them
        # when resuming an interrupted publication, rather than creating duplicates.
        existing = None
        page = 1
        while True:
            releases = api(f'/releases?per_page=100&page={page}')
            existing = next((r for r in releases if r['tag_name'] == tag), None)
            if existing or len(releases) < 100:
                break
            page += 1
        if existing and not existing['draft']:
            # Never amend a published release on retry; verify its immutable tag.
            commit = api('/commits/' + tag)['sha']
            if commit != plan['sha']:
                raise ValueError('Existing release tag points at a different commit')
            print('Already published:', tag)
            continue
        # An orphaned tag must also point at this exact commit.
        try:
            tagged_commit = api('/commits/' + tag)['sha']
        except urllib.error.HTTPError as error:
            if error.code not in (404, 422):
                raise
        else:
            if tagged_commit != plan['sha']:
                raise ValueError('Existing tag points at a different commit')
        release = existing or api('/releases', {'tag_name': tag, 'target_commitish': plan['sha'],
                                                 'name': tag, 'draft': True, 'body': body})
        if release['target_commitish'] != plan['sha']:
            raise ValueError('Draft release belongs to a different commit')
        notes = assets / (name + '-notes.md')
        notes.write_text(body)
        # Uploads happen only to drafts; a failed upload can be resumed safely.
        subprocess.run(['gh', 'release', 'upload', tag, *map(str, files), '--clobber'], check=True)
        api('/releases/' + str(release['id']), {'body': body, 'draft': False, 'make_latest': 'false'}, 'PATCH')
        print('Published:', tag)


if __name__ == '__main__':
    main()
