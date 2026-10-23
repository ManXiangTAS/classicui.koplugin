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
 return nil,nil,'未找到可读取的 Kindle 原生屏保图片，当前壁纸未更改。可在“自定义图片”中手动选择目录。'
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
  local backup={};local was_active=Stock.active(settings)
  local applied={screensaver_type='random_image',screensaver_dir=path}
  if type(previous)=='table' and previous.version==1 then
   for key,item in pairs(previous.backup or {}) do
    if applied[key]~=nil then
     if was_active then backup[key]=item end
    elseif settings:readSetting(key)==(previous.applied or {})[key] then
     -- Release display overrides written by older plugin versions.
     if item.present then settings:saveSetting(key,item.value) else settings:delSetting(key) end
    end
   end
  end
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
-- Decorate only the copied native Wallpaper menu, never a shared provider table.
function Stock.extendMenu(node)
 if not require('device'):isKindle() then return end
 local tr=require('gettext')
 for _,wallpaper in ipairs(node.sub_item_table or {}) do
  if wallpaper.text==tr('Wallpaper') and type(wallpaper.sub_item_table)=='table' then
   local items=wallpaper.sub_item_table
   for _,item in ipairs(items) do if item.id=='eink_stock_wallpaper' then return end end
   local function failure(why)
    require('ui/uimanager'):show(require('ui/widget/infomessage'):new{text=why})
   end
   local insert_at=1
   for index,item in ipairs(items) do
    if item.radio and type(item.callback)=='function' then
     local callback=item.callback
     item.callback=function(...)
      if G_reader_settings:has('eink_stock_screensaver') then
       local ok,why=Stock.restore(G_reader_settings)
       if not ok then failure(why);return end
      end
      return callback(...)
     end
     if item.text==tr('Show random image from folder on sleep screen') then
      insert_at=index+1
      local checked=item.checked_func
      item.checked_func=function() return not Stock.active(G_reader_settings) and checked() end
     end
    end
   end
   table.insert(items,insert_at,{
    id='eink_stock_wallpaper',text='使用 Kindle 原生屏保',radio=true,keep_menu_open=true,
    checked_func=function() return Stock.active(G_reader_settings) end,
    enabled_func=function() return Stock.supported() end,
    callback=function()
     local path,_,why=Stock.detect()
     if not path then failure(why);return end
     local ok,err=Stock.activate(G_reader_settings,path)
     if not ok then failure(err) end
    end,
   })
   return
  end
 end
end
return Stock
