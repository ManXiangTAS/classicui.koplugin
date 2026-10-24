require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');local Settings=require('luasettings');local lfs=require('libs/libkoreader-lfs');local F=require('ffi/util')
G_reader_settings=Settings:open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,full_takeover=true})
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
G_reader_settings:saveSetting('document_metadata_folder','doc')
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local FM=require('apps/filemanager/filemanager');local Reader=require('apps/reader/readerui')
local Doc=require('docsettings');local History=require('readhistory');local Collection=require('readcollection')
local Maintenance=require('einkfrontend/bookmaintenance');local util=require('util')
local base=assert(os.getenv('EINK_030_BOOKS'));local out=assert(os.getenv('EINK_TEST_OUTPUT'))..'/'
local variant=assert(os.getenv('EINK_VARIANT'));local cases=base..'/maintenance';assert(lfs.mkdir(cases))
local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function bytes(path) local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local function write(path,data) util.makePath(path:match('^(.*)/'));local f=assert(io.open(path,'wb'));f:write(data);f:close() end
local function exists(path) return lfs.symlinkattributes(path)~=nil end
local function book(name)
 local path=cases..'/'..name..'.epub';write(path,bytes(base..'/A.epub'))
 return {file=path,title=name,authors='作者',series=''}
end
local function sidecar(b)
 local d=Doc:open(b.file);d:saveSetting('summary',{status='reading'});d:saveSetting('annotation',{{text='fixture note'}});d:flush()
 local path=assert(Doc:findSidecarFile(b.file));local dir=path:match('^(.*)/')
 write(dir..'/cover.jpg','fixture cover');write(dir..'/custom_metadata.lua','return {custom_props={title="fixture"}}')
 return path,dir
end
local function pump(service)
 for _=1,1000 do
  if not service.co then break end
  UI:shiftScheduledTasksBy(-require('ui/time').s(.03));UI:_checkTasks()
 end
 assert(not service.co,'Task failed to finish');assert(service.state~='error',service.error)
end
local function row(app,title) for _,r in ipairs(app.screen.model.rows) do if r.title==title then return r end end;error('Missing row: '..title) end
local function button(w,text)
 if type(w)~='table' then return end;if w.text==text and w.onTapSelectButton then return w end
 for _,c in ipairs(w) do local b=button(c,text);if b then return b end end
end
local function shot(name) UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(out..file);report.frames[#report.frames+1]=file end
FM:showFiles(base);local app=FM.instance.einkfrontend.app
for _=1,30 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end
local close={};for _,e in ipairs(UI._window_stack) do if e.widget.text then close[#close+1]=e.widget end end;for _,w in ipairs(close) do UI:close(w) end
app.library.root=cases;app.library.books={};app.library:save()
local statistics=DS:getSettingsDir()..'/maintenance-statistics-sentinel.sqlite3';write(statistics,'historical-statistics-preserved')
local stats_before=bytes(statistics)
check('Long hold book actions include Delete; cancelling keeps the document and sidecar intact',function()
 local b=book("Delete's test");local path=sidecar(b);app.library.books={b};app.library:save()
 app:open('books',{});local held=app.screen.model.rows[1];assert(held.hold_callback);held.hold_callback()
 assert(row(app,'删除书籍').callback);shot('book-delete-entry')
 row(app,'删除书籍').callback();UI:forceRePaint();local confirm=UI._window_stack[#UI._window_stack].widget
 assert(confirm.text:find(b.file,1,true));assert(button(confirm,confirm.cancel_text)):onTapSelectButton()
 assert(exists(b.file) and exists(path))
end)
check('Confirmed deletion removes the document, per-book metadata, collection, price and library/history records',function()
 local b=app.library.books[1];local path,dir=sidecar(b)
 History:addItem(b.file);Collection:addCollection('maintenance');Collection:addItem(b.file,'maintenance');Collection:write()
 app.book_value:setPrice(b.file,'12.50');app:open('books',{});app:go('book',b)
 row(app,'删除书籍').callback();UI:forceRePaint();local confirm=UI._window_stack[#UI._window_stack].widget
 assert(button(confirm,confirm.ok_text)):onTapSelectButton()
 assert(not exists(b.file) and not exists(path) and not exists(dir..'/cover.jpg') and not exists(dir..'/custom_metadata.lua'))
 assert(#app.library.books==0 and not History:getIndexByFile(b.file) and not app.book_value:price(b.file))
 local coll=Settings:open(DS:getSettingsDir()..'/collection.lua'):readSetting('maintenance');assert(#coll==0)
 assert(bytes(statistics)==stats_before and app.plugin.active)
end)
check('A changed document snapshot and a failed unlink retain the file and all book records',function()
 local b=book('changed');local path=sidecar(b);app.library.books={b};app.library:save()
 local a=lfs.attributes(b.file);write(b.file,bytes(b.file)..'changed')
 assert(not pcall(Maintenance.deleteBook,app,b,a));assert(exists(b.file) and exists(path))
 local remove=os.remove;os.remove=function(p) if p==b.file then return nil,'fixture permission failure' end;return remove(p) end
 local ok=pcall(Maintenance.deleteBook,app,b);os.remove=remove
 assert(not ok and exists(b.file) and exists(path) and #app.library.books==1)
end)
local dead,dead_meta,dead_dir,live,live_meta
check('Read-only scan discovers deleted-book sidecars even after the library index was rescanned',function()
 dead=book('orphan');dead_meta,dead_dir=sidecar(dead)
 live=book('live');live_meta=sidecar(live);assert(os.remove(dead.file))
 app.library.books={live};app.library:save()
 local service=Maintenance.new(app);app.book_maintenance=service
 app:open('library_cleanup');service:scan();pump(service);app:render()
 assert(service.state=='ready' and service.plan.books[dead.file] and exists(dead_meta))
 assert(not service.plan.books[live.file]);assert(bytes(live_meta):find('fixture note',1,true))
 shot('cleanup-preview')
end)
check('Cleanup removes only reviewed missing-book data and preserves live notes, unknown files and statistics',function()
 write(dead_dir..'/keep-user-file.txt','keep')
 local before=bytes(live_meta);local service=app.book_maintenance
 service:apply(service.plan);pump(service);app:render()
 assert(not exists(dead_meta) and not exists(dead_dir..'/cover.jpg') and exists(dead_dir..'/keep-user-file.txt'))
 assert(exists(live.file) and bytes(live_meta)==before and bytes(statistics)==stats_before)
 assert(service.result.removed>=3 and service.result.failed==0);shot('cleanup-complete')
end)
check('A book restored after preview keeps all its metadata and library records',function()
 local b=book('restored');local path=sidecar(b);assert(os.remove(b.file))
 app.library.books[#app.library.books+1]=b;app.library:save();app.book_value:setPrice(b.file,'4')
 local service=Maintenance.new(app);service:scan();pump(service);assert(service.plan.books[b.file])
 write(b.file,bytes(base..'/A.epub'));local before=bytes(path)
 service:apply(service.plan);pump(service)
 assert(bytes(path)==before and exists(b.file) and app.book_value:price(b.file)==400)
 local found=false;for _,v in ipairs(app.library.books) do if v.file==b.file then found=true end end;assert(found)
end)
check('Same-stem books with different formats keep shared covers and custom metadata',function()
 local b=book('shared');local path,dir=sidecar(b);local other=cases..'/shared.pdf';write(other,'fixture pdf')
 assert(os.remove(b.file));local service=Maintenance.new(app);service:scan();pump(service);service:apply(service.plan);pump(service)
 assert(not exists(path) and exists(other) and exists(dir..'/cover.jpg') and exists(dir..'/custom_metadata.lua'))
end)
check('Deleting one format does not purge another already-missing format metadata',function()
 local b=book('delete-one-format');local path,dir=sidecar(b);local other=dir..'/metadata.pdf.lua'
 write(other,'return {annotation={{text="keep other format"}}}')
 Maintenance.deleteBook(app,b)
 assert(not exists(b.file) and not exists(path) and exists(other) and exists(dir..'/cover.jpg') and exists(dir..'/custom_metadata.lua'))
end)
check('Central sidecar storage is cleaned by verified original book paths',function()
 local b=book('central');G_reader_settings:saveSetting('document_metadata_folder','dir')
 local path=sidecar(b);assert(path:sub(1,#DS:getDocSettingsDir())==DS:getDocSettingsDir());assert(os.remove(b.file))
 local service=Maintenance.new(app);service:scan();pump(service);assert(service.plan.books[b.file]);service:apply(service.plan);pump(service)
 assert(not exists(path));G_reader_settings:saveSetting('document_metadata_folder','doc')
end)
check('A replaced metadata file is skipped instead of deleting its new contents',function()
 local b=book('metadata-changed');local path=sidecar(b);assert(os.remove(b.file))
 local service=Maintenance.new(app);service:scan();pump(service);local attr=lfs.attributes(path)
 local replacement=bytes(path):gsub('fixture note','Fixture note');assert(#replacement==attr.size);write(path,replacement);lfs.touch(path,attr.access,attr.modification)
 service:apply(service.plan);pump(service);assert(bytes(path)==replacement and service.result.skipped>0)
end)
check('Cover-cache cleanup is scoped, parameterized and does not migrate or reset the cache during preview',function()
 local b=book("cache 'deleted");assert(os.remove(b.file))
 local dbpath=DS:getSettingsDir()..'/bookinfo_cache.sqlite3';local db=require('lua-ljsqlite3/init').open(dbpath,'rw')
 local insert=db:prepare('INSERT OR REPLACE INTO bookinfo(directory,filename,title) VALUES(?,?,?);')
 local outside=DS:getDataDir()..'/disconnected/book.epub'
 for _,path in ipairs({b.file,live.file,outside}) do local dir,name=util.splitFilePathName(path);insert:bind(dir,name,'fixture cache');insert:step();insert:clearbind():reset() end;insert:close()
 db:exec('PRAGMA user_version=1;');db:close()
 local service=Maintenance.new(app);service:scan();pump(service);assert(service.plan.books[b.file] and not service.plan.books[outside])
 db=require('lua-ljsqlite3/init').open(dbpath,'ro');assert(tonumber(db:rowexec('PRAGMA user_version;'))==1);db:close()
 service:apply(service.plan);pump(service)
 db=require('lua-ljsqlite3/init').open(dbpath,'rw');local select=db:prepare('SELECT count(*) FROM bookinfo WHERE directory=? AND filename=?;')
 for _,path in ipairs({b.file,live.file,outside}) do local dir,name=util.splitFilePathName(path);select:bind(dir,name);local r=select:step();assert(tonumber(r[1])==(path==b.file and 0 or 1));select:clearbind():reset() end
 select:close();db:exec('PRAGMA user_version=20201210;');db:close()
end)
check('Hash-shared metadata is retained when an identical surviving copy exists',function()
 local b=book('hashed');local copy=book('hashed-copy')
 G_reader_settings:saveSetting('document_metadata_folder','hash');util.makePath(DS:getDocSettingsHashDir());Doc.setIsHashLocationEnabled(nil)
 local doc=Doc:open(b.file);doc:saveSetting('annotation',{{text='shared hash note'}});doc:flush()
 local path=assert(Doc:findSidecarFile(b.file));assert(path:sub(1,#DS:getDocSettingsHashDir())==DS:getDocSettingsHashDir())
 app.library.books[#app.library.books+1]=b;app.library.books[#app.library.books+1]=copy;app.library:save()
 assert(os.remove(b.file));local before=bytes(path);local service=Maintenance.new(app);service:scan();pump(service);service:apply(service.plan);pump(service)
 assert(exists(copy.file) and bytes(path)==before)
 G_reader_settings:saveSetting('document_metadata_folder','doc')
end)
check('A failed metadata unlink remains discoverable and can be retried',function()
 local b=book('retry');local path=sidecar(b);assert(os.remove(b.file))
 local service=Maintenance.new(app);service:scan();pump(service)
 local remove=os.remove;os.remove=function(p) if p==path then return nil,'fixture permissions' end;return remove(p) end
 service:apply(service.plan);pump(service);os.remove=remove
 assert(service.result.failed>=1 and exists(path))
 service:scan();pump(service);assert(service.plan.books[b.file]);service:apply(service.plan);pump(service);assert(not exists(path))
end)
check('Empty sidecar directories are removed only when no same-stem document remains',function()
 local orphan=cases..'/empty-orphan.sdr';local kept=cases..'/live.sdr'
 assert(lfs.mkdir(orphan));assert(exists(kept))
 local service=Maintenance.new(app);service:scan();pump(service);assert(#service.plan.empty_dirs>=1)
 service:apply(service.plan);pump(service);assert(not exists(orphan) and exists(kept) and exists(live.file))
end)
check('Symbolic-link directories and missing paths through them are never cleaned',function()
 local outside=DS:getDataDir()..'/outside';util.makePath(outside..'/missing.sdr');write(outside..'/missing.sdr/metadata.epub.lua','return {outside=true}')
 assert(lfs.link(outside,cases..'/shortcut',true))
 local b={file=cases..'/shortcut/missing.epub',title='linked',authors='',series=''}
 app.library.books[#app.library.books+1]=b;app.library:save()
 local service=Maintenance.new(app);service:scan();pump(service);assert(not service.plan.books[b.file]);service:apply(service.plan);pump(service)
 assert(exists(outside..'/missing.sdr/metadata.epub.lua'))
end)
check('Unavailable or changed library storage prevents cleanup',function()
 local service=Maintenance.new(app);service:scan();pump(service);service.plan.root_attr.ino=-1
 service:apply(service.plan)
 for _=1,20 do UI:shiftScheduledTasksBy(-require('ui/time').s(.03));UI:_checkTasks() end
 assert(service.state=='error' and service.error:find('存储',1,true))
 local old=app.library.root;app.library.root=cases..'/not-mounted';service:scan()
 for _=1,20 do UI:shiftScheduledTasksBy(-require('ui/time').s(.03));UI:_checkTasks() end
 assert(service.state=='error');app.library.root=old
end)
check('Current reading documents cannot be deleted, even by a direct stale action',function()
 app:close();Reader:doShowReader(live.file);local reader=assert(Reader.instance);local current=reader.einkfrontend.app
 assert(not pcall(Maintenance.deleteBook,current,live));assert(exists(live.file))
 current.adapter:returnToLibrary('library');app=assert(FM.instance).einkfrontend.app
end)
check('Library menu, settings search and suspend provide maintenance entry and task cancellation',function()
 app:open('books',{});local menu=app:showLibraryMenu('more')
 if menu then menu:close() end
 require('einkfrontend/settings').search(app,'残留');assert(row(app,'清理已删除书籍的数据').callback)
 app.book_maintenance=Maintenance.new(app);app.book_maintenance:scan();assert(app.book_maintenance.co)
 app.plugin:onSuspend();assert(not app.book_maintenance.co and not app.book_maintenance.tick)
end)
check('Home long hold opens deletion actions for history-only books without optional series metadata',function()
 local b=book('history-only');History:addItem(b.file);app:open('home');UI:forceRePaint()
 local hit;for _,h in ipairs(app.screen.hits) do if h.id=='home_continue' then hit=h end end
 assert(hit and hit.hold_callback);hit.hold_callback();assert(row(app,'删除书籍').callback and app.plugin.active)
end)
assert(bytes(statistics)==stats_before)
if FM.instance then FM.instance:onClose() end
local f=assert(io.open(out..'maintenance-'..variant..'.json','w'));f:write(require('json').encode(report));f:close()
print('COMPLETE '..variant)
