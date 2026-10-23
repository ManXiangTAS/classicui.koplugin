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
local C=require('einkfrontend/updatecore');local B=require('einkfrontend/updateboot');local S=require('einkfrontend/updatesource')
local https=require('ssl.https');local create=https.tcp;local good=tonumber(os.getenv('TLS_GOOD'));local port=good
local output=assert(os.getenv('TLS_OUTPUT'));C.ca_file=os.getenv('TLS_CA')
https.tcp=function(params)
 local factory=create(params)
 return function()
  local conn=factory();local connect=conn.connect
  function conn:connect(host,_) return connect(self,'127.0.0.1',port) end
  return conn
 end
end
local report={checks=0,distinct_cases=0,runs=1,failures=0,scope='Real local LuaSec HTTPS query relay, ZIP staging and bounded 410 recovery; no public-site success claimed',device='NOT_RUN'}
local function check(name,fn) local ok,why=pcall(fn);assert(ok,name..': '..tostring(why));report.checks=report.checks+1;report.distinct_cases=report.distinct_cases+1;print('PASS '..name) end
local function config(mode) return {source='custom',relay_base='https://relay.example/'..mode..'/index.php?classicui_relay=',channel='testing'} end
local serial=0
local function sandbox()
 serial=serial+1;local path=output..'/install-'..serial;B.mkdir(path);B.mkdir(B.work(path));B.atomic(path,'main.lua','live old code');return path
end
check('Actual query manifest uses ampersand channel and verified TLS',function()
 local c=config('good');local r=C.fetch('0.5.0-test.7','testing',c);assert(r.relay_base==c.relay_base and r.version=='0.5.0-test.8')
end)
check('Complete HTTPS package verifies and stages without replacing running code',function()
 local c=config('good');local r=C.fetch('0.5.0-test.7','testing',c);local path=sandbox();assert(C.download(path,r).version==r.version)
 assert(B.pending(path).version==r.version and B.read(path..'/main.lua')=='live old code')
end)
check('Same-source redirect retains query prefix and verified bytes',function()
 local c=config('same');local r=C.fetch('0.5.0-test.7','testing',c);local path=sandbox();assert(C.download(path,r).version==r.version)
end)
check('Relay cannot redirect download to GitHub',function()
 local c=config('cross');local r=C.fetch('0.5.0-test.7','testing',c);local path=sandbox();assert(not pcall(C.download,path,r) and not B.pending(path) and not B.regular(B.work(path)..'/download.zip'))
end)
check('Relay cannot downgrade download to HTTP',function()
 local c=config('downgrade');local r=C.fetch('0.5.0-test.7','testing',c);assert(not pcall(C.download,sandbox(),r))
end)
check('Actual 410 response refreshes manifest then downloads once successfully',function()
 local c=config('retry');local r=C.fetch('0.5.0-test.7','testing',c);local path=sandbox();assert(C.prepare(path,r,'0.5.0-test.7',c).version==r.version)
 assert(C.fetch('0.5.0-test.7','testing',c).notes=='package_calls=2' and B.pending(path).version==r.version)
end)
check('Repeated 410 stops after second attempt and leaves no partial package',function()
 local c=config('expired');local r=C.fetch('0.5.0-test.7','testing',c);local path=sandbox();local ok,err=pcall(C.prepare,path,r,'0.5.0-test.7',c)
 assert(not ok and err.status==410 and err.code=='PACKAGE_RETIRED' and not B.pending(path) and not B.regular(B.work(path)..'/download.zip'))
 assert(C.fetch('0.5.0-test.7','testing',c).notes=='package_calls=2')
end)
check('Actual 503 JSON error preserves Retry-After and is never extracted',function()
 local c=config('busy');local r=C.fetch('0.5.0-test.7','testing',c);local path=sandbox();local ok,err=pcall(C.download,path,r)
 assert(not ok and err.status==503 and err.code=='CACHE_NOT_READY' and err.retry_at>=os.time()+59 and not B.regular(B.work(path)..'/download.zip'))
end)
check('Truncated response and wrong SHA remove temporary bytes and preserve live files',function()
 for _,mode in ipairs({'truncated','wrongsha'}) do
  local c=config(mode);local r=C.fetch('0.5.0-test.7','testing',c);local path=sandbox()
  assert(not pcall(C.download,path,r) and not B.regular(B.work(path)..'/download.zip') and not B.pending(path) and B.read(path..'/main.lua')=='live old code')
 end
end)
check('HTML response is rejected before version parsing',function() assert(not pcall(C.fetch,'0.5.0-test.7','testing',config('html'))) end)
check('Relay certificate hostname and trust checks cannot be skipped',function()
 local c=config('good');port=tonumber(os.getenv('TLS_WRONG'));assert(not pcall(C.fetch,'0.5.0-test.7','testing',c));port=good
 local ca=C.ca_file;C.ca_file=nil;assert(not pcall(C.fetch,'0.5.0-test.7','testing',c));C.ca_file=ca
end)
local f=assert(io.open(output..'/tls.json','w'));f:write(require('json').encode(report));f:close();os.exit(0)
