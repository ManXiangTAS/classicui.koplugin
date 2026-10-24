-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local C=require('einkfrontend/lightcurve')
local Light={};Light.__index=Light
local KEY='eink_autolight'
local SAMPLE_SECONDS=60
local function validLevel(v,lo,hi) return C.finite(v) and v%1==0 and v>=lo and v<=hi end
local function validThreshold(v) return C.finite(v) and v%1==0 and v>=100 and v<=200000 end
local function clone(v)
 if type(v)~='table' then return v end
 local t={};for k,x in pairs(v) do t[k]=clone(x) end;return t
end
function Light.new(settings,device,ui,sensor,now)
 local power=device:getPowerDevice();local lo,hi=power.fl_min,power.fl_max
 if not C.finite(lo) or not C.finite(hi) or hi<=lo then lo,hi=0,1 end
 local key=tostring(device.model or 'unknown')..':'..lo..':'..hi
 local saved=settings:readSetting(KEY)
 if type(saved)~='table' or saved.schema~=1 or saved.device_key~=key then saved={} end
 local anchor=C.finite(saved.anchor) and saved.anchor%1==0 and saved.anchor>=lo and saved.anchor<=hi and saved.anchor or nil
 local dark=type(saved.dark)=='table' and saved.dark or {}
 local dark_anchor=C.finite(dark.anchor) and dark.anchor%1==0 and dark.anchor>=lo and dark.anchor<=hi and dark.anchor or nil
 local self=setmetatable({settings=settings,device=device,power=power,ui=ui,sensor=sensor,lo=lo,hi=hi,
  config={schema=1,device_key=key,enabled=saved.enabled==true and anchor~=nil and anchor>lo,anchor=anchor,
   daylight=validLevel(saved.daylight,lo,anchor or hi) and saved.daylight or lo,
   threshold=validThreshold(saved.threshold) and saved.threshold or C.default_threshold,
   learning=saved.learning~=false,memories=C.clean(saved.memories,lo,hi),off_locked=saved.off_locked==true,
   dark={anchor=dark_anchor,daylight=validLevel(dark.daylight,lo,dark_anchor or anchor or hi) and dark.daylight or nil,
    threshold=validThreshold(dark.threshold) and dark.threshold or nil,memories=C.clean(dark.memories,lo,hi)}},
  owners=setmetatable({},{__mode='k'}),samples={},state='disabled',now=now,
  current_dark=device.screen and device.screen.night_mode==true or false},Light)
 self:rememberLevel(power.fl_intensity)
 local function job(method)
  return function()
   local ok,why=pcall(method,self)
   if not ok then
    self.failure_detail=tostring(why)
    self.error='自动前光暂不可用，已保留手动控制';self.state='error';self.fault=true;self:cancel()
   end
  end
 end
 self.sample_job=job(Light.sample)
 self.ramp_job=job(Light.ramp)
 self.learn_job=job(Light.commitLearning)
 self.resume_job=job(Light.finishResume)
 return self
end
function Light:save(config)
 local old=clone(self.config)
 local ok,result=pcall(function() self.settings:saveSetting(KEY,clone(config));return self.settings:flush() end)
 if not ok or result==false then
  pcall(self.settings.saveSetting,self.settings,KEY,old);self.error='无法保存自动前光设置';self.fault=true
  self:cancel();return false,self.error
 end
 self.config=clone(config);return true
end
function Light:change(key,value)
 local c=clone(self.config);c[key]=value;return self:save(c)
end
function Light:isDark() return self.device.screen and self.device.screen.night_mode==true or false end
function Light:profile() return self:isDark() and self.config.dark or self.config end
function Light:anchor() return self:profile().anchor or self.config.anchor end
function Light:curveOptions()
 local profile=self:profile();return {daylight=math.min(self:anchor() or self.hi,profile.daylight or self.config.daylight or self.lo),
  threshold=profile.threshold or self.config.threshold or C.default_threshold}
end
function Light:calculate(lux,base_only)
 return C.target(lux,self:anchor(),self.lo,self.hi,base_only and {} or self:profile().memories,self:curveOptions())
end
function Light:setCurve(key,value)
 if key=='daylight' then
  if not validLevel(value,self.lo,self:anchor() or self.hi) then return false,'请输入 0 到暗处亮度之间的整数' end
 elseif key=='threshold' then
  if not validThreshold(value) then return false,'请输入 100 到 200000 之间的整数照度' end
 else return false,'不支持的调光设置' end
 local config=clone(self.config);local profile=self:isDark() and config.dark or config
 profile[key]=value
 local threshold=profile.threshold or config.threshold
 for i=#profile.memories,1,-1 do if profile.memories[i].lux>=threshold then table.remove(profile.memories,i) end end
 local ok,why=self:save(config);if not ok then return false,why end
 self:cancel();self.manual_hold=nil
 if self.config.enabled then self:sample() end
 if self.fault then return false,self.error end
 return true
end
function Light:changeProfile(key,value)
 local c=clone(self.config);local profile=self:isDark() and c.dark or c
 profile[key]=value;return self:save(c)
end
function Light:syncMode()
 local dark=self:isDark();if dark==self.current_dark then return false end
 if self.calibration then self:finishCalibration(self.calibration,false) end
 self.current_dark=dark;self:cancel();self.samples={};self.manual_hold=nil
 if self.config.enabled then self.state='settling';self:queue(1) end
 return true
end
function Light:rememberLevel(level)
 if C.finite(level) and level%1==0 and level>self.lo and level<=self.hi then self.last_level=level end
end
function Light:refreshControls()
 for app in pairs(self.owners) do if app.controls and self.ui.setDirty then self.ui:setDirty(app.controls,'ui') end end
end
function Light:restoreLevel()
 return self.last_level or (C.finite(self.power.fl_intensity) and self.power.fl_intensity>self.lo and math.min(self.hi,self.power.fl_intensity)) or math.min(self.hi,self.lo+1)
end
function Light:cancel()
 self.ui:unschedule(self.sample_job);self.ui:unschedule(self.ramp_job);self.ui:unschedule(self.learn_job);self.ui:unschedule(self.resume_job)
 self.resuming=nil;self.pending_learning=nil;self.target=nil;self.candidate=nil;self.confirmations=0
end
function Light:queue(seconds)
 self.ui:unschedule(self.sample_job)
 if self.running and not self.suspended and self.config.enabled and not self.fault then self.ui:scheduleIn(seconds,self.sample_job) end
end
function Light:actual()
 local ok,value=pcall(function()
  if self.device:isKindle() then return self.power:frontlightIntensityHW() end
  return self.power:frontlightIntensity()
 end)
 if not ok or not C.finite(value) or value%1~=0 or value<self.lo or value>self.hi then return nil end
 -- Kindle's public getter is cached. Keep its cache consistent with a live read.
 if self.device:isKindle() then
  self.power.is_fl_on=value>self.lo
  if value>self.lo then self.power.fl_intensity=value end
 end
 return value
end
function Light:probe()
 local ok,supported,why,lux=pcall(self.sensor.probe,self.sensor)
 self.available=ok and supported==true
 self.reason=ok and why or '光感接口检查失败'
 if self.available then self.lux=lux;self.last_read=self.now();self.reason=nil end
 return self.available,self.reason
end
function Light:read()
 local ok,lux,why=pcall(self.sensor.read,self.sensor)
 if not ok or not C.lux(lux) then
  self.available=false;self.error=ok and why or '光感读取失败';self.state='error'
  self.ui:unschedule(self.ramp_job);self.target=nil;self.samples={};self.candidate=nil;self.confirmations=0
  return nil
 end
 self.available=true;self.lux=lux;self.last_read=self.now();self.error=nil
 return lux
end
function Light:hostOwnsFrontlight()
 for app in pairs(self.owners) do
  local host=app.plugin and app.plugin.ui
  if host and host.autodim and host.autodim.autodim_save_fl~=nil then self.state='idle';return true end
  if host and host.autofrontlight and host.autofrontlight.enabled then self.error='请先停用其他自动前光插件';self.state='error';return true end
 end
 return false
end
function Light:externalChanged()
 if self.writing or not self.running or self.suspended or not self.config.enabled or self.calibration then return end
 self:syncMode()
 if self:hostOwnsFrontlight() or self.resuming then return end
 local actual=self:actual()
 if actual~=nil and self.expected~=nil and actual~=self.expected then self:manual(actual,false) end
end
function Light:manual(level,learn)
 self:rememberLevel(level)
 if not self.config.enabled or self.writing or self.calibration then return end
 self:syncMode()
 self.ui:unschedule(self.ramp_job);self.ui:unschedule(self.learn_job)
 self.pending_learning=nil;self.target=nil;self.expected=level
 self.state=level<=self.lo and 'off_locked' or 'manual'
 self.manual_hold=nil
 pcall(self.power.updateResumeFrontlightState,self.power)
 if self.config.off_locked~=(level<=self.lo) then
  if not self:change('off_locked',level<=self.lo) then return end
 end
 if level>self.lo then
  local lux=not self.suspended and self:read() or nil
  -- Compare the base curve so learning this adjustment cannot release it.
  self.manual_hold={base_target=lux and self:calculate(lux,true) or nil,dark=self:isDark()}
  if lux and learn and self.config.learning then
   self.pending_learning={lux=lux,level=level,dark=self:isDark()};self.ui:scheduleIn(3,self.learn_job)
  end
 end
 self:queue(SAMPLE_SECONDS)
end
function Light:commitLearning()
 local p=self.pending_learning;self.pending_learning=nil
 if not p or not self.running or self.suspended or not self.config.enabled or not self.config.learning or self.calibration then return end
 if p.dark~=self:isDark() then self:syncMode();return end
 local lux=self:read()
 if not lux or self:actual()~=p.level or math.abs(math.log(1+lux)-math.log(1+p.lux))>.7 then return end
 local memories=C.remember(self:profile().memories,p.lux,p.level,self.lo,self.hi)
 if memories then self:changeProfile('memories',memories) end
end
function Light:guard()
 if not self.running or self.suspended or self.fault or not self.config.enabled or self.calibration then return false end
 if self:syncMode() then return false end
 -- Native dimming and other controllers must not be learned as manual input.
 if self:hostOwnsFrontlight() then return false end
 local actual=self:actual()
 if actual==nil then self.error='无法读取实际前光';self.state='error';return false end
 if self.resuming then self.expected=actual
 elseif self.expected~=nil and actual~=self.expected then self:manual(actual,false);return false end
 self.expected=actual
 if self.config.off_locked then self.state='off_locked';return false end
 return true,actual
end
function Light:checkNow()
 -- A settings probe alone only reads Lux. Run the same guarded controller path.
 local ok=self:probe()
 if self.running and not self.suspended and not self.fault and self.config.enabled then self:sample(ok and self.lux or nil) end
end
function Light:sample(lux)
 self.ui:unschedule(self.sample_job)
 if not self.running or self.suspended or self.fault or not self.config.enabled then return end
 if not self:guard() then self:queue(SAMPLE_SECONDS);return end
 if lux==nil then lux=self:read() end
 if not lux then self:queue(SAMPLE_SECONDS);return end
 self.last_sample=self.now();self.filtered=lux
 local target=self:calculate(lux)
 if self.manual_hold then
  local base=self:calculate(lux,true)
  self.manual_hold.base_target=self.manual_hold.base_target or base
  if base==self.manual_hold.base_target then self.desired=target;self.state='manual';self:queue(SAMPLE_SECONDS);return end
  self.manual_hold=nil
 end
 self.desired=target;self.state='running'
 if target~=self.expected and self.target~=target then
  self.target=target
  self.ui:unschedule(self.ramp_job);self:ramp()
 elseif target==self.expected then
  self.ui:unschedule(self.ramp_job);self.target=nil
 end
 self:queue(SAMPLE_SECONDS)
end
function Light:write(value)
 self.writing=true
 local ok,why=pcall(function()
  self.power:setIntensity(value)
  assert(self:actual()==value,'设备未接受前光档位')
  self.power:updateResumeFrontlightState()
 end)
 self.writing=false
 if not ok then self.failure_detail=tostring(why);self.error='前光调整失败，已保留手动控制';self.state='error';self.target=nil;self.fault=true;self:cancel();return false,why end
 self.last_write=self.now();self.expected=value;self:rememberLevel(value);self:refreshControls();return true
end
function Light:ramp()
 self.ui:unschedule(self.ramp_job)
 local allowed,current=self:guard()
 if not allowed then self.target=nil;return end
 if self.target==nil then return end
 -- Keep checking manual/native ownership during ramps; Lux is sampled every 60s.
 if current==self.target then self.target=nil;return end
 local value=current+(self.target>current and 1 or -1)
 if self:write(value) and value~=self.target then self.ui:scheduleIn(2,self.ramp_job) else self.target=nil end
end
function Light:setEnabled(enabled)
 self:syncMode()
 if not enabled then
  local ok,why=self:change('enabled',false);if not ok then return false,why end
  self:cancel();self.state='disabled';return true
 end
 if not self:probe() then return false,self.reason end
 local actual=self:actual();if actual==nil then return false,'无法读取实际前光' end
 local anchor=self:anchor() or actual
 if anchor<=self.lo then return false,'请先将暗处亮度设为非零档位，再开启自动调光' end
 local config=clone(self.config);config.enabled=true;config.off_locked=false;config.anchor=config.anchor or actual
 if not self:save(config) then return false,self.error end
 self.fault=nil;self.error=nil;self.failure_detail=nil;self.manual_hold=nil;self.samples={};self.desired=nil;self.expected=actual;self:cancel();self.state='running';self:sample(self.lux)
 if self.fault then return false,self.error end
 return true
end
function Light:resumeAuto() return self:setEnabled(true) end
function Light:setLearning(enabled)
 self.ui:unschedule(self.learn_job);self.pending_learning=nil
 return self:change('learning',enabled==true)
end
function Light:clearMemory() return self:changeProfile('memories',{}) end
function Light:beginCalibration(kind)
 self:syncMode()
 local actual=self:actual();if actual==nil then return nil,'无法读取实际前光' end
 self:cancel();local upper=kind=='daylight' and (self:anchor() or self.hi) or self.hi
 local token={original=actual,value=actual,dark=self:isDark(),kind=kind,low=self.lo,high=upper}
 if kind=='daylight' then token.value=self:curveOptions().daylight end
 self.calibration=token;return token
end
function Light:preview(token,value)
 if self.calibration~=token or self.suspended or not C.finite(value) or value%1~=0 or value<token.low or value>token.high then return false end
 if self:write(value) then token.value=value;return true end
 return false
end
function Light:finishCalibration(token,accept)
 if self.calibration~=token then return end
 if token.dark~=self:isDark() then accept=false end
 if accept and token.kind~='daylight' and token.value<=self.lo then self.error='暗处亮度需要大于 0';accept=false end
 if accept then
  local c=clone(self.config);local profile=token.dark and c.dark or c
  if token.kind=='daylight' then
   profile.daylight=token.value
   local threshold=profile.threshold or c.threshold
   for i=#profile.memories,1,-1 do if profile.memories[i].lux>=threshold then table.remove(profile.memories,i) end end
  else
  profile.anchor=token.value
  if profile.daylight then profile.daylight=math.min(profile.daylight,token.value) end
  -- First calibration also provides a conservative fallback for the other mode.
  c.anchor=c.anchor or token.value
  -- Explicit dark recalibration replaces only dark memories.
  for i=#profile.memories,1,-1 do if profile.memories[i].lux<=5 then table.remove(profile.memories,i) end end
  end
  if not self:save(c) then accept=false end
 end
 if not accept then self:write(token.original) end
 self.calibration=nil;self.samples={};if accept then self.manual_hold=nil end;self:queue(1)
 return accept
end
function Light:finishManual(token)
 if self.calibration~=token then return false end
 local value=token.value;self.calibration=nil;self.samples={}
 self:manual(value,true);return true
end
function Light:start()
 if self.running then return end
 self.running=true;self.suspended=false;self.samples={}
 if self.config.enabled then
  self:probe()
  local actual=self:actual()
  -- A cold start must not silently undo a manual off that occurred outside KOReader.
  if self.expected==nil and actual==self.lo then self.config.off_locked=true end
  self.expected=actual;self:queue(5)
 end
end
function Light:suspend()
 if self.suspended then return end
 if self.calibration then self:finishCalibration(self.calibration,false) end
 self.suspended=true;self:cancel();self.samples={};self.state='suspended'
end
function Light:resume()
 if not self.running then return end
 self:syncMode();self.suspended=false;self:cancel();self.samples={}
 if not self.config.enabled or self.fault then return end
 -- A resume is system restoration, not a new manual input. Recheck after 1s.
 self.resuming=true;self:sample()
 if not self.fault then
  self.ui:unschedule(self.sample_job);self.ui:scheduleIn(1,self.resume_job)
 end
end
function Light:finishResume()
 if not self.running or self.suspended or not self.config.enabled or self.fault then self.resuming=nil;return end
 self:sample();self.resuming=nil
end
function Light:detach(app)
 self.owners[app]=nil
 if next(self.owners)==nil then
  if self.calibration then self:finishCalibration(self.calibration,false) end
  self.running=false;self:cancel();self.state='stopped'
 end
end
function Light:diagnosticText()
 local now=self.now()
 local age=function(t) return tostring(math.max(0,math.floor(now-t)))..' 秒前' end
 local lines={self:statusText(), '当前亮度：'..tostring(self:actual() or '不可读')..' / '..self.hi,
  '环境照度：'..tostring(self.lux or '未读取')..' lux',
  '目标亮度：'..tostring(self.desired or '尚未计算'),
  self.last_sample and ('自动采样：'..age(self.last_sample)) or '尚未自动采样',
  self.last_write and ('前光写入：'..age(self.last_write)) or '尚未写入前光'}
 if self.error or self.reason then lines[#lines+1]=tostring(self.error or self.reason) end
 if self.failure_detail then lines[#lines+1]=self.failure_detail end
 return table.concat(lines,'\n')
end
function Light:statusText()
 if not self.config.enabled then return '未开启' end
 if self.fault or self.state=='error' then return '暂不可用' end
 if not self.running then return '已停止' end
 if self.suspended then return '休眠暂停' end
 if self.calibration then return '正在校准' end
 if self.state=='idle' then return '待机调暗中' end
 if self.config.off_locked then return '已手动关灯' end
 if self.manual_hold then return '手动优先' end
 if self.state=='settling' then return '正在适应' end
 return '已开启'
end
local shared
function Light.attach(app)
 if not shared then
  local device=require('device');local time=require('ui/time')
  shared=Light.new(G_reader_settings,device,require('ui/uimanager'),require('einkfrontend/lightsensor').new(device),function() return time.to_s(time.now()) end)
 end
 shared.owners[app]=true;shared:start();return shared
end
return Light
