local count,failed,checks=0,0,{}
local function test(name,fn) local ok,why=pcall(fn);count=count+1;if not ok then failed=failed+1 end;checks[#checks+1]={name=name,passed=ok,error=not ok and tostring(why) or nil} end
local Light=require('einkfrontend/autolight')
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

test('enable immediately reads the environment and starts applying its target',function() local f,m=fixture();assert(m:setEnabled(true));assert(m.last_sample==0 and m.desired==11 and f.level==17 and f.writes[1].time==0) end)
test('periodic sensor checks occur at exactly sixty-second intervals, including during ramps',function() local f,m=fixture();local reads=0;f.sensor.probe=function() reads=reads+1;return true,nil,f.lux end;f.sensor.read=function() reads=reads+1;return f.lux end;assert(m:setEnabled(true));assert(reads==1);f:advance(59);assert(reads==1);f:advance(1);assert(reads==2 and m.last_sample==60);f:advance(60);assert(reads==3 and m.last_sample==120) end)
test('new ambient target is applied at the next minute check without multi-minute confirmation',function() local f,m=fixture();assert(m:setEnabled(true));f:advance(20);assert(f.level==11);f.lux=0;f:advance(39);assert(f.level==11);f:advance(1);assert(f.level==12 and m.desired==18);f:advance(12);assert(f.level==18) end)
test('manual off remains locked even when explicitly refreshing the environment',function() local f,m=fixture();assert(m:setEnabled(true));f.power:setIntensity(0);m:manual(0,false);local n=#f.writes;m:checkNow();f:advance(180);assert(#f.writes==n and m.config.off_locked) end)
test('automatic off can relight on a later dark sample',function() local f,m=fixture();f.lux=10000;assert(m:setEnabled(true));f:advance(40);assert(f.level==0 and not m.config.off_locked);f.lux=0;f:advance(20);assert(f.level==1 and not m.config.off_locked);f:advance(34);assert(f.level==18) end)
test('zero anchor cannot silently enable an all-off curve',function() local f,m=fixture({schema=1,device_key='Mock:0:25',anchor=0});assert(not m:setEnabled(true));assert(not m.config.enabled) end)
test('persisted all-off calibration starts disabled',function() local f,m=fixture({schema=1,device_key='Mock:0:25',enabled=true,anchor=0});assert(not m.config.enabled and next(f.tasks)==nil) end)
test('zero dark calibration restores original light and leaves anchor intact',function() local f,m=fixture();assert(m:setEnabled(true));local before=f.level;local token=assert(m:beginCalibration());assert(m:preview(token,0));assert(not m:finishCalibration(token,true));assert(f.level==before and m:anchor()==18) end)
test('controller health distinguishes native idle and stopped jobs',function() local f,m=fixture();assert(m:setEnabled(true));m.state='idle';assert(m:statusText()~='�ѿ���');m.running=false;assert(m:statusText()~='�ѿ���') end)
test('diagnostics distinguish probe readings from actual automatic samples and writes',function() local f,m=fixture();m:probe();assert(m:diagnosticText():find('��δ�Զ�����',1,true));assert(m:setEnabled(true));assert(m.last_sample==0 and m.last_write==0);assert(m:diagnosticText():find('Ŀ�����ȣ�11',1,true)) end)
test('interrupted ramp restarts at a minute check after native dimming restores brightness',function() local f,m=fixture();local app={plugin={ui={autodim={}}}};m.owners[app]=true;assert(m:setEnabled(true));assert(f.level==17);app.plugin.ui.autodim.autodim_save_fl=17;f.level=6;f:advance(3);assert(m.target==nil);f.level=17;app.plugin.ui.autodim.autodim_save_fl=nil;f:advance(57);assert(f.level==16);f:advance(10);assert(f.level==11 and not m.pause_until) end)
test('explicit refresh performs a guarded sample and schedules the next one sixty seconds later',function() local f,m=fixture();assert(m:setEnabled(true));f:advance(20);f.lux=0;m:checkNow();assert(m.last_sample==20 and m.desired==18);assert(f.tasks[m.sample_job]==80) end)
local out={};for _,c in ipairs(checks) do out[#out+1]='{"name":'..string.format('%q',c.name)..',"passed":'..tostring(c.passed)..',"error":'..(c.error and string.format('%q',c.error) or 'null')..'}' end
AUDIT_RESULT='{"total":'..count..',"failed":'..failed..',"checks":['..table.concat(out,',')..']}'
