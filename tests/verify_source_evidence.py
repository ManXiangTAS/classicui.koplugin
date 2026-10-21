#!/usr/bin/env python3
"""Verify static source evidence. Does not run KOReader or test a plugin."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

manifest = json.loads((Path(__file__).resolve().parents[1] / 'docs/source_evidence.json').read_text())
source = Path(sys.argv[1]).resolve()
commit = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
if commit != manifest['commit']:
    raise SystemExit('FAIL: source commit differs from audited baseline')
count = 0
for item in manifest['evidence']:
    raw = (source / item['path']).read_bytes()
    if hashlib.sha256(raw).hexdigest() != item['sha256']:
        raise SystemExit('FAIL: content hash differs: ' + item['path'])
    lines = raw.decode().splitlines()
    for entry in item['anchors']:
        if entry['anchor'] not in lines[entry['line'] - 1]:
            raise SystemExit('FAIL: anchor differs: ' + item['path'])
        count += 1
print(json.dumps({'static_evidence': 'PASS', 'files': len(manifest['evidence']),
                  'anchors': count, 'commit': commit,
                  'runtime_tests': 'NOT_EXECUTED_BY_THIS_STATIC_CHECK'}))
