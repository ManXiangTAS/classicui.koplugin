from pathlib import Path
from PIL import Image
import os,sys,subprocess,tempfile,shutil,json,hashlib
p=Path(__file__).resolve().parents[1];r=Path(sys.argv[1]).resolve();out=p/'test-results-051';(out/'data').mkdir(parents=True,exist_ok=True)
results=[]
for variant,w,h,dpi,tz in [('desktop',600,800,160,'UTC'),('voyage',1072,1448,300,'Asia/Shanghai'),('landscape',1448,1072,300,'America/New_York')]:
 state=Path(tempfile.mkdtemp(prefix=variant+'-',dir=out/'data'));books=state/'books';books.mkdir()
 for name in ['A.epub','B.epub']:shutil.copyfile(p/'tests/fixtures'/name,books/name)
 shutil.copyfile(p/'tests/navigation/chapters.epub',books/'navigation.epub');shutil.copyfile(p/'tests/pdf/layout.pdf',books/'sample.pdf')
 hashes={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in books.iterdir()}
 env=os.environ.copy();env.update(KO_HOME=str(state),EINK_PROJECT=str(p),EINK_030_BOOKS=str(books),EINK_VARIANT=variant,TZ=tz,SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',EMULATE_READER_W=str(w),EMULATE_READER_H=str(h),EMULATE_READER_DPI=str(dpi))
 log=out/f'regression-{variant}.log'
 with log.open('w') as f:proc=subprocess.run([str(r/'luajit'),str(p/'tests/transfer051.lua')],cwd=r,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=120)
 if proc.returncode:print(log.read_text()[-7000:]);raise SystemExit('FAIL '+variant)
 report=json.loads((out/f'regression-{variant}.json').read_text());results.append(report)
 assert hashes=={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in books.iterdir() if f.is_file()}
 print('PASS',variant,len(report['tests']),'checks',flush=True)
summary={'version':'0.5.0-test.1','failures':0,'checks':sum(len(v['tests']) for v in results),'distinct_cases':len({t['name'] for v in results for t in v['tests']}),'runs':len(results),'pixel_frames':len(list(out.glob('*.png'))),'device':'NOT_RUN','results':results}
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n');print({k:v for k,v in summary.items() if k!='results'})
