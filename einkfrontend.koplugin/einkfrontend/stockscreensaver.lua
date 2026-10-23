-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Read stock artwork in place; all writes go to KOReader settings only.
local lfs=require('libs/libkoreader-lfs')
local Stock={paths={'/usr/share/blanket/screensaver','/usr/share/blanket/screensavers'}}
function Stock.supported(device)
 device=device or require('device')
 if not device:isKindle() then return false,'此功能用于 Kindle' end
 if not device:supportsScreensaver() then return false,'当前设备由 Kindle 系统管理屏保，KOReader 无法显示自选图片' end
 return true
end
function Stock.scan(path)
 if type(path)~='string' or #path>1024 or path:sub(1,1)~='/' or path:find('%z') then return nil,'请输入有效的绝对目录路径' end
 local files={}
 local ok=pcall(function()
  for name in lfs.dir(path) do
   if #files>=256 then break end
   if name:sub(1,2)~='._' and name:lower():match('%.%w+$') then
    local ext=name:lower():match('%.(%w+)$')
    if ext=='png' or ext=='jpg' or ext=='jpeg' then
     local file=path..'/'..name;local attr=lfs.attributes(file)
     if attr and attr.mode=='file' and attr.size>0 and attr.size<=25*1024*1024 then files[#files+1]=file end
    end
   end
  end
 end)
 if not ok then return nil,'目录不存在或无法读取' end
 table.sort(files);if #files==0 then return nil,'目录中没有可用的 PNG / JPG 图片' end
 return files
end
function Stock.detect()
 for _,path in ipairs(Stock.paths) do local files=Stock.scan(path);if files then return path,files end end
 return nil,nil,'未找到 Kindle 自带屏保图片，可手动指定设备上的目录'
end
function Stock.active(settings)
 local state=settings:readSetting('eink_stock_screensaver')
 return type(state)=='table' and state.version==1 and settings:readSetting('screensaver_type')=='random_image'
  and settings:readSetting('screensaver_dir')==state.path
end
local function transaction(settings,fn)
 local snapshot={};local keys={'eink_stock_screensaver','screensaver_type','screensaver_dir','screensaver_show_message','screensaver_img_background','screensaver_stretch_images','screensaver_rotate_auto_for_best_fit','screensaver_cycle_images_alphabetically'}
 for _,key in ipairs(keys) do snapshot[key]={present=settings:has(key),value=settings:readSetting(key)} end
 local ok,why=pcall(function() fn();assert(settings:flush()~=false,'无法保存屏保设置') end)
 if not ok then
  for key,item in pairs(snapshot) do if item.present then settings:saveSetting(key,item.value) else settings:delSetting(key) end end
  pcall(settings.flush,settings);return false,tostring(why)
 end
 return true
end
function Stock.activate(settings,path,device)
 local ok,why=Stock.supported(device);if not ok then return false,why end
 local files;files,why=Stock.scan(path);if not files then return false,why end
 return transaction(settings,function()
  local previous=settings:readSetting('eink_stock_screensaver')
  local backup={}
  if type(previous)=='table' and previous.version==1 then for key,value in pairs(previous.backup or {}) do backup[key]=value end end
  local applied={screensaver_type='random_image',screensaver_dir=path,screensaver_show_message=false,screensaver_img_background='white',screensaver_stretch_images=false,screensaver_rotate_auto_for_best_fit=true,screensaver_cycle_images_alphabetically=false}
  for key,value in pairs(applied) do
   if not backup[key] then backup[key]={present=settings:has(key),value=settings:readSetting(key)} end
   settings:saveSetting(key,value)
  end
  settings:saveSetting('eink_stock_screensaver',{version=1,path=path,backup=backup,applied=applied})
 end)
end
function Stock.restore(settings)
 local state=settings:readSetting('eink_stock_screensaver')
 if type(state)~='table' or state.version~=1 then return false,'没有可恢复的屏保设置' end
 return transaction(settings,function()
  for key,item in pairs(state.backup or {}) do
   -- Preserve changes the user subsequently made in KOReader's own menu.
   if settings:readSetting(key)==(state.applied or {})[key] then
    if item.present then settings:saveSetting(key,item.value) else settings:delSetting(key) end
   end
  end
  settings:delSetting('eink_stock_screensaver')
 end)
end
return Stock
