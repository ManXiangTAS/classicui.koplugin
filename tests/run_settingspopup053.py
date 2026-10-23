"""Test the settings-root popover in the actual KOReader runtime."""
from pathlib import Path
import hashlib, json, os, shutil, subprocess, sys, tempfile

project=Path(__file__).resolve().parents[1];runtime=Path(sys.argv[1]).resolve()
output=project/'test-results-053';(output/'data').mkdir(parents=True,exist_ok=True)
results=[]
for variant,width,height,dpi in [('desktop',600,800,160),('voyage',1072,1448,300),('landscape',1448,1072,300)]:
    state=Path(tempfile.mkdtemp(prefix=variant+'-',dir=output/'data'));books=state/'books';books.mkdir()
    shutil.copyfile(project/'tests/navigation/chapters.epub',books/'navigation.epub')
    before=hashlib.sha256((books/'navigation.epub').read_bytes()).hexdigest()
    env=dict(os.environ,KO_HOME=str(state),EINK_PROJECT=str(project),EINK_030_BOOKS=str(books),EINK_VARIANT=variant,
             SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',
             EMULATE_READER_W=str(width),EMULATE_READER_H=str(height),EMULATE_READER_DPI=str(dpi))
    log=output/f'settings-popup-{variant}.log'
    with log.open('w') as f:
        proc=subprocess.run([str(runtime/'luajit'),str(project/'tests/settingspopup053.lua')],cwd=runtime,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=90)
    if proc.returncode:
        print(log.read_text()[-6000:]);raise SystemExit('FAIL '+variant)
    results.append(json.loads((output/f'settings-popup-{variant}.json').read_text()))
    assert hashlib.sha256((books/'navigation.epub').read_bytes()).hexdigest()==before
    print('PASS',variant,len(results[-1]['tests']),'checks',flush=True)
summary={'failures':0,'checks':sum(len(r['tests']) for r in results),'distinct_cases':len({t['name'] for r in results for t in r['tests']}),
         'runs':len(results),'device':'NOT_RUN','runtime_revision':(runtime/'git-rev').read_text().strip(),'results':results}
(output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print({k:v for k,v in summary.items() if k!='results'})
