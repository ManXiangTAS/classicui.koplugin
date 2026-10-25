#!/usr/bin/env python3
"""Compare public release downloads with the exact locally rebuilt artifacts."""
from pathlib import Path
import hashlib
import io
import json
import os
import sys
import urllib.error
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from build_public_release import VERSION

BASE = 'https://api.github.com/repos/ManXiangTAS/classicui.koplugin'


def get(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'ClassicUI-verify'})
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()


def verify(directory, optional=False):
    try:
        release = json.loads(get(BASE + '/releases/tags/v' + VERSION))
    except urllib.error.HTTPError as error:
        if error.code == 404 and optional:
            print('No public release for this version; candidate verification skipped.')
            return
        raise
    assert not release['draft'] and not release['prerelease']
    expected_commit = os.environ.get('EXPECTED_RELEASE_COMMIT')
    if expected_commit:
        tag = json.loads(get(BASE + '/git/ref/tags/v' + VERSION))['object']
        if tag['type'] == 'tag':
            tag = json.loads(get(tag['url']))['object']
        assert tag['type'] == 'commit' and tag['sha'] == expected_commit, 'Release tag source mismatch'
    assets = {asset['name']: asset for asset in release['assets']}
    for name in [f'ClassicUI_{VERSION}_{kind}.zip' for kind in ('install', 'source')] + ['SHA256SUMS.txt']:
        asset = assets[name]
        data = get(asset['browser_download_url'])
        digest = hashlib.sha256(data).hexdigest()
        assert asset['digest'] == 'sha256:' + digest, 'GitHub asset digest mismatch: ' + name
        assert data == (Path(directory) / name).read_bytes(), 'Rebuilt artifact mismatch: ' + name
        if name.endswith('.zip'):
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                assert archive.testzip() is None
                manifest = json.loads(archive.read('SHA256.json'))
                assert set(manifest) == set(archive.namelist()) - {'SHA256.json'}
                for path, expected in manifest.items():
                    assert hashlib.sha256(archive.read(path)).hexdigest() == expected, path
                meta = archive.read('einkfrontend.koplugin/_meta.lua').decode('utf-8')
                assert '墨页' in meta and '\ufffd' not in meta
                print(f'{name}: verified {len(archive.namelist())} exact entries; SHA256 {digest}')
        else:
            print(name + ': exact bytes verified')


if __name__ == '__main__':
    verify(sys.argv[1], '--optional' in sys.argv[2:])
