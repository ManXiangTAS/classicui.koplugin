-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Read-only sensor adapters. Raw ADC values and 0..4 ambient bins are never Lux.
local Curve=require('einkfrontend/lightcurve')
local Sensor={};Sensor.__index=Sensor
local function call(object,name,...)
 if not object or type(object[name])~='function' then return nil end
 local ok,value=pcall(object[name],object,...);if ok then return value end
end
function Sensor.new(device) return setmetatable({device=device},Sensor) end
function Sensor:kindleRead()
 local ok,lipc=pcall(require,'liblipclua')
 if not ok or type(lipc)~='table' then return nil,'ϵͳ��нӿڲ�����' end
 local opened,h=pcall(lipc.init,'com.github.classicui.adaptivelight')
 if not opened or not h then return nil,'�޷�����ϵͳ��з���' end
 local success,lux,native,state=pcall(function()
  return call(h,'get_int_property','com.lab126.powerd','alsLux'),
   call(h,'get_int_property','com.lab126.powerd','flAuto'),call(h,'get_string_property','com.lab126.powerd','state')
 end)
 pcall(function() h:close() end)
 if not success or not Curve.lux(lux) then return nil,'�޷���ȡ��Ч�ն�' end
 if native==1 then return nil,'���ȹر� Kindle ԭ���Զ����ȣ�������������ͬʱ����' end
 if native~=0 then return nil,'�޷�ȷ��ԭ���Զ������Ƿ�ر�' end
 if state=='screenSaver' or state=='suspended' then return nil,'�豸��������' end
 return lux
end
function Sensor:readFile(path)
 local f=io.open(path,'r');if not f then return nil end
 local value=tonumber(f:read(128));f:close();return value
end
function Sensor:read()
 if self.backend=='lipc' then return self:kindleRead() end
 if self.path then
  local lux=self:readFile(self.path)
  if Curve.lux(lux) then return lux end
 end
 return nil,'��ж����ݲ�����'
end
function Sensor:probe()
 self.backend=nil;self.path=nil
 if not call(self.device,'hasFrontlight') then return false,'��ǰ�豸û�пɿ�ǰ��' end
 if not call(self.device,'hasLightSensor') then return false,'��ǰ�豸δ�ṩ�����⴫����' end
 local power=self.device:getPowerDevice()
 if not Curve.finite(power.fl_min) or not Curve.finite(power.fl_max) or power.fl_max<=power.fl_min then return false,'�޷���ȡ�豸ǰ�ⷶΧ' end
 if call(self.device,'isKindle') then
  -- Kindle Powerd requires its LIPC handle for correctly scaled writes.
  if not power.lipc_handle then return false,'KOReader ��ǰ����ƽӿ�δ����' end
  self.backend='lipc'
  local lux,why=self:read();if lux==nil then return false,why end
  return true,nil,lux
 end
 local ok,lfs=pcall(require,'libs/libkoreader-lfs')
 if ok then
  local listed,entries=pcall(function()
   local paths={}
   for name in lfs.dir('/sys/bus/iio/devices') do
    if name:match('^iio:device%d+$') then paths[#paths+1]='/sys/bus/iio/devices/'..name..'/in_illuminance_input' end
   end
   table.sort(paths);return paths
  end)
  if listed then for _,path in ipairs(entries) do
   -- Only the standard processed illuminance ABI is accepted, never *_raw.
   local lux=self:readFile(path)
   if Curve.lux(lux) then self.path=path;self.backend='iio';return true,nil,lux end
  end end
 end
 return false,'δ�ҵ��ɶ�ȡ Lux �Ļ�����ӿ�'
end
return Sensor
