#!/usr/bin/env python3
"""Measure actual rendered ink against circles/switches, not widget box centers."""
from pathlib import Path
from PIL import Image
import hashlib,json,math,os,shutil,subprocess,sys,tempfile
project=Path(__file__).resolve().parents[1];runtime=Path(sys.argv[1]).resolve();output=project/'test-results-040'
(output/'data').mkdir(parents=True,exist_ok=True);results=[];pixel_samples=[]

def ink_bbox(points):
 assert points,'No visible ink'
 return [min(p[0] for p in points),min(p[1] for p in points),max(p[0] for p in points),max(p[1] for p in points)]

def internal_components(image,white):
 # Isolate glyph pixels from the switch border/background. Reject connected
 # components touching the crop edge, independent of the label draw metrics.
 points={(x,y) for y in range(image.height) for x in range(image.width) if (image.getpixel((x,y))>191 if white else image.getpixel((x,y))<64)}
 kept=[]
 while points:
  start=points.pop();stack=[start];component=[start];touch=False
  while stack:
   x,y=stack.pop();touch|=x==0 or y==0 or x==image.width-1 or y==image.height-1
   for q in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
    if q in points:points.remove(q);stack.append(q);component.append(q)
  if not touch:kept.extend(component)
 return kept

for variant,w,h,dpi in [('desktop',600,800,160),('voyage_layout',1072,1448,300),('landscape',1448,1072,300)]:
 state=Path(tempfile.mkdtemp(prefix=variant+'-',dir=output/'data'));books=state/'books';books.mkdir()
 for name in ['A.epub','B.epub']:shutil.copyfile(project/'tests/fixtures'/name,books/name)
 shutil.copyfile(project/'tests/pdf/layout.pdf',books/'sample.pdf')
 shutil.copyfile(project/'tests/navigation/chapters.epub',books/'navigation.epub')
 before={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in books.iterdir()}
 env=os.environ.copy();env.update(KO_HOME=str(state),EINK_PROJECT=str(project),EINK_030_BOOKS=str(books),EINK_VARIANT=variant,
  SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',EMULATE_READER_W=str(w),EMULATE_READER_H=str(h),EMULATE_READER_DPI=str(dpi))
 for mode in ['style_navigation','regression036','alignment040']:
  log=output/f'{mode}-{variant}.log'
  script=project/'tests'/('alignment040.lua' if mode=='alignment040' else 'integration030.lua')
  with log.open('w') as file:p=subprocess.run([str(runtime/'luajit'),str(script),mode],cwd=runtime,env=env,stdout=file,stderr=subprocess.STDOUT,timeout=90)
  if p.returncode:print(log.read_text()[-7000:]);raise SystemExit(f'FAIL {variant}/{mode}')
  if mode!='alignment040':
   report=json.loads((project/'test-results-030'/f'{mode}-{variant}.json').read_text());assert all(t['status']=='PASS' for t in report['tests'])
   # Keep current rerun evidence separate from the previous release's summaries.
   shutil.copyfile(project/'test-results-030'/f'{mode}-{variant}.json',output/f'{mode}-{variant}.json')
   results.append(report);print(f'PASS {variant}/{mode}: {len(report["tests"])} checks',flush=True)
 report=json.loads((output/f'alignment-{variant}.json').read_text())
 for frame in report['frames']:
  image=Image.open(output/frame['file']).convert('L');measurements=[]
  for action in frame['actions']:
   cx,cy,r=action['cx'],action['cy'],action['radius']
   # Inner disk excludes the circle outline and the selected-state marker.
   radius=r-max(5,math.ceil(r*.13));bounds=ink_bbox([(x,y) for y in range(math.floor(cy-radius),math.ceil(cy+radius)+1) for x in range(math.floor(cx-radius),math.ceil(cx+radius)+1) if (x-cx)**2+(y-cy)**2<radius**2 and image.getpixel((x,y))<128])
   dx=(bounds[0]+bounds[2])/2-cx;dy=(bounds[1]+bounds[3])/2-cy
   measurements.append({'label':action['label'],'bbox':bounds,'offset':[dx,dy]})
   assert abs(dx)<=1 and abs(dy)<=1,(frame['file'],action['label'],dx,dy)
  switch=frame['frontlight'];x,y,sw,sh=[switch[k] for k in ['x','y','w','h']]
  crop=image.crop((x,y,x+sw,y+sh));bounds=ink_bbox(internal_components(crop,switch['on']))
  dx=(bounds[0]+bounds[2])/2-sw/2;dy=(bounds[1]+bounds[3])/2-sh/2
  assert abs(dx)<=1 and abs(dy)<=1,(frame['file'],'frontlight',dx,dy)
  measurements.append({'label':'开' if switch['on'] else '关','bbox':bounds,'offset':[dx,dy]})
  pixel_samples.append({'file':frame['file'],'measurements':measurements})
  print('PASS pixel ink alignment '+frame['file'],flush=True)
 after={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in books.iterdir() if p.is_file()};assert before==after
summary={'version':'0.3.10-dev','process_runs':9,'regression_checks':sum(len(r['tests']) for r in results),'pixel_frames':len(pixel_samples),'measured_elements':sum(len(f['measurements']) for f in pixel_samples),'failures':0,'tolerance_pixels':1,'device':'NOT_RUN','results':results,'pixel_samples':pixel_samples}
(output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k not in ['results','pixel_samples']},ensure_ascii=False,indent=2))
