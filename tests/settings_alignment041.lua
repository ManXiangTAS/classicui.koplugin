require("setupkoenv")
package.path="plugins/einkfrontend.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
local DS=require("datastorage")
G_reader_settings=require("luasettings"):open(DS:getDataDir().."/settings.reader.lua")
G_reader_settings:saveSetting("language","zh_CN");require("gettext").changeLang("zh_CN")
G_reader_settings:saveSetting("eink_frontend",{auto_open=false,reader_entry=true,full_takeover=true})
require("logger"):setLevel(require("logger").levels.warn)
local Device=require("device");require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager");local FM=require("apps/filemanager/filemanager");local S=require("einkfrontend/paint").s
local root=assert(os.getenv("EINK_PROJECT"));local variant=assert(os.getenv("EINK_VARIANT"))
FM:showFiles(assert(os.getenv("EINK_030_BOOKS")));local app=FM.instance.einkfrontend.app
app:open("settings");local page=app.screen
local report={variant=variant,device="NOT_RUN",frames={}}
local function shot(name)
 local remove={};for _,w in ipairs(UI._window_stack) do if w.widget.text then remove[#remove+1]=w.widget end end
 for _,w in ipairs(remove) do UI:close(w) end
 UI:forceRePaint();assert(not page.paint_fault)
 local filename="settings-"..name.."-"..variant..".png";Device.screen:shot(root.."/test-results-041/"..filename)
 local rows={}
 for i,row in ipairs(page.model.rows) do rows[i]={icon=row.icon~=nil,note=row.note~=nil and row.note~="",value=row.value~=nil,arrow=row.callback~=nil and row.enabled~=false} end
 report.frames[#report.frames+1]={file=filename,width=page.dimen.w,height=page.dimen.h,header=page.header_h,
  top=page.header_h+page.info_h,row_h=page.row_h,scroll=page.scroll_y,viewport=page.viewport_h,
  root=page.model.route.id=="settings",scale=math.min(page.dimen.w,page.dimen.h)/600,rows=rows}
 return filename
end
shot("root");page:scrollBy(page.scroll_max);shot("root-bottom")
local clicked,held=0,0;local rows={
 {title="阅读偏好",icon="reading",callback=function() clicked=1 end},
 {title="Wi-Fi 与同步",icon="wifi",callback=function() clicked=2 end},
 {title="两行设置",note="说明文字与标题作为整体居中",icon="appbar.settings",callback=function() clicked=3 end,hold_callback=function() held=3 end},
 {title="搜索工具 gyp",note="说明文字很长时应在数值列前截断，不覆盖右侧数字和箭头",value=12,icon="appbar.search",callback=function() clicked=4 end},
 {title="禁用项目",note="仍按原行高度显示",icon="plugins",enabled=false,callback=function() error("disabled tap executed") end},
}
for i=6,20 do rows[i]={title="设置项目 "..i,note=i%2==0 and "更多设置说明" or nil,icon="appbar.settings",callback=function() clicked=i end} end
page:setModel{title="对齐检查",settings=true,subtitle="",route={id="alignment_fixture",page=1},rows=rows,page=1}
shot("mixed")
local function hit(index)
 for _,h in ipairs(page.hits) do if h.id=="settings_row_"..index then return {x=h.x+S(30),y=h.y+h.h/2} end end
 error("missing row "..index)
end
page:onFrontendTap(nil,{pos=hit(3)});assert(clicked==3)
page:onFrontendHold(nil,{pos=hit(3)});assert(held==3)
page:onFrontendTap(nil,{pos=hit(5)});assert(clicked==3)
page:scrollBy(S(21));shot("partial")
page:scrollBy(page.scroll_max);shot("bottom")
app:close();FM.instance:onClose()
local file=assert(io.open(root.."/test-results-041/settings-"..variant..".json","w"));file:write(require("rapidjson").encode(report));file:close()
print("PASS settings tap hold disabled semantics "..variant)
