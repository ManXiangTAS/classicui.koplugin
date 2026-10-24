#!/usr/bin/env python3
"""Run maintained regression suites in an isolated KOReader emulator."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,tempfile
p=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('runtime',type=Path);parser.add_argument('--suite',choices=['core','interaction','offline','input','native_widgets','home','wallpaper','settings','autolight']);args=parser.parse_args();r=args.runtime.resolve()
assert (r/'plugins/einkfrontend.koplugin').resolve()==p/'einkfrontend.koplugin','Point the runtime plugin symlink at this checkout'
out=p/'test-results';out.mkdir(exist_ok=True);results=[]
for suite in ([args.suite] if args.suite else ['core','interaction','offline','input','native_widgets','home','wallpaper','settings','autolight']):
 for variant,w,h,dpi in [('desktop',600,800,160),('voyage',1072,1448,300),('landscape',1448,1072,300)]:
  target=out/suite/variant;target.mkdir(parents=True,exist_ok=True);state=Path(tempfile.mkdtemp(prefix='state-',dir=target));books=state/'books';books.mkdir()
  for name in ['A.epub','B.epub','navigation.epub']:shutil.copyfile(p/'tests/fixtures'/name,books/name)
  hashes={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in books.glob('*.epub')}
  actual=r;plugin=p/'einkfrontend.koplugin'
  if suite=='offline':
   plugin=state/'einkfrontend.koplugin';shutil.copytree(p/'einkfrontend.koplugin',plugin);actual=state/'runtime';shutil.copytree(r,actual,copy_function=os.link,symlinks=True)
   link=actual/'plugins/einkfrontend.koplugin';link.unlink();link.symlink_to(plugin,target_is_directory=True)
  env=dict(os.environ,KO_HOME=str(state),EINK_PROJECT=str(p),EINK_030_BOOKS=str(books),EINK_VARIANT=variant,EINK_PLUGIN_ROOT=str(plugin),EINK_TEST_OUTPUT=str(target),
           SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',EMULATE_READER_W=str(w),EMULATE_READER_H=str(h),EMULATE_READER_DPI=str(dpi))
  log=target/'runtime.log'
  with log.open('w') as f:proc=subprocess.run([str(actual/'luajit'),str(p/'tests'/('test_'+suite+'.lua'))],cwd=actual,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=150)
  if proc.returncode:print(log.read_text()[-6500:]);raise SystemExit('FAIL '+suite+'/'+variant)
  reports=[json.loads(f.read_text()) for f in target.glob('*.json')];report=next(d for d in reports if 'tests' in d)
  assert all(t['status']=='PASS' for t in report['tests']);assert hashes=={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in books.glob('*.epub')}
  results.append({'suite':suite,**report});print('PASS',suite,variant,len(report['tests']),'checks',flush=True)
summary={'failures':0,'checks':sum(len(r['tests']) for r in results),'runs':len(results),'distinct_cases':len({t['name'] for r in results for t in r['tests']}),'physical_device':'NOT_RUN','results':results}
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n');print({k:v for k,v in summary.items() if k!='results'})
