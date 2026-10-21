#!/usr/bin/env python3
"""Real-runtime fault injection for 0.3.9; only isolated fixture/config writes."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,tempfile
project=Path(__file__).resolve().parents[1];runtime=Path(sys.argv[1]).resolve();output=project/'test-results-039'
(output/'data').mkdir(parents=True,exist_ok=True);results=[]
for variant,w,h,dpi in [('desktop',600,800,160),('voyage_layout',1072,1448,300),('landscape',1448,1072,300)]:
 state=Path(tempfile.mkdtemp(prefix=variant+'-',dir=output/'data'));books=state/'books';books.mkdir()
 shutil.copyfile(project/'tests/fixtures/A.epub',books/'A.epub')
 before=hashlib.sha256((books/'A.epub').read_bytes()).hexdigest()
 env=os.environ.copy();env.update(KO_HOME=str(state),EINK_PROJECT=str(project),EINK_039_BOOKS=str(books),EINK_VARIANT=variant,
  SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',EMULATE_READER_W=str(w),EMULATE_READER_H=str(h),EMULATE_READER_DPI=str(dpi))
 log=output/f'regression039-{variant}.log'
 with log.open('w') as f:process=subprocess.run([str(runtime/'luajit'),str(project/'tests/regression039.lua')],cwd=runtime,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=90)
 if process.returncode:print(log.read_text()[-9000:]);raise SystemExit(f'FAIL {variant}')
 r=json.loads((output/f'regression039-{variant}.json').read_text());assert all(t['status']=='PASS' for t in r['tests'])
 assert hashlib.sha256((books/'A.epub').read_bytes()).hexdigest()==before
 results.append(r);print(f'PASS {variant}: {len(r["tests"])} checks',flush=True)
summary={'version':'0.3.9-dev','runs':len(results),'checks':sum(len(r['tests']) for r in results),'distinct_cases':len({t['name'] for r in results for t in r['tests']}),'failures':0,'fixtures_unchanged':True,'device':'NOT_RUN','results':results}
(output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k!='results'},ensure_ascii=False,indent=2))
