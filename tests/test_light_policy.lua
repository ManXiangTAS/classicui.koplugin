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
 f.device={model='Mock',getPowerDevice=function() return f.power end,isKindle=function() return true end}
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
test('Base curve follows all knots and remains bounded and monotone',function()
 for _,k in ipairs(C.knots) do assert(math.abs(C.base(k[1],18,0,25)-18*k[2])<1e-8) end
 local last=26
 for lux=0,2000 do local t=C.target(lux,25,0,25,{});assert(t<=last and t>=0);last=t end
 assert(C.target(0,18,2,25,{})==18 and C.target(500,18,2,25,{})==2)
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
 local f,m=fixture();f.level=7;assert(m:setEnabled(true));assert(m.config.anchor==7 and f.saved.anchor==7 and #f.writes==0)
end)
test('Stable light confirms twice after a three-sample filter then ramps one step per 2s',function()
 local f,m=fixture();assert(m:setEnabled(true));f:advance(45);assert(#f.writes==0)
 f:advance(20);assert(f.level==13 and #f.writes==5)
 for i=2,#f.writes do assert(math.abs(f.writes[i].value-f.writes[i-1].value)==1 and f.writes[i].time-f.writes[i-1].time>=2) end
end)
test('An isolated sensor occlusion does not change brightness',function()
 local f,m=fixture();assert(m:setEnabled(true));f:advance(70);local before=#f.writes
 f.lux=0;f:advance(15);f.lux=100;f:advance(45);assert(#f.writes==before)
end)
test('Explicit manual adjustment settles before learning and remains in control for 15 minutes',function()
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
test('Sensor failure cancels transitions, holds hardware and recovers conservatively',function()
 local f,m=fixture();assert(m:setEnabled(true));f:advance(46);assert(#f.writes==1)
 f.sensor_fail=true;f:advance(2);local before=#f.writes;f:advance(120);assert(#f.writes==before)
 f.sensor_fail=false;f:advance(150);assert(f.level==13)
end)
test('Suspend and final detach remove every pending sampler, transition and learning job',function()
 local f,m=fixture();assert(m:setEnabled(true));f:advance(46);m:suspend();assert(next(f.tasks)==nil)
 local before=#f.writes;f:advance(3600);m:sample();m:ramp();assert(#f.writes==before and next(f.tasks)==nil)
 m:resume();m:resume();local tasks=0;for _ in pairs(f.tasks) do tasks=tasks+1 end;assert(tasks==1)
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
 local g,n=fixture();assert(n:setEnabled(true));g.write_fail=true;g:advance(60);assert(n.fault and next(g.tasks)==nil)
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
