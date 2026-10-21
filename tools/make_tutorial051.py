#!/usr/bin/env python3
"""Build captioned guide frames from genuine, test-owned KOReader/browser captures."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import base64,json,html,textwrap,sys
from io import BytesIO
P=Path(__file__).resolve().parents[1];O=Path(sys.argv[1]).resolve();O.mkdir(parents=True,exist_ok=True);frames=O/'tutorial-frames';frames.mkdir(exist_ok=True)
FONT=P.parent/'runtime-downloads/squashfs-root/usr/lib/koreader/fonts/noto/NotoSansCJKsc-Regular.otf'
def font(n):return ImageFont.truetype(str(FONT),n)
def f(folder,name):return str(P/folder/name)
more=f('test-results-051','tutorial-more-menu-voyage.png');wizard=f('test-results-051','transfer-wizard-voyage.png');settings=f('test-results-051','transfer-settings-voyage.png');web=f('test-results-051','transfer-desktop.png');advanced=f('test-results-051','epub-advanced-desktop.png');library=f('test-results-051','tutorial-library-voyage.png');home=f('test-results-049','home-fixed-default-voyage.png');editor=f('test-results-051','tutorial-editor-voyage.png');themes=f('test-results-050','themes-saved-voyage.png');pagepress=f('test-results-048','pagepress-title-help-voyage.png')
# title, details, source capture, hold seconds, chapter
scenes=[
('墨页：从安装到日常阅读',['0.5.0-test.1 完整字幕教程，无配音。','原生界面使用 KOReader 桌面模拟；网页部分是真实录屏。','演示书籍和阅读数据均为测试素材。Kindle 实机网络、触控与恢复行为仍需复测。'],home,18,'开始前'),
('01 / 安装前准备',['先确认已安装 KOReader 2026.07.1 或 2026.07.2。','插件放进 KOReader 的 plugins，和 Kindle 的 documents 书籍文件夹是两条不同路径。','先完全退出 KOReader，再用 USB 连接电脑。'],None,18,'安装与升级'),
('02 / 下载正确的包',['下载 ClassicUI_0.5.0-test.1_install.zip 并解压。','日常安装用 install；source 是源码；full_handoff 用于完整项目移交。','升级前备份原插件目录和 koreader/settings。'],None,18,'安装与升级'),
('03 / 把文件夹放对位置',['把 einkfrontend.koplugin 整个文件夹复制到：','Kindle 可见磁盘 → koreader → plugins','最终必须是 plugins/einkfrontend.koplugin/main.lua，避免多套一层同名文件夹。'],None,22,'安装与升级'),
('04 / 升级与启用',['升级时覆盖同名 einkfrontend.koplugin，保持目录名不变。','弹出 Kindle 磁盘，打开 KOReader。必要时在插件管理中启用“墨页前端”，再重启 KOReader。','这是 KOReader 插件，不需要安装成 Kindle 固件更新。'],None,20,'安装与升级'),
('05 / 首次传书向导',['首次自动进入墨页时，会出现传书向导。','可以使用 ManualBook 默认目录，也可以选择已有文件夹或输入新目录。','已有书库不想改：点“保留当前书库，稍后设置”。'],wizard,20,'目录向导'),
('06 / 传书目录就是书库目录',['默认：/mnt/us/documents/ManualBook','修改目录后，墨页会扫描新目录；旧书不会被移动或删除。','之后在 设置 → 书库与文件 → 传书与书库 调整；网络与同步中也有入口。'],settings,20,'目录向导'),
('07 / 右上角的三个点',['设置界面的放大镜已改为“更多”。','点击三个点，可以选择“搜索”或“重启 KOReader”。','重启前会确认，调用原生保存与重启。不要在传书进行中重启。'],more,18,'设置与搜索'),
('08 / 搜索范围跟随位置',['普通设置页：搜索全部设置。时区页：搜索时区。','收藏成员页：搜索当前收藏中的书；部分详情页：搜索当前页选项。','书库找书、目录找章节、书签找标注，各用对应界面的搜索。'],more,20,'设置与搜索'),
('09 / 开启网页传书',['手机或电脑与 Kindle 连接同一 Wi-Fi。','在“传书与书库”中点“开启网页传书”，再显示二维码并扫描。','电脑可以输入“显示完整连接地址”中的地址；不要漏掉 # 后面的临时密钥。'],settings,22,'网页传书'),
('10 / 认识上传网页',['白色页面中可以选择文件，也可以直接拖入。','一次最多20本，每本最多200 MB；支持 EPUB、PDF、TXT、漫画等已列格式。','不登录亚马逊，不经过亚马逊云端；这是直接传到本机 KOReader 的传书页面。'],web,20,'网页传书'),
('11 / EPUB 重排默认关闭',['不勾选重排：直接发送原文件，保留原始字节。','勾选重排：仅处理 EPUB，生成带“_精排”的副本；其他格式仍按原样发送。','要把 PDF、AZW 或 KFX 转为 EPUB，需要另用转换工具。'],web,20,'EPUB 重排'),
('12 / 高级设置与预览',['先选一本 EPUB，再打开“高级设置与预览”。','调整段首缩进、行距、段间距、页边距、标题大小和自动识别标题。','电脑左右比较；手机可切换原版 / 精排结果。向下滚动可看完整选项。'],advanced,22,'EPUB 重排'),
('13 / 怎样选择重排参数',['一般中文正文可从缩进2字、行距1.65开始，再按自己的阅读习惯调整。','段间距0表示靠缩进区分段落；页边距影响书内样式，KOReader 阅读设置也会影响最终效果。','漫画、固定版式、竖排、公式或复杂艺术排版，请先逐章检查，必要时关闭重排。'],advanced,25,'EPUB 重排'),
('14 / 确认后再发送',['点击“使用此排版”，才会启用重排；然后在主页面点“发送到 Kindle”。','批量 EPUB 使用当前参数。需要每本不同参数时，分批发送。','下方实录演示从选书到查看结果的完整操作。'],advanced,18,'EPUB 重排'),
('15 / 接收完成后',['看到“已送达”后，Kindle 会自动重新扫描书库。','已有同名文件时增加“(1)”等序号；旧书不会被覆盖。','更改接收目录会同时修改书库根目录；原目录中的书仍在原处。'],f('test-results-051','transfer-success.png'),20,'传书结果与异常'),
('16 / 取消、断线与休眠',['传输中可以点“取消发送”。已完成的书保留，未完成的临时文件会清理。','请保持 Kindle 唤醒。休眠、退出、关闭服务、修改目录后需要重新开启并扫码。','临时会话最长30分钟。断线后重新发送未完成的书即可。'],web,22,'传书结果与异常'),
('17 / 不支持重排时怎么办',['重排限50 MB；加密、签名、损坏、异常压缩包或非规范 XHTML 会被拒绝。','不要为了继续发送而忽略错误。可以关闭重排，按原文件发送，再使用 KOReader 本身的排版。','若浏览器提示会话失效，回 Kindle 重新开启并扫描二维码。'],advanced,22,'传书结果与异常'),
('18 / 书库的四个分类',['书籍、作者、系列、收藏，按阅读习惯切换。','书籍页支持筛选、排序、搜索和网格 / 列表显示。','传完还没出现：先等扫描结束，再在“传书与书库”点“重新扫描书库”。'],library,20,'书库与收藏'),
('19 / 整理收藏夹',['从收藏管理中新建、改名、删除收藏，调整成员书籍。','可以设置收藏夹在墨页书库中隐藏；隐藏不等于删除。','To Be Read 在墨页中显示为“待读”，底层收藏键不变。'],f('test-results-030','collection-manager-037-voyage_layout.png'),20,'书库与收藏'),
('20 / 系列与书籍信息',['在书籍详情中查看和维护系列等元数据，再回系列分类浏览。','原有书籍、阅读进度、书签和笔记仍由 KOReader 管理。','改变传书根目录只是改变当前索引范围，不会把外部收藏书籍删除。'],f('test-results-030','collection-members-037-voyage_layout.png'),20,'书库与收藏'),
('21 / 阅读时打开菜单',['打开一本书，轻点中部进入墨页阅读菜单；顶部区域可打开阅读提示栏。','从屏幕顶部向下滑动可打开下拉控制。实际手势受当前 KOReader 配置影响。','下方“主题 / 字体 / 排版”分别设置阅读样式。'],f('test-results-030','reader-topbar-integrated-voyage_layout.png'),22,'阅读与排版'),
('22 / 保存自己的主题',['系统只内置一个“默认”主题，使用 KOReader 当前全局默认值。','调整到满意的排版后，点“保存当前设置”并命名。','“管理主题”中可重命名、更新或删除；不会自动复制 Kindle 原生阅读器中的主题。'],themes,22,'阅读与排版'),
('23 / 字体和排版',['字体页调整字体、字号、字重等；排版页调整行距和页边距。','这些控制主要用于 EPUB 等流式书籍；PDF 使用相应页面 / 缩放 / 重排功能。','点叉号会关闭整个排版设置菜单与导航栏。'],f('test-results-043','aa-layout-voyage.png'),20,'阅读与排版'),
('24 / 目录、书签与标注',['目录按钮用来浏览章节和搜索当前书目录。','书签按钮打开书签 / 标注共用菜单，可以切换查看两类内容。','书签菜单中可搜索，或添加本页书签；正文标注仍按 KOReader 的选字流程操作。'],f('test-results-043','navigation-bookmarks-voyage.png'),22,'阅读与导航'),
('25 / 主页固定一屏',['主页在标题栏和底部导航之间显示，不依赖下划或翻页来找部件。','点“主页”旁的铅笔进入编辑，修改会即时预览。','半行部件相邻时并排，配对等高；太多部件放不下时会提示，不会悄悄删掉配置。'],home,22,'主页与部件'),
('26 / 编辑部件与布局',['选择部件后调整显隐、整行 / 半行和顺序，预览满意后再保存。','想找某个部件，使用编辑器内的搜索；取消则放弃当前草稿。','空间不足时，可隐藏部件、改成半行、减少书架数量或选紧凑间距。'],editor,22,'主页与部件'),
('27 / 13种主页部件',['最近在读、当前书统计、书库概览、最近书架、待读书架、名言、时钟。','另有热力图、统计表、七天柱图、阅读天数、时段分布、每日目标。','选择自己真正要看的几项；不是要求同时把13项塞进一屏。'],f('test-results-049','module-heatmap-2-voyage.png'),22,'主页与部件'),
('28 / 阅读统计和每日目标',['主页和书籍的统计读取 KOReader 数据；刷新图标可以立即重新读取。','每日目标在部件选项中设置分钟数；热力图可调整显示周数。','统计依赖 KOReader 统计功能和已有记录；没有记录时显示为空，不会制造数据。'],f('test-results-049','module-daily_goal-2-voyage.png'),22,'主页与部件'),
('29 / 手机编辑主页',['主页编辑器中点“手机编辑”，同一 Wi-Fi 下扫码打开。','在手机上调整显隐、宽度、顺序与内容，预览来自 Kindle 上的实际渲染。','点保存回传；会话15分钟到期，关闭编辑器或休眠会结束。它与传书会话是两个入口。'],f('test-results-046','home-editor-voyage.png'),22,'主页与部件'),
('30 / 时间与日期',['设备与系统或网络与同步中进入“时间与日期”。','可以调用原生网络校时，选择时区；时区按 KOReader 进程生效，不修改设备全局时区文件。','网络时间与系统时钟的实机行为仍需设备验证。'],f('test-results-045','clock-settings-voyage.png'),20,'设备设置'),
('31 / Voyage 翻页键',['仅 Voyage 提供翻页键设置：开关、按压力度、震动及强度、方向反转。','压力数字越小越容易触发。每项都可以沿用 Kindle 设置。','系统短暂占用时会重试；持续占用请保留操作步骤和日志，不会强行解锁驱动。'],pagepress,24,'设备设置'),
('32 / 维护与恢复',['维护与恢复中分为前端恢复、原生界面设置、诊断工具和退出操作。','部分只作用于原生文件列表的设置移到“原生界面设置”，避免与墨页书库选项混淆。','首次排查问题，可先临时回原生菜单确认是插件还是 KOReader 行为。'],f('test-results-051','tutorial-maintenance-voyage.png'),22,'维护与排障'),
('33 / 界面打不开的恢复方法',['完全退出 KOReader，把 plugins/einkfrontend.koplugin 暂时移走，再启动。','保留书籍和 settings 配置，先恢复原生界面；不要通过删除书库来修复界面。','恢复旧插件备份后可回退。反馈时附版本、机型、操作步骤与相关日志。'],None,22,'维护与排障'),
('34 / 网页连不上时逐项检查',['确认同一局域网，避开访客网络 / AP隔离；核对 Kindle 未休眠、服务未关闭。','重新扫码，不要只输入 IP 和端口而漏掉密钥。会话过期后旧地址不可继续用。','不要配置公网端口转发。HTTP没有加密，只在可信 Wi-Fi 使用。'],web,24,'维护与排障'),
('35 / 第一次使用的建议顺序',['先传一本小的 TXT 或 EPUB，确认书库能看到并正常打开。','再测试一份 EPUB 重排副本，对比插图、脚注、目录与阅读效果。','最后调整主页、保存自己的主题。原书、插件和配置备份都保留到确认稳定。'],home,22,'完成与实测边界'),
]
# Installation diagram is precise explanatory artwork, not a simulated file-manager screenshot.
diag=Image.new('RGB',(1000,820),'#f6f8f8');d=ImageDraw.Draw(diag);d.text((50,35),'安装目录示意',font=font(38),fill='#24343b')
for i,(text,indent) in enumerate([('Kindle 可见磁盘',0),('koreader',1),('plugins',2),('einkfrontend.koplugin',3),('main.lua',4),('_meta.lua',4),('einkfrontend / resources',4)]):
 y=130+i*76;x=60+indent*48;d.rounded_rectangle((x,y,x+40,y+35),5,fill='#ffd814' if i<4 else '#d6e2e4');d.text((x+56,y-7),text,font=font(32),fill='#1c303b')
d.text((50,714),'书籍目录另设为 documents / ManualBook',font=font(26),fill='#48636a');diagram=frames/'install-diagram.png';diag.save(diagram)
def wrap(s,draw,width,fo):
 result=[];line=''
 for char in s:
  if draw.textlength(line+char,font=fo)>width:result.append(line);line=char
  else:line+=char
 if line:result.append(line)
 return result
chapters=[];cursor=0;html_parts=[]
for i,(title,details,image,seconds,chapter) in enumerate(scenes):
 if i==15 and (P/'test-results-051/tutorial-recording.json').exists():cursor+=41
 if not chapters or chapters[-1]['title']!=chapter:chapters.append({'title':chapter,'start':cursor})
 im=Image.new('RGB',(1920,1080),'#f7f8f8');d=ImageDraw.Draw(im);d.rectangle((0,0,1920,14),fill='#ffd814');d.text((70,45),'墨页 · 安装与使用教程',font=font(27),fill='#52676e');d.text((70,102),title,font=font(43),fill='#102a33')
 y=230
 for n,detail in enumerate(details):
  d.ellipse((74,y+11,84,y+21),fill='#007185')
  for line in wrap(detail,d,615,font(31)):
   d.text((104,y),line,font=font(31),fill='#263d46');y+=54
  y+=26
 source=Path(image) if image else diagram
 assert source.exists(),source
 pic=Image.open(source).convert('RGB');pic.thumbnail((1020,810),Image.Resampling.LANCZOS);im.paste(pic,(820+(1020-pic.width)//2,186+(810-pic.height)//2))
 d.text((70,1018),f'{i+1:02d} / {len(scenes):02d}   |   0.5.0-test.1   |   字幕教程，可暂停查看',font=font(22),fill='#65777d');d.text((1220,1018),'界面截图为桌面模拟 / 测试数据',font=font(22),fill='#65777d')
 im.save(frames/f'{i:03d}.png');time=f'{cursor//60:02d}:{cursor%60:02d}';thumb=Image.open(source).convert('RGB');thumb.thumbnail((880,920),Image.Resampling.LANCZOS);buffer=BytesIO();thumb.save(buffer,format='JPEG',quality=82,optimize=True);encoded=base64.b64encode(buffer.getvalue()).decode();items=''.join('<li>'+html.escape(t)+'</li>' for t in details)
 html_parts.append(f'<section id="step{i}"><span class="time">视频 {time}</span><h2>{html.escape(title)}</h2><div class="grid"><ol>{items}</ol><img alt="{html.escape(title)}：界面示例" src="data:image/jpeg;base64,{encoded}" loading="lazy"></div></section>')
 cursor+=seconds
(frames/'scenes.json').write_text(json.dumps([{'title':t,'details':d,'image':im,'duration':sec,'chapter':c} for t,d,im,sec,c in scenes],ensure_ascii=False,indent=2)+'\n')
html_page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>墨页 0.5.0 · 安装与使用教程</title><style>*{box-sizing:border-box}body{font:16px/1.9 system-ui,'Microsoft YaHei',sans-serif;color:#18323d;margin:0;background:#fff}header{background:#f4f7f7;border-top:8px solid #ffd814;padding:36px max(20px,calc((100vw - 1180px)/2))}h1{font-size:32px;line-height:1.3}header p{max-width:950px}nav{max-width:1180px;margin:20px auto;padding:0 20px;display:flex;gap:12px;flex-wrap:wrap}a{color:#007185}main{max-width:1180px;margin:auto;padding:0 20px 60px}section{border-top:1px solid #d5d9d9;padding:30px 0;scroll-margin-top:10px}h2{font-size:24px;margin:6px 0 20px}.time{color:#65777d;font-size:13px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:35px}li{margin-bottom:16px;padding-left:5px}img{max-width:100%;max-height:650px;object-fit:contain;border:1px solid #e3e9ea;background:#f7fafa}.box{padding:18px 23px;background:#fff8d7;border-left:4px solid #ffd814}@media(max-width:760px){.grid{grid-template-columns:1fr}h1{font-size:27px}h2{font-size:21px}header{padding:24px 20px}.grid img{max-height:580px}}</style><header><h1>墨页：安装、传书、重排与日常阅读</h1><p>0.5.0-test.1 完整使用教程。原生界面使用真实 KOReader 桌面模拟，网页部分为实际本地传书页面。所有书籍和统计为演示素材，不代表已完成 Voyage / Kindle 2022 实机验收。</p><div class="box">建议：先备份 → 安装 → 目录向导 → 传一本原书 → 检查阅读 → 再尝试重排副本。不要覆盖原书，也不要删除配置来排查界面问题。</div></header>'''
html_page+='<nav>'+''.join(f'<a href="#step{next(i for i,x in enumerate(scenes) if x[4]==c["title"])}">{html.escape(c["title"])}</a>' for c in chapters)+'</nav><main>'+''.join(html_parts)+'''<section><h2>验证与反馈</h2><p>桌面验证包括真实 KOReader 引擎、LuaSocket HTTP、Chromium 和测试目录中的逐字节对比。实机 Wi-Fi、防火墙、压力手感、休眠恢复与残影仍需验证。若有问题，请给出机型、固件、KOReader版本、墨页版本、触发步骤、截图与相关日志；不要公开包含临时会话密钥的地址。</p><p>重排基于用户提供的离线工具进行整合与安全加固；JSZip / pako 保留 MIT 许可。这个工具独立于亚马逊服务，不能解密 DRM，也不把亚马逊云端书库同步到设备。</p></section></main></html>'''
(P/'docs/墨页安装与使用教程.html').write_text(html_page);(P/'einkfrontend.koplugin/resources/guide.html').write_text(html_page);(O/'墨页_0.5.0_安装与使用教程.html').write_text(html_page)
# Main silent captioned video; browser recording will be added as its own final chapter.
concat=''.join("file '"+str(frames/f'{i:03d}.png')+"'\nduration "+str(scene[3])+"\n" for i,scene in enumerate(scenes));concat+="file '"+str(frames/f'{len(scenes)-1:03d}.png')+"'\n";(frames/'slides.txt').write_text(concat)
metadata=';FFMETADATA1\ntitle=墨页安装与使用教程 0.5.0-test.1\ncomment=字幕教程，无配音；原生为桌面模拟，网页部分为真实操作录屏。\n'
for i,c in enumerate(chapters):metadata+=f'\n[CHAPTER]\nTIMEBASE=1/1000\nSTART={c["start"]*1000}\nEND={(chapters[i+1]["start"] if i+1<len(chapters) else cursor)*1000}\ntitle={c["title"]}\n'
(frames/'chapters.ffmeta').write_text(metadata);(frames/'timeline.json').write_text(json.dumps({'seconds':cursor,'chapters':chapters,'scenes':len(scenes)},ensure_ascii=False,indent=2)+'\n');print({'frames':len(scenes),'seconds':cursor,'guide_bytes':len(html_page.encode())})
