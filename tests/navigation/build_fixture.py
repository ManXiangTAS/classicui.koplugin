"""Original EPUB with a nested ToC for real-engine navigation regression."""
from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED,ZIP_STORED
from html import escape
p=Path(__file__).parent
base=ZipFile(p.parent/'fixtures/B.epub')
sections=[];nav=[];order=0
for chapter in range(1,13):
 order+=1;cid=f'c{chapter}';title=f'第{chapter}章 · 阅读导航测试'
 points=[]
 sections.append(f'<h1 id="{cid}">{title}</h1>'+''.join(f'<p>第{chapter}章，第{i}段。这是原创测试文本，验证真实目录、书签与章节跳转。 Reading navigation fixture.</p>' for i in range(1,7)))
 for part in range(1,3):
  order+=1;sid=f'c{chapter}s{part}';label=f'第{chapter}章 · 第{part}节'
  sections.append(f'<h2 id="{sid}">{label}</h2>'+''.join(f'<p>第{part}节，第{i}段。用于真实阅读进度、标注与层级目录验证。</p>' for i in range(1,7)))
  points.append(f'<navPoint id="{sid}" playOrder="{order}"><navLabel><text>{label}</text></navLabel><content src="chapter.xhtml#{sid}"/></navPoint>')
 nav.append(f'<navPoint id="{cid}" playOrder="{order-2}"><navLabel><text>{title}</text></navLabel><content src="chapter.xhtml#{cid}"/>'+''.join(points)+'</navPoint>')
ncx='<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="eink-navigation-034"/></head><docTitle><text>目录与标注测试书</text></docTitle><navMap>'+''.join(nav)+'</navMap></ncx>'
with ZipFile(p/'chapters.epub','w',ZIP_DEFLATED) as z:
 for name in base.namelist():
  data=base.read(name)
  if name.endswith('.opf'):data=data.decode().replace('测试书乙','目录与标注测试书').replace('einkfrontend-test-B','eink-navigation-034').encode()
  if name.endswith('chapter.xhtml'):data=('<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>目录与标注测试书</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>'+''.join(sections)+'</body></html>').encode()
  if name.endswith('.ncx'):data=ncx.encode()
  z.writestr(name,data,compress_type=ZIP_STORED if name=='mimetype' else ZIP_DEFLATED)
print(p/'chapters.epub')
