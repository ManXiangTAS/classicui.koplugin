from pathlib import Path
import json,os,tempfile,shutil,subprocess,sys,hashlib
p=Path(__file__).resolve().parents[1];runtime=Path(sys.argv[1]).resolve();out=p/'test-results-045';(out/'data').mkdir(parents=True,exist_ok=True);results=[]
for variant,w,h,dpi in [('desktop',600,800,160),('voyage',1072,1448,300),('landscape',1448,1072,300)]:
 state=Path(tempfile.mkdtemp(prefix=variant+'-',dir=out/'data'));books=state/'books';books.mkdir()
 shutil.copyfile(p/'tests/fixtures/A.epub',books/'A.epub');before=hashlib.sha256((books/'A.epub').read_bytes()).hexdigest()
 env=os.environ.copy();env.update(KO_HOME=str(state),EINK_PROJECT=str(p),EINK_030_BOOKS=str(books),EINK_VARIANT=variant,TZ='UTC',SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',EMULATE_READER_W=str(w),EMULATE_READER_H=str(h),EMULATE_READER_DPI=str(dpi))
 for mode in ['clock','restart']:
  log=out/f'{mode}-{variant}.log'
  with log.open('w') as f:run=subprocess.run([str(runtime/'luajit'),str(p/'tests/clock045.lua'),mode],cwd=runtime,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=90)
  if run.returncode:print(log.read_text()[-9000:]);raise SystemExit('FAIL '+variant+'/'+mode)
  r=json.loads((out/f'{mode}-{variant}.json').read_text());assert all(t['status']=='PASS' for t in r['tests']);results.append(r);print('PASS',variant,mode,len(r['tests']),flush=True)
 assert before==hashlib.sha256((books/'A.epub').read_bytes()).hexdigest()
summary={'version':'0.3.14-dev','checks':sum(len(r['tests']) for r in results),'cases':len({t['name'] for r in results for t in r['tests']}),'runs':len(results),'failures':0,'device':'NOT_RUN','network_sync':'Native callback mocked; actual clock/RTC/network not mutated','results':results}
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n');print({k:v for k,v in summary.items() if k!='results'})
