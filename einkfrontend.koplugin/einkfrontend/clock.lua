-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Process-local timezone; system UTC is synchronized by KOReader's own plugin.
local ffi=require('ffi');require('ffi/posix_h');ffi.cdef[[void tzset(void);]]
local Settings=require('luasettings');local Copy=require('einkfrontend/catalog').copy
local Equal=require('einkfrontend/adapter').equal;local UI=require('ui/uimanager')
local original_tz=os.getenv('TZ');local live=setmetatable({},{__mode='k'})
local base=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')..'/../resources/timezones/'
if base:sub(1,1)~='/' then base=require('libs/libkoreader-lfs').currentdir()..'/'..base end
local file=assert(io.open(base..'zones.json','r'));local database=require('json').decode(file:read('*a'));file:close()
local Clock={zones=database.zones,version=database.version};Clock.__index=Clock
Clock.by_id={system={id='system',label='跟随系统'}}
local labels={['Etc/UTC']='协调世界时 UTC',['Asia/Shanghai']='北京 / 上海',['Asia/Taipei']='台北',
 ['Asia/Hong_Kong']='香港',['Asia/Tokyo']='东京',['Asia/Singapore']='新加坡',['Asia/Seoul']='首尔',
 ['Asia/Kolkata']='印度',['Asia/Kathmandu']='尼泊尔',['Asia/Dubai']='迪拜',['Europe/London']='伦敦',
 ['Europe/Paris']='巴黎',['Europe/Berlin']='柏林',['America/New_York']='纽约',['America/Chicago']='芝加哥',
 ['America/Los_Angeles']='洛杉矶',['America/Vancouver']='温哥华',['Australia/Sydney']='悉尼',['Pacific/Auckland']='奥克兰'}
Clock.common={'system','Asia/Shanghai','Asia/Tokyo','Asia/Taipei','Asia/Hong_Kong','Asia/Singapore','Asia/Seoul','Etc/UTC',
 'Asia/Kolkata','Asia/Kathmandu','Asia/Dubai','Europe/London','Europe/Paris','Europe/Berlin','America/New_York',
 'America/Chicago','America/Los_Angeles','America/Vancouver','Australia/Sydney','Pacific/Auckland'}
for _,zone in ipairs(Clock.zones) do zone.label=labels[zone.id] or zone.id;Clock.by_id[zone.id]=zone end
function Clock.label(id) local zone=Clock.by_id[id];return zone and zone.label or '未知时区' end
function Clock.apply(id)
 assert(Clock.by_id[id],'请选择列表中的时区')
 if id=='system' then
  assert((original_tz and ffi.C.setenv('TZ',original_tz,1) or ffi.C.unsetenv('TZ'))==0,'无法恢复系统时区')
 else
  local path=base..id;local f=assert(io.open(path,'rb'),'时区数据缺失，请重新安装插件')
  local signature=f:read(4);f:close();assert(signature=='TZif','时区数据损坏，请重新安装插件')
  assert(ffi.C.setenv('TZ',':'..path,1)==0,'无法设置时区')
 end
 ffi.C.tzset()
end
function Clock.new(app)
 local before_tz=os.getenv('TZ')
 local settings=Settings:open(require('datastorage'):getSettingsDir()..'/einkfrontend-clock.lua')
 local config=settings:readSetting('clock') or {version=1,zone='system'}
 local ok,why=pcall(function()
  assert(type(config)=='table' and config.version==1 and type(config.zone)=='string' and Clock.by_id[config.zone],'时间配置损坏；原文件已保留，请重新选择时区')
  Clock.apply(config.zone)
 end)
 if app then live[app]=true end
 if ok and before_tz~=os.getenv('TZ') then UI:nextTick(function() Clock.refresh() end) end
 return setmetatable({settings=settings,config=ok and Copy(config) or {version=1,zone='system'},error=not ok and tostring(why) or nil},Clock)
end
function Clock.refresh()
 for app in pairs(live) do if app.screen then app:render() end end
 UI:broadcastEvent(require('ui/event'):new('TimeFormatChanged'));UI:setDirty('all','full')
end
function Clock:select(id)
 local previous=Copy(self.settings.data);local old_tz=os.getenv('TZ');local config={version=1,zone=id}
 local ok,why=pcall(function()
  Clock.apply(id);self.settings:saveSetting('clock',config);self.settings:flush()
  assert(Equal(Settings:open(self.settings.file):readSetting('clock'),config),'时区未能保存')
 end)
 if not ok then
  if old_tz then ffi.C.setenv('TZ',old_tz,1) else ffi.C.unsetenv('TZ') end;ffi.C.tzset()
  self.settings.data=previous;pcall(self.settings.flush,self.settings)
  return false,tostring(why)
 end
 self.config=config;self.error=nil
 for app in pairs(live) do if app.clock and app.clock~=self then
  app.clock.config=Copy(config);app.clock.error=nil;app.clock.settings.data=Copy(self.settings.data)
 end end
 Clock.refresh();return true
end
function Clock.syncNode(app)
 app.native:refresh();local entry=app.native.catalog.entries.synchronize_time
 local node=entry and entry.node
 if not node or type(node.callback)~='function' or not require('einkfrontend/native').enabled(node) then
  return nil,'原生时间同步不可用；请检查 timesync 插件、联网及系统校时权限'
 end
 return node
end
function Clock.sync(app)
 if not app.plugin.active or not app.adapter:alive() then return false,'当前阅读器已关闭或前端已停用' end
 local node,why=Clock.syncNode(app);if not node then return false,why end
 -- The pinned native timesync callback owns networking, NTP, RTC, Kindle
 -- setdate and truthful success/failure messages. Never simulate success.
 require('ui/network/manager'):runWhenOnline(function()
  if not app.plugin.active or not app.adapter:alive() then return end
  local ok,err=pcall(node.callback)
  if not ok then app:message('时间同步未完成：'..tostring(err)) end
  Clock.refresh()
 end)
 return true
end
return Clock
