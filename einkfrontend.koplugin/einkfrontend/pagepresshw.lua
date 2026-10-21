-- Original adapter. SPDX-License-Identifier: AGPL-3.0-or-later
-- ABI references and readback caveats: docs/PagePress.md
local ffi=require('ffi');require('ffi/posix_h')
local HW={};HW.__index=HW
local GAIN='/sys/devices/system/drv26xx_haptics/drv26xx_haptics0/'
function HW.new(io) return setmetatable({io=io},HW) end
local function ioctl(path,request,value)
 local fd=ffi.C.open(path,2);if fd<0 then error('无法打开 '..path..'（权限或驱动不可用）') end
 local data=ffi.new('uint32_t[1]',value or 0)
 local ok,ret=pcall(function() return ffi.C.ioctl(fd,request,data) end)
 local errno=ffi.errno();ffi.C.close(fd)
 if not ok or ret<0 then error('PagePress 驱动操作失败（'..errno..'）') end
 return tonumber(data[0])
end
function HW:ioctl(path,request,value)
 if self.io then return self.io.ioctl(path,request,value) end
 return ioctl(path,request,value)
end
function HW:fsr(request,value)
 if self:ioctl('/dev/keypad',0x80044202)~=0 then error('PagePress 被系统锁定，请返回 Kindle 设置检查') end
 return self:ioctl('/dev/keypad',request,value)
end
local function readfile(path)
 local f=assert(io.open(path,'r'),'无法读取震动强度接口');local s=f:read('*a');f:close();return s
end
function HW:read(key)
 if key=='enabled' then
  local prev=self:fsr(0x80044219);local next_=self:fsr(0x8004421b)
  assert(prev<=1 and next_<=1,'PagePress 开关返回异常');return {prev,next_}
 elseif key=='pressure' then
  local v=self:fsr(0x80044213);assert(v>=1 and v<=65535,'按压力度返回异常');return v
 elseif key=='haptic' then
  local v=self:ioctl('/dev/haptic',0x80044307);assert(v<=1,'震动开关返回异常');return v==0
 elseif key=='gain' then
  -- GET_GAIN ioctl returns a stale cache in the published driver. Read the
  -- actual control register through its dedicated read-only id attribute.
  local reg=(self.io and self.io.readfile or readfile)(GAIN..'id'):match('ctrl reg=0x(%x+)')
  assert(reg,'震动强度接口格式不兼容');return tonumber(reg,16)%4
 end
 error('未知 PagePress 设置')
end
function HW:write(key,value)
 if key=='enabled' then
  -- Preserve separate previous/next states when restoring the stock state.
  self:fsr(0x4004421a,value[1]);self:fsr(0x4004421c,value[2])
 elseif key=='pressure' then self:fsr(0x40044214,value)
 elseif key=='haptic' then self:ioctl('/dev/haptic',0x40044306,value and 0 or 1)
 elseif key=='gain' then
  if self.io then return self.io.writefile(GAIN..'gain_setting',tostring(value)..'\n') end
  local f=assert(io.open(GAIN..'gain_setting','w'),'无法写入震动强度接口')
  local ok,why=f:write(tostring(value)..'\n');local closed,err=f:close();assert(ok and closed,why or err)
 else error('未知 PagePress 设置') end
end
return HW
