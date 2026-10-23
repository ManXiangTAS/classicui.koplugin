require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');G_reader_settings=require('luasettings'):open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,full_takeover=true})
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local Event=require('ui/event')
local FM=require('apps/filemanager/filemanager');local Reader=require('apps/reader/readerui')
local P=require('einkfrontend/paint');local S=P.s;local Rail=require('einkfrontend/scrollrail')
local root=assert(os.getenv('EINK_PROJECT'));local books=assert(os.getenv('EINK_030_BOOKS'));local variant=assert(os.getenv('EINK_VARIANT'))
local out=assert(os.getenv('EINK_TEST_OUTPUT'))..'/';local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function shot(name)
 UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(out..file);report.frames[#report.frames+1]=file
end
local function find(w,id) UI:forceRePaint();for _,h in ipairs(w.hits or {}) do if h.id==id then return h end end end
local function center(h) return {x=h.x+h.w/2,y=h.y+h.h/2} end
local function tap(w,id) local h=assert(find(w,id),id);UI:sendEvent(Event:new('Gesture',{ges='tap',pos=require('ui/geometry'):new(center(h))})) end
local function railGeometry(w,t)
 assert(t and t.w==S(44));assert(math.abs((w.dimen.w-t.x-t.w)-S(16))<=1)
 for _,hit in ipairs(w.hits) do
  if hit.y<t.y+t.h and hit.y+hit.h>t.y then assert(hit.x+hit.w<=t.x-S(12),hit.id or 'overlap') end
 end
 assert(t.thumb_h>=math.min(S(36),t.track_h))
end
local function drag(w,t,handler,release,value)
 local start={x=t.x+t.w/2,y=t.thumb_y+t.thumb_h/2}
 local pos={x=start.x,y=value==0 and t.track_y-S(40) or t.track_y+t.track_h+S(40)}
 w[handler](w,nil,{pos=pos,start_pos=start,relative={x=0,y=pos.y-start.y}})
 UI:forceRePaint();w[release](w,nil,{pos=pos,relative={x=0,y=pos.y-start.y}});UI:forceRePaint()
end
FM:showFiles(books);local app=FM.instance.einkfrontend.app
for _=1,30 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end
local close={};for _,e in ipairs(UI._window_stack) do if e.widget.text then close[#close+1]=e.widget end end;for _,w in ipairs(close) do UI:close(w) end
local V=require('einkfrontend/bookvalue');local DS=require('docsettings');local L=require('einkfrontend/homelayout');local lfs=require('libs/libkoreader-lfs');local json=require('rapidjson')
local a,b,c={file=books..'/A.epub',title='书籍甲',authors='作者甲',series=''}, {file=books..'/B.epub',title='书籍乙',authors='作者乙',series=''}, {file=books..'/navigation.epub',title='书籍丙',authors='作者丙',series=''}
app.library.books={a,b,c};local value=app.book_value
local function status(book,s) local d=DS:open(book.file);d:saveSetting('summary',{status=s});assert(d:flush()~=false) end
check('Money uses exact fen and rejects negatives, nonfinite values and extra precision',function()
 assert(V.parse('39.80')==3980 and V.parse(' 0.10 ')==10 and V.parse('0')==0 and V.parse('')==nil)
 for _,bad in ipairs({'-1','nan','Infinity','1e3','1.234','1,000','0x20','9999999.99','2.','..2'}) do assert(not pcall(V.parse,bad),bad) end
 assert(not pcall(V.parse,'0',true));assert(V.parse('25',true)==2500)
end)
check('Only completed books count; missing and free prices differ',function()
 status(a,'reading');status(b,'complete');status(c,'complete');value:investment('100');value:setPrice(a.file,'99');value:setPrice(b.file,'0')
 local s=value:summary();assert(s.total==0 and s.priced==1 and s.missing==1 and s.percent==0)
 status(a,'complete');s=value:summary();assert(s.total==9900 and s.percent==99 and s.comment=='就快回本')
end)
check('Rounding never declares break-even too early, and progress may exceed 100 percent',function()
 value:setPrice(a.file,'99.99');assert(value:summary().percent==99 and value:summary().comment=='就快回本')
 value:setPrice(c.file,'0.01');assert(value:summary().total==10000 and value:summary().comment=='已经回本')
 value:setPrice(a.file,'300');assert(value:summary().percent==300 and value:summary().comment=='超值书旅')
end)
check('Repeated completion does not add duplicate reading credit',function()
 local one=value:summary().total;for _=1,4 do status(a,'complete');assert(value:summary().total==one) end
end)
check('Identical uploaded copies count once using the latest explicit price',function()
 local id=string.rep('a',64);value:setPrice(a.file,'40',id);value:setPrice(b.file,'50',id)
 local s=value:summary();assert(s.total==5001 and s.completed==2 and s.priced==2)
 value:setPrice(b.file,'',id);assert(value:summary().total==1 and value:summary().missing==1)
end)
check('Uploading an identical book with an untouched price preserves its existing value',function()
 local id=string.rep('a',64);value:setPrice(a.file,'40',id);value:recordUpload(b.file,'',id)
 assert(value:price(b.file)==4000 and value:summary().total==4001)
end)
check('Reversing completion reverses its contribution',function()
 value:setPrice(a.file,'40');status(a,'reading');status(b,'reading');status(c,'reading');assert(value:summary().total==0)
 status(a,'complete');assert(value:summary().total==4000)
end)
check('Failed price writes preserve the last persisted state',function()
 local store=app.library.settings;local old=value:summary().investment;local flush=store.flush
 store.flush=function()return false end;assert(not pcall(value.investment,value,'999'));store.flush=flush;assert(value:summary().investment==old)
end)
check('Title and author edits are native metadata overrides and preserve original bytes',function()
 app.library:editDetails(a,{title='新书名 & <原文>',authors='测试作者'})
 local props=require('apps/filemanager/filemanagerbookinfo'):new{ui=app.plugin.ui}:getDocProps(a.file,nil,false)
 assert(props.title=='新书名 & <原文>' and props.authors=='测试作者' and a.title=='新书名 & <原文>')
 assert(not pcall(app.library.editDetails,app.library,a,{title=''}))
end)
check('Editing a title alone retains the native original author',function()
 local title=a.title;app.library:editDetails(a,{title='仅修改标题'})
 local props=require('apps/filemanager/filemanagerbookinfo'):new{ui=app.plugin.ui}:getDocProps(a.file,nil,false)
 assert(props.authors=='测试作者');app.library:editDetails(a,{title=title})
end)
check('Metadata write failure restores the earlier title and author',function()
 local method=DS.flushCustomMetadata;DS.flushCustomMetadata=function()return false end
 assert(not pcall(app.library.editDetails,app.library,a,{title='不应保存',authors='错误'}));DS.flushCustomMetadata=method
 assert(a.title=='新书名 & <原文>' and a.authors=='测试作者')
end)
check('All explicit reading states work and completing a book immediately updates the return model',function()
 for _,entry in ipairs({{'new','未读'},{'reading','在读'},{'complete','已完成'},{'abandoned','搁置'}}) do
  app.library:setReadStatus(a,entry[1]);assert(app.library:status(a)==entry[2])
 end
 app.library:setReadStatus(a,'complete');assert(value:summary().total==4000)
end)
check('Corrupted value data cannot crash book details or overwrite existing records',function()
 local saved=app.library.settings:readSetting('reading_return');app.library.settings:saveSetting('reading_return',{version=9})
 assert(value:price(a.file)==nil);assert(not pcall(value.summary,value));assert(not pcall(value.investment,value,'500'))
 assert(app.library.settings:readSetting('reading_return').version==9);app.library.settings:saveSetting('reading_return',saved)
end)
check('Legacy home layouts retain user choices and append the return widget hidden',function()
 local config=L.defaults();table.remove(config.widgets);config.widgets[2].enabled=false;config.widgets[1].span=1
 local settings=require('luasettings'):open(require('datastorage'):getSettingsDir()..'/einkfrontend-home.lua');settings:saveSetting('layout',config);settings:flush()
 local migrated=L.new();assert(not migrated.error and #migrated.config.widgets==14 and migrated.config.widgets[1].span==1 and not migrated.config.widgets[2].enabled)
 assert(migrated.config.widgets[14].id=='reading_return' and not migrated.config.widgets[14].enabled)
 assert(#require('luasettings'):open(settings.file):readSetting('layout').widgets==13);app.home_layout=migrated
end)
check('The ring fits full and half rows without making the home scrollable',function()
 local config=L.defaults();for _,w in ipairs(config.widgets) do w.enabled=w.id=='reading_return' end
 assert(app.home_layout:commit(config));app:open('home');UI:forceRePaint();assert(app.screen.scroll_max==0);shot('return-full')
 config.widgets[#config.widgets].span=1;assert(app.home_layout:commit(config));app:render();UI:forceRePaint();assert(app.screen.home_fit.fits);shot('return-half')
end)
check('Return settings have no misplaced More and global search finds the feature',function()
 app:open('reading_return');UI:forceRePaint();assert(app.screen.model.title=='阅读回报' and not find(app.screen,'settings_more'));shot('return-settings')
 require('einkfrontend/settings').search(app,'回报');assert(#app.screen.model.rows>0)
end)
local rootpath=books..'/ManualBook';assert(lfs.mkdir(rootpath));local Web=require('einkfrontend/transferweb');local server=Web.new(app,{root=rootpath,ip='127.0.0.1',no_firewall=true});app.transfer_server=server
local headers={host=server.host,authorization='Bearer '..server.token,['content-type']='application/json'}
local function req(method,path,d,h) local response=server:request(method,path,h or headers,d or '');local code=tonumber(response:match('HTTP/1.1 (%d+)'));local body=response:match('\r\n\r\n(.*)');return code,body and json.decode(body) end
check('Reflow routes are removed; the upload page cannot frame or connect remote content',function()
 assert(req('GET','/polish')==404 and req('GET','/jszip.min.js')==404)
 local r=server:request('GET','/',{host=server.host},'');assert(r:find("frame-src 'none'",1,true) and not r:find('iframe',1,true))
end)
check('Security headers never rewrite response bytes or invalidate their Content-Length',function()
 local body='{"note":"img-src blob:;"}'
 local response=server:response(200,body)
 assert(response:match('\r\n\r\n(.*)')==body)
 assert(tonumber(response:match('Content%-Length: (%d+)'))==#body)
 assert(response:find("img-src 'self' blob:; frame-src 'none';",1,true))
end)
check('Invalid metadata and prices are rejected before file creation',function()
 for _,d in ipairs({{name='a.txt',size=4,title=''},{name='a.txt',size=4,author=3},{name='a.txt',size=4,price='-10'},{name='a.txt',size=4,price='0.001'},{name='a.txt',size=4,command='ls'},{name='../a.txt',size=4,title='x'}}) do assert(req('POST','/api/begin',json.encode(d))==400);assert(not server.store.upload) end
 assert(req('POST','/api/begin',json.encode{name='a.txt',size=4}, {host='evil',authorization=headers.authorization,['content-type']='application/json'})==403)
end)
check('Deep JSON is rejected before decoding and public asset routes remain bounded',function()
 local body='{"title":'..string.rep('[',50)..'0'..string.rep(']',50)..'}'
 assert(req('POST','/api/begin',body)==400 and not server.store.upload)
 assert(server:request('GET','/assets/kindle-devices.png',{host=server.host},''):match('HTTP/1.1 200'))
 assert(req('GET','/assets/../../main.lua')==404)
end)
check('Cancellation reports failed cleanup and permits retry without losing delivered books',function()
 local _,u=req('POST','/api/begin',json.encode{name='取消.txt',size=5,title='取消'})
 local temp=assert(server.store.temp);local remove=os.remove
 os.remove=function(path) if path==temp then return nil,'fixture' end;return remove(path) end
 local code,result=req('POST','/api/cancel/'..u.id,'');os.remove=remove
 assert(code==400 and not result.cancelled and lfs.attributes(temp))
 local retried,data=req('POST','/api/cancel/'..u.id,'');assert(retried==200 and data.cancelled and not lfs.attributes(temp))
end)
check('Upload preserves bytes and persists filename, native metadata and price; finish replay is idempotent',function()
 local code,u=req('POST','/api/begin',json.encode{name='新书.txt',size=5,title='测试标题',author='测试作者',price='39.80'});assert(code==200)
 local h={host=server.host,authorization=headers.authorization,['content-type']='application/octet-stream'}
 assert(req('POST','/api/chunk/'..u.id..'/0','hello',h)==200)
 local n,saved=req('POST','/api/finish/'..u.id,'',h);assert(n==200 and saved.saved and not saved.warning)
 local f=assert(io.open(rootpath..'/新书.txt','rb'));assert(f:read('*a')=='hello');f:close();assert(value:price(rootpath..'/新书.txt')==3980)
 local again,r=req('POST','/api/finish/'..u.id,'',h);assert(again==200 and r.name==saved.name);assert(not lfs.attributes(rootpath..'/新书 (1).txt'))
 local props=require('apps/filemanager/filemanagerbookinfo'):new{ui=app.plugin.ui}:getDocProps(rootpath..'/新书.txt',nil,false);assert(props.title=='测试标题' and props.authors=='测试作者')
end)
check('Metadata failure gives a warning and retains the complete delivered book',function()
 local _,u=req('POST','/api/begin',json.encode{name='保留.txt',size=4,title='保留',author='',price='20'});local h={host=server.host,authorization=headers.authorization,['content-type']='application/octet-stream'}
 req('POST','/api/chunk/'..u.id..'/0','safe',h);local edit=app.library.editDetails;app.library.editDetails=function()error('fixture')end
 local code,result=req('POST','/api/finish/'..u.id,'',h);app.library.editDetails=edit;assert(code==200 and result.saved and result.warning and lfs.attributes(rootpath..'/保留.txt','size')==4)
end)
check('Shutdown removes the temporary file, listener, token and scan task',function()
 req('POST','/api/begin',json.encode{name='中断.txt',size=5,title='中断'});local temp=server.store.temp;assert(lfs.attributes(temp));server:stop()
 assert(not lfs.attributes(temp) and not server.listener and not server.token and not server.scan_job)
end)
app:close();FM.instance:onClose();local f=assert(io.open(out..'interaction-'..variant..'.json','w'));f:write(require('json').encode(report));f:close();os.exit(0)
