-- Original project code. SPDX-License-Identifier: AGPL-3.0-or-later
-- All KOReader internal interfaces are isolated here.
-- Audited commit: 9192014d8bd82a91dc1012473be0f238dedfdb54.
local Event = require("ui/event")
local DocSettings = require("docsettings")
local LuaSettings = require("luasettings")
local FileChooser = require("ui/widget/filechooser")
local Version = require("version")
local Registry = require("einkfrontend/registry")
local Adapter = {}
Adapter.__index = Adapter

-- readerfont.lua:onSet*, readertypeset.lua:onToggle*, readerconfig.lua:onSaveSettings.
local bindings = {
    font_gamma={key="copt_font_gamma",field="font_gamma",event="SetFontGamma"},
    font_base_weight={key="copt_font_base_weight",field="font_base_weight",event="SetFontBaseWeight"},
    word_spacing={key="copt_word_spacing",field="word_spacing",event="SetWordSpacing"},
    word_expansion={key="copt_word_expansion",field="word_expansion",event="SetWordExpansion"},
    cjk_width_scaling={key="copt_cjk_width_scaling",field="cjk_width_scaling",event="SetCJKWidthScaling"},
    page_margins = {key="copt_h_page_margins",field="h_page_margins"},
    embedded_css = {key="copt_embedded_css", field="embedded_css", event="ToggleEmbeddedStyleSheet", boolean=true},
    embedded_fonts = {key="copt_embedded_fonts", field="embedded_fonts", event="ToggleEmbeddedFonts", boolean=true},
    font_size = {key="copt_font_size", field="font_size", event="SetFontSize"},
    font_face = {key="font_face", event="SetFont", global_key="cre_font"},
    line_spacing = {key="copt_line_spacing", field="line_spacing", event="SetLineSpace"},
    font_hinting = {key="copt_font_hinting", field="font_hinting", event="SetFontHinting"},
    font_kerning = {key="copt_font_kerning", field="font_kerning", event="SetFontKerning"},
}

function Adapter.new(ui) return setmetatable({ui=ui}, Adapter) end

function Adapter.supported()
    local revision = Version:getCurrentRevision() or ""
    return revision == "v2026.07.1" or revision == "v2026.07.2", revision
end

function Adapter:alive()
    if self.ui.document then
        return require("apps/reader/readerui").instance == self.ui
    end
    return require("apps/filemanager/filemanager").instance == self.ui
end

function Adapter:available(id)
    if not self:alive() then return false, "阅读或文件管理上下文已关闭" end
    if bindings[id] then
        if not self.ui.document or not self.ui.font or not self.ui.typeset then
            return false, "请先打开 EPUB 等流式文档；此项不用于 PDF"
        end
        if id == "embedded_fonts" then
            if self.ui.document.configurable.embedded_css ~= 1 then return false, "请先启用内嵌样式" end
            if next(self.ui.document:getEmbeddedFontList()) == nil then return false, "当前书籍没有内嵌字体" end
        end
        return true
    end
    return self.ui.file_chooser ~= nil, "请从文件管理器打开本设置"
end

function Adapter:read(id, raw)
    local ok, why = self:available(id)
    if raw and id=="embedded_fonts" then ok=self:alive() and self.ui.font and self.ui.typeset end
    if not ok then return nil, nil, why end
    local b = bindings[id]
    if b then
        if id=="page_margins" then
            local c=self.ui.document.configurable
            return {c.h_page_margins[1],c.t_page_margin,c.h_page_margins[2],c.b_page_margin},"当前书籍"
        end
        local value = id=="font_face" and self.ui.font.font_face or self.ui.document.configurable[b.field]
        if b.boolean then value = value == 1 end -- Lua 0 is truthy.
        local source = self.ui.doc_settings:has(b.key) and "当前书籍" or
            (G_reader_settings:has(b.global_key or b.key) and "全局默认" or "程序默认")
        return value, source
    elseif id == "sort" then
        local _, key = self.ui.file_chooser:getCollate()
        return key, "全局"
    elseif id == "show_hidden" then
        return FileChooser.show_hidden == true, "全局"
    end
    error("Unknown setting: "..tostring(id))
end

function Adapter:choices(id)
    if id == "font_face" then
        local t,seen={},{}
        for _,info in pairs(require("fontlist").fontinfo) do
            local face=info[1].name
            if not seen[face] then t[#t+1]={face,face};seen[face]=true end
        end
        table.sort(t,function(a,b) return a[1]<b[1] end)
        return t
    end
    if id == "sort" then
        local keys, labels = require("apps/filemanager/filemanager").getSortByActions()
        local t = {}
        for i, k in ipairs(keys) do t[#t+1] = {k, labels[i]} end
        return t
    end
    return Registry.by_id[id].choices
end

function Adapter:gammaLabel(index)
    for _,group in ipairs(require("ui/data/creoptions")) do for _,option in ipairs(group.options or {}) do
        if option.name=="font_gamma" then return tostring(option.more_options_param.value_table[index+1]).."×" end
    end end
    return tostring(index)
end

function Adapter:validate(id, value)
    local item = assert(Registry.by_id[id], "Unknown setting")
    if item.kind=="pair" then
        assert(type(value)=="table" and #value==2,"需要缩放和收缩两个百分比")
        for i,v in ipairs(value) do assert(type(v)=="number" and v==v and v%1==0 and v>=(i==1 and 10 or 25) and v<=(i==1 and 500 or 100),"词间距数值超出范围") end
    elseif item.kind=="margins" then
        assert(type(value)=="table" and #value==4,"需要左、上、右、下四个边距")
        for _,v in ipairs(value) do assert(type(v)=="number" and v==v and v%1==0 and v>=0 and v<=140,"边距需为0至140的整数") end
    elseif item.kind == "toggle" then assert(type(value)=="boolean", "需要布尔值")
    elseif item.kind == "number" then
        assert(type(value)=="number" and value==value and value%(item.fractional and item.step or 1)==0 and value>=item.min and value<=item.max, "数值超出范围")
    else
        local found = false
        for _, choice in ipairs(self:choices(id)) do if choice[1] == value then found=true end end
        assert(found, "无效的选项")
    end
end

function Adapter:_apply(id, value)
    local b = bindings[id]
    if id=="page_margins" then
        local c=self.ui.document.configurable
        c.h_page_margins={value[1],value[3]};c.t_page_margin=value[2];c.b_page_margin=value[4]
        if value[2]~=value[4] then c.sync_t_b_page_margins=0;self.ui.typeset.sync_t_b_page_margins=false end
        self.ui.typeset.unscaled_margins={unpack(value)}
        self.ui:handleEvent(Event:new("SetPageMargins",value))
    elseif b then self.ui:handleEvent(Event:new(b.event, value))
    elseif id == "sort" then self.ui:onSetSortBy(value)
    elseif id == "show_hidden" and (FileChooser.show_hidden == true) ~= value then
        self.ui.file_chooser:toggleShowFilesMode("show_hidden")
    end
end

function Adapter:_persist(id, expected)
    local b = bindings[id]
    if b then
        -- readerui.lua:saveSettings emits SaveSettings, flushes the document and globals.
        self.ui:saveSettings()
        local doc=DocSettings:open(self.ui.document.file)
        if id=="page_margins" then
            local h=doc:readSetting("copt_h_page_margins")
            assert(h and h[1]==expected[1] and h[2]==expected[3] and doc:readSetting("copt_t_page_margin")==expected[2]
                and doc:readSetting("copt_b_page_margin")==expected[4],"页边距未能写入")
            return
        end
        local stored = doc:readSetting(b.key)
        local wanted = b.boolean and (expected and 1 or 0) or expected
        assert(Adapter.equal(stored,wanted), "当前书籍设置未能写入，请检查存储空间与文件权限")
    else
        G_reader_settings:flush()
        local stored = LuaSettings:open(G_reader_settings.file):readSetting(id=="sort" and "collate" or "show_hidden")
        assert(stored == expected, "全局设置未能写入，请检查存储空间与文件权限")
    end
end

function Adapter:set(id, value)
    local old
    local ok, err = pcall(function()
        assert(Adapter.supported(), "当前 KOReader 版本未经适配")
        local available, why = self:available(id)
        assert(available, why)
        self:validate(id, value)
        old = self:read(id)
        self:_apply(id, value)
        assert(Adapter.equal(self:read(id),value), "运行值与请求值不同")
        self:_persist(id, value)
    end)
    if ok then return true, "已生效并读回保存值" end
    local rollback_ok, rollback_err = true, nil
    if old ~= nil then
        rollback_ok, rollback_err = pcall(function()
            self:_apply(id, old)
            assert(Adapter.equal(self:read(id),old), "运行值恢复失败")
            self:_persist(id, old)
        end)
    end
    return false, tostring(err)..(rollback_ok and "；未保留本次修改" or "；恢复也失败："..tostring(rollback_err))
end

function Adapter:dispatch(event,...)
    assert(self:alive(), "阅读上下文已关闭")
    return self.ui:handleEvent(Event:new(event,...))
end

function Adapter:recent()
    local t = {}
    for _, entry in ipairs(require("readhistory").hist) do
        if not entry.dim then t[#t+1] = {title=entry.text, file=entry.file} end
        if #t == 5 then break end
    end
    return t
end

function Adapter:openBook(file)
    require("apps/reader/readerui"):showReader(file)
end

function Adapter:libraryRoot()
    if self.ui.file_chooser then return self.ui.file_chooser.path end
    return self.ui.document and self.ui.document.file:match("^(.*)/[^/]+$") or "/mnt/us/documents"
end

function Adapter:promptText(title,initial,callback,options)
    if self.app and not require('einkfrontend/context').alive(self.app) then return end
    local InputDialog=require("ui/widget/inputdialog")
    local UIManager=require("ui/uimanager")
    local dialog;local resolved=false
    local valid=self.app and self.app:dialogGuard() or function() return true end
    options=options or {}
    dialog=InputDialog:new{title=title,input=initial or "",radius=0,allow_newline=options.multiline or false,input_type=options.input_type,
        text_height=options.multiline and require("device").screen:scaleBySize(120) or nil,
        buttons={{{text="取消",callback=function() resolved=true;UIManager:close(dialog) end},
            {text="确定",callback=function()
                if resolved or not valid() or not UIManager:isWidgetShown(dialog) then resolved=true;UIManager:close(dialog);return end
                local text=dialog:getInputText()
                if options.keep_on_error then
                    local ok,accepted=pcall(callback,text)
                    if not ok then
                        UIManager:show(require("ui/widget/infomessage"):new{text=tostring(accepted)})
                    elseif accepted~=false then resolved=true;UIManager:close(dialog) end
                else resolved=true;UIManager:close(dialog);callback(text) end
            end}}}}
    if self.app then self.app:trackDialog(dialog) end
    UIManager:show(dialog);dialog:onShowKeyboard()
    return dialog
end

function Adapter:chooseLibraryRoot(current,callback)
    if self.app and not require('einkfrontend/context').alive(self.app) then return end
    local UIManager=require("ui/uimanager")
    local chooser;local resolved=false
    local valid=self.app and self.app:dialogGuard() or function() return true end
    chooser=require("ui/widget/pathchooser"):new{path=current,select_directory=true,select_file=false,
        title="选择书库目录：长按文件夹确认",onConfirm=function(path)
            if resolved or not valid() then return end;resolved=true
            -- PathChooser closes itself after onConfirm returns.
            callback(path)
        end}
    if self.app then self.app:trackDialog(chooser) end
    UIManager:show(chooser)
    return chooser
end

function Adapter:gotoPercent(number)
    assert(self.ui.document and self:alive(),"请先打开书籍")
    assert(type(number)=="number" and number>=0 and number<=100,"请输入0至100的百分比")
    if not self.jump_origin then
        self.jump_origin=self.ui.rolling and {xpointer=self.ui.document:getXPointer()} or {page=self.ui:getCurrentPage()}
    end
    self.ui:handleEvent(Event:new("GotoPercent",number))
end

function Adapter:returnFromJump()
    assert(self:alive() and self.ui.document and self.jump_origin,"没有可返回的位置")
    local origin=self.jump_origin
    if origin.xpointer then self.ui:handleEvent(Event:new("GotoXPointer",origin.xpointer))
    else self.ui:handleEvent(Event:new("GotoPage",origin.page)) end
    self.jump_origin=nil
end

-- Optional upstream action contract, not a bundled Kindle conversion pipeline.
function Adapter:hasKindleLibrary()
    local plugin=self.ui.kindle_plugin
    return type(plugin)=="table" and type(plugin.onShowKindleLibrary)=="function"
end

function Adapter:deviceStatus()
    local Device=require("device")
    local power=Device:getPowerDevice()
    return {frontlight=Device:hasFrontlight(),wifi=Device:hasWifiToggle(),
        battery=Device:hasBattery() and power:getCapacity() or nil,
        low=power.fl_min,high=power.fl_max,intensity=power:frontlightIntensity(),
        night=G_reader_settings:isTrue("night_mode"),sync=self.ui.kosync~=nil}
end

function Adapter:setFrontlight(value)
    local state=self:deviceStatus()
    assert(state.frontlight and type(value)=="number" and value==value and value%1==0 and value>=state.low and value<=state.high,"前光数值超出设备范围")
    local power=require("device"):getPowerDevice()
    power:setIntensity(value)
    assert(power:frontlightIntensity()==value,"设备前光未能生效")
    power:updateResumeFrontlightState()
    if self.app and self.app.autolight then self.app.autolight:manual(value,true) end
end

function Adapter:toggleNightMode()
    local old=G_reader_settings:isTrue("night_mode")
    local ok,err=pcall(function()
        self:dispatch("ToggleNightMode");G_reader_settings:flush()
        assert(LuaSettings:open(G_reader_settings.file):isTrue("night_mode")~=old,"夜间模式未能保存")
    end)
    if not ok then
        if G_reader_settings:isTrue("night_mode")~=old then self:dispatch("ToggleNightMode") end
        pcall(G_reader_settings.flush,G_reader_settings)
        error(err)
    end
end

function Adapter:showWifi()
    assert(self:deviceStatus().wifi,"当前设备不支持 Wi-Fi 控制")
    require("ui/network/manager"):promptWifi(nil,false,true)
end

function Adapter:openKindleLibrary()
    assert(self:alive() and self:hasKindleLibrary(),"请先安装并启用 kindle.koplugin")
    Adapter.suppress_next_start=self.ui.document~=nil or nil
    local ok,handled=pcall(self.ui.handleEvent,self.ui,Event:new("ShowKindleLibrary"))
    Adapter.suppress_next_start=nil
    assert(ok and handled,"Kindle 书库未能打开；请检查该插件设置")
end

function Adapter:returnToLibrary(shell)
    assert(self:alive() and self.ui.document,"请先打开书籍")
    local gate=self.app and self.app.plugin.gate
    if gate then gate:native(function() self.ui:onHome() end) else self.ui:onHome() end
    -- onHome may reuse an existing FileManager, which never runs plugin init.
    -- Complete the handoff against its actual live plugin instead of relying
    -- solely on a startup flag or post-init task to reopen the shell.
    local fm=require("apps/filemanager/filemanager").instance
    local target=fm and fm.einkfrontend
    if target and target.active and target.adapter:alive() then
        if target.pending_open then
            require("ui/uimanager"):unschedule(target.pending_open);target.pending_open=nil
        end
        Adapter.shell_requested=nil;Adapter.library_requested=nil
        target.app:safe(function() target.app:open(shell=="home" and "home" or "library") end)
    end
end

function Adapter.equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not Adapter.equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
Adapter.bindings=bindings
return Adapter
