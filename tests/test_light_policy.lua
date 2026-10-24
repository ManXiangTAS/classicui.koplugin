-- Hardware-independent policy tests. Run from the project root with LuaJIT.
package.path='einkfrontend.koplugin/?.lua;'..package.path
local C=require('einkfrontend/lightcurve');local Light=require('einkfrontend/autolight')
local count=0
local function test(name,fn) fn();count=count+1;print('PASS '..name) end
local function fixture(saved)
 local f={now=0,lux=100,level=18,writes={},tasks={},settings={}}
 f.settings.readSetting=function() return saved end
 f.settings.saveSetting=function(_,key,value) f.saved=value end
 f.settings.flush=function() return not f.save_fail end
 f.ui={scheduleIn=function(_,seconds,job) f.tasks[job]=f.now+seconds end,unschedule=function(_,job) f.tasks[job]=nil end}
 f.power={fl_min=0,fl_max=25,fl_intensity=18,is_fl_on=true}
 function f.power:frontlightIntensityHW() return f.level end
 function f.power:frontlightIntensity() return self.fl_intensity end
 function f.power:updateResumeFrontlightState() self.fl_was_on=self.is_fl_on end
 function f.power:setIntensity(value)
  assert(not f.write_fail,'hardware failure');f.level=value;self.fl_intensity=value;self.is_fl_on=value>0
  f.writes[#f.writes+1]={value=value,time=f.now};f.manager:externalChanged()
 end
 f.device={model='Mock',screen={night_mode=false},getPowerDevice=function() return f.power end,isKindle=function() return true end}
 f.sensor={backend='lipc',probe=function() if f.sensor_fail then return false,'sensor failure' end;return true,nil,f.lux end,
  read=function() if f.sensor_fail then return nil,'sensor failure' end;return f.lux end}
 f.manager=Light.new(f.settings,f.device,f.ui,f.sensor,function() return f.now end)
 f.manager:start()
 function f:advance(seconds)
  local until_time=self.now+seconds;local rounds=0
  while true do
   local first,when
   for job,time in pairs(self.tasks) do if not when or time<when then first,when=job,time end end
   if not first or when>until_time then break end
   self.now=when;self.tasks[first]=nil;first();rounds=rounds+1;assert(rounds<5000,'timer loop')
  end
  self.now=until_time
 end
 return f,f.manager
end
test('Normalized curve preserves endpoints, removes dark cutoff jumps and stays monotone',function()
 assert(C.base(0,18,0,25)==18 and C.base(5,18,0,25)==18)
 assert(math.abs(C.base(5.001,18,0,25)-18)<.01)
 local last=26;for lux=0,20000 do local t=C.target(lux,25,0,25,{});assert(t<=last and t>=0);last=t end
 assert(C.target(0,18,2,25,{})==18 and C.target(10000,18,2,25,{})==2)
end)

test('Invalid sensor readings never become darkness',function()
 for _,lux in ipairs({-1,0/0,math.huge,-math.huge,'0',false,200001}) do assert(C.target(lux,18,0,25,{})==nil) end
 assert(C.target(nil,18,0,25,{})==nil)
end)
test('Learning exactly recalls a preference and leaves distant lighting alone',function()
 local m=assert(C.remember({},100,20,0,25))
 assert(C.target(100,18,0,25,m)==20)
 assert(C.target(0,18,0,25,m)==18 and C.target(10000,18,0,25,m)==0)
 m=C.remember(m,110,21,0,25);assert(#m==1 and C.target(110,18,0,25,m)==21)
end)
test('Memory stays bounded, sanitizes corruption, and never learns off as a preference',function()
 local m={};for i=1,30 do m=C.remember(m,math.exp(i*.4)-1,10,0,25) or m end
 assert(#m<=12 and C.remember(m,0,0,0,25)==nil)
 assert(#C.clean({false,{lux=-1,level=2},{lux=1,level=26},{lux=1,level=2}},0,25)==1)
end)
test('Disabled starts and capability probes perform no writes and schedule no work',function()
 local f,m=fixture();assert(not m.config.enabled and next(f.tasks)==nil)
 m:probe();f:advance(3600);assert(#f.writes==0 and next(f.tasks)==nil)
end)
test('A different device or range never inherits activation and calibration',function()
 local f,m=fixture({schema=1,device_key='Mock:0:24',enabled=true,anchor=24,memories={{lux=100,level=24}}})
 assert(not m.config.enabled and not m.config.anchor and #m.config.memories==0 and next(f.tasks)==nil)
end)
test('Activation uses current native brightness rather than a fixed dark anchor',function()
 local f,m=fixture();f.level=7;assert(m:setEnabled(true));assert(m.config.anchor==7 and f.saved.anchor==7 and #f.writes==1 and f.level==6)
end)
test('Activation immediately starts a one-step-per-two-seconds ramp',function()
 local f,m=fixture();assert(m:setEnabled(true));assert(#f.writes==1 and f.writes[1].time==0)
 f:advance(12);assert(f.level==11 and #f.writes==7)
 for i=2,#f.writes do assert(math.abs(f.writes[i].value-f.writes[i-1].value)==1 and f.writes[i].time-f.writes[i-1].time>=2) end
end)
test('An isolated sensor occlusion does not change brightness',function()
 local f,m=fixture();assert(m:setEnabled(true));f:advance(70);local before=#f.writes
 f.lux=0;f:advance(5);f.lux=100;f:advance(20);assert(#f.writes==before)
end)
test('Explicit manual adjustment settles before learning and remains while the environment is unchanged',function()
 local f,m=fixture();assert(m:setEnabled(true));f:advance(70)
 f.power:setIntensity(20);m:manual(20,true);f:advance(2);assert(#m.config.memories==0)
 f:advance(1);assert(#m.config.memories==1 and m.config.memories[1].level==20)
 local before=#f.writes;f:advance(890);assert(#f.writes==before and f.level==20)
 assert(m:resumeAuto());f:advance(80);assert(f.level==20)
end)
test('Continuous dragging commits only the final settled adjustment',function()
 local f,m=fixture();assert(m:setEnabled(true))
 for value=19,22 do f.power:setIntensity(value);m:manual(value,true);f:advance(1) end
 f:advance(3);assert(#m.config.memories==1 and m.config.memories[1].level==22)
end)
test('A changing environment or disabled learning prevents accidental memories',function()
 local f,m=fixture();assert(m:setEnabled(true));f.power:setIntensity(20);m:manual(20,true);f.lux=0;f:advance(3);assert(#m.config.memories==0)
 assert(m:setLearning(false));f.power:setIntensity(21);m:manual(21,true);f:advance(4);assert(#m.config.memories==0)
end)
test('External hardware changes pause automatic control and are not learned',function()
 local f,m=fixture();assert(m:setEnabled(true));f:advance(70);f.level=21;m:externalChanged()
 local before=#f.writes;f:advance(100);assert(#f.writes==before and f.level==21 and #m.config.memories==0)
end)
test('Manual off persists across restart and never relights until explicit resume',function()
 local f,m=fixture();assert(m:setEnabled(true));f.power:setIntensity(0);m:manual(0,false)
 f.lux=0;f:advance(3600);assert(f.level==0 and m.config.off_locked and #m.config.memories==0)
 local g,n=fixture(f.saved);g.level=0;g:advance(1000);assert(g.level==0 and #g.writes==0)
 assert(n:resumeAuto());g:advance(80);assert(g.level>0)
end)
test('External off also updates the KOReader resume state',function()
 local f,m=fixture();assert(m:setEnabled(true));f.level=0;m:externalChanged()
 assert(m.config.off_locked and f.power.fl_was_on==false)
end)
test('Sensor failure holds brightness and recovers at the next minute sample',function()
 local f,m=fixture();assert(m:setEnabled(true));f:advance(20);assert(f.level==11)
 f.sensor_fail=true;f.lux=0;f:advance(60);local before=#f.writes;f:advance(120);assert(#f.writes==before and f.level==11)
 f.sensor_fail=false;f:advance(80);assert(f.level==18)
end)

test('Suspend and final detach remove every pending sampler, transition and learning job',function()
 local f,m=fixture();assert(m:setEnabled(true));f:advance(16);m:suspend();assert(next(f.tasks)==nil)
 local before=#f.writes;f:advance(3600);m:sample();m:ramp();assert(#f.writes==before and next(f.tasks)==nil)
 m:resume();m:resume();assert(f.tasks[m.resume_job]~=nil and f.tasks[m.sample_job]==nil)
 m:detach({});assert(next(f.tasks)==nil);m:sample();assert(next(f.tasks)==nil)
end)
test('AutoDim ownership is respected and never added to preference memory',function()
 local f,m=fixture();local app={plugin={ui={autodim={autodim_save_fl=18}}}};m.owners[app]=true
 assert(m:setEnabled(true));f:advance(100);assert(#f.writes==0 and #m.config.memories==0)
end)
test('Calibration cancel restores brightness and does not learn or enable automation',function()
 local f,m=fixture();local t=assert(m:beginCalibration());assert(m:preview(t,4) and f.level==4)
 assert(not m:finishCalibration(t,false));assert(f.level==18 and not m.config.enabled and #m.config.memories==0)
 local u=m:beginCalibration();m:preview(u,7);assert(m:finishCalibration(u,true));assert(m.config.anchor==7 and not m.config.enabled)
end)
test('Storage and device write failures stop automation instead of disabling the frontend',function()
 local f,m=fixture();f.save_fail=true;assert(not m:setEnabled(true) and next(f.tasks)==nil and #f.writes==0)
 local g,n=fixture();g.write_fail=true;assert(not n:setEnabled(true));assert(n.fault and next(g.tasks)==nil)
end)
test('Light and dark mode learn independent preferences for identical ambient light',function()
 local f,m=fixture();assert(m:setEnabled(true));f.power:setIntensity(20);m:manual(20,true);f:advance(3)
 f.device.screen.night_mode=true;m:syncMode()
 f.power:setIntensity(7);m:manual(7,true);f:advance(3)
 assert(m:profile().memories[1].level==7 and m.config.memories[1].level==20)
 assert(m:resumeAuto());f:advance(80);assert(f.level==7)
 f.device.screen.night_mode=false;m:syncMode();f:advance(80);assert(f.level==20)
end)
test('Mode-specific dark calibration persists without overwriting the other mode',function()
 local f,m=fixture();assert(m:setEnabled(true));f.device.screen.night_mode=true;m:syncMode()
 local token=m:beginCalibration();m:preview(token,9);assert(m:finishCalibration(token,true))
 assert(m:anchor()==9 and m.config.anchor==18)
 local g,n=fixture(f.saved);g.device.screen.night_mode=true;n:syncMode();assert(n:anchor()==9)
 g.device.screen.night_mode=false;n:syncMode();assert(n:anchor()==18)
end)
test('Mode switching discards unsettled learning, preserves off lock and deduplicates timers',function()
 local f,m=fixture();assert(m:setEnabled(true));f.power:setIntensity(20);m:manual(20,true)
 f.device.screen.night_mode=true;f:advance(3);assert(#m.config.memories==0 and #m.config.dark.memories==0)
 f.power:setIntensity(0);m:manual(0,false)
 for i=1,10 do f.device.screen.night_mode=not f.device.screen.night_mode;m:syncMode() end
 local jobs=0;for _ in pairs(f.tasks) do jobs=jobs+1 end
 assert(jobs==1 and m.config.off_locked);f:advance(1000);assert(f.level==0)
end)
test('Clearing current mode memory keeps calibration and the other mode intact',function()
 local f,m=fixture();assert(m:setEnabled(true));assert(m:change('memories',{{lux=100,level=20}}))
 f.device.screen.night_mode=true;m:syncMode();assert(m:changeProfile('memories',{{lux=100,level=7}}))
 assert(m:clearMemory());assert(#m.config.dark.memories==0 and #m.config.memories==1 and m:anchor()==18)
end)
test('Old settings retain light-mode preferences and start dark mode with separate memory',function()
 local f,m=fixture({schema=1,device_key='Mock:0:25',enabled=true,anchor=18,memories={{lux=100,level=20}}})
 assert(m.config.memories[1].level==20 and #m.config.dark.memories==0)
 f.device.screen.night_mode=true;m:syncMode();assert(m:anchor()==18)
end)
test('Restore-last-level works in manual mode without enabling or training automation',function()
 local f,m=fixture();m:manual(12,true);m:manual(0,false);assert(m:restoreLevel()==12)
 assert(not m.config.enabled and next(f.tasks)==nil and #m.config.memories==0)
end)
test('Kindle sensor probing is capability based across model names and native ranges',function()
 local Sensor=require('einkfrontend/lightsensor');local old=package.loaded.liblipclua
 package.loaded.liblipclua={init=function() return {close=function() end,
  get_int_property=function(_,_,key) return key=='alsLux' and 45 or 0 end,
  get_string_property=function() return 'active' end} end}
 for _,model in ipairs({'KindleVoyage','KindleOasis2','KindleOasis3','KindlePaperWhite5SE','KindleScribe','KindleColorSoft','KindleFutureSensor'}) do
  for _,high in ipairs({15,24,25,100}) do
   local f=fixture();f.device.model=model;f.power.fl_max=high;f.power.lipc_handle={}
   f.device.hasFrontlight=function() return true end;f.device.hasLightSensor=function() return true end
   local sensor=Sensor.new(f.device);assert(sensor:probe());assert(sensor:read()==45 and sensor.backend=='lipc')
  end
 end
 package.loaded.liblipclua=old
end)
test('Warmth capability alone never opens Lux automation on a Kindle without a sensor',function()
 local Sensor=require('einkfrontend/lightsensor')
 for _,warm in ipairs({false,true}) do
  local f=fixture();f.device.model=warm and 'KindlePaperWhite5' or 'KindleBasic4'
  f.device.hasFrontlight=function() return true end;f.device.hasLightSensor=function() return false end
  f.device.hasNaturalLight=function() return warm end
  local sensor=Sensor.new(f.device);local ok,why=sensor:probe();assert(not ok and why:find('传感器',1,true))
  local m=Light.new(f.settings,f.device,f.ui,sensor,function() return f.now end);m:start();assert(not m:setEnabled(true))
  assert(next(f.tasks)==nil and #f.writes==0)
 end
end)
test('Kindles without frontlight expose a reason and schedule no lighting jobs',function()
 local Sensor=require('einkfrontend/lightsensor');local f=fixture();f.device.model='KindleDXG'
 f.device.hasFrontlight=function() return false end;f.device.hasLightSensor=function() return false end
 local sensor=Sensor.new(f.device);local ok,why=sensor:probe();assert(not ok and why:find('前光',1,true))
 local m=Light.new(f.settings,f.device,f.ui,sensor,function() return f.now end);m:start();assert(not m:setEnabled(true))
 assert(next(f.tasks)==nil and #f.writes==0)
end)
test('Read-only Kindle backend validates native ownership and closes handles on errors',function()
 local Sensor=require('einkfrontend/lightsensor');local f=fixture();local native=0;local lux=20;local closed=0
 f.device.hasFrontlight=function() return true end;f.device.hasLightSensor=function() return true end;f.power.lipc_handle={}
 local old=package.loaded.liblipclua
 package.loaded.liblipclua={init=function() return {close=function() closed=closed+1 end,
  get_int_property=function(_,_,property) if property=='alsLux' then return lux end;return native end,
  get_string_property=function() return 'active' end} end}
 local s=Sensor.new(f.device);assert(s:probe());assert(s:read()==20 and s:read()==20)
 native=1;assert(not s:probe());native=nil;assert(not s:probe());native=0;lux=-1;assert(not s:probe())
 assert(closed==6);package.loaded.liblipclua=old
end)
print('COMPLETE '..count..' adaptive frontlight checks')
