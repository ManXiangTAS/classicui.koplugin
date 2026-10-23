#!/usr/bin/env python3
"""Verify final settings PNG pixels; draw-returned ink metrics are not inputs."""
from pathlib import Path
from PIL import Image,ImageChops
import hashlib,json,math,os,shutil,subprocess,sys,tempfile
project=Path(__file__).resolve().parents[1];runtime=Path(sys.argv[1]).resolve();output=project/'test-results-041'
(output/'data').mkdir(parents=True,exist_ok=True);results=[];samples=[];count=0
def bounds(image,box):
 x0,y0,x1,y1=map(int,box);crop=image.crop((x0,y0,x1,y1))
 # Normalize the threshold to the actual foreground (disabled rows are gray).
 threshold=(crop.getextrema()[0]+256)//2
 mask=crop.point(lambda v:255 if v<threshold else 0);b=mask.getbbox()
 assert b,box
 return [x0+b[0],y0+b[1],x0+b[2]-1,y0+b[3]-1]
def center(b):return ((b[0]+b[2])/2,(b[1]+b[3])/2)
for variant,w,h,dpi in [('desktop',600,800,160),('voyage_layout',1072,1448,300),('landscape',1448,1072,300)]:
 state=Path(tempfile.mkdtemp(prefix=variant+'-',dir=output/'data'));books=state/'books';books.mkdir()
 for name in ['A.epub','B.epub']:shutil.copyfile(project/'tests/fixtures'/name,books/name)
 shutil.copyfile(project/'tests/pdf/layout.pdf',books/'sample.pdf')
 env=os.environ.copy();env.update(KO_HOME=str(state),EINK_PROJECT=str(project),EINK_030_BOOKS=str(books),EINK_VARIANT=variant,
  SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',EMULATE_READER_W=str(w),EMULATE_READER_H=str(h),EMULATE_READER_DPI=str(dpi))
 for mode in ['style_navigation','fixes033','settings_alignment041']:
  log=output/f'{mode}-{variant}.log';script=project/'tests'/('settings_alignment041.lua' if mode=='settings_alignment041' else 'integration030.lua')
  with log.open('w') as file:p=subprocess.run([str(runtime/'luajit'),str(script),mode],cwd=runtime,env=env,stdout=file,stderr=subprocess.STDOUT,timeout=90)
  if p.returncode:print(log.read_text()[-7000:]);raise SystemExit(f'FAIL {variant}/{mode}')
  if mode!='settings_alignment041':
   report=json.loads((project/'test-results-030'/f'{mode}-{variant}.json').read_text());assert all(t['status']=='PASS' for t in report['tests'])
   shutil.copyfile(project/'test-results-030'/f'{mode}-{variant}.json',output/f'{mode}-{variant}.json');results.append(report)
   print(f'PASS {variant}/{mode}: {len(report["tests"])} checks',flush=True)
 report=json.loads((output/f'settings-{variant}.json').read_text());frames={}
 for frame in report['frames']:
  image=Image.open(output/frame['file']).convert('L');scale=frame['scale'];S=lambda n:int(math.ceil(n*scale-1e-8))
  width,height=frame['width'],frame['height'];header=frame['header'];top=frame['top'];rowh=frame['row_h'];scroll=frame['scroll']
  measured=[];title_x=S(20) if frame['root'] else S(48)
  header_boxes=[('title',(title_x,0,width-S(112 if frame['root'] else 59),header-S(4))),('close',(width-S(53),0,width,header-S(4)))]
  if frame['root']:header_boxes.append(('more',(width-S(106),0,width-S(53),header-S(4))))
  for label,box in header_boxes:
   b=bounds(image,box);delta=center(b)[1]-header/2;assert abs(delta)<=1,(frame['file'],label,delta);count+=1;measured.append({'element':label,'offset_y':delta})
  if not frame['root']:
   b=bounds(image,(0,0,S(46),header-S(4)));delta=center(b)[1]-header/2;assert abs(delta)<=1;count+=1
  for i,row in enumerate(frame['rows']):
   ry=top+i*rowh-scroll
   if ry<top or ry+rowh>top+frame['viewport']:continue
   target=ry+rowh/2;y0,y1=ry+S(4),ry+rowh-S(5);pad=S(20)+S(46) if row['icon'] else S(20)
   valuew=S(125) if row['value'] else S(24);textend=width-valuew-S(36)
   tb=bounds(image,(pad,y0,textend,y1));delta=center(tb)[1]-target
   assert abs(delta)<=1,(frame['file'],i+1,'text block',delta);assert tb[0]==pad,(frame['file'],i+1,'left edge',tb[0],pad)
   count+=1;measured.append({'element':'text '+str(i+1),'offset_y':delta})
   if row['icon']:
    b=bounds(image,(S(18),y0,S(50),y1));delta=center(b)[1]-center(tb)[1]
    assert abs(delta)<=1,(frame['file'],i+1,'icon/text',delta);assert tb[0]-b[2]>=S(10)
    count+=1;measured.append({'element':'icon '+str(i+1),'offset_y':delta})
   if row['arrow']:
    b=bounds(image,(width-S(38),y0,width-S(14),y1));delta=center(b)[1]-center(tb)[1]
    assert abs(delta)<=1,(frame['file'],i+1,'arrow/text',delta);count+=1
   if row['value']:
    b=bounds(image,(width-valuew-S(28),y0,width-S(36),y1));delta=center(b)[1]-center(tb)[1]
    assert abs(delta)<=1,(frame['file'],i+1,'value/text',delta);count+=1
  samples.append({'file':frame['file'],'measurements':measured});frames[frame['file'].split('-')[1]]=(image,frame)
  print('PASS settings pixel alignment '+frame['file'],flush=True)
 original,info=frames['mixed'];partial,pinfo=frames['partial'];shift=pinfo['scroll']
 # The fixed header separator overlaps the first viewport pixel on scaled
 # layouts. Compare scrolling content, excluding it and the fixed scrollbar.
 border=S(2)
 a=original.crop((0,info['top']+shift+border,w-S(24),info['top']+info['viewport']))
 b=partial.crop((0,pinfo['top']+border,w-S(24),pinfo['top']+pinfo['viewport']-shift))
 assert ImageChops.difference(a,b).getbbox() is None,('partial scroll pixels moved or clipped incorrectly',variant)
summary={'version':'0.3.11-dev','process_runs':9,'regression_checks':sum(len(r['tests']) for r in results),'pixel_frames':len(samples),'measured_elements':count,'failures':0,'tolerance_pixels':1,'partial_scroll_pixel_matches':3,'device':'NOT_RUN','results':results,'pixel_samples':samples}
(output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k not in ['results','pixel_samples']},ensure_ascii=False,indent=2))
