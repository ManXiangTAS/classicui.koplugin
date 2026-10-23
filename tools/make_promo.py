#!/usr/bin/env python3
"""Render the ClassicUI launch film: original typography, animation and score."""
from pathlib import Path
import argparse,json,math,subprocess,wave
import numpy as np
from PIL import Image,ImageDraw,ImageFont,ImageOps
ROOT=Path(__file__).resolve().parents[1]
W,H,FPS=1920,1080,24
FONT=ROOT/'media/fonts/NotoSansCJKsc-subset.otf'
SCENES=[
 (4,'question','这台 Kindle，','读回本了吗？',None),
 (5,'ring','阅读回报','每一本读完的书，都在前进一步。',None),
 (5,'cost','买下设备，是开始。','把书读完，才是回报。',None),
 (5,'screen','填下，本书的价格。','传书时填写，也能在书籍详情中补填。','transfer-ready.png'),
 (5,'screen','读完一本，记下一本。','标记为「已完成」，计入阅读回报。','book-details.png'),
 (6,'ring-win','就快回本。','已经回本。越读越值。',None),
 (4,'statement','数字，是一个小小的彩蛋。','故事，才是真正的回报。',None),
 (5,'brand','墨页','CLASSICUI  /  0.6.0',None),
 (6,'screen','让 KOReader，拥有完整前端。','从找书到阅读，始终熟悉。','home.png'),
 (6,'duo','主页，按你的习惯排列。','最近在读、名言、书架；整行与半行，自由组合。','home-custom.png'),
 (6,'screen','换部件。调布局。看预览。','也能扫码，在手机或电脑上编辑主页。','home-editor.png'),
 (6,'duo-stats','读过的日子，都有痕迹。','热力图 · 七天柱图 · 阅读天数 · 每日目标','home-statistics.png'),
 (5,'screen','把阅读，慢慢积累起来。','统计表与时段分布，看见自己的节奏。','home-insights.png'),
 (6,'screen','先找到，想读的那一本。','书籍 / 作者 / 系列 / 收藏','library.png'),
 (5,'duo-library','让书架，有自己的秩序。','筛选、排序、搜索；收藏夹可以按需隐藏。','collections.png'),
 (6,'screen','把文字，调成舒服的样子。','字体、字号、行距、页边距、对比度与字重。','reader-font.png'),
 (5,'screen','喜欢的排版，存成主题。','下次打开，一键回到熟悉的阅读感。','reader-themes.png'),
 (6,'duo-reader','找到章节，留住句子。','目录、书签与标注，都有清晰的入口。','reader-toc.png'),
 (5,'keyboard','中 / EN，一点切换。','离线拼音候选，保留正在输入的内容。','keyboard.png'),
 (5,'screen','顺手的操作，随时在手边。','前光、夜间模式、旋转、刷新；点击有反馈。','controls.png'),
 (5,'screen','每一项设置，都有去处。','分层设置、时间时区；支持设备上的可用功能。','settings.png'),
 (5,'screen','设备功能，也照顾到。','Voyage 翻页键、Kindle 图片屏保、时区校时。','clock-settings.png'),
 (6,'web','拖进来。改好名字。发送。','同一 Wi-Fi，文件直接到设备。','transfer-ready.png'),
 (4,'statement','不用先传到云端。','下一本，就在你的书库里。',None),
 (5,'install','解压 → 复制 → 重启','koreader / plugins / einkfrontend.koplugin',None),
 (6,'difference','SimpleUI，侧重可定制的主页与导航。','我们选择把主页、书库、阅读菜单和设置一起整理。',None),
 (5,'difference2','从找书，到合上这一页。','同一套界面，同一种操作习惯。',None),
 (6,'end','墨页','把设备，读成自己的。',None),
]
DURATION=sum(s[0] for s in SCENES)
assert DURATION<=300
fonts={};texts={};screens={}
def font(size):
 if size not in fonts:fonts[size]=ImageFont.truetype(str(FONT),size)
 return fonts[size]
def ease(x):return 1-(1-max(0,min(1,x)))**3
def text_layer(text,size,color):
 key=(text,size,color)
 if key not in texts:
  f=font(size);box=f.getbbox(text);im=Image.new('RGBA',(max(1,box[2]-box[0]+8),max(1,box[3]-box[1]+8)));ImageDraw.Draw(im).text((4-box[0],4-box[1]),text,font=f,fill=color);texts[key]=im
 return texts[key]
def text(im,value,x,y,size=64,color='white',align='left',alpha=1):
 layer=text_layer(value,size,color)
 if align=='center':x-=layer.width/2
 if alpha<1:layer=layer.copy();layer.putalpha(layer.getchannel('A').point(lambda a:int(a*max(0,alpha))))
 im.paste(layer,(int(x),int(y)),layer)
def fitted(name,width,height):
 key=(name,width,height)
 if key not in screens:
  src=Image.open(ROOT/'media/screens'/name).convert('RGB');src=ImageOps.grayscale(src).convert('RGB')
  src.thumbnail((int(width),int(height)),Image.Resampling.LANCZOS);screens[key]=src
 return screens[key]
def card(im,name,x,y,width,height):
 src=fitted(name,width-12,height-12);draw=ImageDraw.Draw(im)
 bx=x+(width-src.width)/2;by=y+(height-src.height)/2
 draw.rectangle((bx-7,by-7,bx+src.width+6,by+src.height+6),fill='white',outline='#606060',width=2)
 im.paste(src,(int(bx),int(by)))
def ring(im,cx,cy,r,percent,fg,bg):
 d=ImageDraw.Draw(im);d.ellipse((cx-r,cy-r,cx+r,cy+r),outline='#777777',width=3)
 d.arc((cx-r,cy-r,cx+r,cy+r),-90,-90+min(360,max(0,percent)*3.6),fill=fg,width=22)
 text(im,f'{int(percent)}%',cx,cy-85,112,fg,'center')
 label='故事刚开始' if percent<25 else '渐入佳境' if percent<50 else '稳步接近' if percent<75 else '就快回本' if percent<100 else '已经回本' if percent<150 else '越读越值'
 text(im,label,cx,cy+65,38,fg,'center')
def render(scene,t,index):
 dur,kind,title,sub,name=scene;p=t/dur;intro=ease(t/.65);shift=int((1-intro)*90)
 white=kind in ['ring','cost','screen','duo-stats','duo-library','keyboard','web','install','difference2'] and index%3!=0
 if kind=='ring':white=True
 bg='white' if white else '#080808';fg='#0c0c0c' if white else 'white'
 im=Image.new('RGB',(W,H),bg);d=ImageDraw.Draw(im)
 # A single moving edge and quiet folio establish a consistent visual language.
 d.rectangle((0,0,int(W*min(1,(index+p)/len(SCENES))),5),fill=fg)
 if kind not in ['question','brand','end']:
  text(im,'墨页 / CLASSICUI',76,45,23,fg);text(im,f'{index+1:02d} / {len(SCENES):02d}',W-76,45,23,fg,'center')
 if kind=='question' and t<1.1:
  word='买了。' if t<.55 else '读了。'
  text(im,word,W/2,350,220,fg,'center')
  d.line((150,760,1770,760),fill=fg,width=5)
 elif kind=='question':
  text(im,title,120,285+shift,108,fg,alpha=intro)
  text(im,sub,120+int((1-ease((t-.35)/.7))*120),445,148,fg,alpha=ease((t-.35)/.7))
  d.line((120,710,120+int(1480*ease((t-.7)/1)),710),fill=fg,width=4)
  text(im,'一个关于阅读的小小问题。',125,760,35,fg,alpha=ease((t-1.1)/.5))
 elif kind in ['ring','ring-win']:
  progress=66*ease((t-.3)/3) if kind=='ring' else (66+33*ease(t/2.3) if t<2.5 else 100 if t<3.8 else 100+76*ease((t-3.8)/1.7))
  ring(im,1320,540,275,progress,fg,bg)
  text(im,'阅读回报',120,230+shift,88,fg)
  text(im,'读完的每一本',120,400,67,fg);text(im,'都算数。',120,495,96,fg)
  text(im,'仅累计已完成书籍的填写价格',125,725,30,fg)
  text(im,'以你设置的购机投入为目标',125,780,30,fg)
 elif kind=='cost':
  text(im,title,110,160+shift,86,fg);text(im,sub,110,280,66,fg)
  for i,(n,label) in enumerate([('¥400','购机投入'),('¥266','已读书籍价值')]):
   x=110+i*880;y=475+int((1-ease((t-i*.35-.3)/.8))*100)
   d.line((x,y-35,x+730,y-35),fill=fg,width=3);text(im,n,x,y,135,fg);text(im,label,x+5,y+200,43,fg)
  text(im,'数字由你填写，进度随着已读记录变化。',110,925,31,fg)
 elif kind in ['statement','difference','difference2']:
  size=66 if kind=='difference' else 80
  text(im,title,W/2,355+shift,size,fg,'center',intro)
  text(im,sub,W/2,505,43 if kind=='difference' else 57,fg,'center',ease((t-.5)/.8))
  if kind=='difference':
   text(im,'不同取向，各有喜欢它的人。',W/2,750,30,fg,'center')
  elif kind=='difference2':
   for i,label in enumerate(['主页','书库','阅读','设置']):
    x=335+i*385;y=715+int(55*(1-ease((t-i*.1-.4)/.5)))
    d.rectangle((x,y,x+290,y+115),outline=fg,width=3);text(im,label,x+145,y+28,43,fg,'center')
 elif kind=='brand' and t<.85:
  text(im,'墨' if t<.42 else '页',W/2,230,400,fg,'center')
 elif kind in ['brand','end']:
  text(im,title,W/2,245+shift,240,fg,'center',intro)
  text(im,sub,W/2,615,48,fg,'center',ease((t-.7)/.8))
  if kind=='brand':text(im,'为电子墨水屏，重新整理每一处界面。',W/2,760,36,fg,'center')
  else:
   text(im,'CLASSICUI 0.6.0  /  现已发布',W/2,735,38,fg,'center')
   text(im,'github.com/ManXiangTAS/classicui.koplugin',W/2,865,30,fg,'center')
 elif kind=='install':
  text(im,'安装，只需三步。',110,190+shift,92,fg)
  for i,label in enumerate(['01  解压','02  复制','03  重启']):
   x=115+i*605;y=440+int(80*(1-ease((t-i*.3-.3)/.8)))
   d.rectangle((x,y,x+510,y+185),outline=fg,width=4);text(im,label,x+255,y+54,63,fg,'center')
  text(im,sub,120,760,43,fg);text(im,'保留 einkfrontend.koplugin 文件夹名称',120,860,31,fg)
 elif kind=='web':
  text(im,title,100,130+shift,76,fg);text(im,sub,105,238,37,fg)
  card(im,name,100+int((1-intro)*70),330,1720,645)
 elif kind in ['duo','duo-stats','duo-library','duo-reader']:
  text(im,title,100,130+shift,72,fg);text(im,sub,105,238,35,fg)
  other={'duo':'home.png','duo-stats':'home-insights.png','duo-library':'series.png','duo-reader':'reader-bookmarks.png'}[kind]
  card(im,name,350+shift,335,540,650);card(im,other,1030-shift,335,540,650)
 else:
  title_size=78
  while text_layer(title,title_size,fg).width>890:title_size-=2
  text(im,title,100,240+shift,title_size,fg)
  # Subtitle wraps manually at punctuation, preserving a calm reading rhythm.
  chunks=sub.split('；') if '；' in sub else [sub]
  if len(chunks)==1 and len(sub)>24:chunks=[sub[:22],sub[22:]]
  for i,line in enumerate(chunks):text(im,line,106,430+i*65,36,fg)
  if kind=='keyboard':card(im,name,1020+shift,170,790,770)
  elif name=='transfer-ready.png':card(im,name,1000+shift,140,800,805)
  else:
   if name=='home-statistics.png' and t>3:name='home-insights.png'
   if name=='reader-font.png' and t>4:name='reader-themes.png'
   drift=int(12*math.sin(p*math.pi))
   card(im,name,1115+shift+drift,125-int(8*math.sin(p*math.pi)),655,855)
  d.line((110,730,730,730),fill=fg,width=3)
  text(im,('14 种主页部件' if kind=='screen' and name=='home.png' else '为阅读，留出更多空间。'),110,785,30,fg)
 # An understated footer identifies demonstrations without turning into a report.
 if kind not in ['brand','end']:text(im,'界面演示 / 示例书目与数据',W/2,1034,19,fg,'center')
 # Brief sliding shutters, rather than a stream of full-screen flashes.
 if t<.18 and index:
  edge=int(W*(1-t/.18));d.rectangle((0,0,edge,H),fill=fg)
 if kind=='end' and t>dur-1:
  im=Image.blend(im,Image.new('RGB',(W,H),'black'),(t-(dur-1)))
 return im

def compose_score(path):
 rate=44100;n=int(DURATION*rate);mix=np.zeros((n,2),dtype=np.float32);rng=np.random.default_rng(600)
 def add(signal,start,volume=1,pan=0):
  offset=int(start*rate);end=min(n,offset+len(signal));signal=signal[:end-offset]*volume
  if len(signal):mix[offset:end,0]+=signal*(1-pan*.45);mix[offset:end,1]+=signal*(1+pan*.45)
 def tone(freq,length,kind='sine'):
  t=np.arange(int(length*rate),dtype=np.float32)/rate
  wave=np.sin(2*np.pi*freq*t)
  if kind=='pluck':wave=(wave+.27*np.sin(4*np.pi*freq*t)+.1*np.sin(6*np.pi*freq*t))*np.exp(-t*8)
  elif kind=='bass':wave=(wave+.3*np.sin(4*np.pi*freq*t))*np.minimum(1,t*80)*np.exp(-t*5)
  return wave
 beat=.5;notes=[146.832,174.614,130.813,164.814]
 for b in range(int(DURATION/beat)):
  at=b*beat;energy=.38 if at<4 else .65 if 28<at<34 or 119<at<124 else 1
  if at>DURATION-7:energy*=max(0,(DURATION-at)/7)
  if b%4 in [0,2] or energy>.7:
   t=np.arange(int(.3*rate))/rate;phase=2*np.pi*(48*t+(130-48)*.035*(1-np.exp(-t/.035)))
   add(np.sin(phase)*np.exp(-t*15),at,.42*energy)
  if b%4 in [1,3]:
   t=np.arange(int(.19*rate))/rate;noise=rng.normal(0,1,len(t));clap=(noise-np.roll(noise,1))*.25*np.exp(-t*24)+np.sin(2*np.pi*185*t)*np.exp(-t*30)*.25
   add(clap,at,.32*energy)
  for off in [0,.25]:
   t=np.arange(int(.05*rate))/rate;noise=rng.normal(0,1,len(t));add((noise-np.roll(noise,1))*.16*np.exp(-t*90),at+off,.17*energy,(-1 if b%2 else 1)*.55)
  root=notes[(b//8)%4]/2
  add(tone(root,.45,'bass'),at,.28*energy)
  if b%2==0 and at>4:
   seq=[0,7,12,10,3,7,15,12];note=notes[(b//8)%4]*2**(seq[(b//2)%8]/12)
   signal=tone(note,.72,'pluck');add(signal,at+.125,.105*energy,.6 if b%4 else -.6);add(signal,at+.375,.04*energy,-.6)
 # Sparse, warm chords give breathing room to the spoken-in-type passages.
 for bar in range(0,int(DURATION/2),4):
  start=bar*2;root=notes[(bar//4)%4];length=min(7,DURATION-start);t=np.arange(int(length*rate))/rate
  pad=sum(np.sin(2*np.pi*root*2**(k/12)*t+.4*np.sin(t*.7)) for k in [0,3,7])/3
  env=np.minimum(1,t/1.5)*np.minimum(1,(length-t)/2);add(pad*env,start,.055)
 cursor=0
 for dur,*_ in SCENES:
  if cursor>0:
   t=np.arange(int(.35*rate))/rate;noise=rng.normal(0,1,len(t));env=np.sin(np.pi*np.arange(len(t))/len(t))**2
   add(noise*env,cursor-.22,.025,-.3)
  cursor+=dur
 mix=np.tanh(mix*1.25);peak=np.max(np.abs(mix));mix*=.89/max(peak,1e-6)
 fade=int(rate*1.5);mix[:fade]*=np.linspace(0,1,fade)[:,None];mix[-fade:]*=np.linspace(1,0,fade)[:,None]
 with wave.open(str(path),'wb') as f:f.setnchannels(2);f.setsampwidth(2);f.setframerate(rate);f.writeframes((mix*32767).astype('<i2').tobytes())

def main():
 parser=argparse.ArgumentParser();parser.add_argument('output');args=parser.parse_args();output=Path(args.output).resolve();output.parent.mkdir(parents=True,exist_ok=True)
 audio=output.with_suffix('.score.wav');compose_score(audio)
 args=['ffmpeg','-y','-hide_banner','-loglevel','warning','-f','rawvideo','-vcodec','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','pipe:0','-i',str(audio),'-map','0:v','-map','1:a','-c:v','libx264','-preset','veryfast','-crf','21','-threads','2','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-af','loudnorm=I=-16:TP=-3:LRA=9,volume=0.85','-movflags','+faststart','-shortest','-metadata','title=墨页 ClassicUI 0.6.0 · 把设备，读成自己的','-metadata','comment=Original motion design and original score. UI demonstrations use example books and data.',str(output)]
 proc=subprocess.Popen(args,stdin=subprocess.PIPE);cursor=0
 try:
  for index,scene in enumerate(SCENES):
   print(f'Rendering {index+1}/{len(SCENES)} — {scene[2]}',flush=True)
   for frame in range(int(scene[0]*FPS)):proc.stdin.write(render(scene,frame/FPS,index).tobytes())
   cursor+=scene[0]
  proc.stdin.close();assert proc.wait()==0
 except BaseException:
  proc.kill();raise
 audio.unlink();(output.parent/'film-timeline.json').write_text(json.dumps({'duration':DURATION,'fps':FPS,'resolution':[W,H],'music':'Original synthesized score, 120 BPM','scenes':SCENES},ensure_ascii=False,indent=2)+'\n')
 print('Created',output,DURATION,'seconds',flush=True)
if __name__=='__main__':main()
