require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');local Settings=require('luasettings')
G_reader_settings=Settings:open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,reader_entry=true,full_takeover=true})
G_reader_settings:saveSetting('document_metadata_folder','dir')
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local Reader=require('apps/reader/readerui');local FM=require('apps/filemanager/filemanager')
local P=require('einkfrontend/paint');local S=P.s;local B=P.BB
local Layout=require('einkfrontend/homelayout');local Copy=require('einkfrontend/catalog').copy
local Equal=require('einkfrontend/adapter').equal;local Stats=require('einkfrontend/homestats')
local root=assert(os.getenv('EINK_PROJECT'));local books=assert(os.getenv('EINK_030_BOOKS'));local variant=os.getenv('EINK_VARIANT')
local output=root..'/test-results-051/';local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn) local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil};print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err) end
local function clear() local list={};for _,entry in ipairs(UI._window_stack) do if entry.widget.text then list[#list+1]=entry.widget end end;for _,w in ipairs(list) do UI:close(w) end end
local function shot(name,meta) clear();UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(output..file);meta=meta or {};meta.file=file;report.frames[#report.frames+1]=meta end
local function hit(widget,id) UI:setDirty(widget,"ui");UI:forceRePaint();for _,h in ipairs(widget.hits) do if h.id==id then assert(h.callback,id);return h end end;error('missing hit '..id) end
local function activate(widget,id) return hit(widget,id).callback() end

local Store=require('einkfrontend/transferstore');local T=require('einkfrontend/transfersettings');local Web=require('einkfrontend/transferweb');local lfs=require('libs/libkoreader-lfs')
G_reader_settings:delSetting('eink_transfer');G_reader_settings:saveSetting('eink_frontend',{auto_open=true,full_takeover=true})
FM:showFiles(books);local app=FM.instance.einkfrontend.app;UI:_checkTasks()
check('First automatic launch opens the setup wizard before ordinary library navigation',function()assert(app.screen and app.screen.model.route.id=='transfer_setup')end)
app:open('settings')
local function row(title) for _,r in ipairs(app.screen.model.rows) do if r.title==title then return r end end;error('missing row '..title) end
local function drain() for i=1,500 do UI:_checkTasks();if not app.library.job then return end;require('socket').sleep(.002) end;error('scan did not finish') end
local target=books..'/ManualBook';assert(lfs.mkdir(target));local store=Store.new(target);local id=string.rep('a',48)
check('Only safe basenames supported books and bounded sizes can start an upload',function()
 for _,name in ipairs({'../escape.epub','/etc/passwd','x\\x.epub','.hidden.epub','a.lua','x.epub'..string.char(0),'x.epub\r\nX: a','a.epub '}) do assert(not pcall(store.begin,store,name,1,id)) end
 for _,size in ipairs({0,-1,0/0,Store.limit+1,1.5}) do assert(not pcall(store.begin,store,'safe.epub',size,id)) end
 assert(not store.upload)
end)
check('Chunk offsets size and session ID protect order and boundaries',function()
 store:begin('中文书.txt',5,id);assert(not pcall(store.append,store,id,1,'abc'));assert(not pcall(store.append,store,string.rep('b',48),0,'abc'))
 assert(not pcall(store.append,store,id,0,string.rep('x',Store.chunk+1)));assert(store:append(id,0,'abc')==3)
 assert(not pcall(store.finish,store,id));assert(store:append(id,3,'de')==5);assert(store:finish(id)=='中文书.txt')
 local f=assert(io.open(target..'/中文书.txt','rb'));assert(f:read('*a')=='abcde');f:close()
end)
check('Existing books and symlink targets cannot be overwritten',function()
 store:begin('中文书.txt',3,id);store:append(id,0,'new');assert(store:finish(id)=='中文书 (1).txt')
 local f=assert(io.open(target..'/中文书.txt','rb'));assert(f:read('*a')=='abcde');f:close()
 assert(lfs.link(target..'/中文书.txt',target..'/link.txt',true));store:begin('link.txt',3,id);store:append(id,0,'new');assert(store:finish(id)=='link (1).txt')
end)
check('Cancellation removes incomplete temporary files without a visible partial book',function()
 store:begin('partial.epub',5,id);local path=store.temp;store:append(id,0,'abc');store:abort();assert(not lfs.attributes(path) and not lfs.attributes(target..'/partial.epub'))
end)
check('Failed cleanup retains its temporary path and retries before accepting another file',function()
 store:begin('cleanup.txt',5,id);store:append(id,0,'abc');local temp=store.temp;local remove=os.remove
 os.remove=function(path)if path==temp then return nil,'injected unlink failure' end;return remove(path)end
 assert(store:abort()==false and store.temp==temp and store.upload==nil and lfs.attributes(temp))
 os.remove=remove;store:begin('recovered.txt',1,string.rep('b',48));assert(not lfs.attributes(temp));store:abort()
end)
check('Directory traversal symlink roots and file roots are rejected',function()
 assert(not pcall(Store.directory,books..'/../outside',true));assert(not pcall(Store.directory,target..'/中文书.txt',false))
 assert(lfs.link(target,books..'/linked',true));assert(not pcall(Store.new,books..'/linked'))
end)
check('Insufficient free space is rejected before creating a temporary file',function()
 local util=require('ffi/util');local df=util.df;util.df=function()return 100,1 end
 local ok=pcall(store.begin,store,'space.txt',5,id);util.df=df;assert(not ok and not store.upload)
end)
check('Write failures remain cancellable and do not publish a partial book',function()
 store:begin('failed.txt',5,id);local file=store.file;store.file={write=function()return nil end,close=function()return file:close()end}
 assert(not pcall(store.append,store,id,0,'hello'));local temp=store.temp;store:abort();assert(not lfs.attributes(temp) and not lfs.attributes(target..'/failed.txt'))
end)
check('One-time wizard can be skipped without moving files or changing the existing root',function()
 local previous=app.library.root;G_reader_settings:delSetting('eink_transfer');T.wizard(app);assert(app.screen.model.title=='传书向导');shot('transfer-wizard')
 row('保留当前书库，稍后设置').callback();assert(T.config().wizard_seen and app.library.root==previous)
end)
check('Configured destination persists and synchronizes the library without moving source books',function()
 T.configure(app,target);drain();assert(app.library.root==target and T.config().path==target and T.config().configured)
 assert(Settings:open(G_reader_settings.file):readSetting('eink_transfer').path==target)
 assert(lfs.attributes(books..'/A.epub','mode')=='file');app:open('transfer_settings');shot('transfer-settings')
end)
check('Settings header uses More and its two shortcuts preserve scoped search and restart',function()
 app:open('settings');UI:forceRePaint();hit(app.screen,'settings_more');shot('settings-more-entry')
 local dialog=app:showSettingsMore();assert(#dialog.rows==2 and dialog.rows[1].text=='搜索' and dialog.rows[2].text=='重启 KOReader');UI:close(dialog)
 local oldSearch=app.searchSettings;local searched=false;app.searchSettings=function() searched=true end
 dialog=app:showSettingsMore();dialog.rows[1].callback();assert(searched);app.searchSettings=oldSearch
 local oldConfirm,oldFlush,oldRestart=app.confirm,UI.flushSettings,UI.restartKOReader;local flushed,restarted=false,false
 app.confirm=function(_,text,fn) assert(text:find('重启',1,true));fn() end;UI.flushSettings=function() flushed=true end;UI.restartKOReader=function() assert(flushed);restarted=true end
 dialog=app:showSettingsMore();dialog.rows[2].callback();assert(restarted);app.confirm=oldConfirm;UI.flushSettings=oldFlush;UI.restartKOReader=oldRestart
end)
check('Transfer settings are discoverable from both categories and global search',function()
 for _,category in ipairs({'library','network'}) do app:open('catalog_category',category);row('传书与书库').callback();assert(app.screen.model.title=='传书与书库') end
 require('einkfrontend/settings').search(app,'传书');row('传书与书库').callback()
end)
local server=Web.new(app,{ip='127.0.0.1',root=target,no_firewall=true});app.transfer_server=server
local function request(method,path,body,extra)
 local headers={host=server.host,origin=server.origin,authorization='Bearer '..server.token,['content-type']='application/json'}
 for k,v in pairs(extra or {}) do headers[k]=v end
 return server:request(method,path,headers,body or '')
end
check('Upload endpoints reject missing authorization foreign origins and hosts',function()
 assert(request('GET','/api/info',nil,{authorization='wrong'}):find(' 401 ',1,true));assert(request('GET','/api/info',nil,{origin='http://evil'}):find(' 403 ',1,true));assert(request('GET','/api/info',nil,{host='evil'}):find(' 403 ',1,true))
 assert(request('GET','/api/files'):find(' 404 ',1,true));assert(request('GET','/etc/passwd'):find(' 404 ',1,true))
end)
check('HTTP framing rejects smuggling duplicate length fields oversize and unauthorized headers early',function()
 local prefix='POST /api/begin HTTP/1.1\r\nHost: '..server.host..'\r\nAuthorization: Bearer '..server.token..'\r\n'
 for _,tail in ipairs({'Content-Length: 0\r\nContent-Length: 0\r\n\r\n','Transfer-Encoding: chunked\r\n\r\n','Content-Length: -1\r\n\r\n','Content-Length: 0\r\n\r\nx'}) do assert(server:parse(prefix..tail):find(' 400 ',1,true)) end
 assert(server:parse(prefix..'Content-Length: 65537\r\n\r\n'):find(' 413 ',1,true))
 assert(server:parse('POST /api/begin HTTP/1.1\r\nHost: '..server.host..'\r\nContent-Length: 65536\r\n\r\n'):find(' 401 ',1,true))
end)
check('Successful HTTP upload commits exactly once and schedules a real library refresh',function()
 local response=request('POST','/api/begin',require('rapidjson').encode{name='网络上传.txt',size=5});local body=response:match('\r\n\r\n(.*)$');local u=require('rapidjson').decode(body)
 assert(u.id);assert(request('POST','/api/chunk/'..u.id..'/0','hello',{['content-type']='application/octet-stream'}):find(' 200 ',1,true))
 assert(request('POST','/api/finish/'..u.id):find(' 200 ',1,true));assert(request('POST','/api/finish/'..u.id):find(' 400 ',1,true))
 server.scan_job();drain();local found=false;for _,b in ipairs(app.library.books) do if b.file==target..'/网络上传.txt' then found=true end end;assert(found)
end)
check('Temporary firewall rules are scoped and rolled back after partial setup failure',function()
 local originalKindle,execute=Device.isKindle,os.execute;local calls={};Device.isKindle=function()return true end
 os.execute=function(command) calls[#calls+1]=command;return #calls==2 and 1 or 0 end
 local ok=pcall(Web.new,app,{root=target,ip='127.0.0.1'});Device.isKindle=originalKindle;os.execute=execute
 assert(not ok and #calls==3 and calls[1]:find('iptables -I INPUT',1,true) and calls[2]:find('iptables -I OUTPUT',1,true) and calls[3]:find('iptables -D INPUT',1,true))
end)
check('Idle uploads and expired sessions close without leaving partial data',function()
 server.store:begin('idle.txt',8,id);server.store:append(id,0,'abc');local temp=server.store.temp
 server.last_activity=-1000000;server:poll();assert(not server.store.upload and not lfs.attributes(temp))
 local other=Web.new(app,{root=target,ip='127.0.0.1',no_firewall=true});other.expires=0;other:poll();assert(other.stopped and other.token==nil)
end)
check('Suspend stops listening invalidates the token and deletes partial data',function()
 server.store:begin('sleep.txt',8,id);server.store:append(id,0,'abc');local temp=server.store.temp;app.plugin:onSuspend()
 assert(server.stopped and server.token==nil and app.transfer_server==nil and not lfs.attributes(temp));assert(server:request('GET','/api/info',{},''):find(' 401 ',1,true))
end)
check('Changing the library root synchronizes transfer preferences and closes old sessions',function()
 local another=books..'/Other';assert(lfs.mkdir(another));server=Web.new(app,{ip='127.0.0.1',root=target,no_firewall=true});app.transfer_server=server
 app:scanLibrary(another);drain();assert(T.config().path==another and app.library.root==another and server.stopped)
end)
app:close();FM.instance:onClose()
local file=assert(io.open(output..'regression-'..variant..'.json','w'));file:write(require('json').encode(report));file:close();print('COMPLETE '..variant)
