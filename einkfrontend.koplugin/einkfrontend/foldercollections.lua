-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Explicit, additive migration of directory groupings into native collections.
local UI=require('ui/uimanager')
local lfs=require('libs/libkoreader-lfs')
local Util=require('ffi/util')
local Registry=require('document/documentregistry')
local LuaSettings=require('luasettings')
local DataStorage=require('datastorage')
local Copy=require('einkfrontend/catalog').copy
local Equal=require('einkfrontend/adapter').equal
local Import={};Import.__index=Import
local function same(a,b,content)
 if not a or not b or a.mode~=b.mode then return false end
 for _,key in ipairs(content and {'dev','ino','size','modification'} or {'dev','ino'}) do
  if a[key]~=b[key] then return false end
 end
 return true
end
function Import.new(app) return setmetatable({app=app,state='idle'},Import) end
function Import:cancel()
 if self.tick then UI:unschedule(self.tick) end
 self.tick=nil;self.job=nil
 if self.state=='scanning' then self.state='cancelled';self.plan=nil end
end
function Import:scan(path)
 self:cancel();self.state='idle';self.plan=nil;self.result=nil;self.error=nil
 local root=assert(Util.realpath(path),'文件夹不存在')
 if root~='/' then root=root:gsub('/+$','') end
 local root_attr=lfs.symlinkattributes(root)
 assert(root_attr and root_attr.mode=='directory','请选择文件夹')
 self.source=root
 local plan={root=root,groups={},books={},dirs={[root]=root_attr},skipped=0,loose=0,count=0}
 local groups={};local visited,memberships=0,0
 local co=coroutine.create(function()
  local function visit(dir,relative,depth)
   assert(depth<=32,'目录层级超过32层，请选择较小的文件夹')
   local ok,iter,state=pcall(lfs.dir,dir)
   if not ok then
    assert(dir~=root,'无法读取所选文件夹');plan.skipped=plan.skipped+1;return
   end
   for name in iter,state do
    if name~='.' and name~='..' then
     visited=visited+1;assert(visited<=100000,'扫描项目超过上限，请选择较小的文件夹')
     if name:sub(1,1)~='.' and not name:match('%.sdr$') and name~='koreader' and name~='system' then
      local file=(dir=='/' and '' or dir)..'/'..name
      local attr=lfs.symlinkattributes(file)
      if attr and attr.mode=='directory' then
       plan.dirs[file]=attr
       visit(file,relative=='' and name or relative..'/'..name,depth+1)
      elseif attr and attr.mode=='file' and Registry:hasProvider(file) and not Registry:isImageFile(file) then
       if relative=='' then plan.loose=plan.loose+1
       else
        plan.count=plan.count+1;assert(plan.count<=10000,'书籍超过10000本，请分目录导入')
        plan.books[file]=attr
        local prefix=''
        for part in relative:gmatch('[^/]+') do
         prefix=prefix=='' and part or prefix..'/'..part
         assert(#prefix<=200,'目录名称过长，请缩短名称或选择更深一级的文件夹')
         if not groups[prefix] then
          assert(#plan.groups<2000,'收藏数量超过2000个，请分目录导入')
          groups[prefix]={name=prefix,files={}};plan.groups[#plan.groups+1]=groups[prefix]
         end
         memberships=memberships+1;assert(memberships<=100000,'收藏成员超过上限，请分目录导入')
         local files=groups[prefix].files;files[#files+1]=file
        end
       end
      elseif not attr or attr.mode=='link' then plan.skipped=plan.skipped+1 end
     end
     if visited%48==0 then coroutine.yield() end
    end
   end
  end
  visit(root,'',0)
  table.sort(plan.groups,function(a,b) return a.name<b.name end)
  for _,group in ipairs(plan.groups) do table.sort(group.files) end
 end)
 self.state='scanning';self.job=co
 self.tick=function()
  if self.job~=co then return end
  local ok,why=coroutine.resume(co)
  if not ok then self:cancel();self.state='error';self.error=tostring(why)
  elseif coroutine.status(co)=='dead' then
   self.job=nil;self.tick=nil;self.plan=plan;self.state='ready'
  else UI:scheduleIn(.01,self.tick) end
  local rendered,err=pcall(self.app.render,self.app)
  if not rendered then self:cancel();self.state='error';self.error=tostring(err) end
 end
 UI:nextTick(self.tick)
end
function Import:summary(plan)
 local rc=require('readcollection');local out={created=0,merged=0,unchanged=0,added=0,existing=0,groups={}}
 for _,group in ipairs(plan.groups) do
  local coll=rc.coll[group.name]
  local added=0
  for _,file in ipairs(group.files) do
   if coll and coll[file] then out.existing=out.existing+1 else out.added=out.added+1;added=added+1 end
  end
  if not coll then out.created=out.created+1
  elseif added>0 then out.merged=out.merged+1 else out.unchanged=out.unchanged+1 end
  out.groups[#out.groups+1]={name=group.name,count=#group.files,added=added,
   status=not coll and '新增' or added>0 and ('补入'..added..'本') or '已导入'}
 end
 return out
end
function Import:apply(plan)
 assert(self.state=='ready' and plan==self.plan,'预览已失效，请重新扫描')
 assert(Util.realpath(plan.root)==plan.root,'文件夹路径已变化，请重新扫描')
 for dir,attr in pairs(plan.dirs) do
  assert(same(attr,lfs.symlinkattributes(dir),false),'文件夹已变化，请重新扫描：'..dir)
 end
 for file,attr in pairs(plan.books) do
  assert(same(attr,lfs.symlinkattributes(file),true) and Util.realpath(file)==file,
   '书籍已变化，请重新扫描：'..file)
 end
 local rc=require('readcollection');local summary=self:summary(plan)
 if summary.added==0 then self.result=summary;self.state='done';return summary end
 local path=DataStorage:getSettingsDir()..'/collection.lua'
 local disk=LuaSettings:open(path);local disk_before=Copy(disk.data)
 local before={coll=Copy(rc.coll),settings=Copy(rc.coll_settings),default=rc.coll_default}
 -- A persistent copy is kept even if restoring the main collection file fails.
 local backup_path=DataStorage:getSettingsDir()..'/collection-before-folder-import.lua'
 local backup=LuaSettings:open(backup_path);backup.data=Copy(disk_before)
 assert(backup:flush()~=false and Equal(LuaSettings:open(backup_path).data,disk_before),'收藏备份保存失败，未导入')
 local touched={}
 local ok,why=pcall(function()
  for _,group in ipairs(plan.groups) do
   if not rc.coll[group.name] then rc:addCollection(group.name) end
   for _,file in ipairs(group.files) do
    if not rc.coll[group.name][file] then rc:addItem(file,group.name,plan.books[file]);touched[group.name]=true end
   end
  end
  rc:write(touched)
  local saved=LuaSettings:open(path)
  for name in pairs(touched) do
   local data=assert(saved:readSetting(name),'收藏未保存：'..name)
   assert(Equal(data.settings,rc.coll_settings[name]),'收藏设置保存不一致：'..name)
   local members={}
   for _,item in ipairs(data) do members[item.file]=true end
   for file in pairs(rc.coll[name]) do assert(members[file],'收藏成员未保存：'..file);members[file]=nil end
   assert(not next(members),'收藏成员保存不一致：'..name)
  end
  for name,data in pairs(disk_before) do
   if not touched[name] then assert(Equal(saved:readSetting(name),data),'原收藏发生变化：'..name) end
  end
 end)
 if not ok then
  rc.coll,rc.coll_settings,rc.coll_default=before.coll,before.settings,before.default
  local restored=pcall(function()
   local restore=LuaSettings:open(path);restore.data=Copy(disk_before)
   assert(restore:flush()~=false and Equal(LuaSettings:open(path).data,disk_before))
  end)
  error(tostring(why)..(restored and '；已恢复原收藏' or '；恢复失败，原收藏备份保存在：'..backup_path))
 end
 self.result=summary;self.state='done';return summary
end
return Import
