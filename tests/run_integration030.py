#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,time,tempfile
project=Path(__file__).resolve().parents[1];runtime=Path(sys.argv[1]).resolve();output=project/'test-results-030';output.mkdir(exist_ok=True)
results=[]
for variant,w,h,dpi in [('desktop',600,800,160),('voyage_layout',1072,1448,300),('landscape',1448,1072,300)]:
 (output/'data').mkdir(exist_ok=True)
 state=Path(tempfile.mkdtemp(prefix=variant+'-',dir=output/'data'))
 books=state/'books';books.mkdir(parents=True)
 for name in ['A.epub','B.epub']:shutil.copyfile(project/'tests/fixtures'/name,books/name)
 shutil.copyfile(project/'tests/pdf/layout.pdf',books/'sample.pdf')
 before={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in books.iterdir() if p.is_file()}
 env=os.environ.copy();env.update(KO_HOME=str(state),EINK_PROJECT=str(project),EINK_030_BOOKS=str(books),EINK_VARIANT=variant,SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',EMULATE_READER_W=str(w),EMULATE_READER_H=str(h),EMULATE_READER_DPI=str(dpi))
 for mode in ['catalog','typography','restart','pdf','library_navigation','style_navigation','fixes033','fixes033_restart','navigation034','navigation034_restart','navigation034_pdf','home034','regression035','regression035_restart','regression036','regression037','regression037_restart','home_widgets','home_widgets_restart','notice_transitions']:
  if mode=='navigation034':
   navigation=books/'navigation.epub';shutil.copyfile(project/'tests/navigation/chapters.epub',navigation)
   before[navigation.name]=hashlib.sha256(navigation.read_bytes()).hexdigest()
  log=output/f'{mode}-{variant}.log';start=time.monotonic()
  with log.open('w') as f:p=subprocess.run([str(runtime/'luajit'),str(project/'tests/integration030.lua'),mode],cwd=runtime,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=90)
  if p.returncode:print(log.read_text()[-7000:]);raise SystemExit(f'FAIL {variant}/{mode}')
  assert 'Home reading snapshot:' not in log.read_text(), f'Home snapshot error: {variant}/{mode}'
  r=json.loads((output/f'{mode}-{variant}.json').read_text());assert all(t['status']=='PASS' for t in r['tests']);r['seconds']=round(time.monotonic()-start,3);results.append(r);print(f'PASS {variant}/{mode}: {len(r["tests"])} checks',flush=True)
 image_a=output/f'overlap-layout-036-{variant}.png';image_b=output/f'overlap-layout-clean-036-{variant}.png'
 assert image_a.read_bytes()==image_b.read_bytes(), f'Old panel pixels remain after shrinking: {variant}'
 after={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in books.iterdir() if p.is_file()};assert before==after
summary={'version':'0.3.14-dev','runs':len(results),'checks':sum(len(r['tests']) for r in results),'distinct_cases':len({t['name'] for r in results for t in r['tests']}),'failures':0,'fixtures_unchanged':True,'device':'NOT_RUN','backend':'real KOReader v2026.07.1, SDL3 dummy, crengine/MuPDF','results':results}
(output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items() if k!='results'},indent=2))
