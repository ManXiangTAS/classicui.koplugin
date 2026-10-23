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
local root=assert(os.getenv('EINK_PROJECT'));local out=assert(os.getenv('EINK_TEST_OUTPUT'))..'/';local variant=os.getenv('EINK_VARIANT')
local report={tests={},variant=variant,device='NOT_RUN'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function ticks() for _=1,20 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end end
local lfs=require('libs/libkoreader-lfs');local ffi=require('ffi');local json=require('json')
local pluginroot=assert(os.getenv('EINK_PLUGIN_ROOT'));local work=pluginroot..'-update';local marker=DS:getDataDir()..'/must-not-execute'
local function write(path,data) local f=assert(io.open(path,'wb'));f:write(data);f:close() end
local function read(path) local f=assert(io.open(path,'rb'));local data=f:read('*a');f:close();return data end
local main_before=read(pluginroot..'/main.lua')
local http=require('socket.http');local oldrequest=http.request;local requests=0
http.request=function() requests=requests+1;write(marker..'-network','request');error('Offline build made a network request') end
G_reader_settings:saveSetting('eink_updater',{auto_check=true,auto_install=true,source='relay',relay_base='https://retired.invalid/'})
G_reader_settings:saveSetting('eink_updater_state',{release={version='99.0.0'}})
G_reader_settings:saveSetting('offline_preserve_sentinel','keep settings');G_reader_settings:flush()
assert(lfs.mkdir(work));assert(lfs.mkdir(work..'/next'));assert(lfs.mkdir(work..'/previous'));assert(lfs.mkdir(work..'/incoming'))
local payload="local f=assert(io.open('"..marker.."','w'));f:write('executed');f:close();error('must not execute')"
write(work..'/pending.json','{"schema":1,"version":"99.0.0"}')
write(work..'/journal.json',json.encode({schema=1,root=pluginroot,phase='applying',version='99.0.0',files={{path='main.lua',had=true}}}))
write(work..'/next/main.lua',payload);write(work..'/previous/main.lua',payload);write(work..'/incoming/main.lua',payload);write(work..'/download.zip','invalid old bytes')
FM:showFiles(assert(os.getenv('EINK_030_BOOKS')));local app=FM.instance.einkfrontend.app;ticks()
local Offline=require('einkfrontend/offlineupdate')
check('Fresh startup never applies or recovers the old staged entry point',function()
 assert(read(pluginroot..'/main.lua')==main_before and not lfs.attributes(marker) and Offline.result.ok)
 assert(not lfs.attributes(work) and not package.loaded['einkfrontend/updater'] and not package.loaded['einkfrontend/updateboot'])
end)
check('Legacy automatic flags and cached release state are removed without changing other preferences',function()
 assert(not G_reader_settings:has('eink_updater') and not G_reader_settings:has('eink_updater_state'))
 assert(G_reader_settings:readSetting('offline_preserve_sentinel')=='keep settings')
 local saved=require('luasettings'):open(DS:getDataDir()..'/settings.reader.lua');assert(not saved:has('eink_updater') and saved:readSetting('offline_preserve_sentinel')=='keep settings')
end)
check('Startup resume and suspend cannot schedule or request plugin updates',function()
 FM.instance.einkfrontend:onResume();for _=1,15 do UI:shiftScheduledTasksBy(-require('ui/time').s(1));UI:_checkTasks() end
 FM.instance.einkfrontend:onSuspend();FM.instance.einkfrontend:onResume();ticks()
 assert(requests==0 and not lfs.attributes(marker..'-network') and not package.loaded['einkfrontend/updater'])
end)
check('Settings categories and global search contain no plugin online-update entry',function()
 for _,c in ipairs(app.native.categories) do
  app:open('catalog_category',c[1]);for _,row in ipairs(app.screen.model.rows) do assert(row.title~='墨页更新' and row.title~='更新源' and row.title~='自动更新') end
 end
 require('einkfrontend/settings').search(app,'墨页更新');for _,row in ipairs(app.screen.model.rows) do assert(row.title~='墨页更新') end
 app:open('catalog_category','maintenance');UI:forceRePaint();Device.screen.bb:writePNG(out..'offline-settings-'..variant..'.png')
end)
check('Obsolete update routes lead to About instead of opening a dead settings page',function()
 for _,id in ipairs({'plugin_update','plugin_update_channel','plugin_update_source'}) do
  app:open(id);assert(app.stack[#app.stack].id=='about');app:go(id);assert(app.stack[#app.stack].id=='about')
 end
end)
check('Overlay compatibility modules cannot connect, start workers, render update menus or install',function()
 local U=require('einkfrontend/updater');assert(U.removed and not U.config().auto_check and not U.config().auto_install)
 for _,key in ipairs({'attach','detach','resume','suspend','check','prepare','run','schedule','set'}) do assert(U[key]()==false) end
 assert(require('einkfrontend/updateboot').startup()==false)
 assert(require('einkfrontend/updatesettings').render()==false and not require('einkfrontend/updatesource').default_base)
 local C=require('einkfrontend/updatecore');for _,key in ipairs({'fetch','download','prepare','stage'}) do assert(not pcall(C[key])) end
 assert(requests==0 and not lfs.attributes(marker))
end)
check('Malformed pending and journal data is discarded without parsing or executing it',function()
 local root=DS:getDataDir()..'/malformed';assert(lfs.mkdir(root));assert(lfs.mkdir(root..'-update'))
 write(root..'-update/pending.json','not json');write(root..'-update/journal.json',payload)
 assert(Offline.disable(G_reader_settings,root).ok and not lfs.attributes(root..'-update') and not lfs.attributes(marker))
end)
check('Cleanup unlinks cache symlinks without traversing outside the dedicated work directory',function()
 ffi.cdef('int symlink(const char *, const char *);')
 local root=DS:getDataDir()..'/links';assert(lfs.mkdir(root));local outside=DS:getDataDir()..'/outside';assert(lfs.mkdir(outside));write(outside..'/keep.txt','preserve')
 assert(ffi.C.symlink(outside,root..'-update')==0);assert(Offline.disable(G_reader_settings,root).ok)
 assert(read(outside..'/keep.txt')=='preserve' and not lfs.symlinkattributes(root..'-update'))
 assert(lfs.mkdir(root..'-update'));assert(ffi.C.symlink(outside,root..'-update/previous')==0);assert(Offline.disable(G_reader_settings,root).ok)
 assert(read(outside..'/keep.txt')=='preserve')
end)
check('Settings persistence failure cannot enable the retired updater or block frontend use',function()
 local settings=require('luasettings'):open(DS:getDataDir()..'/failed.lua');settings:saveSetting('eink_updater',{auto_check=true});settings.flush=function() return false end
 local root=DS:getDataDir()..'/failed';assert(lfs.mkdir(root));assert(lfs.mkdir(root..'-update'));write(root..'-update/pending.json','pending')
 assert(not Offline.disable(settings,root).ok and not settings:has('eink_updater') and not lfs.attributes(root..'-update'))
 app:open('home');assert(app.screen.model.home);app:open('library');assert(app.screen.model.rows or app.screen.model.books)
end)
check('Repeated cleanup is idempotent and closing the plugin makes no update request',function()
 local root=DS:getDataDir()..'/repeat';assert(lfs.mkdir(root));assert(Offline.disable(G_reader_settings,root).ok);assert(Offline.disable(G_reader_settings,root).ok)
 app:close();FM.instance.einkfrontend:stopPlugin();assert(requests==0 and not lfs.attributes(marker..'-network'))
end)
http.request=oldrequest
if FM.instance then FM.instance:onClose() end
local f=assert(io.open(out..'offline-'..variant..'.json','w'));f:write(json.encode(report));f:close();os.exit(0)
