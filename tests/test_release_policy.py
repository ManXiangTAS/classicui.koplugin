#!/usr/bin/env python3
"""Exercise the publisher against an in-memory GitHub API, without network."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import runpy
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class Response(io.BytesIO):
    def __init__(self, body=None, status=200):
        super().__init__(json.dumps(body).encode() if status != 204 else b'')
        self.status = status


class ReleasePolicy(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.assets = Path(self.directory.name)
        self.version = (ROOT / 'einkfrontend.koplugin/einkfrontend/version.lua').read_text().split("'")[1]
        for kind in ('install', 'source'):
            (self.assets / f'ClassicUI_{self.version}_{kind}.zip').write_bytes(kind.encode())
        self.release = None
        self.old = {'id': 1, 'tag_name': 'v0.6.3', 'draft': False}
        self.calls = []

    def request(self, req, **kwargs):
        method, url = req.get_method(), req.full_url
        data = json.loads(req.data) if req.data and req.headers.get('Content-type') == 'application/json' else None
        self.calls.append((method, url, data))
        if '/releases/tags/' in url:
            if self.release is None:
                raise urllib.error.HTTPError(url, 404, 'missing', {}, None)
            return Response(self.release)
        if method == 'POST' and url.endswith('/releases'):
            self.release = {**data, 'id': 2, 'assets': [], 'html_url': 'https://github.com/example/candidate', 'upload_url': 'https://uploads.github.com/example/assets{?name}'}
            return Response(self.release)
        if method == 'GET' and '/releases?' in url:
            return Response([self.old, self.release])
        if method == 'PATCH':
            target = self.old if url.endswith('/1') else self.release
            target.update(data)
            return Response(target)
        if method == 'DELETE':
            asset_id = int(url.rsplit('/', 1)[1])
            self.release['assets'] = [a for a in self.release['assets'] if a['id'] != asset_id]
            return Response(status=204)
        if method == 'POST' and url.startswith('https://uploads.github.com/'):
            asset = {'id': len(self.calls), 'name': url.split('name=')[1], 'size': len(req.data), 'digest': 'sha256:' + hashlib.sha256(req.data).hexdigest()}
            self.release['assets'].append(asset)
            return Response(asset)
        raise AssertionError((method, url))

    def run_publisher(self, confirmed=False):
        env = {'GITHUB_REPOSITORY': 'ManXiangTAS/classicui.koplugin', 'GITHUB_SHA': 'a' * 40, 'GH_TOKEN': 'fixture-token'}
        if confirmed:
            env['RELEASE_PUBLISH_CONFIRMED'] = '1'
        with patch.dict(os.environ, env, clear=True), patch('sys.argv', ['publish', str(self.assets)]), patch('urllib.request.urlopen', self.request), patch('time.sleep'), contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(ROOT / 'tools/publish_test_release.py'), run_name='__main__')

    def test_push_prepares_draft_and_hides_previous_releases(self):
        self.run_publisher()
        self.assertTrue(self.release['draft'])
        self.assertTrue(self.old['draft'])
        self.assertEqual(len(self.release['assets']), 3)
        self.assertFalse(any(data and data.get('draft') is False for method, url, data in self.calls if method == 'PATCH'))

    def test_rebuilt_candidate_replaces_assets_while_remaining_a_draft(self):
        self.run_publisher()
        (self.assets / f'ClassicUI_{self.version}_install.zip').write_bytes(b'corrected-candidate')
        self.run_publisher()
        self.assertTrue(self.release['draft'])
        self.assertEqual(len(self.release['assets']), 3)
        self.assertTrue(any(method == 'DELETE' for method, _, _ in self.calls))

    def test_only_explicit_confirmation_publishes(self):
        self.run_publisher()
        self.run_publisher(confirmed=True)
        self.assertFalse(self.release['draft'])
        self.assertFalse(self.release['prerelease'])
        self.assertTrue(self.old['draft'])


if __name__ == '__main__':
    unittest.main()
