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
local root=assert(os.getenv('EINK_PROJECT'));local out=root..'/test-results-057/';local variant=os.getenv('EINK_VARIANT')
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
local fixtures=root..'/tests/update-fixtures/';local index=require('json').decode(B.read(fixtures..'index.json'))
local function release(name)
 local data=index[name or 'valid'];return {version='0.5.0-test.8',tag='v0.5.0-test.8',size=data.size,sha256=data.sha256,url='https://github.com/'..C.repo..'/releases/download/v0.5.0-test.8/ClassicUI_0.5.0-test.8_install.zip',notes='测试更新说明'}
end
local serial=0
local function sandbox(with_manifest)
 serial=serial+1;local path=DS:getDataDir()..'/install-'..serial;B.mkdir(path);B.mkdir(path..'/einkfrontend');B.mkdir(path..'/resources')
 B.atomic(path,'main.lua','old main');B.atomic(path,'einkfrontend/updateboot.lua','old bootstrap');B.atomic(path,'einkfrontend/version.lua',"return '0.5.0-test.7'");B.atomic(path,'obsolete.lua','obsolete');B.atomic(path,'user-note.txt','keep my notes')
 if with_manifest then
  local files={};for _,name in ipairs({'main.lua','einkfrontend/updateboot.lua','einkfrontend/version.lua','obsolete.lua'}) do files[name]=B.hash(path..'/'..name) end
  B.save(path,'UPDATE_MANIFEST.json',{schema=1,version='0.5.0-test.7',files=files,koreader={'v2026.07.1'}})
 end
 B.mkdir(B.work(path));return path
end
local function metadata(v,draft,pre)
 local tag='v'..v;local name='ClassicUI_'..v..'_install.zip'
 return {tag_name=tag,draft=draft,prerelease=pre,body='更新说明',assets={{name=name,size=123,digest='sha256:'..string.rep('a',64),browser_download_url='https://github.com/'..C.repo..'/releases/download/'..tag..'/'..name}}}
end
local function waitJob()
 for _=1,1500 do if not U.job then return end;UI:shiftScheduledTasksBy(-require('ui/time').s(.25));UI:_checkTasks();require('ffi').C.usleep(1000) end
 assert(not U.job,'worker did not terminate')
end
check('Semantic versions compare test.10 and test.9 numerically and stable beats prerelease',function()
 assert(C.newer('0.5.0-test.10','0.5.0-test.9'));assert(C.newer('0.5.0','0.5.0-test.10'));assert(not C.newer('0.5.0-test.10','0.5.0'))
 assert(C.newer('0.5.0-test.1e0','0.5.0-test.99'));assert(not C.newer('0.5.0-test.7','0.5.0-test.7'));assert(C.newer('0.6.0-alpha.1','0.5.0'))
 for _,v in ipairs({'../1','0.05.0','0.5','0.5.0-test..1','0.5.0-test.01','0.5.0/extra'}) do assert(not C.version(v)) end
end)
check('Release selection includes test releases only in the testing channel and skips drafts',function()
 local data={metadata('0.5.0-test.9',true,true),metadata('0.5.0-test.8',false,true),metadata('0.4.0',false,false),metadata('0.5.0',false,false)}
 assert(C.select(data,'0.5.0-test.7','testing').version=='0.5.0')
 assert(C.select(data,'0.5.0-test.7','stable').version=='0.5.0')
 assert(C.select({data[1],data[2]},'0.5.0-test.7','testing').version=='0.5.0-test.8')
 assert(C.select({data[1],data[2]},'0.5.0-test.7','stable')==nil)
end)
check('Only official installer asset URLs with SHA-256 and bounded sizes are accepted',function()
 local d=metadata('0.5.0-test.8');assert(C.asset(d).version=='0.5.0-test.8')
 d.assets[1].browser_download_url='https://github.com/attacker/repo/releases/download/v1/install.zip';assert(not pcall(C.asset,d))
 d=metadata('0.5.0-test.8');d.assets[1].digest=nil;assert(not pcall(C.asset,d))
 d=metadata('0.5.0-test.8');d.assets[1].size=C.max_zip+1;assert(not pcall(C.asset,d))
 for _,url in ipairs({'http://github.com/x','https://github.com.evil.test/x','https://github.com@evil.test/x','https://evil.test/x','file:///tmp/a','https://github.com:444/x'}) do assert(not C.allowed(url)) end
 assert(C.allowed('https://release-assets.githubusercontent.com/signed?token=example'))
end)
check('All eleven archive fixtures are immutable and invalid packages cannot alter live files',function()
 for _,name in ipairs({'traversal','absolute','backslash','duplicate_case','symlink','missing','hash_mismatch','incompatible','oversize','no_manifest'}) do
  local path=sandbox();local before=B.hash(path..'/main.lua');local zip=fixtures..name..'.zip'
  assert(not pcall(C.stage,path,zip,release(name)),name);assert(B.hash(path..'/main.lua')==before and not B.pending(path),name)
 end
end)
check('Valid package is verified into staging without changing code or user files',function()
 local path=sandbox();C.stage(path,fixtures..'valid.zip',release());assert(B.pending(path).version=='0.5.0-test.8')
 assert(B.read(path..'/main.lua')=='old main' and B.read(path..'/user-note.txt')=='keep my notes')
 assert(B.checkStage(path).version=='0.5.0-test.8');B.clearPending(path);assert(not B.pending(path))
end)
check('A rejected incompatible replacement preserves an already prepared valid update',function()
 local path=sandbox();C.stage(path,fixtures..'valid.zip',release())
 assert(not pcall(C.stage,path,fixtures..'incompatible.zip',release('incompatible')))
 assert(B.pending(path).version=='0.5.0-test.8' and B.checkStage(path).version=='0.5.0-test.8')
end)
check('Activation installs managed files, prunes obsolete managed files and preserves untracked notes',function()
 local path=sandbox(true);C.stage(path,fixtures..'valid.zip',release());assert(B.apply(path))
 assert(B.read(path..'/resources/new.txt')=='new content' and B.read(path..'/user-note.txt')=='keep my notes')
 assert(not B.regular(path..'/obsolete.lua') and not B.pending(path) and not B.load(B.work(path),'journal.json'))
 assert(B.load(B.work(path),'result.json').ok)
end)
check('Interrupted activation restores the old tree and recovery can safely run again',function()
 for _,stop in ipairs({1,5}) do
  local path=sandbox(true);local old=B.read(path..'/main.lua');C.stage(path,fixtures..'valid.zip',release())
  assert(not pcall(B.apply,path,function(i) if i==stop then error('simulated interruption') end end))
  assert(B.load(B.work(path),'journal.json').phase=='applying');assert(B.recover(path))
  assert(B.read(path..'/main.lua')==old and B.read(path..'/obsolete.lua')=='obsolete' and not B.regular(path..'/resources/new.txt'))
  assert(not B.pending(path) and not B.recover(path) and not B.load(B.work(path),'result.json').ok)
 end
end)
check('Insufficient backup space and changed staged files are rejected before live replacement',function()
 local path=sandbox();C.stage(path,fixtures..'valid.zip',release());local df=require('ffi/util').df
 require('ffi/util').df=function() return 0,0 end;local ok=pcall(B.apply,path);require('ffi/util').df=df;assert(not ok)
 assert(B.read(path..'/main.lua')=='old main');B.atomic(B.work(path)..'/next','resources/new.txt','tampered');assert(not pcall(B.apply,path))
 assert(B.read(path..'/main.lua')=='old main')
end)
check('Symlink parents and malicious recovery paths cannot redirect writes outside the plugin',function()
 local path=sandbox();local ffi=require('ffi');ffi.cdef('int symlink(const char *, const char *);');B.mkdir(path..'/outside')
 assert(ffi.C.symlink((path..'/outside'),(path..'/link'))==0);assert(not pcall(B.parents,path,'link/escape',true))
 B.save(B.work(path),'journal.json',{schema=1,root=path,phase='applying',files={{path='../escape',had=false}}})
 assert(not pcall(B.recover,path));assert(B.read(path..'/main.lua')=='old main')
end)
check('Automatic checking and installation default off; preferences enforce install implies check',function()
 assert(not U.config().auto_check and not U.config().auto_install)
 U.set('auto_install',true);assert(U.config().auto_check and U.config().auto_install)
 U.set('auto_check',false);assert(not U.config().auto_check and not U.config().auto_install)
end)
check('Automatic checks never request Wi-Fi when the device is disconnected',function()
 local net=require('ui/network/manager');local connected,run=net.isConnected,net.runWhenOnline;local requested=false
 net.isConnected=function() return false end;net.runWhenOnline=function() requested=true end
 U.check(nil,true);assert(not requested and not U.job);net.isConnected=connected;net.runWhenOnline=run
end)
check('Non-modal subprocess checks persist a valid result and leave unrelated pages alone',function()
 local fetch=C.fetch;local net=require('ui/network/manager');local run=net.runWhenOnline
 C.fetch=function() return release() end;net.runWhenOnline=function(_,fn) fn() end
 app:open('plugin_update');U.check(app,false);assert(U.job);app:open('home');waitJob()
 assert(U.state().release.version=='0.5.0-test.8' and app.screen.model.home)
 C.fetch=fetch;net.runWhenOnline=run
end)
check('Prepared background download leaves the running tree untouched until startup activation',function()
 local path=sandbox();local rootfn=B.root;local download=C.download;B.root=function() return path end
 C.download=function(target,r) C.stage(target,fixtures..'valid.zip',r);return {version=r.version} end
 U.prepare(nil,release(),true);waitJob();assert(B.pending(path) and B.read(path..'/main.lua')=='old main')
 B.clearPending(path);B.root=rootfn;C.download=download
end)
check('Cancelling a worker prevents concurrent replacement jobs and reaps the child',function()
 U.run('check',function() require('ffi').C.usleep(1000000);return {} end,function() error('cancelled callback must not run') end)
 assert(U.job);U.cancel();if U.job then assert(not U.run('check',function() return {} end,function() end)) end;waitJob();assert(not U.job)
end)
check('Automatic checks are throttled to a day with one-hour failed-attempt backoff',function()
 local checkfn=U.check;local calls=0;U.check=function() calls=calls+1 end
 U.set('auto_check',true);U.save({checked=os.time()});U.schedule();ticks();assert(calls==0)
 U.save({attempt=os.time()});U.schedule();ticks();assert(calls==0)
 U.save({checked=0,attempt=0});U.schedule();for _=1,10 do UI:shiftScheduledTasksBy(-require('ui/time').s(1));UI:_checkTasks() end;assert(calls==1)
 U.set('auto_check',false);U.check=checkfn
end)
check('Update entry stays in maintenance; search works and update subpages inherit no More menu',function()
 for _,category in ipairs(app.native.categories) do
  app:open('catalog_category',category[1]);local found=false
  for _,r in ipairs(app.screen.model.rows) do found=found or r.title=='墨页更新' end
  assert(found==(category[1]=='maintenance'))
 end
 require('einkfrontend/settings').search(app,'自动更新');local found=false
 for _,r in ipairs(app.screen.model.rows) do found=found or r.title=='墨页更新' end;assert(found)
 app:open('plugin_update');UI:forceRePaint();assert(not require('einkfrontend/context').allowed(app,'settings_popup'))
 Device.screen.bb:writePNG(out..'update-'..variant..'.png')
 app:go('plugin_update_channel');assert(not require('einkfrontend/context').allowed(app,'settings_popup'))
end)
check('GitHub release metadata fixture selects the official versioned install asset',function()
 local data=require('json').decode(B.read(fixtures..'github-releases.json'))
 assert(C.select(data,'0.5.0-test.5','testing').version=='0.5.0-test.6')
end)
check('Completed installed releases are not offered again from persisted state',function()
 U.save({release={version=U.current}});assert(U.state().release==nil)
end)
check('Incomplete download length removes the temporary archive',function()
 local path=sandbox();local get=C.get;C.get=function(_,file) B.write(file,'bad');return 3 end
 local ok=pcall(C.download,path,release());C.get=get
 assert(not ok and not B.regular(B.work(path)..'/download.zip') and B.read(path..'/main.lua')=='old main')
end)
check('Cancelling a downloader removes its newly prepared update without touching current code',function()
 local path=sandbox();local rootfn=B.root;local download=C.download;B.root=function() return path end
 C.download=function(target,r) C.stage(target,fixtures..'valid.zip',r);require('ffi').C.usleep(1000000);return {version=r.version} end
 U.prepare(nil,release(),true)
 for _=1,1000 do if B.pending(path) then break end;UI:shiftScheduledTasksBy(-require('ui/time').s(.01));UI:_checkTasks();require('ffi').C.usleep(1000) end
 assert(B.pending(path));U.cancel();waitJob();assert(not B.pending(path) and B.read(path..'/main.lua')=='old main')
 B.root=rootfn;C.download=download
end)
check('Enabling automatic installation can prepare an already detected release without another check',function()
 local prepare=U.prepare;local net=require('ui/network/manager');local connected=net.isConnected;local prepared=0
 U.prepare=function(_,r,automatic) assert(automatic and r.version=='0.5.0-test.8');prepared=prepared+1 end
 net.isConnected=function() return true end;U.set('auto_install',true);U.save({checked=os.time(),release=release()});U.schedule()
 for _=1,6 do UI:shiftScheduledTasksBy(-require('ui/time').s(1));UI:_checkTasks() end
 assert(prepared==1);U.set('auto_check',false);U.prepare=prepare;net.isConnected=connected
end)
app:close();local f=assert(io.open(out..'update-'..variant..'.json','w'));f:write(require('json').encode(report));f:close();os.exit(0)
