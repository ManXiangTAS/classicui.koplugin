#!/usr/bin/env python3
"""Run real KOReader modules from an extracted official Linux AppImage.

Usage: python3 tests/run_tests.py /absolute/path/to/usr/lib/koreader
Uses only test-owned KO_HOME directories. Does not install onto an e-reader.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import tempfile

project=Path(__file__).resolve().parents[1]
runtime=Path(sys.argv[1]).resolve()
output=project/'test-results'
output.mkdir(exist_ok=True)
plugin=runtime/'plugins/einkfrontend.koplugin'
if plugin.is_symlink():
    assert plugin.resolve()==project/'einkfrontend.koplugin', 'Runtime contains another plugin'
elif plugin.exists():
    raise SystemExit('Use a clean extracted runtime; refusing to replace an existing plugin')
else:
    plugin.symlink_to(project/'einkfrontend.koplugin',target_is_directory=True)

fixtures=list((project/'tests').rglob('*.epub'))
before={str(p.relative_to(project)):hashlib.sha256(p.read_bytes()).hexdigest() for p in fixtures}
for old in output.glob('*.json'):
    old.unlink()
results=[]
variants=[('desktop',600,800,160,['write','restart','faults','library','references','references_restart','reader_actions','pdf','embedded','embedded_restart','auto_start','stress_flow','disable','native_restart','uninstalled']),
          ('voyage_layout',1072,1448,300,['write','restart','library','references','references_restart','auto_start']),
          ('landscape',1448,1072,300,['library','references','references_restart','auto_start'])]
for variant,width,height,dpi,modes in variants:
    # Never inherit a prior run's .old settings or return stack.
    (output/'data').mkdir(exist_ok=True)
    state=Path(tempfile.mkdtemp(prefix=variant+'-',dir=output/'data'))
    stress=state/'stress-books'
    if variant=='desktop':
        stress.mkdir()
        for i in range(120):shutil.copyfile(project/'tests/fixtures/B.epub',stress/f'book{i:03}.epub')
    env=os.environ.copy()
    env.update(KO_HOME=str(state),EINK_PROJECT=str(project),EINK_VARIANT=variant,
               SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',
               EMULATE_READER_W=str(width),EMULATE_READER_H=str(height),EMULATE_READER_DPI=str(dpi))
    env['EINK_STRESS_ROOT']=str(stress)
    for mode in modes:
        disabled=plugin.with_name('einkfrontend.disabled-for-test')
        if mode=='uninstalled':plugin.rename(disabled)
        log=output/f'{mode}-{variant}.log'
        started=time.monotonic()
        try:
            with log.open('w') as f:
                process=subprocess.run([str(runtime/'luajit'),str(project/'tests/integration.lua'),mode],
                    cwd=runtime,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=90)
        finally:
            if mode=='uninstalled' and disabled.exists():disabled.rename(plugin)
        if process.returncode:
            print(log.read_text()[-6000:])
            raise SystemExit(f'FAIL: {variant} / {mode}: exit {process.returncode}')
        assert 'Home reading snapshot:' not in log.read_text(), f'Home snapshot error: {variant}/{mode}'
        report=json.loads((output/f'{mode}-{variant}.json').read_text())
        assert all(t['status']=='PASS' for t in report['tests'])
        report['seconds']=round(time.monotonic()-started,3)
        results.append(report)
        print(f"PASS {variant}/{mode}: {len(report['tests'])} checks",flush=True)

after={str(p.relative_to(project)):hashlib.sha256(p.read_bytes()).hexdigest() for p in fixtures}
assert before==after,'Fixture EPUB bytes changed during tests'
summary={'runs':len(results),'checks':sum(len(r['tests']) for r in results),
         'failures':0,'fixture_epub_unchanged':True,'fixture_sha256':after,
         'runtime_revision':(runtime/'git-rev').read_text().strip(),
         'source_commit':'9192014d8bd82a91dc1012473be0f238dedfdb54',
         'device':'NOT_RUN','display_backend':'SDL3 dummy (real KOReader widgets and engines)',
         'results':results}
(output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k!='results'},ensure_ascii=False,indent=2))
