-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local PP={};PP.__index=PP
local keys={'enabled','pressure','haptic','gain'}
local function copy(v) if type(v)=='table' then return {v[1],v[2]} end;return v end
local function equal(a,b) if type(a)=='table' and type(b)=='table' then return a[1]==b[1] and a[2]==b[2] end;return a==b end
local function valid(key,v)
 if v==nil then return true end
 if key=='enabled' or key=='haptic' then return type(v)=='boolean' end
 return type(v)=='number' and v==math.floor(v) and ((key=='pressure' and v>=1 and v<=65535) or (key=='gain' and v>=0 and v<=3))
end
function PP.supported(device) return (device or require('device')).model=='KindleVoyage' end
function PP.new(settings,hw)
 local config=settings:readSetting('eink_pagepress');local clean={}
 for _,key in ipairs(keys) do if type(config)=='table' and valid(key,config[key]) then clean[key]=config[key] end end
 return setmetatable({settings=settings,hw=hw,config=clean,baseline={},applied={},restore_pending={},errors={},owners=setmetatable({},{__mode='k'})},PP)
end
function PP:read(key)
 local ok,value=pcall(self.hw.read,self.hw,key)
 if not ok then return nil,tostring(value) end
 return value
end
function PP:verifiedWrite(key,value)
 self.hw:write(key,value)
 local actual=self.hw:read(key);assert(equal(actual,value),'设备未接受设置，读回值不一致')
end
function PP:change(key,value,persist)
 if not valid(key,value) or not ({enabled=true,pressure=true,haptic=true,gain=true})[key] then return false,'无效的 PagePress 设置' end
 local old,why=self:read(key);if old==nil then return false,why end
 local desired=value
 if key=='enabled' and value~=nil then desired=value and {1,1} or {0,0} end
 if value==nil then desired=self.baseline[key] end
 if desired==nil then desired=old end
 local previous=self.config[key]
 local wrote=false
 local ok,err=pcall(function()
  if not equal(old,desired) then wrote=true;self:verifiedWrite(key,desired) end
  if persist~=false then
   self.config[key]=value;self.settings:saveSetting('eink_pagepress',self.config)
   assert(self.settings:flush()~=false,'无法保存 PagePress 设置')
   if self.settings.file then
    local saved=require('luasettings'):open(self.settings.file):readSetting('eink_pagepress')
    for _,k in ipairs(keys) do assert(type(saved)=='table' and saved[k]==self.config[k],'PagePress 设置未能保存') end
   end
  end
 end)
 if not ok then
  self.config[key]=previous
  if persist~=false then self.settings:saveSetting('eink_pagepress',self.config);pcall(self.settings.flush,self.settings) end
  local restored,restore_error=true,nil
  if wrote then restored,restore_error=pcall(self.verifiedWrite,self,key,old) end
  if not restored then
   if self.baseline[key]==nil then self.baseline[key]=copy(old) end;self.applied[key]=copy(desired)
   self.restore_pending[key]=true
   err=tostring(err)..'；恢复原值失败：'..tostring(restore_error)
  end
  self.errors[key]=tostring(err);return false,self.errors[key]
 end
 self.errors[key]=nil
 self.restore_pending[key]=nil
 if value==nil then self.baseline[key]=nil;self.applied[key]=nil
 else if self.baseline[key]==nil then self.baseline[key]=copy(old) end;self.applied[key]=copy(desired) end
 return true
end
function PP:resume()
 if self.running then return end;self.running=true
 for _,key in ipairs(keys) do if self.config[key]~=nil then
  local ok,why=self:change(key,self.config[key],false);if not ok then self.errors[key]=why end
 end end
end
function PP:suspend()
 if not self.running then return end;self.running=false
 for _,key in ipairs(keys) do if self.baseline[key]~=nil then
  local current,why=self:read(key)
  -- Do not overwrite changes made by the Kindle framework or another plugin.
  if current~=nil and (self.restore_pending[key] or equal(current,self.applied[key])) then
   local ok,why=true,nil
   if not equal(current,self.baseline[key]) then ok,why=pcall(self.verifiedWrite,self,key,self.baseline[key]) end
   if ok then self.baseline[key]=nil;self.applied[key]=nil;self.restore_pending[key]=nil
   else self.restore_pending[key]=true;self.errors[key]=tostring(why) end
  elseif current~=nil then self.baseline[key]=nil;self.applied[key]=nil
  else self.errors[key]='恢复前无法读取设备：'..tostring(why) end
 end end
end
local shared
function PP.attach(app)
 if not PP.supported() then return nil end
 if not shared then shared=PP.new(G_reader_settings,require('einkfrontend/pagepresshw').new()) end
 shared.owners[app]=true;shared:resume();return shared
end
function PP:detach(app)
 self.owners[app]=nil
 if next(self.owners)==nil then self:suspend() end
end
return PP
