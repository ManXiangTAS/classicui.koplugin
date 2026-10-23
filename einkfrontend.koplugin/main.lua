-- Original project code. SPDX-License-Identifier: AGPL-3.0-or-later
require('einkfrontend/offlineupdate').disable()
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local Adapter = require("einkfrontend/adapter")
local App = require("einkfrontend/app")
local Plugin = WidgetContainer:extend{is_doc_only=false}

function Plugin:option(key,default)
    local values=G_reader_settings:readSetting("eink_frontend") or {}
    if type(values)~="table" then values={} end
    if values[key]==nil then return default end
    return values[key]
end

function Plugin:toggleOption(key,default)
    local values=G_reader_settings:readSetting("eink_frontend") or {}
    if type(values)~="table" then values={} end
    values[key]=not self:option(key,default)
    G_reader_settings:saveSetting("eink_frontend",values)
    G_reader_settings:flush()
end

function Plugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("einkfrontend_open",{category="none",event="EInkFrontendOpen",title="墨页：打开前端",general=true})
end

function Plugin:init()
    -- registerModule later prefixes instance.name with reader/filemanager.
    self.plugin_id=self.name or "einkfrontend"
    self.active=Adapter.supported()
    self.adapter=Adapter.new(self.ui)
    self.app=App.new(self,self.adapter)
    if self.active then require('einkfrontend/pinyin').install(self) end
    self:onDispatcherRegisterActions()
    if self.active and self:option("full_takeover",true) then self:installTakeover() end
    self.ui.menu:registerToMainMenu(self) -- Explicit compatibility/recovery entry.
    -- FileManager creates file_chooser after plugins are initialized.
    local suppress_start=Adapter.suppress_next_start
    local requested=not self.ui.document and (Adapter.shell_requested or (Adapter.library_requested and "library"))
    local context=self.app.library.settings:readSetting("return_context")
    if not self.ui.document and not suppress_start and not requested and type(context)=="table" and context.version==1
        and self.ui.focused_file==context.file and self.app.library.settings:isTrue("resume_library") then requested=context.shell end
    if not self.ui.document then Adapter.suppress_next_start=nil end
    if not self.ui.document then Adapter.library_requested=nil;Adapter.shell_requested=nil end
    if self.active and not self.ui.document and (requested or (not suppress_start and self:option("auto_open",true))) then
        self.pending_open=function()
            self.pending_open=nil
            if self.active and self.adapter:alive() then self.app:safe(function() self.app:open(requested);local t=require("einkfrontend/transfersettings");if not t.config().configured and not t.config().wizard_seen then t.wizard(self.app) end end) end
        end
        self.ui:registerPostInitCallback(function()
            if self.active and self.pending_open then UIManager:nextTick(self.pending_open) end
        end)
    end
end

function Plugin:addToMainMenu(items)
    items.einkfrontend={text="墨页前端",sorting_hint="more_tools",callback=function() self:onEInkFrontendOpen() end}
end

function Plugin:onEInkFrontendOpen()
    if not self.active then
        local supported=Adapter.supported()
        UIManager:show(InfoMessage:new{text=supported and "墨页已停用；重新启用后重启 KOReader。" or
            "墨页仅适配 KOReader 2026.07.1 / 2026.07.2 稳定版；当前版本保留原生界面。"})
        return true
    end
    return self.app:safe(function() if self.ui.document then self.app:showReader("menu") else self.app:open() end end)
end

function Plugin:refreshReaderEntry()
    if self.zones then self.ui:unRegisterTouchZones(self.zones);self.zones=nil end
    if not self.active or not self.ui.document or not self:option("reader_entry",true) then return end
    self.zones={{id="einkfrontend_reader_panel",ges="tap",
        screen_zone={ratio_x=0.3,ratio_y=0.28,ratio_w=0.4,ratio_h=0.35},
        overrides={"readermenu_tap","readermenu_ext_tap","tap_forward","tap_backward"},
        handler=function() return self:onEInkFrontendOpen() end}}
    self.ui:registerTouchZones(self.zones)
    self.zones[#self.zones+1]={id="einkfrontend_reader_topbar",ges="tap",
        screen_zone={ratio_x=0,ratio_y=0,ratio_w=1,ratio_h=0.15},
        overrides={"readermenu_tap","readermenu_ext_tap","tap_forward","tap_backward"},
        handler=function() return self.app:safe(function() self.app:showReaderTopbar() end) end}
    self.ui:registerTouchZones({self.zones[#self.zones]})
    self.zones[#self.zones+1]={id="einkfrontend_controls",ges="swipe",
        screen_zone={ratio_x=0,ratio_y=0,ratio_w=1,ratio_h=0.06},
        overrides={"readermenu_swipe","readermenu_ext_swipe","rolling_swipe","paging_swipe"},
        handler=function(ges)
            if ges.direction=="south" then return self.app:safe(function() self.app:showControls() end) end
            return false
        end}
    self.ui:registerTouchZones({self.zones[#self.zones]})
end

function Plugin:onReaderReady()
    self.app:safe(function() if self.app.typography then self.app.typography:onReady() end;self:refreshReaderEntry() end)
end

function Plugin:stopPlugin(transition)
    local notices=require("einkfrontend/notices")
    if transition then notices.handoff(self) end
    self.active=false
    if self.app.pagepress then self.app.pagepress:detach(self.app) end
    notices.detach(self,not transition)
    if self.gate then self.gate:restore() end
    if self.app.typography then self.app.typography:detach() end
    if self.pending_open then UIManager:unschedule(self.pending_open);self.pending_open=nil end
    if self.zones then self.ui:unRegisterTouchZones(self.zones);self.zones=nil end
    self.app:close()
    require('einkfrontend/pinyin').detach(self)
    return true
end

function Plugin:disableFrontend()
    local disabled=G_reader_settings:readSetting("plugins_disabled") or {}
    disabled[self.plugin_id]=true
    G_reader_settings:saveSetting("plugins_disabled",disabled)
    G_reader_settings:flush()
    self:stopPlugin()
end

function Plugin:installTakeover()
    require("einkfrontend/notices").install(self)
    if self.gate then self.gate:restore() end
    self.gate=require("einkfrontend/gate").new(self.ui,function(destination,key,...)
        if not self.active or not self.adapter:alive() then error("上下文已关闭") end
        if destination=="ignore_top_tap" then return true
        elseif destination=="settings" then self.app:open("settings")
        elseif destination=="settings_search" then self.app:searchSettings()
        elseif destination=="controls" then self.app:showControls()
        elseif destination=="reader_top" then self.app:showReaderTopbar()
        elseif destination=="toc" then self.app:showNavigation("toc")
        elseif destination=="bookmarks" then self.app:showNavigation("bookmarks")
        elseif destination=="annotation_details" then self.app:showNavigation("details",...)
        elseif destination=="aa" then self.app:showReader("font")
        elseif destination=="book_statistics" then self.app:showBookStatistics()
        elseif destination=="library" then self.app:returnToOrigin()
        else self.app:showReader("menu") end
    end):install()
    self.gate.onFailure=function() self:stopPlugin() end
end
function Plugin:onCloseWidget() self:stopPlugin(self.ui.tearing_down) end
function Plugin:onCloseDocument()
    if self.active then local ok,why=pcall(require("einkfrontend/home").capture,self.app);if not ok then require("logger").warn("Home reading snapshot:",why) end end
    self:stopPlugin(self.ui.tearing_down)
end
function Plugin:onSuspend()
    if self.app and self.app.transfer_server then self.app.transfer_server:stop() end
    if self.app and self.app.pagepress then self.app.pagepress:suspend() end
    if self.app and self.app.home_editor then self.app.home_editor:onSuspend() end
end
function Plugin:onResume()
    if self.active and self.app and self.app.pagepress then self.app.pagepress:resume() end
end
return Plugin
