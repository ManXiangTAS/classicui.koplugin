require("setupkoenv")
package.path="plugins/einkfrontend.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
local DS=require("datastorage")
G_reader_settings=require("luasettings"):open(DS:getDataDir().."/settings.reader.lua")
G_reader_settings:saveSetting("language","zh_CN");require("gettext").changeLang("zh_CN")
G_reader_settings:saveSetting("eink_frontend",{auto_open=false,reader_entry=true,full_takeover=true})
require("logger"):setLevel(require("logger").levels.warn)
local Device=require("device");require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager");local FM=require("apps/filemanager/filemanager")
local root=assert(os.getenv("EINK_PROJECT"));local variant=assert(os.getenv("EINK_VARIANT"))
FM:showFiles(assert(os.getenv("EINK_030_BOOKS")));local app=FM.instance.einkfrontend.app
local power=Device:getPowerDevice();local original_power=rawget(power,"isFrontlightOn")
local original_status=app.adapter.deviceStatus
local report={variant=variant,device="NOT_RUN",frames={}}
for _,sync in ipairs({false,true}) do for _,on in ipairs({true,false}) do
 power.isFrontlightOn=function() return on end
 app.adapter.deviceStatus=function() return {wifi=true,sync=sync,night=not on,frontlight=true,battery=34,intensity=50,low=0,high=100} end
 app:showControls()
 -- Remove native welcome messages; the dropdown itself uses real widgets,
 -- font shaping, SVG rendering and framebuffer paint primitives.
 local remove={};for _,w in ipairs(UI._window_stack) do if w.widget.text then remove[#remove+1]=w.widget end end
 for _,w in ipairs(remove) do UI:close(w) end
 UI:forceRePaint();local controls=assert(app.controls)
 local name="dropdown-"..(sync and "6" or "5").."-"..(on and "on" or "off").."-"..variant..".png"
 Device.screen:shot(root.."/test-results-040/"..name)
 report.frames[#report.frames+1]={file=name,actions=controls.action_layout,frontlight=controls.frontlight_layout}
 controls:close()
end end
power.isFrontlightOn=original_power;app.adapter.deviceStatus=original_status
app:close();FM.instance:onClose()
local file=assert(io.open(root.."/test-results-040/alignment-"..variant..".json","w"));file:write(require("rapidjson").encode(report));file:close()
print("COMPLETE alignment040 "..variant)
