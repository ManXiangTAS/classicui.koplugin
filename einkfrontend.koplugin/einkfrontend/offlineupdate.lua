-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Retire the former updater without reading or executing its staged contents.
local O={}
local function pluginRoot()
 local file=debug.getinfo(1,'S').source:match('^@(.+)/einkfrontend/offlineupdate%.lua$')
 return assert(require('ffi/util').realpath(assert(file,'无法定位插件目录')))
end
function O.disable(settings,root)
 if not root and O.done then return O.result end
 local production=root==nil
 local lfs=require('libs/libkoreader-lfs');local count=0
 local function erase(path,depth)
  count=count+1;assert(count<=10000 and depth<=32,'旧更新缓存过多，请手动清理插件更新目录')
  local mode=lfs.symlinkattributes(path,'mode');if not mode then return end
  if mode=='directory' then
   for name in lfs.dir(path) do if name~='.' and name~='..' then erase(path..'/'..name,depth+1) end end
   assert(lfs.rmdir(path))
  else assert(os.remove(path)) end -- unlink symbolic links; never follow them
 end
 local failures={}
 settings=settings or G_reader_settings
 if settings then
  local ok,why=pcall(function()
   local changed=settings:has('eink_updater') or settings:has('eink_updater_state')
   settings:delSetting('eink_updater');settings:delSetting('eink_updater_state')
   if changed then assert(settings:flush()~=false,'旧更新设置保存失败') end
  end)
  if not ok then failures[#failures+1]=tostring(why) end
 end
 local ok,why=pcall(function()
  root=root or pluginRoot();local work=root..'-update'
  if lfs.symlinkattributes(work,'mode')=='directory' then erase(work..'/pending.json',0) end
  erase(work,0)
 end)
 if not ok then failures[#failures+1]=tostring(why) end
 local result={ok=#failures==0,errors=failures}
 if production then O.done=true;O.result=result end
 if not result.ok then require('logger').warn('Offline updater cleanup:',table.concat(failures,'; ')) end
 return result
end
return O
