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
            if self.release is None or self.release['tag_name'] != url.rsplit('/', 1)[1]:
                raise urllib.error.HTTPError(url, 404, 'missing', {}, None)
            return Response(self.release)
        if method == 'POST' and url.endswith('/releases'):
            self.release = {**data, 'id': 2, 'assets': [], 'html_url': 'https://github.com/example/candidate', 'upload_url': 'https://uploads.github.com/example/assets{?name}'}
            self.release['tag_name'] = 'untagged-candidate'
            return Response(self.release)
        if method == 'GET' and '/releases?' in url:
            return Response([r for r in [self.old, self.release] if r])
        if method == 'PATCH':
            target = self.old if url.endswith('/1') else self.release
            target.update(data)
            if target.get('id') == 2 and target['draft']:
                target['tag_name'] = 'untagged-candidate'
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

    def run_publisher(self, confirmed=False, subject='', event='push'):
        env = {'GITHUB_REPOSITORY': 'ManXiangTAS/classicui.koplugin', 'GITHUB_SHA': 'a' * 40, 'GH_TOKEN': 'fixture-token', 'GITHUB_EVENT_NAME': event, 'RELEASE_COMMIT_MESSAGE': subject}
        if confirmed:
            env['RELEASE_PUBLISH_CONFIRMED'] = '1'
        with patch.dict(os.environ, env, clear=True), patch('sys.argv', ['publish', str(self.assets)]), patch('urllib.request.urlopen', self.request), patch('time.sleep'), contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(ROOT / 'tools/publish_test_release.py'), run_name='__main__')

    def test_push_prepares_draft_and_preserves_previous_releases(self):
        self.run_publisher()
        self.assertTrue(self.release['draft'])
        self.assertFalse(self.old['draft'])
        self.assertEqual(len(self.release['assets']), 3)
        self.assertFalse(any(data and data.get('draft') is False for method, url, data in self.calls if method == 'PATCH'))

    def test_rebuilt_candidate_replaces_assets_while_remaining_a_draft(self):
        self.run_publisher()
        (self.assets / f'ClassicUI_{self.version}_install.zip').write_bytes(b'corrected-candidate')
        self.run_publisher()
        self.assertTrue(self.release['draft'])
        self.assertEqual(len(self.release['assets']), 3)
        self.assertTrue(any(method == 'DELETE' for method, _, _ in self.calls))
        self.assertEqual(sum(method == 'POST' and url.endswith('/releases') for method, url, _ in self.calls), 1)

    def test_only_explicit_confirmation_publishes(self):
        self.run_publisher()
        self.run_publisher(confirmed=True)
        self.assertFalse(self.release['draft'])
        self.assertFalse(self.release['prerelease'])
        self.assertEqual(self.release['tag_name'], 'v' + self.version)
        self.assertTrue(self.old['draft'])

    def test_exact_release_commit_publishes_the_matching_version(self):
        self.run_publisher(subject='Release ClassicUI ' + self.version)
        self.assertFalse(self.release['draft'])
        self.assertEqual(self.release['tag_name'], 'v' + self.version)

    def test_other_versions_and_unrelated_events_do_not_publish(self):
        self.run_publisher(subject='Release ClassicUI 99.0.0')
        self.assertTrue(self.release['draft'])
        self.run_publisher(subject='Release ClassicUI ' + self.version, event='workflow_dispatch')
        self.assertTrue(self.release['draft'])


    def test_candidate_does_not_hide_existing_stable_release(self):
        self.run_publisher()
        self.assertFalse(self.old['draft'])
        self.assertFalse(any(method=='PATCH' and url.endswith('/1') for method,url,data in self.calls))

    def test_failed_publication_keeps_existing_stable_visible(self):
        original=self.request
        def failing(req,**kwargs):
            if req.method=='PATCH' and req.headers.get('Content-type')=='application/json':
                data=json.loads(req.data)
                if data.get('draft') is False:
                    raise urllib.error.HTTPError(req.full_url,503,'unavailable',{},None)
            return original(req,**kwargs)
        with patch.object(self,'request',failing):
            with self.assertRaises(urllib.error.HTTPError): self.run_publisher(confirmed=True)
        self.assertFalse(self.old['draft'])

    def test_previous_release_is_hidden_only_after_new_publication(self):
        self.run_publisher(confirmed=True)
        published=next(i for i,(m,u,d) in enumerate(self.calls) if m=='PATCH' and d and d.get('draft') is False)
        hidden=next(i for i,(m,u,d) in enumerate(self.calls) if m=='PATCH' and u.endswith('/1') and d and d.get('draft') is True)
        self.assertLess(published,hidden)


if __name__ == '__main__':
    unittest.main()
