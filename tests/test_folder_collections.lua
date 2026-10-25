-- Portable module checks with simulated KOReader storage, filesystem and gestures.
local checks,failed={},0
local function test(name,fn)
 local ok,why=pcall(fn);checks[#checks+1]={name=name,passed=ok,error=not ok and tostring(why) or nil}
 if not ok then failed=failed+1;print('FAIL '..name..': '..tostring(why)) end
end
local function copy(x) if type(x)~='table' then return x end;local o={};for k,v in pairs(x) do o[k]=copy(v) end;return o end
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end;return true
end
local function encode(v)
 if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"' end
 if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
 if v==nil then return 'null' end
 local t={};if #v>0 then for _,x in ipairs(v) do t[#t+1]=encode(x) end;return '['..table.concat(t,',')..']' end
 for k,x in pairs(v) do t[#t+1]=encode(k)..':'..encode(x) end;return '{'..table.concat(t,',')..'}'
end
local function fixture()
 for name in pairs(package.loaded) do if name:match('^einkfrontend/') then package.loaded[name]=nil end end
 local f={files={},disk={},tasks={},writes=0,seq=0}
 function f:add(path,mode)
  self.seq=self.seq+1;self.files[path]={mode=mode or 'file',dev=1,ino=self.seq,size=10,modification=1};return self.files[path]
 end
 for _,p in ipairs({'/','/old','/old/文学','/old/文学/鲁迅','/old/外文','/old/空目录','/settings','/books'}) do f:add(p,'directory') end
 for _,p in ipairs({'/old/文学/a.epub','/old/文学/鲁迅/b.epub','/old/外文/c.pdf','/old/loose.epub','/old/外文/cover.jpg','/old/外文/note.lua','/books/new.epub'}) do f:add(p) end
 local function attr(path,key) local a=f.files[path];return a and (key and a[key] or copy(a)) end
 local lfs={attributes=attr,symlinkattributes=attr,dir=function(path)
  assert(f.files[path] and not f.files[path].unreadable,'cannot read directory')
  local prefix=path=='/' and '/' or path..'/';local names={}
  for q in pairs(f.files) do
   if q:sub(1,#prefix)==prefix then local n=q:sub(#prefix+1);if n~='' and not n:find('/',1,true) then names[#names+1]=n end end
  end
  table.sort(names);local i=0;return function() i=i+1;return names[i] end
 end}
 local ui={}
 function ui:nextTick(fn) f.tasks[#f.tasks+1]=fn end
 function ui:scheduleIn(_,fn) self:nextTick(fn) end
 function ui:unschedule(fn) for i=#f.tasks,1,-1 do if f.tasks[i]==fn then table.remove(f.tasks,i) end end end
 function ui:close(widget) f.closed=widget end
 function ui:setDirty() end
 function f:drain() local n=0;while #self.tasks>0 do n=n+1;assert(n<3000);table.remove(self.tasks,1)() end end
 local store={}
 function store:open(path)
  local obj={data=copy(f.disk[path] or {}),file=path}
  function obj:readSetting(k) return self.data[k] end
  function obj:flush()
   if f.fail_backup and self.file:find('before%-folder') then return false end
   if f.fail_restore and self.file=='/settings/collection.lua' then return false end
   f.disk[self.file]=copy(self.data);return true
  end
  return obj
 end
 local rc={coll={favorites={}},coll_settings={favorites={order=1,default=true}},coll_default='favorites',default_collection_name='favorites'}
 function rc:addCollection(name) self.coll[name]={};self.coll_settings[name]={order=2} end
 function rc:addItem(file,name,a) assert(f.files[file]);self.coll[name][file]={file=file,order=1,attr=a or attr(file)} end
 function rc:write(touched)
  f.writes=f.writes+1
  local data=copy(f.disk['/settings/collection.lua'] or {})
  for name,coll in pairs(self.coll) do if not touched or touched[name] then
   local records={settings=copy(self.coll_settings[name])};for file,item in pairs(coll) do records[#records+1]={file=file,order=item.order} end
   data[name]=records
  end end
  if f.drop_write then f.drop_write=false;return end
  f.disk['/settings/collection.lua']=data
  if f.throw_after_write then error('injected write error') end
 end
 rc:write();f.writes=0
 local app={library={root='/books'},stack={},renders=0,messages={},plugin={active=true,ui={document={}}},adapter={alive=function() return true end}}
 function app:render() self.renders=self.renders+1;if f.render_fail then error('render failed') end end
 function app:userAction(fn) local ok,why=pcall(fn);if not ok then self.messages[#self.messages+1]=why end;return ok end
 function app:message(text) self.messages[#self.messages+1]=text end
 package.loaded['ui/uimanager']=ui
 package.loaded['libs/libkoreader-lfs']=lfs
 package.loaded['ffi/util']={realpath=function(path) return f.files[path] and (f.files[path].realpath or path) end}
 package.loaded['document/documentregistry']={hasProvider=function(_,p) return p:match('%.epub$') or p:match('%.pdf$') or p:match('%.jpg$') end,isImageFile=function(_,p) return p:match('%.jpg$') end}
 package.loaded['luasettings']=store
 package.loaded['datastorage']={getSettingsDir=function() return '/settings' end}
 package.loaded['einkfrontend/catalog']={copy=copy}
 package.loaded['einkfrontend/adapter']={equal=equal}
 package.loaded['readcollection']=rc
 package.loaded['docsettings']={open=function() return {readSetting=function() return nil end} end}
 package.loaded['apps/filemanager/filemanagerbookinfo']={new=function(self) return self end,getDocProps=function(_,file,_,no_open_document) if not no_open_document then f.opened_document=true end;return {title=file:match('([^/]+)$'),authors='作者',series=''} end}
 f.rc=rc;f.app=app;f.ui=ui;f.store=store;f.service=require('einkfrontend/foldercollections').new(app)
 function f:scan() self.service:scan('/old');self:drain();assert(self.service.state=='ready',self.service.error);return self.service.plan end
 return f
end
test('preview preserves files, library root and collections while retaining nested folder groups',function()
 local f=fixture();local disk=copy(f.disk);local plan=f:scan()
 assert(#plan.groups==3 and plan.count==3 and plan.loose==1)
 assert(plan.groups[2].name=='文学' and #plan.groups[2].files==2)
 assert(plan.groups[3].name=='文学/鲁迅' and #plan.groups[3].files==1)
 assert(equal(f.disk,disk) and f.writes==0 and f.app.library.root=='/books')
end)
test('identical leaf names in separate branches remain different collections',function()
 local f=fixture();f:add('/old/外文/鲁迅','directory');f:add('/old/外文/鲁迅/d.epub')
 local plan=f:scan();local names={};for _,g in ipairs(plan.groups) do names[g.name]=true end
 assert(names['外文/鲁迅'] and names['文学/鲁迅'])
end)
test('hidden folders, sidecars, unsupported files, images and links are excluded',function()
 local f=fixture()
 for _,dir in ipairs({'.hidden','a.sdr','koreader','system'}) do f:add('/old/'..dir,'directory');f:add('/old/'..dir..'/x.epub') end
 f:add('/old/link','link');local plan=f:scan();assert(plan.count==3 and plan.skipped==1 and #plan.groups==3)
end)
test('unreadable child directory is counted without changing collections',function()
 local f=fixture();f.files['/old/文学'].unreadable=true;local plan=f:scan()
 assert(plan.count==1 and plan.skipped==1 and f.writes==0)
end)
test('unreadable root fails without publishing a partial preview',function()
 local f=fixture();f.files['/old'].unreadable=true;f.service:scan('/old');f:drain()
 assert(f.service.state=='error' and not f.service.plan and f.writes==0)
end)
test('overlong folder names fail instead of truncating or merging unrelated names',function()
 local f=fixture();local dir='/old/'..string.rep('a',201);f:add(dir,'directory');f:add(dir..'/x.epub')
 f.service:scan('/old');f:drain();assert(f.service.state=='error' and not f.service.plan and f.writes==0)
end)
test('scan can be cancelled and stale scheduled work cannot modify collections',function()
 local f=fixture();for i=1,120 do f:add('/old/文学/'..i..'.epub') end
 f.service:scan('/old');table.remove(f.tasks,1)();assert(f.service.state=='scanning')
 local stale=f.service.tick;f.service:cancel();stale();f:drain()
 assert(f.service.state=='cancelled' and not f.service.plan and #f.tasks==0 and f.writes==0)
end)
test('render failure cancels every remaining scan task',function()
 local f=fixture();for i=1,120 do f:add('/old/文学/'..i..'.epub') end
 f.render_fail=true;f.service:scan('/old');f:drain();assert(f.service.state=='error' and #f.tasks==0 and f.writes==0)
end)
test('import merges additively while preserving defaults, folder rules and original members',function()
 local f=fixture();f.rc:addCollection('文学');f.rc:addItem('/books/new.epub','文学')
 f.rc.coll_settings['文学']={order=8,default=true,folders={['/books']={recursive=true}},collate='strcoll'}
 f.rc.coll_default='文学';f.rc:write();f.writes=0
 local before=copy(f.rc.coll_settings);local files=copy(f.files);local plan=f:scan();local result=f.service:apply(plan)
 assert(result.created==2 and result.merged==1 and result.added==4 and f.writes==1)
 assert(f.rc.coll['文学']['/books/new.epub'] and f.rc.coll['文学']['/old/文学/a.epub'])
 assert(equal(f.rc.coll_settings['文学'],before['文学']) and f.rc.coll_default=='文学')
 assert(equal(f.files,files) and f.app.library.root=='/books' and f.disk['/settings/collection-before-folder-import.lua'])
end)
test('repeated import adds neither duplicate entries nor unnecessary writes',function()
 local f=fixture();f.service:apply(f:scan());local writes=f.writes;local disk=copy(f.disk)
 local result=f.service:apply(f:scan());assert(result.added==0 and f.writes==writes and equal(f.disk,disk))
end)
test('a disappeared or replaced book invalidates preview before any collection write',function()
 for _,field in ipairs({'missing','ino','size','modification','link'}) do
  local f=fixture();local plan=f:scan();local a=f.files['/old/文学/a.epub']
  if field=='missing' then f.files['/old/文学/a.epub']=nil elseif field=='link' then a.mode='link' else a[field]=a[field]+1 end
  assert(not pcall(f.service.apply,f.service,plan) and f.writes==0 and not f.rc.coll['文学'])
 end
end)
test('replaced directories and redirected roots invalidate preview',function()
 for _,redirect in ipairs({false,true}) do
  local f=fixture();local plan=f:scan()
  if redirect then f.files['/old'].realpath='/elsewhere' else f.files['/old/文学'].ino=999 end
  assert(not pcall(f.service.apply,f.service,plan) and f.writes==0)
 end
end)
test('a stale preview cannot be applied after a rescan',function()
 local f=fixture();local old=f:scan();f:scan();assert(not pcall(f.service.apply,f.service,old) and f.writes==0)
end)
test('a missing rescan source clears the previous preview without leaving a broken ready state',function()
 local f=fixture();local old=f:scan()
 assert(not pcall(f.service.scan,f.service,'/missing'))
 assert(f.service.state=='idle' and not f.service.plan and not pcall(f.service.apply,f.service,old) and f.writes==0)
end)
test('failed backup prevents all collection mutations',function()
 local f=fixture();local plan=f:scan();local before=copy(f.rc.coll);f.fail_backup=true
 assert(not pcall(f.service.apply,f.service,plan) and f.writes==0 and equal(f.rc.coll,before))
end)
test('silent write failure restores original disk and in-memory collections',function()
 local f=fixture();local plan=f:scan();local before=copy(f.disk['/settings/collection.lua']);f.drop_write=true
 assert(not pcall(f.service.apply,f.service,plan))
 assert(equal(f.disk['/settings/collection.lua'],before) and not f.rc.coll['文学'] and f.rc.coll_default=='favorites')
end)
test('exception after a partial write restores every original collection',function()
 local f=fixture();local plan=f:scan();local before=copy(f.disk['/settings/collection.lua']);f.throw_after_write=true
 assert(not pcall(f.service.apply,f.service,plan))
 assert(equal(f.disk['/settings/collection.lua'],before) and not f.rc.coll['文学'])
end)
test('failed rollback retains the durable original collection backup',function()
 local f=fixture();local plan=f:scan();local before=copy(f.disk['/settings/collection.lua']);f.throw_after_write=true;f.fail_restore=true
 local ok,err=pcall(f.service.apply,f.service,plan)
 assert(not ok and err:find('恢复失败',1,true) and equal(f.disk['/settings/collection-before-folder-import.lua'],before))
 assert(not f.rc.coll['文学'])
end)
test('imported members outside the indexed root can be listed, searched, filtered and counted',function()
 local f=fixture();f.service:apply(f:scan());local Library=require('einkfrontend/library')
 local library=setmetatable({ui={},settings={readSetting=function() end},books={{file='/books/new.epub',title='New',authors='作者',series='',mtime=1}}},Library)
 local books=library:list({collection='文学'});assert(#books==2)
 assert(#library:list({collection='文学',query='b.epub'})==1)
 assert(#library:list({collection='文学',status='已完成'})==0)
 assert(#library:list()==1 and library.root==nil)
 local found=false;for _,coll in ipairs(library:collections(nil,'recent',true)) do
  if coll.name=='文学' then assert(coll.available==2 and coll.count==2 and coll.book);found=true end
 end;assert(found and not f.opened_document)
end)
test('folder-import UI previews before confirmation and respects cancelling the confirmation',function()
 local f=fixture();f.app.folder_import=f.service;f:scan();local rows={}
 local function row(title,note,callback) rows[#rows+1]={title=title,note=note,callback=callback} end
 f.app.confirm=function(_,_,callback) f.confirm=callback end
 local View=require('einkfrontend/foldercollectionsettings');local model={rows=rows}
 assert(View.render(f.app,{id='folder_collections'},model,row) and model.settings)
 model.folder_import.primary.callback()
 assert(f.confirm and f.writes==0);f.confirm();assert(f.writes==1 and f.service.state=='done')
end)
test('bottom and compound native menu events never route to typography while Aa opens the expanded font panel',function()
 local f=fixture();local calls={};local native=0
 local ui={document={},menu={},config={}}
 for _,key in ipairs({'onShowMenu','onTapShowMenu','onPressMenu','onKeyPressShowMenu'}) do ui.menu[key]=function() native=native+1 end end
 for _,key in ipairs({'onShowConfigMenu','onTapShowConfigMenu','onSwipeShowConfigMenu'}) do ui.config[key]=function() native=native+1 end end
 package.loaded.logger={err=function() end}
 local gate=require('einkfrontend/gate').new(ui,function(destination) calls[#calls+1]=destination end):install()
 ui.config:onTapShowConfigMenu();ui.config:onShowConfigMenu();ui.menu:onPressMenu();ui.menu:onTapShowMenu()
 assert(#calls==4 and calls[1]=='ignore_config_tap' and calls[2]=='ignore_config_tap' and calls[3]=='reader_top' and calls[4]=='reader_top' and native==0)
 gate:native(function() ui.config:onShowConfigMenu() end);assert(native==1)
 gate:restore();ui.config:onTapShowConfigMenu();assert(native==2)
 package.loaded['ui/widget/container/inputcontainer']={extend=function(_,t) return t end}
 package.loaded['ui/gesturerange']={};package.loaded.device={}
 package.loaded['einkfrontend/paint']={s=function(x) return x end}
 local Bar=require('einkfrontend/readertopbar');local tab
 Bar.action({close=function() end,app={showReader=function(_,value) tab=value end}},'aa')
 assert(tab=='font' and tab~='menu')
end)
test('plugin registers only top chrome tap and swipe, removes old center zones, and cancels imports on suspend',function()
 local f=fixture();local registrations,unregistered={},{}
 package.loaded['einkfrontend/offlineupdate']={disable=function() end}
 package.loaded['ui/widget/container/widgetcontainer']={extend=function(_,t) return t end}
 package.loaded.dispatcher={};package.loaded['ui/widget/infomessage']={};package.loaded['einkfrontend/app']={}
 local Plugin=require('einkfrontend/plugin');local ui={document={}}
 function ui:registerTouchZones(zones) for _,zone in ipairs(zones) do registrations[#registrations+1]=zone end end
 function ui:unRegisterTouchZones(zones) unregistered=zones end
 local plugin=setmetatable({active=true,ui=ui,zones={{id='einkfrontend_reader_panel'}},app=f.app,option=function() return true end},{__index=Plugin})
 plugin:refreshReaderEntry();assert(unregistered[1].id=='einkfrontend_reader_panel' and #registrations==2)
 for _,zone in ipairs(registrations) do assert(zone.id~='einkfrontend_reader_panel' and zone.screen_zone.ratio_y==0) end
 f.service:scan('/old');f.app.folder_import=f.service;plugin:onSuspend();f:drain();assert(f.service.state=='cancelled' and f.writes==0)
end)
test('legacy and omitted panel tabs open expanded font controls instead of a standalone navigation strip',function()
 local f=fixture();local created
 package.loaded['ui/widget/infomessage']={}
 package.loaded['einkfrontend/registry']={};package.loaded['einkfrontend/screen']={};package.loaded['einkfrontend/browser']={}
 package.loaded['einkfrontend/overlay']={present=function(_,_,factory) return factory() end}
 package.loaded['einkfrontend/readerpanel']={new=function(_,args) created=args;function args:setTab(tab) self.tab=tab end;return args end}
 local App=require('einkfrontend/app')
 for _,tab in ipairs({'menu','font'}) do local panel=App.showReader(f.app,tab);assert(panel.tab=='font' and created.tab=='font') end
 assert(App.showReader(f.app).tab=='font')
end)
AUDIT_RESULT=encode({checks=checks,total=#checks,failed=failed})
