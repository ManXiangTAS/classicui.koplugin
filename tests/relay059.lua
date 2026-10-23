require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');G_reader_settings=require('luasettings'):open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,full_takeover=true})
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true});G_reader_settings:saveSetting('keyboard_layout','zh_CN')
G_reader_settings:saveSetting('keyboard_layouts',{'zh_CN','en'});G_reader_settings:saveSetting('virtual_keyboard_enabled',true)
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local FM=require('apps/filemanager/filemanager')
local root=assert(os.getenv('EINK_PROJECT'));local out=root..'/test-results-059/';local variant=os.getenv('EINK_VARIANT')
local report={tests={},variant=variant,device='NOT_RUN'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function ticks() for _=1,20 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end end
FM:showFiles(assert(os.getenv('EINK_030_BOOKS')));local app=FM.instance.einkfrontend.app;ticks();app:open('input_method')
local IME=require('einkfrontend/pinyin');local Stock=require('einkfrontend/stockscreensaver')
local notices={};for _,win in ipairs(UI._window_stack) do if win.widget.text then notices[#notices+1]=win.widget end end
for _,notice in ipairs(notices) do UI:close(notice) end
local function dialog(options)
 options=options or {};options.title=options.title or '中英切换测试';options.input=options.input or ''
 options.buttons={{{text='关闭',callback=function() end}}}
 local d=require('ui/widget/inputdialog'):new(options);UI:show(d);d:onShowKeyboard();UI:forceRePaint()
 return d,d._input_widget,d._input_widget.keyboard
end
local function typecode(box,s) for c in s:gmatch('.') do box:addChars(c) end end
local function close(d) UI:close(d);ticks() end
local B=require('einkfrontend/updateboot');local C=require('einkfrontend/updatecore');local U=require('einkfrontend/updater')
-- Keep the release fixture baseline independent of the installed plugin version.
U.current='0.5.0-test.7'
local S=require('einkfrontend/updatesource');local json=require('json');local copy=require('einkfrontend/catalog').copy
local fixture=json.decode(B.read(root..'/tests/relay-fixtures/manifest-ready.example.json'))
local none=json.decode(B.read(root..'/tests/relay-fixtures/manifest-no-release.example.json'))
local retired=B.read(root..'/tests/relay-fixtures/error-retired.example.json')
local config={source='relay',relay_base=S.default_base,channel='testing'}
local function parsed(value) return C.relay(value or copy(fixture),U.current,'testing',S.default_base) end
local function waitJob()
 for _=1,1500 do if not U.job then return end;UI:shiftScheduledTasksBy(-require('ui/time').s(.25));UI:_checkTasks();require('ffi').C.usleep(1000) end
 assert(not U.job,'worker did not terminate')
end
local function sandbox()
 local path=DS:getDataDir()..'/prepare';if not require('libs/libkoreader-lfs').attributes(path) then B.mkdir(path);B.mkdir(B.work(path)) end;return path
end
check('Default relay keeps the full query prefix and channel uses ampersand',function()
 assert(U.config().source=='relay' and U.config().relay_base==S.default_base)
 assert(S.base(S.default_base)==S.default_base)
 assert(S.url(S.default_base,'/v1/classicui/manifest','testing')=='https://www.2001330.xyz/index.php?classicui_relay=/v1/classicui/manifest&channel=testing')
 local r=parsed();assert(S.url(S.default_base,r.download_path)==S.default_base..r.download_path)
 assert(not U.config().auto_check and not U.config().auto_install)
end)
check('Custom WordPress subdirectories and path endpoints preserve their exact prefixes',function()
 assert(S.base(' https://Relay.Example/blog/index.php?classicui_relay= ')=='https://relay.example/blog/index.php?classicui_relay=')
 assert(S.url('https://relay.example/blog/index.php?classicui_relay=','/v1/classicui/manifest','stable')=='https://relay.example/blog/index.php?classicui_relay=/v1/classicui/manifest&channel=stable')
 assert(S.url(S.base('https://relay.example/blog/updates/'),'/v1/classicui/manifest','stable')=='https://relay.example/blog/updates/v1/classicui/manifest?channel=stable')
end)
check('Base validation rejects credentials, arbitrary queries, encoding, traversal and HTTP',function()
 for _,base in ipairs({'http://relay.example','https://user@relay.example','https://relay.example:8443','https://relay.example/#x','https://relay.example/?x=1','https://relay.example/index.php?classicui_relay=/foo','https://relay.example/index.php?classicui_relay=&x=1','https://relay.example/a/../b','https://relay.example/%2e%2e','https://relay.example/a//b','https://relay.example/a\\b','https://relay.example\n/x','https://relay..example/a'}) do assert(not pcall(S.base,base),base) end
end)
check('Ready manifest maps official provenance and same-base package URL without GitHub download',function()
 local r,info=parsed();assert(r.version=='0.5.0-test.8' and r.relay_base==S.default_base and info.status=='ready' and not info.stale)
 local manifest_url=S.url(S.default_base,'/v1/classicui/manifest','testing');assert(C.allowed(manifest_url,config))
 assert(C.allowed(S.url(S.default_base,r.download_path),config))
 for _,url in ipairs({r.url,'https://www.2001330.xyz.evil.test/index.php?classicui_relay='..r.download_path,'https://www.2001330.xyz/v1/classicui/manifest?channel=testing',S.default_base..'/v1/classicui/manifest?channel=testing',S.default_base..r.download_path..'&token=x'}) do assert(not C.allowed(url,config),url) end
end)
check('Protocol, repository, channel, status and full asset fields are validated',function()
 for _,mutate in ipairs({
  function(d) d.schema=2 end,function(d) d.repo='attacker/repo' end,function(d) d.channel='stable' end,function(d) d.status='busy' end,function(d) d.stale='false' end,
  function(d) d.release.version='v0.5.0-test.8' end,function(d) d.release.tag='v0.5.0-test.9' end,function(d) d.release.prerelease='true' end,
  function(d) d.release.asset.name='source.zip' end,function(d) d.release.asset.size=1.5 end,function(d) d.release.asset.size=C.max_zip+1 end,
  function(d) d.release.asset.sha256=string.rep('A',64) end,function(d) d.release.asset.origin_url='https://evil.test/package.zip' end,
  function(d) d.release.asset.download_path='//evil.test/package.zip' end,function(d) d.release.asset.download_path='/v1/classicui/packages/../x.zip' end,
  function(d) d.release.page='https://evil.test/' end,function(d) d.release.notes={} end,function(d) d.release.koreader={} end,
 }) do local value=copy(fixture);mutate(value);assert(not pcall(parsed,value)) end
end)
check('No release and stale remain distinct from unavailable or incompatible update',function()
 local r,info=C.relay(none,U.current,'stable',S.default_base);assert(not r and info.status=='no_release')
 local value=copy(fixture);value.stale=true;r,info=parsed(value);assert(r and info.stale)
 value=copy(fixture);value.release.koreader={'v0.0.1'};assert(not pcall(parsed,value))
 assert(not C.relay(copy(fixture),'0.5.0-test.8','testing',S.default_base));assert(not C.relay(copy(fixture),'0.5.0-test.9','testing',S.default_base))
 value=copy(fixture);value.channel='stable';assert(not pcall(C.relay,value,U.current,'stable',S.default_base))
end)
check('Fetch uses complete query URL and rejects HTML instead of reporting latest',function()
 local get=C.get;local called
 C.get=function(url,path,limit,source) called=url;assert(not path and source.source=='relay');return json.encode(fixture) end
 assert(C.fetch(U.current,'testing',config).relay_base==S.default_base);assert(called==S.url(S.default_base,'/v1/classicui/manifest','testing'))
 C.get=function() return '<html>403 Forbidden</html>' end;assert(not pcall(C.fetch,U.current,'testing',config));C.get=get
end)
check('Actual downloader uses relay path, validates bytes and reuses safe staging',function()
 local path=sandbox();local get=C.get;local entry=json.decode(B.read(root..'/tests/update-fixtures/index.json')).valid
 local r=parsed();r.size=entry.size;r.sha256=entry.sha256;r.download_path='/v1/classicui/packages/'..r.version..'/'..r.sha256..'.zip'
 C.get=function(url,file,limit,source) assert(source.source=='relay' and url==S.default_base..r.download_path);B.write(file,B.read(root..'/tests/update-fixtures/valid.zip'));return entry.size end
 assert(C.download(path,r).version==r.version and B.pending(path).version==r.version);assert(not B.regular(path..'/main.lua'));B.clearPending(path)
 C.get=function(_,file) B.write(file,'wrong');return 5 end;assert(not pcall(C.download,path,r));assert(not B.regular(B.work(path)..'/download.zip'));C.get=get
end)
check('Retired package triggers exactly one fresh manifest and a bounded second download',function()
 local download,fetch=C.download,C.fetch;local downloads,fetches=0,0;local r=parsed()
 C.download=function() downloads=downloads+1;if downloads==1 then error(C.httpError(410,{},retired)) end;return {version=r.version} end
 C.fetch=function(current,channel,source) fetches=fetches+1;assert(current==U.current and channel=='testing' and source.relay_base==S.default_base);return parsed() end
 assert(C.prepare(sandbox(),r,U.current,config).version==r.version);assert(downloads==2 and fetches==1)
 downloads,fetches=0,0;C.download=function() downloads=downloads+1;error(C.httpError(410,{},retired)) end
 assert(not pcall(C.prepare,sandbox(),r,U.current,config));assert(downloads==2 and fetches==1)
 C.download=download;C.fetch=fetch
end)
check('Retired refresh with no update preserves existing pending package and other failures do not retry',function()
 local path=sandbox();local download,fetch=C.download,C.fetch;local count=0
 B.save(B.work(path),'pending.json',{schema=1,version='0.5.0-test.6'})
 C.download=function() error(C.httpError(410,{},retired)) end;C.fetch=function() count=count+1;return nil,{status='no_release',stale=false} end
 assert(C.prepare(path,parsed(),U.current,config).no_update and count==1 and B.pending(path).version=='0.5.0-test.6')
 os.remove(B.work(path)..'/pending.json');count=0;C.download=function() error(C.httpError(503,{['retry-after']='60'},'')) end
 local ok,err=pcall(C.prepare,path,parsed(),U.current,config);assert(not ok and type(err)=='table' and err.status==503 and count==0)
 C.download=download;C.fetch=fetch
end)
check('Retry-After seconds and HTTP dates survive structured errors and block premature checks',function()
 local err=C.httpError(503,{['retry-after']='120'},'{"schema":1,"error":{"code":"CACHE_NOT_READY","message":"缓存未就绪","retryable":true}}')
 assert(err.retry_at>=os.time()+119 and tostring(err):find('CACHE_NOT_READY',1,true))
 local dated=C.httpError(429,{['retry-after']=os.date('!%a, %d %b %Y %H:%M:%S GMT',os.time()+300)},'');assert(dated.retry_at>=os.time()+299)
 U.set('source','relay');U.error(nil,tostring(err),err.retry_at);local net=require('ui/network/manager');local run=net.runWhenOnline;local called=false
 net.runWhenOnline=function() called=true end;U.check(nil,false);assert(not called and not U.job);net.runWhenOnline=run;U.save({})
end)
check('Switching source or channel clears cached release, stale status and retry deadline',function()
 U.save({release=parsed(),info={stale=true},retry_at=os.time()+100});assert(U.state().release)
 U.set('source','github');assert(not U.state().release and not U.state().retry_at)
 U.set('relay_base','https://relay.example/blog/index.php?classicui_relay=');assert(U.config().source=='custom' and not U.state().info)
 U.save({release=parsed()});U.set('channel','stable');assert(not U.state().release)
 U.set('channel','testing');U.set('source','relay');assert(U.config().custom_base=='https://relay.example/blog/index.php?classicui_relay=')
end)
check('Real worker preserves no-release and stale states without changing the page',function()
 local fetch=C.fetch;local net=require('ui/network/manager');local run=net.runWhenOnline;net.runWhenOnline=function(_,fn) fn() end
 local message=app.message;local text;app.message=function(_,value) text=value end
 C.fetch=function() return nil,{status='no_release',stale=true} end;app:open('plugin_update');U.check(app,false);waitJob()
 assert(U.state().info.status=='no_release' and U.state().info.stale and text:find('暂无发布',1,true) and text:find('尚未刷新',1,true))
 C.fetch=function() error(C.httpError(503,{['retry-after']='600'},'{"schema":1,"error":{"code":"CACHE_NOT_READY","message":"缓存未就绪","retryable":true}}')) end
 U.check(app,false);waitJob();assert(U.state().error:find('CACHE_NOT_READY',1,true) and U.state().retry_at>=os.time()+599)
 app.message=message;C.fetch=fetch;net.runWhenOnline=run;U.save({})
end)
check('Late worker responses from a different source cannot update current state',function()
 local run=U.run;local net=require('ui/network/manager');local online=net.runWhenOnline;net.runWhenOnline=function(_,fn) fn() end
 local done;U.run=function(_,_,callback) done=callback;return true end
 app:open('plugin_update');U.check(app,false);assert(done);U.set('source','github');done({ok=true,result={release=parsed()}})
 assert(not U.state().release);U.run=run;net.runWhenOnline=online;U.set('source','relay')
end)
check('Update-source setting is local to updater; global menus retain scoped More behavior',function()
 app:open('plugin_update');local found=false;for _,row in ipairs(app.screen.model.rows) do found=found or row.title=='更新源' end;assert(found)
 app:go('plugin_update_source');assert(app.screen.model.title=='更新源' and not require('einkfrontend/context').allowed(app,'settings_popup'))
 local rows=app.screen.model.rows;assert(rows[1].title=='墨页中转（默认）' and rows[1].checked and rows[2].title=='GitHub 直连' and rows[3].title=='自定义中转地址')
 UI:forceRePaint();Device.screen.bb:writePNG(out..'relay-source-'..variant..'.png')
 for _,category in ipairs(app.native.categories) do app:open('catalog_category',category[1]);for _,row in ipairs(app.screen.model.rows) do assert(row.title~='更新源') end end
 require('einkfrontend/settings').search(app,'中转');local found=false;for _,row in ipairs(app.screen.model.rows) do found=found or row.title=='墨页更新' end;assert(found)
end)
app:close();local f=assert(io.open(out..'relay-'..variant..'.json','w'));f:write(json.encode(report));f:close();os.exit(0)
