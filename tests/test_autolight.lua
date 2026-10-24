require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage')
G_reader_settings=require('luasettings'):open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,full_takeover=true})
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local Event=require('ui/event')
local FM=require('apps/filemanager/filemanager');local Reader=require('apps/reader/readerui')
local books=assert(os.getenv('EINK_030_BOOKS'));local out=assert(os.getenv('EINK_TEST_OUTPUT'))..'/'
local variant=assert(os.getenv('EINK_VARIANT'));local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function shot(name) UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(out..file);report.frames[#report.frames+1]=file end
local function find(widget,id) UI:forceRePaint();for _,h in ipairs(widget.hits or {}) do if h.id==id then return h end end end
local function row(app,title) for _,r in ipairs(app.screen.model.rows) do if r.title==title then return r end end;error('Missing row: '..title) end
FM:showFiles(books);local plugin=FM.instance.einkfrontend;local app=plugin.app
for _=1,30 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end
local close={};for _,e in ipairs(UI._window_stack) do if e.widget.text then close[#close+1]=e.widget end end;for _,w in ipairs(close) do UI:close(w) end
local service=assert(app.autolight);local realSensor=service.sensor;local realHasSensor=Device.hasLightSensor
local power=Device:getPowerDevice();local originalMax=power.fl_max
check('A device without a sensor has a discoverable explanation and no automatic control',function()
 app:open('catalog_category','display');assert(row(app,'自动前光').callback)
 row(app,'自动前光').callback();assert(app.screen.model.route.id=='auto_light')
 assert(row(app,'自动前光').value=='不可用' and not service.config.enabled)
 assert(not service:setEnabled(true));shot('auto-light-unavailable')
 app:showControls();assert(not find(app.controls,'control_auto_light'));app.controls:close()
end)
-- The UI is exercised against a simulated raw sensor and the real KOReader
-- Powerd/scheduler. These screenshots are not claims of a hardware sensor test.
Device.hasLightSensor=function() return true end
power.fl_max=25;power:setIntensity(18)
service.hi=25;service.config.device_key=Device.model..':0:25'
service.sensor={backend='lipc',probe=function() return true,nil,45 end,read=function() return 45 end}
check('A capable device exposes a shortcut and an explicit enable flow',function()
 app:open('auto_light');assert(row(app,'自动前光').value=='未开启')
 assert(row(app,'当前环境').value=='45.0 lux')
 app:showControls();assert(find(app.controls,'control_auto_light'));shot('auto-light-controls');app.controls:close()
 row(app,'自动前光').callback()
 local dialog=UI._window_stack[#UI._window_stack].widget;assert(dialog.token and not service.config.enabled)
 UI:forceRePaint();assert(find(dialog,'light_apply') and find(dialog,'light_cancel'))
 shot('auto-light-calibration');dialog:adjust(7);assert(power:frontlightIntensity()==7)
 dialog:close();assert(power:frontlightIntensity()==18 and not service.config.enabled)
end)
check('Calibration uses device bounds, previews exactly and enables only on confirmation',function()
 row(app,'自动前光').callback();local dialog=UI._window_stack[#UI._window_stack].widget
 dialog:adjust(99);assert(power:frontlightIntensity()==25)
 dialog:adjust(7);dialog:apply()
 assert(service.config.anchor==7 and service.config.enabled and service.expected==7)
 assert(G_reader_settings:readSetting('eink_autolight').anchor==7)
 app:render();shot('auto-light-enabled')
end)
check('Manual sliders and frontlight toggles notify the shared controller without losing the UI',function()
 app:showControls();app.adapter:setFrontlight(10)
 assert(service.expected==10 and service.pause_until and service.pending_learning)
 app.controls:close();power:turnOffFrontlight();power:updateResumeFrontlightState();plugin:onFrontlightStateChanged()
 assert(service.config.off_locked and not service.pending_learning)
 app:render();assert(row(app,'恢复自动').callback and row(app,'自动前光').value=='已手动关灯')
 row(app,'恢复自动').callback();assert(not service.config.off_locked and not service.pause_until)
end)
check('Remembered preferences and calibration survive rereading the settings file',function()
 assert(service:change('memories',{{lux=45,level=12},{lux=300,level=6}}))
 app:open('auto_light_memory');assert(row(app,'已记住的环境').value=='2 处');shot('auto-light-memory')
 local saved=require('luasettings'):open(G_reader_settings.file):readSetting('eink_autolight')
 assert(saved.anchor==7 and saved.enabled and #saved.memories==2 and saved.memories[2].level==6)
end)
check('Suspend closes calibration and every timer; repeated resume deduplicates the sampler',function()
 app:open('auto_light');local dialog=require('einkfrontend/lightsettings').calibrate(app,false)
 dialog:adjust(4);plugin:onSuspend();dialog:onSuspend()
 assert(not service.calibration and service.suspended)
 local function jobs()
  local n=0;for _,entry in ipairs(UI._task_queue) do
   if entry.action==service.sample_job or entry.action==service.ramp_job or entry.action==service.learn_job then n=n+1 end
  end;return n
 end
 assert(jobs()==0);plugin:onResume();plugin:onResume();assert(jobs()==1)
end)
check('Reader and library share one controller and settings, with no second writer',function()
 app:close();Reader:doShowReader(books..'/navigation.epub')
 local readerPlugin=assert(Reader.instance).einkfrontend;local readerApp=readerPlugin.app
 assert(readerApp.autolight==service and service.config.anchor==7)
 readerApp:open('auto_light');assert(row(readerApp,'亮度记忆').value=='2 处');shot('auto-light-reader')
 readerApp.adapter:returnToLibrary('library')
 if FM.instance then assert(FM.instance.einkfrontend.app.autolight==service) end
end)
check('Settings search finds automatic brightness and memory keywords',function()
 app=assert(FM.instance).einkfrontend.app
 require('einkfrontend/settings').search(app,'自适应');assert(row(app,'自动前光').callback)
 row(app,'自动前光').callback();assert(app.screen.model.route.id=='auto_light')
end)
service:setEnabled(false);service.sensor=realSensor;Device.hasLightSensor=realHasSensor;power.fl_max=originalMax
if FM.instance then FM.instance:onClose() end
local f=assert(io.open(out..'auto-light-'..variant..'.json','w'));f:write(require('json').encode(report));f:close()
print('COMPLETE '..variant)
