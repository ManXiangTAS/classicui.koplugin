require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');local Settings=require('luasettings');local json=require('json')
G_reader_settings=Settings:open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,full_takeover=true})
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local FM=require('apps/filemanager/filemanager')
local PP=require('einkfrontend/pagepress');local HW=require('einkfrontend/pagepresshw')
local root=assert(os.getenv('EINK_PROJECT'));local variant=os.getenv('EINK_VARIANT');local output=root..'/test-results-048/'
local report={tests={},frames={},variant=variant,device='NOT_RUN',hardware='ABI emulator; no real hardware writes'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local counter=0
local function fixture()
 counter=counter+1
 local state={prev=1,next_=0,pressure=180,haptic=false,gain=2,writes=0,release=90}
 local io_={}
 function io_.ioctl(path,request,value)
  local key=({[0x80044219]='prev',[0x8004421b]='next_',[0x80044213]='pressure'})[request]
  if request==0x80044202 then assert(path=='/dev/keypad');return state.locked and 1 or 0 end
  if key then assert(path=='/dev/keypad');return state[key] end
  if request==0x80044307 then assert(path=='/dev/haptic');return state.haptic and 0 or 1 end
  state.writes=state.writes+1
  if request==0x4004421a then state.prev=value
  elseif request==0x4004421c then
   if state.fail_next then state.fail_next=false;error('second enable write failed') end;state.next_=value
  elseif request==0x40044214 then
   if state.reject_pressure then state.reject_pressure=false;return 0 end
   state.pressure=value;state.release=math.floor(value/2)
  elseif request==0x40044306 then assert(path=='/dev/haptic');state.haptic=value==0
  else error('unexpected or unsafe ioctl '..request) end
  return 0
 end
 function io_.readfile(path)
  assert(path=='/sys/devices/system/drv26xx_haptics/drv26xx_haptics0/id')
  if state.bad_gain then return 'unknown format' end
  return string.format('ctrl reg=0x%02x, id=0x07\n',0x38+state.gain)
 end
 function io_.writefile(path,value)
  assert(path=='/sys/devices/system/drv26xx_haptics/drv26xx_haptics0/gain_setting')
  state.writes=state.writes+1
  if state.reject_gain then state.reject_gain=false;return true end
  state.gain=assert(tonumber(value));return true
 end
 local settings=Settings:open(DS:getSettingsDir()..'/pagepress-'..counter..'.lua')
 local hw=HW.new(io_);local service=PP.new(settings,hw);service:resume()
 return service,state,settings,hw
end
check('Only Voyage is eligible; other Kindle models and desktop never attach hardware',function()
 assert(PP.supported({model='KindleVoyage'}));assert(not PP.supported({model='KindlePaperWhite3'}));assert(not PP.supported(Device))
 local original=HW.new;HW.new=function() error('non Voyage must not create a backend') end
 assert(PP.attach({})==nil);HW.new=original
end)
check('First use inherits hardware without writing or assuming stock defaults',function()
 local service,state=fixture();assert(state.writes==0);assert(service:read('pressure')==180);assert(service:read('haptic')==false)
 assert(service.config.pressure==nil and service.config.enabled==nil)
 assert(service:change('pressure',nil));assert(service:change('pressure',180));assert(state.writes==0)
 service:suspend();assert(state.writes==0)
end)
check('Pressure uses the native scalar ABI and its release threshold rule, then restores entry value',function()
 local service,state=fixture();assert(service:change('pressure',100));assert(state.pressure==100 and state.release==50)
 assert(service:change('pressure',200));assert(service.baseline.pressure==180)
 service:suspend();assert(state.pressure==180 and state.release==90);service:resume();assert(state.pressure==200)
 assert(service:change('pressure',nil));assert(state.pressure==180 and service.config.pressure==nil)
end)
check('Both PagePress directions toggle together and separate original states survive restore',function()
 local service,state=fixture();assert(service:change('enabled',false));assert(state.prev==0 and state.next_==0)
 assert(service:change('enabled',true));assert(state.prev==1 and state.next_==1)
 assert(service:change('enabled',nil));assert(state.prev==1 and state.next_==0)
end)
check('Failure on the second button write rolls back the first and leaves no saved override',function()
 local service,state=fixture();state.fail_next=true;assert(not service:change('enabled',true))
 assert(state.prev==1 and state.next_==0 and service.config.enabled==nil)
end)
check('Readback mismatch is failure and restores the old pressure',function()
 local service,state=fixture();state.reject_pressure=true;local ok,why=service:change('pressure',100)
 assert(not ok and why:find('读回',1,true));assert(state.pressure==180 and service.config.pressure==nil)
end)
check('A failed rollback is explicit and cleanup retries partially written hardware',function()
 local service,state,_,hw=fixture();state.next_=1
 local write=hw.write;local calls=0
 hw.write=function(self,key,value)
  calls=calls+1
  if calls==1 then state.prev=0;error('partial write') end
  if calls==2 then error('rollback failed') end
  return write(self,key,value)
 end
 local ok,why=service:change('enabled',false);assert(not ok and why:find('恢复原值失败',1,true))
 assert(state.prev==0 and state.next_==1 and service.restore_pending.enabled)
 service:suspend();assert(state.prev==1 and state.next_==1 and not service.restore_pending.enabled)
end)
check('Haptic off uses the lock, gain zero remains a valid strength, and false baseline survives repeated edits',function()
 local service,state=fixture();assert(service:change('haptic',true));assert(service:change('haptic',false));assert(service:change('haptic',true))
 assert(service.baseline.haptic==false);assert(service:change('gain',0));assert(state.gain==0 and state.haptic)
 service:suspend();assert(not state.haptic and state.gain==2)
end)
check('A locked keypad reports a reason without writes or saved settings',function()
 local service,state=fixture();state.locked=true;local ok,why=service:change('pressure',100)
 assert(not ok and why:find('锁定',1,true));assert(state.writes==0 and service.config.pressure==nil)
end)
check('Gain parser rejects unknown firmware output and actual register readback detects ignored writes',function()
 local service,state=fixture();state.bad_gain=true;local value,why=service:read('gain');assert(value==nil and why:find('不兼容',1,true))
 assert(not service:change('gain',1));assert(state.writes==0)
 state.bad_gain=false;state.reject_gain=true;assert(not service:change('gain',1));assert(state.gain==2 and service.config.gain==nil)
end)
check('Invalid persisted data and invalid changes cannot reach the hardware',function()
 local service,state,settings,hw=fixture();settings:saveSetting('eink_pagepress',{gain=4,pressure=-1,enabled='yes',haptic={}})
 local other=PP.new(settings,hw);other:resume();assert(state.writes==0)
 for _,kv in ipairs({{'gain',4},{'pressure',0},{'pressure',65536},{'pressure',0/0},{'enabled',1},{'haptic','yes'},{'unknown',nil}}) do assert(not other:change(kv[1],kv[2])) end
 assert(state.writes==0)
end)
check('Settings flush failure restores in-memory config disk config and hardware',function()
 local service,state,settings=fixture();assert(service:change('pressure',100));local flush=settings.flush
 settings.flush=function() error('injected disk failure') end
 assert(not service:change('pressure',200));assert(state.pressure==100 and service.config.pressure==100)
 settings.flush=flush;assert(Settings:open(settings.file):readSetting('eink_pagepress').pressure==100)
end)
check('A silent failed save is detected by reopening the settings file',function()
 local service,state,settings=fixture();assert(service:change('pressure',100));local flush=settings.flush;settings.flush=function() return settings end
 local ok,why=service:change('pressure',200);settings.flush=flush
 assert(not ok and why:find('未能保存',1,true));assert(state.pressure==100 and service.config.pressure==100)
end)
check('Saved values reapply after restart and external hardware changes are preserved on suspend',function()
 local service,state,settings,hw=fixture();assert(service:change('pressure',100));service:suspend()
 local other=PP.new(Settings:open(settings.file),hw);other:resume();assert(state.pressure==100)
 state.pressure=230;other:suspend();assert(state.pressure==230);other:resume();assert(state.pressure==100 and other.baseline.pressure==230)
end)
check('Filemanager and reader owners share one lifecycle; only the last detach restores hardware',function()
 local service,state=fixture();local a,b={},{};service.owners[a]=true;service.owners[b]=true
 assert(service:change('enabled',false));service:detach(a);assert(state.prev==0 and state.next_==0)
 service:detach(b);assert(state.prev==1 and state.next_==0)
end)
check('The actual Voyage attach factory shares one backend and detaches without leaked ownership',function()
 local _,state,_,hw=fixture();local model=Device.model;local new=HW.new;local calls=0
 Device.model='KindleVoyage';HW.new=function() calls=calls+1;return hw end
 local a,b={},{};local one=PP.attach(a);local two=PP.attach(b)
 assert(one==two and calls==1);assert(one:change('pressure',100));one:detach(a);assert(state.pressure==100)
 one:detach(b);assert(state.pressure==180);one=PP.attach(a);assert(state.pressure==100)
 assert(one:change('pressure',nil));one:detach(a);HW.new=new;Device.model=model
end)
check('Unavailable hardware during suspend is reported and saved overrides can recover on resume',function()
 local service,state=fixture();assert(service:change('pressure',100));state.locked=true;service:suspend()
 assert(service.errors.pressure and state.pressure==100);state.locked=false;service:resume();service:suspend();assert(state.pressure==180)
end)
FM:showFiles(assert(os.getenv('EINK_030_BOOKS')));local app=assert(FM.instance.einkfrontend.app)
local function row(title) for _,r in ipairs(app.screen.model.rows) do if r.title==title then return r end end;error('missing row '..title) end
check('Non Voyage settings and global search do not offer PagePress',function()
 app:open('catalog_category','input');for _,r in ipairs(app.screen.model.rows) do assert(r.title~='翻页键') end
 require('einkfrontend/settings').search(app,'翻页键');for _,r in ipairs(app.screen.model.rows) do assert(r.title~='翻页键') end
end)
local service,state=fixture();app.pagepress=service;service.owners[app]=true
local function shot(name)
 local notices={};for _,entry in ipairs(UI._window_stack) do if entry.widget.text then notices[#notices+1]=entry.widget end end
 for _,notice in ipairs(notices) do UI:close(notice) end
 UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(output..file);report.frames[#report.frames+1]={file=file}
 for _,r in ipairs(app.screen.row_layout) do if r.value then assert(math.abs((r.label.y+r.label.h/2)-(r.value.y+r.value.h/2))<=1) end end
end
check('PagePress integrates with shared settings rendering and live device values',function()
 app:open('catalog_category','input');row('翻页键').callback();assert(app.screen.model.title=='翻页键')
 assert(row('启用翻页键').value=='部分开启');assert(row('按压力度').value=='180');assert(row('震动反馈').value=='关')
 shot('pagepress-settings');row('按压力度').callback();row('轻按（100）').callback();assert(state.pressure==100 and app.screen.model.title=='翻页键')
 row('反馈强度').callback();row('中').callback();assert(state.gain==1);row('震动反馈').callback();row('开').callback();assert(state.haptic)
 row('按压力度').callback();assert(row('轻按（100）').checked);shot('pagepress-pressure');row('沿用 Kindle 设置').callback();assert(state.pressure==180)
end)
check('PagePress search covers sensitivity pressure vibration and Voyage',function()
 for _,q in ipairs({'灵敏度','按压力度','振动','震动','Voyage','翻页键'}) do
  require('einkfrontend/settings').search(app,q);row('翻页键').callback();assert(app.screen.model.title=='翻页键')
 end
end)
check('Direction control invokes the existing KOReader inversion event',function()
 app:go('pagepress_settings');local before=G_reader_settings:isTrue('input_invert_page_turn_keys')
 row('反转翻页方向').callback();assert(G_reader_settings:isTrue('input_invert_page_turn_keys')~=before)
 row('反转翻页方向').callback();assert(G_reader_settings:isTrue('input_invert_page_turn_keys')==before)
end)
check('Unavailable settings remain informative instead of throwing or displaying a fabricated state',function()
 state.locked=true;app:go('pagepress_settings');assert(row('按压力度').value=='不可用');assert(row('反馈强度').value=='中')
 local message;local original=app.message;app.message=function(_,text) message=text end
 row('按压力度').callback();app.message=original;assert(message:find('锁定',1,true));state.locked=false
end)
check('Plugin suspend and resume restore and reapply hardware; stop restores entry values',function()
 assert(service:change('pressure',100));app.plugin:onSuspend();assert(state.pressure==180 and not state.haptic and state.gain==2)
 app.plugin:onResume();assert(state.pressure==100 and state.haptic and state.gain==1)
 app.plugin:stopPlugin();assert(state.pressure==180 and not state.haptic and state.gain==2)
end)
FM.instance:onClose()
local file=assert(io.open(output..'regression-'..variant..'.json','w'));file:write(json.encode(report));file:close();print('COMPLETE '..variant)
