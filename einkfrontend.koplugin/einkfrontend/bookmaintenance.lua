-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Only explicit book deletion removes a document. Cleanup removes identified
-- data for absent documents inside one available library root, with rechecks.
local lfs=require('libs/libkoreader-lfs')
local F=require('ffi/util')
local DS=require('datastorage')
local Settings=require('luasettings')
local Doc=require('docsettings')
local UI=require('ui/uimanager')
local Copy=require('einkfrontend/catalog').copy
local M={};M.__index=M
local function parent(path) return path:match('^(.*)/[^/]+$') or '/' end
local function cleanPath(path)
 return type(path)=='string' and path:sub(1,1)=='/' and not path:find('[%c]') and not path:find('//',1,true)
  and not path:find('/../',1,true) and not path:find('/./',1,true) and not path:match('/%.%.?$')
end
local function inside(path,root) return cleanPath(path) and path:sub(1,#root+1)==root..'/' end
local function identity(path)
 local a=lfs.symlinkattributes(path)
 if not a then return nil end
 return {mode=a.mode,dev=a.dev,ino=a.ino,size=a.size,modification=a.modification}
end
local function same(a,b)
 return a and b and a.mode==b.mode and a.dev==b.dev and a.ino==b.ino and a.size==b.size and a.modification==b.modification
end
local function digest(path)
 local f=io.open(path,'rb');if not f then return nil end
 local ok,value=pcall(function()
  local hash=require('ffi/sha2').sha256()
  while true do local chunk=f:read(65536);if not chunk then break end;hash(chunk) end
  return hash()
 end)
 f:close();if ok then return value end
end
local function safeAncestors(path)
 local dir=parent(path)
 while dir~='' do
  local a,_,code=lfs.symlinkattributes(dir)
  if a then return a.mode=='directory' and F.realpath(dir)==dir end
  if code~=2 then return false end
  if dir=='/' then return false end
  dir=parent(dir)
 end
 return false
end
local function absent(path)
 if not cleanPath(path) or not safeAncestors(path) then return false end
 local a,_,code=lfs.symlinkattributes(path)
 return a==nil and code==2
end
local function opened(path)
 local reader=require('apps/reader/readerui').instance
 local current=reader and reader.document and reader.document.file
 return current and (current==path or F.realpath(current)==path) or false
end
local function listing(dir)
 local out={};local ok=pcall(function() for name in lfs.dir(dir) do if name~='.' and name~='..' then out[#out+1]=name end end end)
 if ok then table.sort(out);return out end
end
local function sibling(stem)
 local reader=require('apps/reader/readerui').instance
 local current=reader and reader.document and reader.document.file
 if current and ((current:match('^(.*)%.[^./]+$') or current)==stem) then return true end
 local dir=parent(stem);local names=listing(dir)
 if not names then return not absent(dir) end -- unknown/unreadable is not proof of absence
 local base=stem:match('([^/]+)$')
 for _,name in ipairs(names) do if name==base or name:sub(1,#base+1)==base..'.' then
  local a=lfs.symlinkattributes(dir..'/'..name)
  if not a or a.mode~='directory' then return true end
 end end
 return false
end
local function extension(name)
 return name:match('^metadata%.([%w_-]+)%.lua$') or name:match('^metadata%.([%w_-]+)%.lua%.old$')
end
local cover_types={jpg=true,jpeg=true,png=true,gif=true,webp=true,bmp=true}
local function common(name)
 return name=='custom_metadata.lua' or name=='custom_metadata.lua.old' or cover_types[name:match('^cover%.([%a]+)$') or '']
end
function M.new(app) return setmetatable({app=app,state='idle'},M) end
function M:cancel()
 if self.tick then UI:unschedule(self.tick) end
 self.tick=nil;self.co=nil;if self.state=='scanning' or self.state=='cleaning' then self.state='cancelled' end
end
function M:rootAlive(plan)
 local a=identity(plan.root)
 return a and a.mode=='directory' and a.dev==plan.root_attr.dev and a.ino==plan.root_attr.ino and F.realpath(plan.root)==plan.root
end
function M:run(state,fn,done)
 self:cancel();self.state=state;self.error=nil
 local co=coroutine.create(fn);self.co=co
 local function fail(why)
  self:cancel();self.state='error';self.error=tostring(why)
  if self.app.message then pcall(self.app.message,self.app,'书库维护未完成：'..self.error) end
 end
 local function step()
  if self.co~=co then return end
  local success,why=pcall(function()
   local ok,result=coroutine.resume(co)
   if not ok then fail(result);return
   elseif coroutine.status(co)=='dead' then self.co=nil;self.tick=nil;done(result)
   else UI:scheduleIn(.01,self.tick) end
   local route=self.app.stack and self.app.stack[#self.app.stack]
   if self.app.screen and route and route.id=='library_cleanup' then self.app:render() end
  end)
  if not success then fail(why) end
 end
 self.tick=step;UI:nextTick(step)
end
function M:addFile(plan,path,book,stem)
 if plan.seen[path] then return end
 local a=identity(path)
 if not a or a.mode~='file' or not safeAncestors(path) then return end
 -- Bound preview work on unexpectedly large files, and catch changes even on
 -- filesystems with one-second mtimes and same-size in-place replacements.
 if a.size>16*1024*1024 then plan.skipped=plan.skipped+1;return end
 local hash=digest(path);if not hash then plan.skipped=plan.skipped+1;return end
 plan.seen[path]=true;plan.files[#plan.files+1]={path=path,book=book,stem=stem,attr=a,hash=hash}
 plan.bytes=plan.bytes+a.size
end
function M:sidecar(plan,dir,stem)
 if F.realpath(dir)~=dir then return end
 local names=listing(dir);if not names then plan.skipped=plan.skipped+1;return end
 if #names==0 and not sibling(stem) then
  plan.empty_dirs=plan.empty_dirs or {};plan.empty_dirs[#plan.empty_dirs+1]={path=dir,stem=stem,attr=identity(dir)}
 end
 for _,name in ipairs(names) do
  local ext=extension(name)
  if ext then
   local file=ext=='_' and stem or stem..'.'..ext
   if inside(file,plan.root) and absent(file) and not opened(file) then
    plan.books[file]=true;self:addFile(plan,dir..'/'..name,file)
   end
  elseif common(name) and not sibling(stem) then self:addFile(plan,dir..'/'..name,nil,stem) end
 end
end
function M:cache()
 local path=DS:getSettingsDir()..'/bookinfo_cache.sqlite3'
 if lfs.symlinkattributes(path,'mode')=='file' and safeAncestors(path) then return path end
end
function M:scan()
 self.plan=nil;self.result=nil
 self:run('scanning',function()
  local root=assert(F.realpath(self.app.library.root or self.app.adapter:libraryRoot()),'书库目录不可用，请先连接存储设备')
  assert(root~='/' and listing(root),'无法读取书库目录，未清理任何数据')
  local plan={root=root,root_attr=assert(identity(root)),books={},files={},empty_dirs={},seen={},bytes=0,skipped=0,visited=0}
  local sources=0
  local function add(file)
   if inside(file,root) and absent(file) and not opened(file) then plan.books[file]=true end
   sources=sources+1;if sources%32==0 then coroutine.yield() end
  end
  for _,book in ipairs(self.app.library.books) do add(book.file) end
  for _,entry in ipairs(require('readhistory').hist) do add(entry.file) end
  local prices=self.app.library.settings:readSetting('reading_return')
  if type(prices)=='table' and type(prices.books)=='table' then for file in pairs(prices.books) do add(file) end end
  local collections=Settings:open(DS:getSettingsDir()..'/collection.lua')
  for _,coll in pairs(collections.data) do if type(coll)=='table' then for _,entry in ipairs(coll) do if type(entry)=='table' then add(entry.file) end end end end
  local cache=self:cache()
  if cache then
   local conn
   local ok,res=pcall(function()
    conn=require('lua-ljsqlite3/init').open(cache,'ro');conn:set_busy_timeout(150)
    return conn:exec('SELECT directory || filename FROM bookinfo LIMIT 50000;')
   end)
   if conn then conn:close() end
   if ok then
    if res and res[1] and #res[1]>=50000 then plan.truncated=true end
    for _,file in ipairs(res and res[1] or {}) do add(file) end
   else plan.skipped=plan.skipped+1 end
  end
  local function walk(dir,central,depth)
   if depth>32 or plan.visited>=50000 then plan.truncated=true;return end
   local names=listing(dir);if not names then plan.skipped=plan.skipped+1;return end
   for _,name in ipairs(names) do
    if not self:rootAlive(plan) then error('书库存储发生变化，已停止扫描') end
    local path=dir..'/'..name;local a=lfs.symlinkattributes(path)
    plan.visited=plan.visited+1
    if a and a.mode=='directory' and F.realpath(path)==path then
     if name:match('%.sdr$') then
      local stem=path:sub(1,-5)
      if central then stem=stem:sub(#DS:getDocSettingsDir()+1) end
      self:sidecar(plan,path,stem)
     elseif name:sub(1,1)~='.' and name~='koreader' and name~='system' then walk(path,central,depth+1) end
    end
    if plan.visited%16==0 then coroutine.yield() end
    if plan.truncated then break end
   end
  end
  walk(root,false,0)
  local central=DS:getDocSettingsDir()..root
  if lfs.symlinkattributes(central,'mode')=='directory' and F.realpath(central)==central then walk(central,true,0) end
  local legacy=0
  for file in pairs(plan.books) do self:addFile(plan,Doc:getHistoryPath(file),file);legacy=legacy+1;if legacy%32==0 then coroutine.yield() end end
  local count=0;for _ in pairs(plan.books) do count=count+1 end;plan.count=count
  return plan
 end,function(plan) self.plan=plan;self.state='ready' end)
end
function M:forget(files)
 if next(files)==nil then return end
 local app=self.app;local library=app.library;local store=library.settings
 local data=Copy(store.data);local books={}
 for _,book in ipairs(library.books) do if not files[book.file] then books[#books+1]=book end end
 data.books=books
 local prices=data.reading_return
 if type(prices)=='table' and type(prices.books)=='table' then
  for file in pairs(files) do prices.books[file]=nil end
  prices.revision=(tonumber(prices.revision) or 0)+1
 end
 for _,key in ipairs({'last_reading_detail','return_context'}) do if type(data[key])=='table' and files[data[key].file] then data[key]=nil end end
 if files[data.return_book] then data.return_book=nil;data.resume_library=nil end
 store.data=data;assert(store:flush()~=false,'书库索引未保存，请重试清理')
 -- Refresh every live reader/file-manager instance before another one can
 -- persist an obsolete library snapshot.
 for instance in pairs(require('einkfrontend/library').instances) do
  if instance.settings.file==store.file then
   instance:cancel();instance:clearCovers();instance.settings=store;instance.books=store:readSetting('books') or {}
  end
 end
 local history=require('readhistory')
 for file in pairs(files) do history:removeItemByPath(file);require('ui/widget/booklist').resetBookInfoCache(file) end
 local coll=Settings:open(DS:getSettingsDir()..'/collection.lua');local changed=false
 for _,list in pairs(coll.data) do if type(list)=='table' then
  for i=#list,1,-1 do if type(list[i])=='table' and files[list[i].file] then table.remove(list,i);changed=true end end
 end end
 if changed then assert(coll:flush()~=false,'收藏记录未保存，请重试清理') end
 local rc=require('readcollection');if rc.coll then for file in pairs(files) do rc:removeItem(file,nil,true) end end
 local cache=self:cache()
 if cache then
  local conn,stmt
  local ok,why=pcall(function()
   conn=require('lua-ljsqlite3/init').open(cache,'rw');conn:set_busy_timeout(150);conn:exec('BEGIN IMMEDIATE;')
   stmt=conn:prepare('DELETE FROM bookinfo WHERE directory=? AND filename=?;')
   for file in pairs(files) do if absent(file) and not opened(file) then
    local dir,name=require('util').splitFilePathName(file);stmt:bind(dir,name);stmt:step();stmt:clearbind():reset()
   end end
   stmt:close();stmt=nil;conn:exec('COMMIT;')
  end)
  if stmt then pcall(stmt.close,stmt) end
  if conn then if not ok then pcall(conn.exec,conn,'ROLLBACK;') end;conn:close() end
  assert(ok,'封面缓存未清理，请重试：'..tostring(why))
 end
end
function M:apply(plan)
 assert(plan and plan==self.plan and self.state=='ready','请先重新扫描清理项目')
 self:run('cleaning',function()
  assert(self:rootAlive(plan),'书库存储已变化，请重新扫描')
  local result={removed=0,bytes=0,skipped=plan.skipped,failed=0,books=0,directories=0}
  self.result=result
  local directories={}
  for _,entry in ipairs(plan.files) do
   assert(self:rootAlive(plan),'书库存储已变化，已停止清理')
   local allowed=same(entry.attr,identity(entry.path)) and safeAncestors(entry.path) and digest(entry.path)==entry.hash
    and (not entry.book or (absent(entry.book) and not opened(entry.book)))
    and (not entry.stem or not sibling(entry.stem))
   if allowed then
    local ok=os.remove(entry.path)
    if ok then result.removed=result.removed+1;result.bytes=result.bytes+entry.attr.size;directories[parent(entry.path)]=true
    else result.failed=result.failed+1 end
   else result.skipped=result.skipped+1 end
   coroutine.yield()
  end
  local missing={}
  assert(self:rootAlive(plan),'书库存储已变化，已停止清理')
  for file in pairs(plan.books) do if absent(file) and not opened(file) then missing[file]=true;result.books=result.books+1 end end
  self:forget(missing)
  for dir in pairs(directories) do if dir:match('%.sdr$') and F.realpath(dir)==dir then if os.remove(dir) then result.directories=result.directories+1 end end end -- empty dirs only
  for _,entry in ipairs(plan.empty_dirs or {}) do
   if self:rootAlive(plan) and same(entry.attr,identity(entry.path)) and safeAncestors(entry.path) and not sibling(entry.stem) then
    if os.remove(entry.path) then result.directories=result.directories+1 else result.skipped=result.skipped+1 end
   else result.skipped=result.skipped+1 end
  end
  return result
 end,function(result) self.result=result;self.plan=nil;self.state='done' end)
end
function M.deleteBook(app,book,expected)
 local file=book and book.file
 assert(cleanPath(file) and F.realpath(file)==file,'书籍路径不可用或是链接，请重新扫描书库')
 assert(not opened(file),'请先退出这本书，再删除书籍')
 local attr=identity(file)
 assert(attr and attr.mode=='file' and (not expected or same(attr,expected)),'书籍文件已变化，请重新确认')
 assert(require('document/documentregistry'):hasProvider(file),'请选择有效的书籍文件')
 assert(os.remove(file),'删除失败，请检查存储设备和文件权限')
 -- The document is already gone. A cleanup error must still let the caller
 -- update its navigation and report a partial cleanup instead of a failed delete.
 local cleaned,failures=pcall(function()
 local service=M.new(app)
 local plan={root=parent(file),root_attr=identity(parent(file)),files={},seen={},books={[file]=true},bytes=0,skipped=0}
 local stem=file:match('^(.*)%.[^./]+$') or file
 for _,location in ipairs({'doc','dir'}) do service:sidecar(plan,Doc:getSidecarDir(file,location),stem) end
 service:addFile(plan,Doc:getHistoryPath(file),file)
 local failures=0
 local other_format=false
 for _,entry in ipairs(plan.files) do if entry.book and entry.book~=file then other_format=true end end
 for _,entry in ipairs(plan.files) do
  if (entry.book==file or (not entry.book and not other_format)) and same(entry.attr,identity(entry.path)) and safeAncestors(entry.path) and digest(entry.path)==entry.hash and (not entry.stem or not sibling(entry.stem)) then
   if not os.remove(entry.path) then failures=failures+1 end
  end
 end
 for _,location in ipairs({'doc','dir'}) do
  local dir=Doc:getSidecarDir(file,location)
  if dir:match('%.sdr$') and F.realpath(dir)==dir then os.remove(dir) end -- empty dirs only
 end
 local ok=pcall(service.forget,service,{[file]=true})
 if not ok then failures=failures+1 end
 return failures
 end)
 if not cleaned then
  require('logger').warn('Book deleted; metadata cleanup pending:',failures)
  return 1
 end
 return failures
end
function M.requestDelete(app,book)
 local attr=identity(book.file)
 if not attr or attr.mode~='file' then app:message('书籍文件不存在，请清理已删除书籍的数据');return end
 if opened(book.file) then app:message('请先退出这本书，再删除书籍');return end
 app:confirm('永久删除“'..book.title..'”？\n'..book.file..'\n\n将移除书籍文件、阅读设置和书库记录，历史阅读统计保留。',function()
  app:userAction(function()
   local failed=M.deleteBook(app,book,attr)
   app:bookDeleted(book.file)
   if failed>0 then app:message('书籍已删除，部分残留数据未能清理，可在书库菜单中重试') end
  end)
 end)
end
return M
