-- Run inside the extracted official KOReader runtime, with isolated KO_HOME.
require("setupkoenv")
local mode=arg[1] or "write"
package.path="plugins/einkfrontend.koplugin/?.lua;"..package.path
require("logger"):setLevel(require("logger").levels.warn)
G_defaults=require("luadefaults"):open()
local DS=require("datastorage")
G_reader_settings=require("luasettings"):open(DS:getDataDir().."/settings.reader.lua")
G_reader_settings:saveSetting("language","zh_CN")
require("gettext").changeLang("zh_CN")
G_reader_settings:saveSetting("eink_frontend",{auto_open=mode=="auto_start",reader_entry=true})
G_reader_settings:saveSetting("document_metadata_folder","dir")
G_reader_settings:saveSetting("dev_no_c_blitter",false)
require("ffi/blitbuffer"):enableCBB(true)
local Device=require("device")
require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager")
local Event=require("ui/event")
local Key=require("device/key")
local FM=require("apps/filemanager/filemanager")
local Reader=require("apps/reader/readerui")
local DocSettings=require("docsettings")
local Adapter=mode~="uninstalled" and require("einkfrontend/adapter") or nil
local root=assert(os.getenv("EINK_PROJECT"))
local A=root.."/tests/fixtures/A.epub"
local B=root.."/tests/fixtures/B.epub"
local results={mode=mode,tests={}}
local function check(name,fn)
    local ok,err=pcall(fn)
    results.tests[#results.tests+1]={name=name,status=ok and "PASS" or "FAIL",error=not ok and tostring(err) or nil}
    print((ok and "PASS " or "FAIL ")..name..(not ok and (": "..tostring(err)) or ""))
    if not ok then error(err) end
end
local function shot(name)
    -- Dismiss native first-run notifications before taking a page-only QA image.
    local keep={}
    for _,window in ipairs(UI._window_stack) do
        local widget=window.widget
        if widget.text and widget~=Reader.instance and widget~=FM.instance then keep[#keep+1]=widget end
    end
    for _,widget in ipairs(keep) do UI:close(widget) end
    UI:forceRePaint()
    assert(not (Reader.instance and Reader.instance.einkfrontend.app.screen and Reader.instance.einkfrontend.app.screen.paint_fault),"Paint fault")
    name=name:gsub("600x800",Device.screen:getWidth().."x"..Device.screen:getHeight())
    Device.screen:shot(root.."/test-results/"..name..".png")
end
local function closeReader()
    if Reader.instance then Reader.instance:onClose() end
end
local function open(file)
    Reader:doShowReader(file)
    assert(Reader.instance and Reader.instance.document)
    return Reader.instance,Reader.instance.einkfrontend
end
local function ticks(count)
    for i=1,count or 10 do UI:shiftScheduledTasksBy(-require("ui/time").s(0.02));UI:_checkTasks() end
end

if mode=="write" then
    FM:showFiles(root.."/tests/fixtures")
    local p=assert(FM.instance.einkfrontend)
    check("plugin loads in FileManager",function() assert(p.active) end)
    check("independent fullscreen route and back",function()
        p:onEInkFrontendOpen();assert(p.app.screen.covers_fullscreen)
        p.app:go("settings");p.app:go("section","files");p.app:go("setting","show_hidden")
        assert(#p.app.stack==4);p.app:back();assert(#p.app.stack==3)
        p.app:back();shot("settings-600x800")
        p.app:close();assert(not p.app.screen)
    end)
    check("global hidden files setter is idempotent and persisted",function()
        local a=p.adapter
        assert(a:set("show_hidden",true));assert(a:read("show_hidden")==true)
        assert(a:set("show_hidden",true));assert(a:read("show_hidden")==true)
    end)
    check("global sort validates and persists",function()
        local choices=p.adapter:choices("sort")
        local previous=p.adapter:read("sort")
        local target=choices[1][1]
        for _,choice in ipairs(choices) do if choice[1]~=previous then target=choice[1];break end end
        assert(target~=previous)
        assert(p.adapter:set("sort",target))
        G_reader_settings:saveSetting("eink_test_expected_sort",target)
        G_reader_settings:flush()
        local ok=p.adapter:set("sort","__invalid__");assert(not ok)
    end)
    FM.instance:onClose()
    local r,plugin=open(A)
    check("plugin loads in ReaderUI and registers reader entry zones",function()
        assert(plugin.active and plugin.zones and #plugin.zones==3)
        assert(r._zones.einkfrontend_reader_panel)
    end)
    local changes={{"embedded_css",false},{"font_hinting",1},{"font_size",28},{"line_spacing",125},{"font_kerning",2}}
    for _,change in ipairs(changes) do
        local id,v=change[1],change[2]
        check("setting roundtrip "..id,function()
            local ok,err=plugin.adapter:set(id,v);assert(ok,err);assert(plugin.adapter:read(id)==v)
        end)
    end
    check("installed font choice applies and persists",function()
        local choices=plugin.adapter:choices("font_face")
        assert(#choices>0)
        local ok,err=plugin.adapter:set("font_face",choices[1][1]);assert(ok,err)
        assert(r.document:getFontFace()==choices[1][1])
    end)
    check("boolean off passes false rather than Lua numeric zero",function()
        assert(r.document.configurable.embedded_css==0)
        assert(DocSettings:open(A):readSetting("copt_embedded_css")==0)
    end)
    check("invalid value preserves previous configuration",function()
        local old=plugin.adapter:read("font_size")
        local ok=plugin.adapter:set("font_size",0/0);assert(not ok)
        assert(plugin.adapter:read("font_size")==old)
        ok=plugin.adapter:set("font_size",256);assert(not ok)
        ok=plugin.adapter:set("embedded_css",0);assert(not ok)
    end)
    check("unsupported embedded fonts stay disabled",function()
        local available=plugin.adapter:available("embedded_fonts");assert(not available)
    end)
    check("reader centre tap opens bottom menu and PagePress cannot turn underlying book",function()
        assert(plugin.zones[1].handler())
        assert(plugin.app.reader_panel)
        local page=r:getCurrentPage()
        plugin.app.reader_panel:onKeyPress(Key:new("RPgFwd",{}))
        plugin.app.reader_panel:onKeyRepeat(Key:new("LPgBack",{}))
        assert(r:getCurrentPage()==page)
        plugin.app:go("settings");shot("reader-settings-600x800")
        plugin.app:go("section","reading");shot("reading-options-600x800")
        plugin.app:go("setting","font_size");shot("font-size-600x800")
        assert(r.document:getFontSize()==Device.screen:scaleBySize(28))
        plugin.app:close()
    end)
    check("real tap event changes value through custom setting controls",function()
        plugin:onEInkFrontendOpen();plugin.app:go("setting","font_size")
        UI:forceRePaint()
        local s=plugin.app.screen
        local y=s.header_h+s.info_h+2*s.row_h+10
        assert(s:handleEvent(Event:new("Gesture",{ges="tap",pos=require("ui/geometry"):new{x=40,y=y,w=0,h=0}})))
        assert(plugin.adapter:read("font_size")==29)
        assert(plugin.adapter:set("font_size",28))
        plugin.app:close()
    end)
    check("font choice scrolling and Enter activate the visible option",function()
        plugin:onEInkFrontendOpen();plugin.app:go("setting","font_face")
        local s=plugin.app.screen
        local old=plugin.adapter:read("font_face")
        if #s.model.rows>s.capacity then
            s:turn(1)
            local choice=plugin.adapter:choices("font_face")[s.focus_index][1]
            s:onKeyPress(Key:new("Enter",{}))
            assert(plugin.adapter:read("font_face")==choice)
            assert(plugin.adapter:set("font_face",old))
        end
        plugin.app:close()
    end)
    check("repeated zone setup stays unique and stop restores host",function()
        plugin:refreshReaderEntry();plugin:refreshReaderEntry()
        local n=0
        for _,zone in ipairs(r._ordered_touch_zones) do if zone.def.id=="einkfrontend_reader_panel" then n=n+1 end end
        assert(n==1)
        plugin:stopPlugin();assert(not r:checkRegisterTouchZone("einkfrontend_reader_panel") and not plugin.app.screen)
        plugin.active=true;plugin:refreshReaderEntry()
    end)
    closeReader()
    local bookb=open(B)
    check("another book does not inherit current-book changes",function()
        assert(bookb.document.configurable.font_size~=28)
        assert(bookb.document.configurable.font_hinting~=1)
        assert(bookb.document.configurable.embedded_css==1)
    end)
    closeReader()
elseif mode=="restart" then
    check("global values survive a new process",function() assert(G_reader_settings:readSetting("show_hidden")==true) end)
    FM:showFiles(root.."/tests/fixtures")
    check("changed global sort survives new process",function()
        assert(FM.instance.einkfrontend.adapter:read("sort")==G_reader_settings:readSetting("eink_test_expected_sort"))
    end)
    FM.instance:onClose()
    local r,p=open(A)
    check("font name survives new process",function()
        assert(p.adapter:read("font_face")==DocSettings:open(A):readSetting("font_face"))
    end)
    for _,change in ipairs({{"embedded_css",false},{"font_hinting",1},{"font_size",28},{"line_spacing",125},{"font_kerning",2}}) do
        check("new-process persistence "..change[1],function() assert(p.adapter:read(change[1])==change[2]) end)
    end
    closeReader()
elseif mode=="faults" then
    local r,p=open(A)
    check("persistence failure rolls back runtime value",function()
        local old=p.adapter:read("font_size")
        local original=p.adapter._persist
        local n=0
        p.adapter._persist=function(self,id,value) n=n+1;if n==1 then error("injected write failure") end;return original(self,id,value) end
        local ok=p.adapter:set("font_size",old+1)
        p.adapter._persist=original
        assert(not ok);assert(p.adapter:read("font_size")==old)
        assert(DocSettings:open(A):readSetting("copt_font_size")==old)
    end)
    check("callback error returns to native UI",function()
        p:onEInkFrontendOpen();p.app:safe(function() error("injected callback failure") end)
        assert(not p.app.screen);assert(Reader.instance==r and r.document)
    end)
    check("version mismatch prevents activation",function()
        local V=require("version");local old=V.rev;V.rev="v2099.01";assert(not Adapter.supported());V.rev=old
    end)
    closeReader()
elseif mode=="library" then
    FM:showFiles(root.."/tests/fixtures")
    local plugin=assert(FM.instance.einkfrontend)
    plugin:onEInkFrontendOpen();plugin.app:go("library")
    local lib=plugin.app.library
    check("asynchronous library scan extracts metadata",function()
        plugin.app:scanLibrary(root.."/tests/fixtures")
        for i=1,100 do
            UI:shiftScheduledTasksBy(-require("ui/time").s(0.05));UI:_checkTasks()
            if not lib.job then break end
        end
        assert(not lib.job and #lib.books==2)
        assert(lib.books[1].title:find("测试书",1,true))
        assert(#lib:groups("authors")==2)
        assert(#lib:groups("series")==1)
    end)
    check("cover extraction and missing-cover fallback",function()
        assert(lib:cover(A)~=nil)
        assert(lib:cover(B)==nil)
        plugin.app:go("books",{});shot("library-grid-600x800")
        assert(not plugin.app.screen.paint_fault)
    end)
    check("author, series, search and list filters",function()
        assert(#lib:list({field="authors",value="作者甲"})==1)
        assert(#lib:list({field="series",value="测试系列"})==1)
        assert(#lib:list(nil,nil,"测试书甲")==1)
        assert(#lib:list(nil,nil,"__no_match__")==0)
        plugin.app.library_layout="list";plugin.app:render();shot("library-list-600x800")
    end)
    check("native collection create, membership, persistence and removal",function()
        local name="墨页测试收藏"
        local rc=require("readcollection")
        if not rc.coll[name] then lib:createCollection(name) end
        lib:setCollection(A,name,true);lib:setCollection(A,name,true)
        assert(lib:inCollection(A,name))
        assert(#lib:list({collection=name})==1)
        lib:setCollection(A,name,false)
        assert(not lib:inCollection(A,name))
        assert(#lib:list({collection=name})==0)
        lib:setCollection(A,name,true)
        plugin.app:go("collections");shot("collections-600x800")
    end)
    check("book detail and returning keep page position",function()
        plugin.app:go("books",{})
        local page=plugin.app.screen.model.page
        plugin.app:go("book",lib.books[1]);shot("book-detail-600x800")
        plugin.app:back();assert(plugin.app.screen.model.page==page)
    end)
    check("series metadata edit, native readback and reset",function()
        local book
        for _,b in ipairs(lib.books) do if b.file==B then book=b end end
        assert(book)
        lib:setMetadata(book,"series","设备上新建的系列")
        lib:setMetadata(book,"series_index",2.5)
        local props=require("apps/filemanager/filemanagerbookinfo").extendProps({},B)
        assert(props.series=="设备上新建的系列" and props.series_index==2.5)
        assert(#lib:list({field="series",value="设备上新建的系列"})==1)
        lib:setMetadata(book,"series",nil);lib:setMetadata(book,"series_index",nil)
        assert(book.series=="")
    end)
    check("collection persistence failure restores membership",function()
        local name="墨页测试收藏"
        local rc=require("readcollection")
        lib:setCollection(B,name,false)
        local original,n=rc.write,0
        rc.write=function(self,...) n=n+1;if n==1 then error("injected collection failure") end;return original(self,...) end
        local ok=pcall(lib.setCollection,lib,B,name,true)
        rc.write=original
        assert(not ok and not lib:inCollection(B,name))
    end)
    check("text input control submits and returns to own page",function()
        local got
        local dialog=plugin.adapter:promptText("测试输入","测试文字",function(text) got=text end)
        assert(dialog:getInputText()=="测试文字")
        dialog.buttons[1][2].callback()
        assert(got=="测试文字" and plugin.app.screen)
    end)
    check("native directory picker confirms without duplicate close",function()
        local got
        local chooser=plugin.adapter:chooseLibraryRoot(root.."/tests/fixtures",function(path) got=path end)
        chooser:onMenuHold({path=root.."/tests/fixtures"})
        local dialog=assert(chooser.button_dialog)
        local row=dialog.buttons[#dialog.buttons]
        row[#row].callback()
        assert(got==root.."/tests/fixtures" and plugin.app.screen)
    end)
    check("closing a scan cancels scheduled work and returns native host",function()
        plugin.app:scanLibrary(root.."/tests/fixtures")
        plugin.app:close();assert(not lib.job and not lib.tick and not plugin.app.screen)
        assert(FM.instance and FM.instance.file_chooser)
    end)
    FM.instance:onClose()
elseif mode=="references" then
    FM:showFiles(root.."/tests/fixtures")
    local p=assert(FM.instance.einkfrontend)
    p:onEInkFrontendOpen()
    local app,lib=p.app,p.app.library
    local function state(file,status,percent)
        local doc=DocSettings:open(file)
        doc:saveSetting("summary",{status=status})
        doc:saveSetting("percent_finished",percent)
        doc:flush()
    end
    local function tapRow(index)
        app.screen.model.page=math.floor((index-1)/app.screen.capacity)+1
        UI:forceRePaint()
        local y=app.screen.header_h+app.screen.info_h+((index-1)%app.screen.capacity)*app.screen.row_h+20
        app.screen:onFrontendTap(nil,{pos={x=40,y=y}})
    end
    check("zero percent sidecar remains unread; finished and hold have explicit precedence",function()
        state(A,"reading",0);assert(lib:status({file=A})=="未读")
        state(A,"complete",0);assert(lib:status({file=A})=="已完成")
        state(A,"abandoned",0);assert(lib:status({file=A})=="搁置")
        state(A,"reading",0.25);state(B,"reading",0)
    end)
    check("combined status search author and collection filters share counts",function()
        local f={statuses={["在读"]=true,["未读"]=true},query="测试书"}
        assert(#lib:list(f)==2)
        f.statuses={["在读"]=true};assert(#lib:list(f)==1)
        local groups=lib:groups("authors",f)
        assert(#groups==1 and groups[1].count==1 and groups[1].name=="作者甲")
        f.field="authors";f.value="作者乙";assert(#lib:list(f)==0)
        f.field=nil;f.value=nil;f.collection="墨页测试收藏";assert(#lib:list(f)==1)
    end)
    check("recent reading sort uses history not file modification time and handles missing history",function()
        local rh=require("readhistory");local original=rh.hist
        rh.hist={{file=B,time=200,text="乙"},{file=A,time=100,text="甲"}}
        local list=lib:list({},"last_opened");assert(list[1].file==B)
        assert(lib:groups("authors",{},"last_opened")[1].name=="作者乙")
        rh.hist={{file=A,time=300,text="甲"}}
        list=lib:list({},"last_opened");assert(list[1].file==A)
        rh.hist=original
    end)
    check("each library tab keeps its own layout sort and nested destination",function()
        app:selectLibraryTab("books");app.library_layout="grid";app.library_sort="last_opened";app:render()
        app:selectLibraryTab("authors");app.library_layout="list";app:render()
        app:go("books",{field="authors",value="作者甲"})
        app:selectLibraryTab("books");assert(app.library_layout=="grid" and app.library_sort=="last_opened")
        app:selectLibraryTab("authors")
        assert(app.library_layout=="list" and app.stack[#app.stack].param.value=="作者甲")
    end)
    check("filter checkbox real tap preserves author context and applies across tabs",function()
        app.browser.filter={statuses={},query="测试书"}
        app:go("library_filter");UI:forceRePaint();tapRow(4)
        assert(app.browser.filter.statuses["在读"])
        app:back();assert(#app.screen.model.rows==1 and app.screen.model.rows[1].book.file==A)
        app:selectLibraryTab("authors");assert(app.stack[#app.stack].param.value=="作者甲")
        app:go("groups","authors");assert(#app.screen.model.rows==1)
        shot("library-combined-filter-600x800")
    end)
    check("search setting result opens own setting with a plain inert title",function()
        app:go("settings",nil,true);app:go("setting_search","字号")
        assert(#app.screen.model.rows==1);tapRow(1)
        assert(app.stack[#app.stack].param=="font_size")
        UI:forceRePaint()
        for _,hit in ipairs(app.screen.hits) do assert(hit.id~="settings_title") end
        app.screen:onFrontendTap(nil,{pos={x=Device.screen:getWidth()/2,y=20}})
        assert(app.stack[#app.stack].id=="setting")
        shot("settings-plain-title-600x800");app:back();app:back()
        assert(app.stack[#app.stack].id=="settings")
    end)
    check("optional Kindle library absence is safe and visible",function()
        assert(not p.adapter:hasKindleLibrary())
        assert(not pcall(p.adapter.openKindleLibrary,p.adapter))
        app:go("library_options",nil,true)
        local found=false
        for _,row in ipairs(app.screen.model.rows) do
            if row.title=="Kindle 原生书库" then found=true;assert(not row.callback) end
        end
        assert(found)
    end)
    check("PocketBook device panel opens by top swipe and leaves underlying route intact",function()
        app:go("settings",nil,true)
        local page=app.screen.model.page
        app.screen:onFrontendSwipe(nil,{direction="south",pos={x=20,y=0}})
        assert(app.controls and not app.controls.covers_fullscreen)
        shot("device-controls-600x800")
        assert(app.controls.panel_h<Device.screen:getHeight())
        app.controls:onKeyPress(Key:new("LPgFwd",{}))
        assert(app.screen.model.page==page and app.controls)
        app.controls:onControlTap(nil,{pos={x=20,y=app.controls.panel_h+10}})
        assert(not app.controls and app.stack[#app.stack].id=="settings")
    end)
    check("device panel night toggle changes live screen and persisted setting",function()
        app:showControls();local previous=G_reader_settings:isTrue("night_mode")
        UI:forceRePaint();local night
        for _,action in ipairs(app.controls:actions()) do if action[1]=="夜间模式" then night=action[2] end end
        assert(night);night()
        assert(G_reader_settings:isTrue("night_mode")~=previous)
        local stored=require("luasettings"):open(G_reader_settings.file):isTrue("night_mode")
        assert(stored~=previous)
        night();assert(G_reader_settings:isTrue("night_mode")==previous)
        app.controls:close()
    end)
    check("upward swipe dismisses device controls and ordinary library swipe still paginates",function()
        app:showControls();app.controls:onControlSwipe(nil,{direction="north"});assert(not app.controls)
        app:selectLibraryTab("books");local page=app.screen.model.page
        app.screen:onFrontendSwipe(nil,{direction="west",pos={x=40,y=200}})
        assert(not app.controls and app.screen.model.page>=page)
    end)
    check("frontlight slider uses device bounds and rejects invalid input without changing intensity",function()
        local state=p.adapter:deviceStatus()
        app:showControls();UI:forceRePaint()
        if state.frontlight then
            local slider=app.controls.slider
            app.controls:onControlTap(nil,{pos={x=slider.x+1,y=slider.y+5}})
            assert(p.adapter:deviceStatus().intensity==state.low)
            UI:forceRePaint();slider=app.controls.slider
            app.controls:onControlTap(nil,{pos={x=slider.x+slider.w-1,y=slider.y+5}})
            assert(p.adapter:deviceStatus().intensity==state.high)
            assert(not pcall(p.adapter.setFrontlight,p.adapter,state.high+1))
            assert(p.adapter:deviceStatus().intensity==state.high)
            p.adapter:setFrontlight(state.intensity)
        end
        app.controls:close()
    end)
    app.browser.filter={statuses={["在读"]=true,["未读"]=true},query="测试书"}
    app:selectLibraryTab("authors");app:go("groups","authors")
    app.library_layout="list";app.library_sort="last_opened";app:render();app:saveLibraryView()
    app:close();FM.instance:onClose()
elseif mode=="references_restart" then
    FM:showFiles(root.."/tests/fixtures")
    local p=assert(FM.instance.einkfrontend);p:onEInkFrontendOpen()
    check("new process restores per-tab destination layout sort and combined filter",function()
        local app=p.app
        assert(app.browser.active=="authors")
        assert(app.browser.filter.statuses["在读"] and app.browser.filter.statuses["未读"])
        assert(app.browser.filter.query=="测试书")
        app:go("library")
        assert(app.stack[#app.stack].id=="groups" and app.stack[#app.stack].param=="authors")
        assert(app.library_layout=="list" and app.library_sort=="last_opened")
        assert(#app.screen.model.rows==2)
        app.browser.filter={statuses={},query=""};app:saveLibraryView()
        app:selectLibraryTab("books")
    end)
    p.app:close();FM.instance:onClose()
elseif mode=="auto_start" then
    FM:showFiles(root.."/tests/fixtures");ticks()
    check("startup reaches own frontend without native menu",function()
        local p=assert(FM.instance.einkfrontend)
        assert(p.app.screen and p.app.screen.model.title)
        assert(p.app.screen.model.library);shot("library-startup-600x800")
        p.app:close()
    end)
    FM.instance:onClose()
    local r,p=open(A)
    p:onEInkFrontendOpen();shot("reader-panel-600x800");p.app:close();closeReader()
elseif mode=="reader_actions" then
    local r,p=open(A)
    for _,event in ipairs({"ShowToc","ShowBookmark","ShowFulltextSearchInput"}) do
        check("reader control action "..event,function()
            p:onEInkFrontendOpen();p.app:close()
            local before=#UI._window_stack
            p.adapter:dispatch(event)
            assert(#UI._window_stack>before)
            local to_close={}
            for _,window in ipairs(UI._window_stack) do if window.widget~=r then to_close[#to_close+1]=window.widget end end
            for _,widget in ipairs(to_close) do UI:close(widget) end
            assert(Reader.instance==r)
        end)
    end
    check("reader top down swipe opens separate device controls without changing book position",function()
        local before=r.document:getXPointer()
        local zone
        for _,entry in ipairs(p.zones) do if entry.id=="einkfrontend_controls" then zone=entry end end
        assert(zone)
        assert(r:handleEvent(Event:new("Gesture",{ges="swipe",direction="south",distance=200,time=require("ui/time").now(),
            pos=require("ui/geometry"):new{x=Device.screen:getWidth()/2,y=0,w=0,h=0}})))
        assert(p.app.controls and r.document:getXPointer()==before)
        p.app.controls:close();assert(not p.app.controls)
    end)
    check("invalid jump keeps own control page and does not move the book",function()
        p:onEInkFrontendOpen();local before=r.document:getXPointer()
        assert(not p.app:jump("wrong") and p.app.reader_panel and r.document:getXPointer()==before)
        p.app:close()
    end)
    check("native book does not inherit another book home return destination",function()
        local settings=p.app.library.settings
        local old_book=settings:readSetting("return_book")
        local old_stack=settings:readSetting("return_stack")
        settings:saveSetting("return_book",B);settings:saveSetting("return_stack",{{id="home"}})
        p.app:open("reader");assert(p.app.screen.model.rows[1].title=="返回书库")
        p.app:close()
        settings:saveSetting("return_book",old_book);settings:saveSetting("return_stack",old_stack);settings:flush()
    end)
    check("percentage jump reaches document",function()
        p.adapter:gotoPercent(50)
        local percent=r.rolling:getLastPercent()
        assert(percent>0.4 and percent<0.6)
    end)
    check("repeated percentage jumps return to original text anchor after typography change",function()
        local origin=p.adapter.jump_origin.xpointer
        local original_size=p.adapter:read("font_size")
        p.adapter:gotoPercent(75)
        assert(p.adapter:set("font_size",original_size+1))
        p.adapter:returnFromJump()
        assert(r.document:getXPointer()==origin and not p.adapter.jump_origin)
        assert(p.adapter:set("font_size",original_size))
    end)
    closeReader()
elseif mode=="pdf" then
    local r,p=open(root.."/tests/pdf/layout.pdf")
    check("PDF excludes EPUB typography and retains native reader",function()
        local available=p.adapter:available("font_size");assert(not available)
        p:onEInkFrontendOpen();p.app:go("section","reading");shot("pdf-disabled-settings-600x800")
        assert(not p.app.screen.paint_fault)
        p.app:close();assert(Reader.instance==r)
    end)
    closeReader()
elseif mode=="embedded" or mode=="embedded_restart" then
    local r,p=open(root.."/tests/embedded/embedded-font.epub")
    if mode=="embedded" then
        check("embedded-font availability and real toggle persistence",function()
            assert(p.adapter:available("embedded_fonts"))
            assert(p.adapter:set("embedded_fonts",false));assert(p.adapter:read("embedded_fonts")==false)
            assert(p.adapter:set("embedded_fonts",true));assert(p.adapter:read("embedded_fonts")==true)
            assert(p.adapter:set("embedded_fonts",false))
        end)
    else
        check("embedded font off survives new process",function() assert(p.adapter:read("embedded_fonts")==false) end)
    end
    closeReader()
elseif mode=="stress_flow" then
    FM:showFiles(root.."/tests/fixtures")
    local p=assert(FM.instance.einkfrontend)
    p:onEInkFrontendOpen()
    check("120-book scan yields, finishes, paginates and keeps detail position",function()
        p.app:scanLibrary(assert(os.getenv("EINK_STRESS_ROOT")))
        for i=1,1000 do ticks(1);if not p.app.library.job then break end end
        assert(not p.app.library.job and #p.app.library.books==120)
        p.app:go("books",{});p.app.screen:turn(1)
        assert(p.app.screen.model.page==2)
        p.app:go("book",p.app.library.books[10]);p.app:back()
        assert(p.app.screen.model.page==2)
    end)
    check("opening real book then returning restores library page",function()
        if not p:option("auto_open",true) then p:toggleOption("auto_open",true) end
        p.app:go("groups","authors")
        p.app:go("books",{field="authors",value="作者乙"})
        p.app.library_layout="list";p.app:render();p.app.screen:turn(1)
        p.app:openLibraryBook(p.app.library.books[10]);ticks(15)
        local r=assert(Reader.instance)
        local rp=assert(r.einkfrontend)
        rp.app:open("reader")
        rp.app:safe(rp.app.screen.model.rows[1].callback);ticks(15)
        local fm=assert(FM.instance)
        assert(fm.einkfrontend.app.screen)
        assert(fm.einkfrontend.app.screen.model.page==2)
        local returned=fm.einkfrontend.app
        assert(returned.stack[#returned.stack].param.field=="authors" and returned.library_layout=="list")
        returned:back();assert(returned.stack[#returned.stack].id=="groups")
        returned:close()
    end)
    check("Home entry opens and returns to its own Home source",function()
        local app=FM.instance.einkfrontend.app
        app:open("home");app:openRecentBook(A);ticks(15)
        local p=assert(Reader.instance.einkfrontend);p.app:open("reader")
        assert(p.app.screen.model.rows[1].title=="返回主页")
        p.app.screen.model.rows[1].callback();ticks(15)
        assert(FM.instance.einkfrontend.app.screen.model.home)
        FM.instance.einkfrontend.app:close()
    end)
    if FM.instance then FM.instance:onClose() end
elseif mode=="disable" then
    local r,p=open(A)
    check("disabling plugin removes UI and reader zone",function()
        p:onEInkFrontendOpen();p:disableFrontend()
        assert(not p.active and not p.app.screen)
        assert(not r:checkRegisterTouchZone("einkfrontend_reader_panel"))
        assert(G_reader_settings:readSetting("plugins_disabled").einkfrontend==true)
    end)
    closeReader()
elseif mode=="native_restart" or mode=="uninstalled" then
    local r=open(A)
    check("disabled plugin stays disabled after new process",function()
        assert(r.einkfrontend==nil)
        assert(r.document:getFontSize()==Device.screen:scaleBySize(28))
        assert(r.document.configurable.embedded_css==0)
    end)
    closeReader()
end
local variant=os.getenv("EINK_VARIANT") or "desktop"
results.variant=variant
results.width=Device.screen:getWidth();results.height=Device.screen:getHeight()
local f=assert(io.open(root.."/test-results/"..mode.."-"..variant..".json","w"))
f:write(require("rapidjson").encode(results));f:close()
print("COMPLETE "..mode)
