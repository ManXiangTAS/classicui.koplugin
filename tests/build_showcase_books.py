"""Original demo books/covers for screenshots; not published books or user data."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from zipfile import ZipFile,ZIP_DEFLATED,ZIP_STORED
from html import escape
import json,sys
out=Path(sys.argv[1]);runtime=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
font=runtime/'fonts/noto/NotoSansCJKsc-Regular.otf'
titles=['山间来信','日光笔记','沿海慢行','夜航手记','小城散步','慢慢读书']
paragraphs=[
 '清晨，窗前的光慢慢移过书页。我把手机放远了一点，给自己留下一小段没有提醒的时间。翻开书的时候，不必急着决定今天要读完多少。',
 '有些句子适合读得很慢。读到喜欢的地方，可以停下来，看看窗外，再回到这一行。文字依然安静地等在那里。',
 '我们总想把日子安排得很满，却也需要一些没有安排的空白。一本书、一盏灯、一张坐得舒服的椅子，已经足够让一个普通的晚上变得不同。',
 '阅读的进度不只是一串数字。有时读过十页，只记住一句话；有时合上书，才明白刚才那段文字为什么让人停留。',
 '我喜欢纸页的边缘，也喜欢电子墨水缓慢改变的样子。工具安静一点，注意力就能多留在故事里一点。',
 '后来我明白，所谓把时间留给阅读，并不是把每一分钟都填上文字，而是允许自己专心做一件喜欢的事情。',
]
manifest=[]
for i,title in enumerate(titles):
 cover=Image.new('RGB',(600,900),['#eeeae2','#ffffff','#dfdfdf','#242424','#f6f6f6','#d8d3c9'][i]);d=ImageDraw.Draw(cover)
 ink='white' if i==3 else '#151515';f=lambda n:ImageFont.truetype(str(font),n)
 d.line((45,50,555,50),fill=ink,width=5);d.text((45,73),'墨页 · 原创演示书目',font=f(23),fill=ink)
 d.text((45,178),title[:2]+'\n'+title[2:],font=f(99),fill=ink,spacing=10,stroke_width=1)
 d.text((48,470),'墨页样书',font=f(29),fill=ink)
 if i%3==0:
  d.polygon([(45,720),(178,555),(305,720)],outline=ink,width=5);d.line((245,720,422,595,555,720),fill=ink,width=5)
 elif i%3==1:
  d.ellipse((380,570,535,725),outline=ink,width=6)
  for yy in range(600,721,30):d.line((45,yy,320,yy),fill=ink,width=4)
 else:
  for yy in range(590,735,25):d.line((45,yy,555,yy),fill=ink,width=4)
 d.line((45,790,555,790),fill=ink,width=3);d.text((45,816),'DEMO  /  '+str(i+1).zfill(2)+'  /  非出版物',font=f(20),fill=ink)
 import io
 b=io.BytesIO();cover.save(b,format='PNG');cover_bytes=b.getvalue()
 uid='classicui-showcase-'+str(i+1);series='慢读集' if i<3 else '日常集'
 opf=f'''<?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uid" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">{uid}</dc:identifier><dc:title>{title}</dc:title><dc:creator>墨页样书</dc:creator><dc:language>zh-CN</dc:language><dc:description>原创界面演示素材，非出版物。阅读进度和统计为演示数据。</dc:description><meta name="cover" content="cover"/><meta name="calibre:series" content="{series}"/><meta name="calibre:series_index" content="{i%3+1}"/></metadata><manifest><item id="cover" href="cover.png" media-type="image/png"/><item id="text" href="chapter.xhtml" media-type="application/xhtml+xml"/><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="css" href="style.css" media-type="text/css"/></manifest><spine toc="ncx"><itemref idref="text"/></spine></package>'''
 body=''
 for n,heading in enumerate(['给自己一段安静的时间','把注意力留在书页上','读到喜欢的地方']):
  body+=f'<h1 id="c{n}">{heading}</h1>'+''.join('<p>'+escape(t)+'</p>' for t in paragraphs*3)
 chapter=f'''<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>{title}</title><link rel="stylesheet" href="style.css" type="text/css"/></head><body>{body}</body></html>'''
 ncx=f'''<?xml version="1.0" encoding="UTF-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="{uid}"/></head><docTitle><text>{title}</text></docTitle><navMap>'''+''.join(f'<navPoint id="n{n}" playOrder="{n+1}"><navLabel><text>{heading}</text></navLabel><content src="chapter.xhtml#c{n}"/></navPoint>' for n,heading in enumerate(['给自己一段安静的时间','把注意力留在书页上','读到喜欢的地方']))+'</navMap></ncx>'
 file=out/f'{i+1:02d}.epub'
 with ZipFile(file,'w',ZIP_DEFLATED) as z:
  z.writestr('mimetype','application/epub+zip',compress_type=ZIP_STORED)
  z.writestr('META-INF/container.xml','<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
  for name,data in [('content.opf',opf),('cover.png',cover_bytes),('chapter.xhtml',chapter),('toc.ncx',ncx),('style.css','body{font-family:serif;} h1{font-size:1.35em;text-align:center;margin:1.5em 0;} p{text-indent:2em;line-height:1.65;margin:.4em 0;}')]:z.writestr('OEBPS/'+name,data)
 manifest.append({'file':file.name,'title':title,'kind':'original demo, not a published book'})
(out/'demo_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
