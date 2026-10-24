local count,failed,checks=0,0,{}
local function test(name,fn) local ok,why=pcall(fn);count=count+1;if not ok then failed=failed+1 end;checks[#checks+1]={name=name,passed=ok,error=not ok and tostring(why) or nil} end
local Light=require('einkfrontend/autolight');local C=require('einkfrontend/lightcurve')
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

test('custom daylight and threshold bound the whole curve',function() local o={daylight=4,threshold=1000};assert(C.target(0,18,0,25,{},o)==18);assert(C.target(1000,18,0,25,{},o)==4);assert(C.target(200000,18,0,25,{},o)==4);local prev=26;for lux=0,2000 do local n=C.target(lux,18,0,25,{},o);assert(n>=4 and n<=prev);prev=n end end)
test('dark cutoff is continuous for every valid curve boundary',function() for _,t in ipairs({100,500,10000,200000}) do for _,d in ipairs({0,4,18}) do assert(math.abs(C.base(5.001,18,0,25,{daylight=d,threshold=t})-18)<.01) end end end)
test('invalid curve settings preserve data and reject nonfinite input',function() local f,m=fixture();assert(m:setEnabled(true));for _,v in ipairs({-1,19,1.5,0/0,math.huge,'3'}) do assert(not m:setCurve('daylight',v)) end;for _,v in ipairs({0,99,200001,100.5,0/0,math.huge,'500'}) do assert(not m:setCurve('threshold',v)) end;assert(not m:setCurve('threshold',nil));assert(m:curveOptions().threshold==10000 and m:curveOptions().daylight==0) end)
test('curve settings persist independently in light and dark modes',function() local f,m=fixture();assert(m:setEnabled(true));assert(m:setCurve('daylight',3));assert(m:setCurve('threshold',1000));f.device.screen.night_mode=true;m:syncMode();assert(m:setCurve('daylight',2));assert(m:setCurve('threshold',2000));local g,n=fixture(f.saved);assert(n:curveOptions().daylight==3 and n:curveOptions().threshold==1000);g.device.screen.night_mode=true;n:syncMode();assert(n:curveOptions().daylight==2 and n:curveOptions().threshold==2000) end)
test('failed settings flush preserves the previous curve and cancels jobs',function() local f,m=fixture();assert(m:setEnabled(true));f.save_fail=true;assert(not m:setCurve('threshold',500));assert(m:curveOptions().threshold==10000 and m.fault and next(f.tasks)==nil) end)
test('manual brightness holds without a timeout while base target is unchanged',function() local f,m=fixture();assert(m:setEnabled(true));f:advance(20);f.power:setIntensity(20);m:manual(20,true);f:advance(3);local n=#f.writes;f:advance(1800);assert(#f.writes==n and f.level==20 and m.manual_hold) end)
test('changed base target releases manual brightness at a minute check',function() local f,m=fixture();assert(m:setEnabled(true));f:advance(20);f.power:setIntensity(20);m:manual(20,false);f.lux=10000;f:advance(59);assert(f.level==20);f:advance(1);assert(f.level==19 and not m.manual_hold);f:advance(38);assert(f.level==0 and not m.config.off_locked) end)
test('dark sensor noise and learning do not release a manual choice',function() local f,m=fixture();f.lux=0;assert(m:setEnabled(true));f.power:setIntensity(20);m:manual(20,true);f:advance(3);f.lux=5;f:advance(180);assert(f.level==20 and m.manual_hold and #m.config.memories==1) end)
test('sensor recovery establishes a missing manual baseline without taking over',function() local f,m=fixture();assert(m:setEnabled(true));f.sensor_fail=true;f.level=21;m:manual(21,false);assert(m.manual_hold and not m.manual_hold.base_target);f:advance(60);f.sensor_fail=false;f:advance(60);assert(f.level==21 and m.manual_hold.base_target);f.lux=0;f:advance(60);assert(f.level==20 and not m.manual_hold) end)
test('resume samples immediately, checks at one second, then resumes sixty-second intervals',function() local f,m=fixture();assert(m:setEnabled(true));f:advance(20);m:suspend();f.lux=0;local times={};f.sensor.read=function() times[#times+1]=f.now;return f.lux end;m:resume();assert(m.last_sample==20 and m.desired==18 and #times==1);f:advance(1);assert(#times==2 and times[2]==21 and not m.resuming);f:advance(59);assert(#times==2);f:advance(1);assert(#times==3 and times[3]==81) end)
test('powerd restore during resume is never learned as manual off or manual input',function() local f,m=fixture();assert(m:setEnabled(true));f:advance(20);m:suspend();f.level=0;f.lux=0;m:resume();assert(f.level==1 and m.resuming);f.power:setIntensity(11);f:advance(3);assert(not m.manual_hold and not m.config.off_locked and f.level>11 and not m.fault) end)
test('manual off survives immediate wake checks and bright-to-dark changes',function() local f,m=fixture();assert(m:setEnabled(true));f.power:setIntensity(0);m:manual(0,false);m:suspend();f.lux=0;local n=#f.writes;m:resume();f:advance(121);assert(f.level==0 and #f.writes==n and m.config.off_locked) end)
test('repeated resume deduplicates the recheck and suspend removes it',function() local f,m=fixture();assert(m:setEnabled(true));m:suspend();m:resume();m:resume();assert(f.tasks[m.resume_job]==1);m:suspend();assert(next(f.tasks)==nil and not m.resuming);f:advance(120);assert(next(f.tasks)==nil) end)
test('sensor failure at wake can recover on the one-second recheck',function() local f,m=fixture();assert(m:setEnabled(true));f:advance(20);m:suspend();f.sensor_fail=true;m:resume();assert(m.state=='error' and f.tasks[m.resume_job]);f.sensor_fail=false;f.lux=0;f:advance(1);assert(m.available and m.state=='running' and not m.resuming and not m.fault) end)
test('daylight calibration allows zero and does not convert it into a manual off lock',function() local f,m=fixture();assert(m:setEnabled(true));local token=assert(m:beginCalibration('daylight'));assert(token.high==18);assert(m:preview(token,0));assert(m:finishCalibration(token,true));assert(m:curveOptions().daylight==0 and not m.config.off_locked);f:advance(60);assert(f.level>0) end)
test('explicit daylight setting clears conflicting bright memories only',function() local f,m=fixture();assert(m:setEnabled(true));assert(m:changeProfile('memories',{{lux=100,level=20},{lux=10000,level=10}}));assert(m:setCurve('daylight',0));assert(#m.config.memories==1 and m.config.memories[1].lux==100) end)
local function renderPage(id,has_sensor)
 local f,m=fixture();f.device.hasFrontlight=function() return true end;f.device.hasLightSensor=function() return has_sensor~=false end;f.device.hasNaturalLight=function() return false end
 package.loaded.device=f.device
 local app={autolight=m,messages={},adapter={}};function app:render() end;function app:message(s) self.messages[#self.messages+1]=s end;function app:confirm(_,fn) fn() end
 function app.adapter:promptText(title,initial,fn,options) app.prompt={callback=fn,options=options,title=title,initial=initial} end
 local model={rows={}};local function row(title,subtitle,callback) model.rows[#model.rows+1]={title=title,subtitle=subtitle,callback=callback} end
 local function go(route) return function() app.route=route end end
 assert(require('einkfrontend/lightsettings').render(app,{id=id},model,row,go));return f,m,app,model
end
test('frontlight home has three clear rows and hides technical details',function() local f,m,app,model=renderPage('frontlight_settings');assert(#model.rows==3);assert(model.rows[1].title=='亮度' and model.rows[2].title=='自动调光' and model.rows[3].title=='自动调光设置');model.rows[3].callback();assert(app.route=='auto_light') end)
test('devices without a sensor show only manual brightness',function() local f,m,app,model=renderPage('frontlight_settings',false);assert(#model.rows==1 and model.rows[1].title=='亮度') end)
test('automatic settings separate curve, memory and diagnostics',function() local f,m,app,model=renderPage('auto_light');assert(#model.rows==5 and model.rows[1].title=='暗处亮度' and model.rows[2].title=='明亮处亮度' and model.rows[3].title=='明亮环境标准');model.rows[5].callback();assert(app.route=='auto_light_status') end)
test('threshold presets and custom validation write the model through the UI',function() local f,m,app,model=renderPage('auto_light_threshold');model.rows[1].callback();assert(m:curveOptions().threshold==500);model.rows[5].callback();assert(app.prompt.options.keep_on_error);assert(app.prompt.callback('bad')==false and m:curveOptions().threshold==500);assert(app.prompt.callback('2000')==true and m:curveOptions().threshold==2000) end)
test('empty memory page hides the destructive clear action',function() local f,m,app,model=renderPage('auto_light_memory');assert(#model.rows==2);model.rows[2].callback();assert(#app.messages==1) end)
test('numeric labels stay above both slider thumbs and remain nonbold at every endpoint',function()
 local oldPaint,oldInput,oldGesture,oldDevice,oldUI,oldOS=package.loaded['einkfrontend/paint'],package.loaded['ui/widget/container/inputcontainer'],package.loaded['ui/gesturerange'],package.loaded.device,package.loaded['ui/uimanager'],os
 local labels,circles={},{}
 local paint={BB={COLOR_BLACK=0,COLOR_WHITE=1},style={label=18},s=function(v) return v end}
 function paint.inkLabel(_,text,x,y,w,h,size,bold) labels[#labels+1]={text=text,x=x,y=y,w=w,h=h,bold=bold};return {x=x,y=y,w=w,h=h} end
 function paint.label(_,_,x,y,w,h) return {x=x,y=y,w=w,h=h} end
 for _,key in ipairs({'rule','text','centerText','icon','inkIcon','battery'}) do paint[key]=function() return {} end end
 local Input={};function Input:extend(t) function t:new(o) setmetatable(o,{__index=self});o:init();return o end;return t end
 local Device={screen={getSize=function() return {w=600,h=800} end},hasLightSensor=function() return false end}
 package.loaded['einkfrontend/paint']=paint;package.loaded['ui/widget/container/inputcontainer']=Input;package.loaded['ui/gesturerange']={new=function(_,o)return o end};package.loaded.device=Device;package.loaded['ui/uimanager']={};os={date=function() return 'date' end}
 package.loaded['einkfrontend/controls']=nil;package.loaded['einkfrontend/lightcalibration']=nil
 local bb={paintRect=function() end,paintBorder=function() end,paintCircle=function(_,x,y,r,color) circles[#circles+1]={x=x,y=y,r=r,color=color} end}
 local Controls=require('einkfrontend/controls');local Dialog=require('einkfrontend/lightcalibration')
 local function check(label,circle) assert(label.bold==false);assert(math.abs(label.x+label.w/2-circle.x)<1);assert(label.y+label.h<circle.y-circle.r,'number is not above the thumb') end
 for _,n in ipairs({0,1,9,18,25,100}) do
  local high=n==100 and 100 or 25
  local app={adapter={deviceStatus=function() return {frontlight=true,low=0,high=high,intensity=n,battery=50} end},autolight={hi=high,lo=0}}
  labels={};circles={};local c=Controls:new{app=app};c:paintTo(bb,0,0);check(labels[#labels],circles[#circles-1]);assert(labels[#labels].text==tostring(n))
  labels={};circles={};local d=Dialog:new{app=app,token={value=n,low=0,high=high}};d:paintTo(bb,0,0);check(labels[#labels],circles[#circles-1]);assert(labels[#labels].text==tostring(n))
 end
 package.loaded['einkfrontend/paint']=oldPaint;package.loaded['ui/widget/container/inputcontainer']=oldInput;package.loaded['ui/gesturerange']=oldGesture;package.loaded.device=oldDevice;package.loaded['ui/uimanager']=oldUI;os=oldOS
 package.loaded['einkfrontend/controls']=nil;package.loaded['einkfrontend/lightcalibration']=nil
end)
local out={};for _,c in ipairs(checks) do out[#out+1]='{"name":'..string.format('%q',c.name)..',"passed":'..tostring(c.passed)..',"error":'..(c.error and string.format('%q',c.error) or 'null')..'}' end
AUDIT_RESULT='{"total":'..count..',"failed":'..failed..',"checks":['..table.concat(out,',')..']}'
