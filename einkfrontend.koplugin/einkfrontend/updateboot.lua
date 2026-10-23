-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Journaled file replacement before frontend modules load. Never hot swap code.
local lfs=require('libs/libkoreader-lfs')
local fs=require('ffi/util')
local json=require('json')
local B={schema=1}
function B.safe(path)
 if type(path)~='string' or #path==0 or #path>240 or path:find('[%c\\:]') or path:sub(1,1)=='/' or path:sub(-1)=='/' then return false end
 for part in (path..'/'):gmatch('(.-)/') do
  if part=='' or part=='.' or part=='..' or part:match('[. ]$') or part=='.git' then return false end
 end
 return true
end
function B.root()
 local path=debug.getinfo(1,'S').source:match('^@(.+)/einkfrontend/updateboot%.lua$')
 return assert(fs.realpath(assert(path,'无法定位插件安装目录')),'插件目录不存在')
end
function B.work(root) return root..'-update' end
function B.regular(path) return lfs.symlinkattributes(path,'mode')=='file' end
function B.parents(base,path,create)
 assert(B.safe(path),'更新路径无效')
 assert(lfs.symlinkattributes(base,'mode')=='directory','更新目录不可用或为链接')
 local parent=base
 for part in path:gmatch('([^/]+)/') do
  parent=parent..'/'..part;local mode=lfs.symlinkattributes(parent,'mode')
  if not mode and create then assert(lfs.mkdir(parent));mode='directory' end
  assert(mode=='directory','更新路径包含链接或非目录')
 end
 local mode=lfs.symlinkattributes(base..'/'..path,'mode')
 assert(not mode or mode=='file','更新目标不是普通文件')
 return base..'/'..path
end
function B.mkdir(path)
 local mode=lfs.symlinkattributes(path,'mode')
 if not mode then assert(lfs.mkdir(path));mode='directory' end
 assert(mode=='directory','更新工作目录不是目录')
end
function B.read(path,limit)
 assert(B.regular(path),'文件不可用或为链接')
 local f=assert(io.open(path,'rb'));local data=f:read((limit or 1024*1024)+1);f:close()
 assert(#data<=(limit or 1024*1024),'更新文件过大');return data
end
function B.write(path,data)
 local f=assert(io.open(path,'wb'));local ok,why=pcall(function() assert(f:write(data));assert(fs.fsyncOpenedFile(f,true)) end)
 f:close();assert(ok,why)
end
function B.atomic(base,path,data)
 local dest=B.parents(base,path,true);local tmp=B.parents(base,path..'.eink-new',true)
 B.write(tmp,data);assert(os.rename(tmp,dest));fs.fsyncDirectory(dest)
end
function B.save(work,name,value) B.atomic(work,name,json.encode(value)) end
function B.load(work,name)
 local path=work..'/'..name;if not lfs.symlinkattributes(path) then return nil end
 return json.decode(B.read(path,1024*1024))
end
function B.removeTree(path)
 local mode=lfs.symlinkattributes(path,'mode');if not mode then return end
 if mode=='directory' then for n in lfs.dir(path) do if n~='.' and n~='..' then B.removeTree(path..'/'..n) end end;assert(lfs.rmdir(path))
 else assert(os.remove(path)) end
end
function B.hash(path)
 local sha=require('ffi/sha2').sha256();local f=assert(io.open(path,'rb'))
 while true do local data=f:read(65536);if not data then break end;sha(data) end
 f:close();return sha()
end
function B.manifest(value)
 assert(type(value)=='table' and value.schema==1 and type(value.version)=='string' and type(value.files)=='table','更新清单无效')
 local count=0;for path,digest in pairs(value.files) do
  assert(B.safe(path) and path~='UPDATE_MANIFEST.json' and type(digest)=='string' and #digest==64 and digest:match('^[a-f0-9]+$'),'更新清单路径或摘要无效')
  count=count+1;assert(count<=4096,'更新文件过多')
 end
 assert(value.files['main.lua'] and value.files['einkfrontend/updateboot.lua'] and value.files['einkfrontend/version.lua'],'安装包缺少必要文件')
 return value
end
function B.checkStage(root,expected,selected_stage)
 local work=B.work(root);local stage=selected_stage or work..'/next';local m=B.manifest(B.load(stage,'UPDATE_MANIFEST.json'))
 assert(not expected or m.version==expected,'安装版本与所选版本不一致')
 local compatible=false
 for _,v in ipairs(m.koreader or {}) do if v==require('version'):getCurrentRevision() then compatible=true end end
 assert(compatible,'此更新不支持当前 KOReader 版本')
 for path,digest in pairs(m.files) do
  local file=B.parents(stage,path,false);assert(B.regular(file) and B.hash(file)==digest,'更新文件校验失败：'..path)
 end
 assert(B.read(stage..'/main.lua',128*1024):find('einkfrontend/updateboot',1,true),'更新包缺少启动恢复入口')
 return m
end
function B.pending(root) return B.load(B.work(root),'pending.json') end
function B.clearPending(root)
 local work=B.work(root);assert(not B.load(work,'journal.json'),'安装恢复尚未结束')
 os.remove(work..'/pending.json');B.removeTree(work..'/next');os.remove(work..'/download.zip')
end
local function copy(from,base,path)
 B.atomic(base,path,B.read(from,32*1024*1024))
end
function B.recover(root)
 local work=B.work(root);local journal=B.load(work,'journal.json');if not journal then return false end
 assert(journal.schema==1 and journal.root==root and type(journal.files)=='table','更新恢复记录无效')
 if journal.phase=='applying' then
  for _,item in ipairs(journal.files) do
   assert(B.safe(item.path) and type(item.had)=='boolean','更新恢复路径无效')
   if item.had then local backup=B.parents(work..'/previous',item.path,false);assert(type(item.sha256)=='string' and B.hash(backup)==item.sha256,'旧版本备份校验失败');copy(backup,root,item.path)
   else local path=B.parents(root,item.path,false);if B.regular(path) then assert(os.remove(path)) end end
  end
 else assert(journal.phase=='backing_up' or journal.phase=='committed','更新恢复阶段无效') end
 os.remove(work..'/pending.json');assert(os.remove(work..'/journal.json'));fs.fsyncDirectory(work)
 B.save(work,'result.json',{ok=journal.phase=='committed',version=journal.version,message=journal.phase=='committed' and '更新安装完成' or '上次安装未完成，已保留或恢复旧版本'})
 return true,journal.phase=='committed'
end
function B.apply(root,hook)
 local work=B.work(root);local pending=B.pending(root);if not pending then return false end
 assert(type(pending)=='table' and pending.schema==1 and type(pending.version)=='string','待安装记录无效')
 local m=B.checkStage(root,pending.version);local paths={};for path in pairs(m.files) do paths[path]=true end;paths['UPDATE_MANIFEST.json']=true
 local previous=lfs.symlinkattributes(root..'/UPDATE_MANIFEST.json') and B.manifest(B.load(root,'UPDATE_MANIFEST.json'))
 for path in pairs(previous and previous.files or {}) do paths[path]=true end
 local files={};local need=8*1024*1024
 for path in pairs(paths) do
  local target=B.parents(root,path,true);local attr=lfs.attributes(target);if attr then assert(attr.size<=32*1024*1024,'原文件过大');need=need+attr.size end
  files[#files+1]={path=path,had=attr~=nil}
 end
 table.sort(files,function(a,b) if a.path=='main.lua' then return false elseif b.path=='main.lua' then return true end;return a.path<b.path end)
 local _,free=fs.df(root);assert(free>=need,'空间不足，不能备份旧版本')
 B.removeTree(work..'/previous');B.mkdir(work..'/previous')
 local journal={schema=1,root=root,phase='backing_up',files=files,version=m.version};B.save(work,'journal.json',journal)
 for _,item in ipairs(files) do if item.had then copy(root..'/'..item.path,work..'/previous',item.path);item.sha256=B.hash(work..'/previous/'..item.path) end end
 journal.phase='applying';B.save(work,'journal.json',journal)
 for i,item in ipairs(files) do
  if m.files[item.path] or item.path=='UPDATE_MANIFEST.json' then copy(work..'/next/'..item.path,root,item.path)
  elseif item.had then assert(os.remove(root..'/'..item.path)) end
  if hook then hook(i,item.path) end
 end
 journal.phase='committed';B.save(work,'journal.json',journal)
 B.save(work,'result.json',{ok=true,version=m.version,message='更新安装完成'})
 os.remove(work..'/pending.json');assert(os.remove(work..'/journal.json'));fs.fsyncDirectory(work)
 pcall(B.removeTree,work..'/next');pcall(B.removeTree,work..'/previous');os.remove(work..'/download.zip')
 return true
end
function B.startup()
 if B.started then return end;B.started=true
 local root=B.root();local work=B.work(root)
 if not lfs.symlinkattributes(work) then return end
 B.mkdir(work)
 local function reload()
  package.loaded['einkfrontend/updateboot']=nil
  require('einkfrontend/updateboot').started=true
  return true
 end
 if B.recover(root) then return reload() end
 if not B.pending(root) then
  pcall(B.removeTree,work..'/incoming');pcall(B.removeTree,work..'/next');pcall(B.removeTree,work..'/previous');os.remove(work..'/download.zip');return
 end
 local ok,why=pcall(B.apply,root)
 if ok then return reload() end
 -- A failed rollback must stop plugin loading: mixed modules cannot be used.
 local recovered,committed=B.recover(root)
 if not committed then
  os.remove(work..'/pending.json');pcall(B.save,work,'result.json',{ok=false,message=tostring(why):sub(1,500)})
  require('logger').warn('ClassicUI update failed; old version retained:',why)
 end
 if recovered then return reload() end
end
return B
