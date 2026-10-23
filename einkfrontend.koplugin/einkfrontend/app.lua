-- Original project code. SPDX-License-Identifier: AGPL-3.0-or-later
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Registry = require("einkfrontend/registry")
local Page = require("einkfrontend/screen")
local Library = require("einkfrontend/library")
local Browser = require("einkfrontend/browser")
local Overlay=require("einkfrontend/overlay")
local Context=require("einkfrontend/context")
local App = {}
App.__index = App

function App.new(plugin, adapter)
    local library=Library.new(plugin.ui)
    local view=library.settings:readSetting("view_state") or {}
    local browser=Browser.new(library.settings)
    local tab=browser.tabs[browser.active]
    local self=setmetatable({plugin=plugin,adapter=adapter,library=library,browser=browser,
        stack={},status="墨页",library_layout=tab.layout,library_sort=tab.sort},App)
    adapter.app=self;self.dialogs=setmetatable({},{__mode='k'})
    self.native=require("einkfrontend/native").new(self)
    self.themes=require("einkfrontend/themes").new()
    self.home_layout=require("einkfrontend/homelayout").new()
    self.book_value=require("einkfrontend/bookvalue").new(library)
    if plugin.active then self.clock=require("einkfrontend/clock").new(self) end
    if plugin.active then self.typography=require("einkfrontend/typography").new(adapter) end
    if plugin.active then self.pagepress=require("einkfrontend/pagepress").attach(self) end
    return self
end

function App:safe(fn)
    local ok,err=pcall(fn)
    if not ok then self:fail(err) end
    return true
end

-- Expected input/write errors stay local; they must not disable the frontend.
function App:userAction(fn)
    local ok,why=pcall(fn)
    if not ok then self:message(why) end
    return ok,why
end

function App:newCollection()
    return self.adapter:promptText("新建收藏","",function(name)
        return self:userAction(function()
            self.library:createCollection(name);self.status="收藏已保存";self:render()
        end)
    end,{keep_on_error=true})
end

function App:fail(err)
    require("logger").err("EInkFrontend:",err)
    pcall(self.plugin.stopPlugin,self.plugin)
    pcall(self.close,self)
    UIManager:show(InfoMessage:new{text="前端操作失败，已返回原生界面。\n"..tostring(err)})
end

function App:open(route,param)
    if type(route)=="string" and route:match("^plugin_update") then route="about";param=nil end
    if not Context.alive(self) then return end
    self:closeDialogs()
    Overlay.close(self)
    if self.reader_topbar then self.reader_topbar:close() end
    if route=="home" then self.shell_page="home" end
    if self.reader_panel then self.reader_panel:close() end
    if self.controls then self.controls:close() end
    if self.library_popup then self.library_popup:close() end
    if not self.adapter:alive() then return end
    if not route or route=="library" then
        self.shell_page="library"
        self:saveLibraryView()
        local resume=self.library.settings:readSetting("resume_library")
        local routes=resume and self.library.settings:readSetting("return_stack")
        routes=routes and self.browser:routes(routes)
        self.stack=Browser.copy(routes and #routes>0 and routes or self.browser.tabs[self.browser.active].stack)
        self.library_layout=self.browser.tabs[self.browser.active].layout
        self.library_sort=self.browser.tabs[self.browser.active].sort
        self.library.settings:delSetting("resume_library");self.library.settings:flush()
        if self.native then self.native:retire() end
        if self.screen then self.screen.focus_index=1;return self:render() end
    elseif route=="home" then
        self:saveLibraryView()
        local context=self.library.settings:readSetting("return_context")
        if type(context)~="table" then context=nil end
        local resume=self.library.settings:readSetting("resume_library")
        local home=resume and context and context.shell=="home" and context.home_route
        if type(home)~="table" or home.id~="home" then home={id="home",page=1} end
        self.stack={{id="home",page=1,scroll_y=type(home.scroll_y)=="number" and home.scroll_y==home.scroll_y and home.scroll_y<math.huge and math.max(0,home.scroll_y) or 0}}
        self.library.settings:delSetting("resume_library");self.library.settings:flush()
        if self.native then self.native:retire() end
        if self.screen then return self:render() end
    elseif self.screen then return self:go(route,param,true)
    else self.stack={{id=route,param=param,page=1}} end
    self.screen=Page:new{app=self}
    self:render()
    UIManager:show(self.screen,"ui")
end

function App:close()
    self:closeDialogs()
    if self.transfer_server then self.transfer_server:stop() end
    Overlay.close(self)
    if self.reader_topbar then self.reader_topbar:close() end
    if self.library_popup then self.library_popup:close() end
    if self.reader_panel then self.reader_panel:close() end
    if self.native then self.native:retire() end
    if self.controls then self.controls:close() end
    self:saveLibraryView()
    local page=self.screen
    if page then UIManager:close(page,"full") end
    self.screen=nil
    self.stack={}
    self.library:close()
end

-- User dismissal stays inside the replacement shell; internal close still tears it down.
function App:dismiss()
    if self.plugin.ui.document or not self.plugin.active then return self:close() end
    return self:open(self.shell_page=="home" and "home" or "library")
end

function App:showControls()
    if not self.adapter:alive() then return end
    return Overlay.present(self,"controls",function() return require("einkfrontend/controls"):new{app=self} end)
end

function App:go(id,param,replace)
    if type(id)=="string" and id:match("^plugin_update") then id="about";param=nil end
    if not Context.alive(self) then return end
    self:closeDialogs()
    if id=="home_customize" then return self:showHomeEditor(param) end
    if id=="home" then return self:open("home") end
    if not self.screen then return self:open(id,param) end
    self:saveLibraryView()
    if id=="library" then return self:selectLibraryTab(self.browser.active) end
    if self.screen.model then self.stack[#self.stack].page=self.screen.model.page end
    local next_route={id=id,param=param,page=1}
    if replace then self.stack={next_route} else self.stack[#self.stack+1]=next_route end
    local tab=Browser.tab(next_route)
    if tab and tab~=self.browser.active then
        self.library_layout=self.browser.tabs[tab].layout;self.library_sort=self.browser.tabs[tab].sort
    end
    self.screen.focus_index=1
    self.status="墨页"
    self:render()
end

function App:back()
    if not Context.alive(self) then return end
    self:closeDialogs()
    if #self.stack<=1 then return self:dismiss() end
    if self.stack[#self.stack].id=="native" and self.native:back() then return end
    self:saveLibraryView()
    table.remove(self.stack)
    local tab=Browser.tab(self.stack[#self.stack])
    if tab and tab~=self.browser.active then
        self.library_layout=self.browser.tabs[tab].layout;self.library_sort=self.browser.tabs[tab].sort
    end
    self.screen.focus_index=1
    self:render()
end

function App:change(item,value)
    local ok,message
    if item.section=="reading" and self.typography then ok,message=self.typography:change(item.id,value)
    else ok,message=self.adapter:set(item.id,value) end
    self.status=ok and "已生效 · 已读回保存值" or "保存失败 · 详见提示"
    if not ok then UIManager:show(InfoMessage:new{text=message}) end
    self:render()
end

function App:showSettingsMore()
 if not Context.allowed(self,'settings_popup') then return end
 local popup=Overlay.present(self,'settings_popup',function()
  return require('einkfrontend/settingspopup'):new{app=self}
 end)
 UIManager:setDirty(self.screen,'ui')
 return popup
end

function App:scanLibrary(path)
    local transfer=require('einkfrontend/transfersettings');local config=transfer.config()
    if config.configured and config.path~=path then
        path=require('einkfrontend/transferstore').directory(path,false)
        local old=config.path;config.path=path;G_reader_settings:saveSetting('eink_transfer',config)
        if G_reader_settings:flush()==false then config.path=old;error('无法保存书库目录') end
        if self.transfer_server then self.transfer_server:stop() end
    end
    self.status="正在整理书库，可随时退出"
    self.library:scan(path,function(ok,message)
        if not self.screen then return end
        self.status=message
        if ok==false then
            UIManager:show(InfoMessage:new{text="书库整理失败："..message})
        end
        self:render()
    end)
    self:render()
end

function App:rememberReadingOrigin(file)
    self:saveLibraryView()
    local route=self.stack[#self.stack]
    local shell=route and route.id=="home" and "home" or "library"
    local routes=self.browser:routes(self.stack)
    if #routes==0 then routes=Browser.copy(self.browser.tabs[self.browser.active].stack) end
    local origin={version=1,file=file,shell=shell,routes=routes,
        home_route=shell=="home" and {id="home",page=1,scroll_y=route.scroll_y or 0} or nil}
    self.library.settings:saveSetting("return_context",origin)
    self.library.settings:saveSetting("return_stack",routes)
    self.library.settings:saveSetting("return_book",file)
    self.library.settings:saveSetting("resume_library",true);self.library.settings:flush()
end
function App:openLibraryBook(book)
    self:rememberReadingOrigin(book.file)
    self:close();self.adapter:openBook(book.file)
end

function App:saveLibraryView()
    local view={layout=self.library_layout,sort=self.library_sort}
    for _,route in ipairs(self.stack) do
        if route.id=="books" then
            view.filter=route.param
            view.page=(self.screen and self.screen.model and self.screen.model.route==route) and self.screen.model.page or route.page
        end
    end
    self.library.settings:saveSetting("view_state",view)
    if self.screen and self.screen.model and self.stack[#self.stack]==self.screen.model.route then
        self.stack[#self.stack].page=self.screen.model.page
    end
    self.browser:remember(self.stack,self.library_layout,self.library_sort)
    self.browser:save()
end


function App:selectLibraryTab(tab)
    self:saveLibraryView()
    local saved=assert(self.browser.tabs[tab])
    self.stack=Browser.copy(saved.stack)
    self.library_layout=saved.layout;self.library_sort=saved.sort
    self.browser.active=tab
    self.screen.focus_index=1
    self:render();self:saveLibraryView()
end

function App:cycleLibrarySort()
    self.library_sort=({title="author",author="last_opened",last_opened="recent",recent="title"})[self.library_sort] or "title"
    self:render();self:saveLibraryView()
end

function App:searchLibrary()
    local route=self.stack[#self.stack]
    local tab=route and Browser.tab(route)
    local grouped=tab and route.param and (route.param.field or route.param.collection)
    return self.adapter:promptText(grouped and "搜索当前分类的书籍" or "搜索书库",self.browser.filter.query or "",function(query) self:userAction(function()
        if not self.screen then return end
        self.browser.filter.query=query;self:resetLibraryPages()
        if not tab then self:go("books",{}) else self:render() end
        self:saveLibraryView()
    end) end)
end

function App:showLibraryMenu(kind)
    if not Context.allowed(self,'library_popup') or (kind~='filter' and kind~='sort' and kind~='more') then return end
    local popup=Overlay.present(self,"library_popup",function() return require("einkfrontend/librarypopup"):new{app=self,kind=kind} end)
    if popup then popup.kind=kind;UIManager:setDirty(popup,"ui") end;return popup
end

function App:libraryToolbar()
    local tabs={}
    for _,entry in ipairs({{"书籍","books"},{"作者","authors"},{"系列","series"},{"收藏","collections"}}) do
        local tab=entry[2]
        tabs[#tabs+1]={(self.browser.active==tab and "■ " or "")..entry[1],function() self:selectLibraryTab(tab) end}
    end
    return {tabs,{{"筛选",function() self:go("library_filter") end},
        {self.library_layout=="grid" and "列表" or "封面",function()
            self.library_layout=self.library_layout=="grid" and "list" or "grid";self:render();self:saveLibraryView()
        end},{"排序",function() self:cycleLibrarySort() end},{"搜索",function()
            self.adapter:promptText("搜索书库",self.browser.filter.query or "",function(query) self:safe(function()
                self.browser.filter.query=query
                self:resetLibraryPages();self:render();self:saveLibraryView()
            end) end)
        end}}}
end

function App:resetLibraryPages()
    for _,tab in pairs(self.browser.tabs) do for _,route in ipairs(tab.stack) do route.page=1 end end
    for _,route in ipairs(self.stack) do if Browser.tab(route) then route.page=1 end end
    if self.screen and self.screen.model then self.screen.model.page=1 end
    self.browser:save()
end

function App:openRecentBook(file)
    self:rememberReadingOrigin(file)
    self:close();self.adapter:openBook(file)
end
function App:readingOrigin()
    local file=self.plugin.ui.document and self.plugin.ui.document.file
    local context=self.library.settings:readSetting("return_context")
    if type(context)=="table" and context.version==1 and context.file==file and (context.shell=="home" or context.shell=="library") then
        local clean={version=1,file=file,shell=context.shell,routes=self.browser:routes(context.routes)}
        local home=context.home_route
        if type(home)=="table" and home.id=="home" then
            clean.home_route={id="home",page=1,scroll_y=type(home.scroll_y)=="number" and home.scroll_y==home.scroll_y and home.scroll_y<math.huge and math.max(0,home.scroll_y) or 0}
        end
        return clean
    end
    return {shell="library",routes=self:readingReturnStack()}
end
function App:readingReturnLabel() return self:readingOrigin().shell=="home" and "主页" or "书库" end

function App:readingReturnStack()
    local file=self.plugin.ui.document and self.plugin.ui.document.file
    if file and self.library.settings:readSetting("return_book")==file then
        local routes=self.browser:routes(self.library.settings:readSetting("return_stack") or {})
        if #routes>0 then return Browser.copy(routes) end
    end
    return Browser.copy(self.browser.tabs[self.browser.active].stack)
end

function App:returnToOrigin()
    local context=self:readingOrigin()
    self.library.settings:saveSetting("return_stack",context.routes)
    self.library.settings:saveSetting("resume_library",true);self.library.settings:flush()
    require("einkfrontend/adapter").shell_requested=context.shell
    self:close();self.adapter:returnToLibrary()
end
-- Compatibility name for existing callers; the destination follows book provenance.
function App:returnToLibrary() return self:returnToOrigin() end

function App:jump(text)
    local n=tonumber(text)
    if not n or n~=n or n<0 or n>100 then
        UIManager:show(InfoMessage:new{text="请输入0至100的百分比"});return false
    end
    self.adapter:gotoPercent(n);self:close();return true
end

function App:valueText(item,value)
    if value==nil then return "不可用" end
    if item.id=="font_gamma" then return self.adapter:gammaLabel(value) end
    if (item.kind=="margins" or item.kind=="pair") then return table.concat(value," / ") end
    if item.kind=="toggle" then return value and "开启" or "关闭" end
    if item.kind=="choice" then
        for _,choice in ipairs(self.adapter:choices(item.id)) do if value==choice[1] then return choice[2] end end
    end
    return tostring(value)..(item.suffix or "")
end

function App:refreshHome()
    local native=self.plugin.ui.statistics
    if self.plugin.ui.document and native and native:isEnabledAndNotFrozen() then native:insertDB() end
    self:render()
    local unavailable=self.screen and self.screen.model.home_data and self.screen.model.home_data.stats_unavailable
    UIManager:show(InfoMessage:new{text=unavailable and "统计暂不可用，请稍后重试" or "已刷新 "..os.date("%H:%M"),timeout=2})
end

function App:collectionChanged(name,new_name)
    local function update(value)
        if type(value)~="table" then return end
        if value.collection==name then value.collection=new_name end
        if (value.id=="collection_manage" or value.id=="collection_members") and value.param==name then
            if new_name then value.param=new_name else value.id="collection_manager";value.param=nil;value.scroll_y=0 end
        elseif value.id=="books" and value.param and value.param.collection==name then
            if new_name then value.param.collection=new_name else value.id="collections";value.param=nil;value.page=1 end
        end
        for _,v in pairs(value) do if type(v)=="table" then update(v) end end
    end
    update(self.stack);update(self.browser.tabs)
    for _,key in ipairs({"return_stack","return_context","view_state"}) do
        local value=self.library.settings:readSetting(key)
        if value then update(value);self.library.settings:saveSetting(key,value) end
    end
    self.browser:save();self.library.settings:flush()
    self:render()
end

function App:editCollection(name,new_name)
    local ok,result=pcall(self.library.editCollection,self.library,name,new_name)
    if not ok then self:message(result);return false end
    self:collectionChanged(name,result);return true
end

function App:render()
    if not self.screen or not Context.alive(self) then return end
    local route=self.stack[#self.stack]
    if route.id=="library" then route.id="books";route.param={} end
    if self.screen.model and self.screen.model.route==route then route.page=self.screen.model.page end
    local m={title="墨页",subtitle="",rows={},page=route.page or 1,route=route}
    local function row(title,note,fn) m.rows[#m.rows+1]={title=title,note=note,callback=fn} end
    local function go(id,param) return function() self:go(id,param) end end
    if require("einkfrontend/transfersettings").render(self,route,m,row,go) then
    elseif require("einkfrontend/inputsettings").render(self,route,m,row,go) then
    elseif require("einkfrontend/clocksettings").render(self,route,m,row,go) then
    elseif require("einkfrontend/pagepresssettings").render(self,route,m,row,go) then
    elseif require("einkfrontend/bookvalue").render(self,route,m,row,go) then
    elseif require("einkfrontend/homecustom").render(self,route,m,row,go) then
    elseif require("einkfrontend/settings").render(self,route,m,row,go) then
    elseif route.id=="home" then
        m.title="主页";m.home=true;m.home_data=require("einkfrontend/home").model(self)
    elseif route.id=="settings" then
        m.title="设置中心";m.subtitle="按分类逐级进入；当前值来自实际运行状态"
        row("阅读与排版","当前书籍 · 需要先打开流式文档",go("section","reading"))
        row("书库与文件","全局 · 原生文件列表排序与隐藏文件",go("section","files"))
        row("前端与恢复","启动入口、阅读入口与安全退出",go("frontend"))
        row("关于与兼容性","目标版本与设备验证状态",go("about"))
        row("搜索设置","按名称和说明查找已重建设置",function()
            self.adapter:promptText("搜索设置","",function(query) self:go("setting_search",query) end)
        end)
    elseif route.id=="setting_search" then
        m.title="搜索设置";m.subtitle="搜索："..(route.param or "").." · 仅索引已重建设置"
        local query=(route.param or ""):lower()
        for _,item in ipairs(Registry) do
            if (item.title.." "..(item.help or "")):lower():find(query,1,true) then
                local value,scope,why=self.adapter:read(item.id)
                row(item.title.." · "..self:valueText(item,value),
                    (item.section=="reading" and "阅读与排版" or "书库与文件").." › "..item.title.." · "..(why or scope),go("setting",item.id))
            end
        end
        if #m.rows==0 then row("没有匹配的设置","换一个名称或说明中的关键词") end
    elseif route.id=="path" then
        m.title="所在位置";m.subtitle="点击任意层级返回"
        for index=1,#self.stack-1 do
            local i=index;local target=self.stack[i]
            row(target.title or ({home="主页",books="书籍",library="书库",groups="分类",collections="收藏",settings="设置中心"})[target.id] or "上一层","第 "..i.." 层",function()
                while #self.stack>i do table.remove(self.stack) end
                self.screen.focus_index=1;self:render()
            end)
        end
    elseif route.id=="section" then
        m.title=route.param=="reading" and "阅读与排版" or "书库与文件"
        m.subtitle=route.param=="reading" and "仅修改当前书籍；不改变其他书的默认值" or "全局设置 · 立即生效并保存"
        for _,item in ipairs(Registry.items(route.param)) do
            local value,scope,why=self.adapter:read(item.id)
            row(item.title.."  ·  "..self:valueText(item,value),why or (scope.." · "..(item.help or "")),go("setting",item.id))
        end
    elseif route.id=="setting" then
        local item=assert(Registry.by_id[route.param])
        local value,scope,why=self.adapter:read(item.id)
        m.title=item.title
        m.subtitle=why or (scope.." · 当前值："..self:valueText(item,value))
        if why then
            row("当前不可用",why)
        elseif item.kind=="pair" then
            row("当前："..self:valueText(item,value),"缩放 / 收缩（%）")
            row("自定义词间距",item.help,function() self.adapter:promptText("缩放 收缩（%）",table.concat(value," "),function(text)
                local pair={};for token in text:gmatch("%S+") do pair[#pair+1]=tonumber(token) or -1 end
                self:change(item,pair)
            end) end)
        elseif item.kind=="margins" then
            row("当前："..self:valueText(item,value),"左 / 上 / 右 / 下")
            for _,v in ipairs({8,12,18}) do local size=v
                row(tostring(size),"四边统一",function() self:change(item,{size,size,size,size}) end)
            end
            row("自定义四边距","左 上 右 下，以空格分隔",function() self.adapter:promptText("左 上 右 下",table.concat(value," "),function(text)
                local margins={};for token in text:gmatch("%S+") do margins[#margins+1]=tonumber(token) or -1 end
                self:change(item,margins)
            end) end)
        elseif item.kind=="number" then
            row("当前值："..self:valueText(item,value),item.help)
            row("减少 "..item.step,"范围 "..item.min.."—"..item.max,function() self:change(item,math.max(item.min,value-item.step)) end)
            row("增加 "..item.step,"立即重新排版并保存",function() self:change(item,math.min(item.max,value+item.step)) end)
            row("减少 "..(item.step*5),"较大步长调整",function() self:change(item,math.max(item.min,value-item.step*5)) end)
            row("增加 "..(item.step*5),"较大步长调整",function() self:change(item,math.min(item.max,value+item.step*5)) end)
        else
            local choices=item.kind=="toggle" and {{false,"关闭"},{true,"开启"}} or self.adapter:choices(item.id)
            for _,choice in ipairs(choices) do
                local v,label=choice[1],choice[2]
                row((value==v and "■ " or "□ ")..label,item.help,function() self:change(item,v) end)
            end
        end
    elseif route.id=="reader" then
        m.title="阅读控制";m.subtitle="排版用独立设置页；目录等沿用已验证的功能窗口"
        row("返回"..self:readingReturnLabel(),"保留阅读进度，回到打开本书的位置",function()
            self:returnToLibrary()
        end)
        row("Aa  排版设置","字号 / 行距 / 内嵌样式 / 字体微调",go("section","reading"))
        for _,action in ipairs({{"目录","ShowToc"},{"书签","ShowBookmark"},{"全文搜索","ShowFulltextSearchInput"}}) do
            local title,event=action[1],action[2]
            row(title,"复用 KOReader 功能窗口",function() self:close();self.adapter:dispatch(event) end)
        end
        row("跳转进度","输入0—100的阅读百分比",function()
            self.adapter:promptText("跳转到百分比","",function(text) self:safe(function()
                self:jump(text)
            end) end)
        end)
        if self.adapter.jump_origin then row("返回跳转前的位置","按正文锚点恢复；PDF按页恢复",function()
            self.adapter:returnFromJump();self:close()
        end) end
        row("设置中心","独立分类与返回路径",go("settings"))
        row("设备快捷控制","从顶部下拉也可打开",function() self:showControls() end)
        row("返回正文","关闭控制页",function() self:close() end)
    elseif route.id=="recent" then
        m.title="最近阅读";m.subtitle="最近打开的书籍"
        for _,book in ipairs(self.adapter:recent()) do
            local file=book.file
            row(book.title,"继续阅读",function() self:openRecentBook(file) end)
        end
        if #m.rows==0 then row("暂无阅读记录","从原生文件管理器打开一本书后，这里会显示记录") end
    elseif route.id=="library" then
        m.title="书库";m.subtitle=(self.library.root or self.adapter:libraryRoot()).." · "..#self.library.books.." 本"
        if self.library.job then row("正在整理书库…","点击取消，保留上次扫描结果",function()
            self.library:cancel();self.status="已取消整理";self:render()
        end) end
        row("全部书籍","按当前排序浏览",go("books",{}))
        row("作者","按元数据中的作者分组",go("groups","authors"))
        row("系列","按系列与卷序组织",go("groups","series"))
        row("收藏","读取和管理 KOReader 的收藏",go("collections"))
        row("搜索书库","搜索书名、作者和系列",function()
            self.adapter:promptText("搜索书库","",function(query) self:safe(function() self:go("books",{query=query}) end) end)
        end)
        row("书库选项","封面 / 列表、排序、状态与目录",go("library_options"))
        if #self.library.books==0 then row("扫描书库","读取目录与子目录中的书籍元数据",function()
            self:scanLibrary(self.library.root or self.adapter:libraryRoot())
        end) end
    elseif route.id=="library_options" then
        m.title="书库选项";m.subtitle="新书库的视图和排序单独管理"
        row("视图："..(self.library_layout=="grid" and "封面" or "列表"),"点击切换",function()
            self.library_layout=self.library_layout=="grid" and "list" or "grid";self:saveLibraryView();self:render()
        end)
        row("排序："..Browser.sort_labels[self.library_sort],"点击切换",function()
            self:cycleLibrarySort()
        end)
        for _,state in ipairs({"未读","在读","已完成","搁置"}) do
            local status=state;row(status,"按阅读状态筛选",go("books",{status=status}))
        end
        row("重新扫描书库","目录："..(self.library.root or self.adapter:libraryRoot()),function()
            self:scanLibrary(self.library.root or self.adapter:libraryRoot())
        end)
        row("更换书库目录","打开兼容目录选择器",function()
            self.adapter:chooseLibraryRoot(self.library.root or self.adapter:libraryRoot(),function(path)
                self:safe(function() self:scanLibrary(path) end)
            end)
        end)
    elseif route.id=="library_filter" then
        m.title="筛选书库";m.subtitle="跨分类应用，可多选；不选择状态表示全部"
        row("当前："..self.browser:label(),"搜索："..(self.browser.filter.query or ""))
        row("清除筛选和搜索","保留当前分类与排序",function()
            self.browser.filter={statuses={},query=""};self:resetLibraryPages();self:render()
        end)
        for _,state in ipairs(Browser.states) do
            local status=state
            local selected=self.browser.filter.statuses[status]
            local count=#self.library:list({status=status,query=self.browser.filter.query})
            row((selected and "■ " or "□ ")..status.."（"..count.."）","点击切换",function()
                self.browser.filter.statuses[status]=not selected or nil
                self:resetLibraryPages();self:render()
            end)
        end
        row("扫描与书库选项","扫描目录 / 布局 / 修改目录",go("library_options"))
    elseif route.id=="groups" then
        m.title=route.param=="authors" and "作者" or "系列";m.subtitle="按已扫描的书籍元数据分组"
        for _,group in ipairs(self.library:groups(route.param,self.browser:combined(),self.library_sort)) do
            row(group.name,group.count.." 本",go("books",{field=route.param,value=group.name}))
            m.rows[#m.rows].book=group.book;m.rows[#m.rows].group=true
        end
        m.library_count=#m.rows
        if #m.rows==0 then row("暂无可分组的书籍","先扫描书库；无系列元数据的书籍仍可在全部书籍中找到") end
    elseif route.id=="books" then
        local filter=self.browser:combined(route.param)
        local books=self.library:list(filter,self.library_sort,filter.query)
        m.library_count=#books
        m.title=filter.value or (filter.collection and self.library:collectionLabel(filter.collection)) or filter.status or (filter.query and filter.query~="" and "搜索结果") or "全部书籍"
        m.subtitle=string.format("%d 本 · %s · %s",#books,self.library_layout=="grid" and "封面" or "列表",
            Browser.sort_labels[self.library_sort])
        m.grid=self.library_layout=="grid" and #books>0
        m.toolbar=self:libraryToolbar()
        for _,book in ipairs(books) do
            local status,percent=self.library:status(book)
            local label=status..(percent and (" "..math.floor(percent*100).."%") or "")
            row(book.title,m.grid and label or (book.authors..(book.series~="" and (" · "..book.series) or "")),function() self:openLibraryBook(book) end)
            m.rows[#m.rows].hold_callback=go("book",book)
            m.rows[#m.rows].book=book
            m.rows[#m.rows].detail=label.." · "..(book.file:match("%.([^%.]+)$") or ""):upper()
            m.rows[#m.rows].progress=percent
            m.rich=true
        end
        if #m.rows==0 then
            if #self.library.books==0 then
                row(self.library.job and "正在整理书库…" or "扫描书库","读取书库目录中的书籍",not self.library.job and function() self:scanLibrary(self.library.root or self.adapter:libraryRoot()) end or nil)
                row("选择书库目录","选择存放书籍的文件夹",function()
                    self.adapter:chooseLibraryRoot(self.library.root or self.adapter:libraryRoot(),function(path) self:safe(function() self:scanLibrary(path) end) end)
                end)
            else row("没有匹配的书籍","点击清除筛选和搜索",function()
                self.browser.filter={statuses={},query=""};self:resetLibraryPages();self:render()
            end) end
        end
    elseif route.id=="book" then
        local book=route.param
        m.title=book.title;m.subtitle=book.authors..(book.series~="" and (" · "..book.series) or "")
        row("开始阅读","打开书籍并关闭书库界面",function() self:openLibraryBook(book) end)
        local status,percent=self.library:status(book)
        row("阅读状态："..status,percent and (math.floor(percent*100).."%") or "尚无进度记录",function() self:chooseReadStatus(book) end)
        row("书名与作者",nil,function()
            self.adapter:promptText("书名",book.title,function(title)
                self.adapter:promptText("作者",book.authors=="作者未知" and "" or book.authors,function(author)
                    return self:userAction(function() self.library:editDetails(book,{title=title,authors=author});self:render() end)
                end,{keep_on_error=true})
            end)
        end)
        local value=require('einkfrontend/bookvalue');local price=self.book_value:price(book.file)
        row("本书价格",price~=nil and "¥"..value.money(price) or "未填写",function()
            self.adapter:promptText("本书价格（元，留空清除）",value.money(self.book_value:price(book.file)),function(text)
                return self:userAction(function() self.book_value:setPrice(book.file,text);self:render() end)
            end,{keep_on_error=true})
        end)
        row("加入或移出收藏","管理本书的收藏归属",go("book_collections",book))
        row("系列："..(book.series~="" and book.series or "未设置"),"修改本机显示，不改动书籍原文件",function()
            self.adapter:promptText("系列名称",book.series,function(text) return self:userAction(function()
                self.library:setMetadata(book,"series",text);self.status="系列已保存";self:render()
            end) end,{keep_on_error=true})
        end)
        row("卷序："..tostring(book.series_index or "未设置"),"可输入小数；留空恢复书籍原值",function()
            self.adapter:promptText("系列卷序",tostring(book.series_index or ""),function(text) return self:userAction(function()
                local value
                if text~="" then value=assert(tonumber(text),"请输入有效数字");assert(value==value and math.abs(value)<math.huge,"请输入有效数字") end
                self.library:setMetadata(book,"series_index",value);self.status="卷序已保存";self:render()
            end) end,{keep_on_error=true})
        end)
        row("恢复书籍原系列","清除本机系列名称和卷序覆盖",function()
            self.library:setMetadata(book,"series",nil);self.library:setMetadata(book,"series_index",nil)
            self.status="已恢复书籍原系列";self:render()
        end)
        row("书籍文件",book.file)
    elseif route.id=="collections" then
        m.title="收藏";m.subtitle="与 KOReader 原生收藏共用数据"
        for _,coll in ipairs(self.library:collections(self.browser:combined(),self.library_sort,true)) do
            row(coll.label,coll.available.." 本符合筛选 · 收藏共 "..coll.count.." 本",go("books",{collection=coll.name}))
            m.rows[#m.rows].group=true
            m.rows[#m.rows].book=coll.book
        end
    elseif route.id=="collection_manager" then
        m.title="管理收藏";m.subtitle="选择收藏夹，管理名称和书籍"
        row("新建收藏","输入一个收藏名称",function()
            self:newCollection()
        end)
        for _,coll in ipairs(self.library:collections()) do
            row(coll.label,coll.count.." 本",go("collection_manage",coll.name))
        end
    elseif route.id=="collection_manage" then
        local name=route.param;local rc=require("readcollection")
        assert(rc.coll[name],"收藏已经不存在")
        m.title=self.library:collectionLabel(name);m.subtitle="收藏夹管理"
        row("在书库显示："..(self.library:collectionVisible(name) and "开启" or "关闭"),nil,function()
            local ok,why=self.library:setCollectionVisible(name,not self.library:collectionVisible(name))
            if not ok then self:message(why) end;self:render()
        end)
        row("管理书籍","添加或移出本收藏的书籍",go("collection_members",name))
        if name~=rc.default_collection_name then
            row("重命名","保留收藏中的书籍与原生设置",function()
                self.adapter:promptText("重命名收藏",name,function(text) self:editCollection(name,text) end)
            end)
            row("删除收藏","只删除收藏分组，保留书籍文件",function()
                self:confirm("删除收藏“"..self.library:collectionLabel(name).."”？书籍文件会保留。",function() self:editCollection(name,nil) end)
            end)
        else row("默认收藏夹","可管理书籍，不能重命名或删除") end
    elseif route.id=="collection_members" then
        local name=route.param
        m.title=self.library:collectionLabel(name);m.subtitle="轻点书籍，添加或移出收藏"
        for _,book in ipairs(self.library:collectionBooks(name)) do
            local selected=self.library:inCollection(book.file,name)
            row((selected and "■ " or "□ ")..book.title,book.authors,function()
                local ok,err=pcall(self.library.setCollection,self.library,book.file,name,not selected)
                if ok then self:render() else self:message(err) end
            end)
        end
        if #m.rows==0 then row("暂无书籍","先扫描书库，再添加收藏成员") end
    elseif route.id=="book_collections" then
        local book=route.param
        m.title="管理收藏";m.subtitle=book.title
        for _,coll in ipairs(self.library:collections()) do
            local name=coll.name
            local selected=self.library:inCollection(book.file,name)
            row((selected and "■ " or "□ ")..coll.label,"点击切换本书归属",function()
                self.library:setCollection(book.file,name,not selected);self.status="收藏归属已保存";self:render()
            end)
        end
    elseif route.id=="frontend" then
        m.title="前端与恢复";m.subtitle="本页修改仅作用于墨页插件"
        row("文件管理器启动入口："..(self.plugin:option("auto_open",true) and "开启" or "关闭"),
            "下一次进入文件管理器时生效",function() self.plugin:toggleOption("auto_open",true);self:render() end)
        row("阅读点击入口："..(self.plugin:option("reader_entry",true) and "开启" or "关闭"),
            "中央 Aa 与顶部提示栏；可立即恢复",function()
                self.plugin:toggleOption("reader_entry",true);self.plugin:refreshReaderEntry();self:render()
            end)
        row("全菜单接管："..(self.plugin:option("full_takeover",true) and "开启" or "关闭"),
            "立即切换；保留插件和阅读数据",function()
                self.plugin:toggleOption("full_takeover",true)
                if self.plugin:option("full_takeover",true) then self.plugin:installTakeover()
                else require("einkfrontend/notices").detach(self.plugin,true);if self.plugin.gate then self.plugin.gate:restore() end end
                self:render()
            end)
        row("原生兼容菜单","临时进入；关闭后返回当前接管状态",function()
            self:close()
            if self.plugin.gate then self.plugin.gate:openNative() else self.plugin.ui.menu:onShowMenu() end
        end)
        row("停用墨页并重启后保持","恢复原生入口；重新启用请用原生插件管理器",function() self.plugin:disableFrontend() end)
    elseif route.id=="about" or route.id=="progress" then
        m.title="关于墨页";m.subtitle="ClassicUI · 墨页 · "..require("einkfrontend/version")
        local _,revision=require("einkfrontend/adapter").supported()
        row("为阅读，整理每一处界面","主页、书库、阅读工具与分层设置")
        row("墨页 "..require("einkfrontend/version"),"开源阅读前端 · AGPL-3.0-or-later")
        row("KOReader "..revision,"支持 v2026.07.1 / v2026.07.2")
        row("项目主页","github.com/ManXiangTAS/classicui.koplugin")
        row("兼容与恢复","可从维护与恢复中切回原生界面")
    else error("Unknown route: "..tostring(route.id)) end
    local tab=Browser.tab(route)
    if tab then
        m.library=true
        m.library_root=(route.id=="groups" or route.id=="collections" or (route.id=="books" and not next(route.param or {})))
        m.library_count=m.library_count or #m.rows
        self.browser.active=tab
        m.toolbar=self:libraryToolbar()
        if route.id~="books" then m.grid=self.library_layout=="grid" and #m.rows>0 and route.id~="library" end
        m.subtitle=m.subtitle.." · "..self.browser:label()..((self.browser.filter.query or "")~="" and (" · 搜索："..self.browser.filter.query) or "")
        if route.id=="groups" or route.id=="collections" then
            m.subtitle=m.subtitle.." · "..(self.library_sort=="title" and "名称" or Browser.sort_labels[self.library_sort])
        end
    end
    if route.id=="library_options" then
        local available=self.adapter:hasKindleLibrary()
        row("Kindle 原生书库",available and "打开已安装插件的书库" or "需安装并启用 kindle.koplugin",available and function()
            self:close();self.adapter:openKindleLibrary()
        end or nil)
    end
    if route.id=="library_options" or route.id=="library_filter" or route.id=="book" or route.id=="book_collections"
        or route.id=="collection_manager" or route.id=="collection_manage" or route.id=="collection_members" then
        m.settings=true;m.library_aux=true
    end
    if m.settings and route.search_query and route.search_query~="" then
        local all=m.rows;m.rows={};local needle=route.search_query:lower()
        for _,r in ipairs(all) do if (r.title.." "..(r.note or "")):lower():find(needle,1,true) then m.rows[#m.rows+1]=r end end
        if #m.rows==0 then row("没有匹配的项目",nil) end
        m.subtitle="搜索："..route.search_query
    end
    route.title=m.title
    m.path_depth=#self.stack
    self.screen:setModel(m)
    Overlay.closeInvalid(self)
end
function App:dialogGuard()
    local parent=self.home_editor or self.navigation or self.reader_panel or self.screen or self.reader_topbar or self.controls
    local route=parent==self.screen and self.stack[#self.stack] or nil
    return function()
        return Context.alive(self) and (not parent or UIManager:isWidgetShown(parent))
            and (not route or self.stack[#self.stack]==route)
    end
end
function App:trackDialog(dialog) self.dialogs[dialog]=true;return dialog end
function App:closeDialogs()
    local dialogs={};for dialog in pairs(self.dialogs or {}) do dialogs[#dialogs+1]=dialog end
    for _,dialog in ipairs(dialogs) do
        if UIManager:isWidgetShown(dialog) then UIManager:close(dialog) end
        self.dialogs[dialog]=nil
    end
end
function App:confirm(text,fn)
    if not Context.alive(self) then return end
    local valid=self:dialogGuard();local resolved=false
    local box
    box=require("ui/widget/confirmbox"):new{text=text,ok_text="确认",ok_callback=function()
        if resolved or not valid() or not UIManager:isWidgetShown(box) then return end
        resolved=true;self:safe(fn)
    end,cancel_callback=function() resolved=true end}
    self:trackDialog(box)
    UIManager:show(box);return box
end
function App:chooseReadStatus(book)
    local valid=self:dialogGuard();local buttons={};local box
    for _,entry in ipairs({{'未读','new'},{'在读','reading'},{'已完成','complete'},{'搁置','abandoned'}}) do
        local item=entry
        buttons[#buttons+1]={{text=item[1],callback=function()
            if not valid() or not UIManager:isWidgetShown(box) then return end
            UIManager:close(box);self:userAction(function() self.library:setReadStatus(book,item[2]);self:render() end)
        end}}
    end
    box=require('ui/widget/buttondialog'):new{title='阅读状态',buttons=buttons};self:trackDialog(box);UIManager:show(box)
end

function App:message(text) UIManager:show(InfoMessage:new{text=tostring(text)}) end
function App:showReader(tab)
    if not Context.allowed(self,'reader_panel') then return end
    if tab=="progress" then return self:showBookStatistics() end
    if self.screen then self:close() end
    local panel=Overlay.present(self,"reader_panel",function() return require("einkfrontend/readerpanel"):new{app=self,tab=tab or "menu"} end)
    if panel and tab then panel:setTab(tab) end
    return panel
end
function App:showBookStatistics()
    if not Context.allowed(self,'book_statistics') then return end
    if self.screen then self:close() end
    local panel=Overlay.present(self,"book_statistics",function() return require("einkfrontend/bookstatistics"):new{app=self} end)
    if panel then panel:refresh() end
    return panel
end
function App:showReaderTopbar()
    if not Context.allowed(self,'reader_topbar') then return end
    if self.screen then self:close() end
    return Overlay.present(self,"reader_topbar",function() return require("einkfrontend/readertopbar"):new{app=self} end)
end

function App:showNavigation(tab,item)
    if not Context.allowed(self,'navigation') then return end
    if self.screen then self:close() end
    local panel=Overlay.present(self,"navigation",function() return require("einkfrontend/readernavigation"):new{app=self} end)
    if panel then panel:setView(tab or "toc",item) end
    return panel
end

function App:showHomeEditor(selected)
    return Overlay.present(self,"home_editor",function() return require("einkfrontend/homeeditor"):new{app=self,selected=selected} end)
end

function App:searchCurrent()
    local route=self.stack[#self.stack];if not route then return end
    if route.id=="clock_zones" or route.id=="clock_zone_list" then
        return self.adapter:promptText("搜索时区",route.id=="clock_zone_list" and route.param or "",function(query)
            if not self.screen then return end
            if route.id=="clock_zone_list" then route.param=query;route.scroll_y=0;self:render() else self:go("clock_zone_list",query) end
        end)
    end
    local local_routes={collection_manager=true,collection_manage=true,collection_members=true,book_collections=true,book=true,home_widget=true,reading_return=true}
    if local_routes[route.id] then
        return self.adapter:promptText(route.id=="collection_members" and "搜索收藏中的书籍" or "搜索当前页面",route.search_query or "",function(query)
            if not self.screen then return end;route.search_query=query;route.scroll_y=0;self:render()
        end)
    end
    if self.screen.model and self.screen.model.library_aux then return self:searchLibrary() end
    return self:searchSettings()
end
function App:searchPage()
    if Context.allowed(self,'page_search') then return self:searchCurrent() end
end
function App:searchSettings()
    if not self.screen then self:open("settings") end
    if not Context.alive(self) or not self.screen then return end
    return self.adapter:promptText("搜索全部设置","",function(query) self:userAction(function() require("einkfrontend/settings").search(self,query) end) end)
end
function App:openNativeConfig()
    Overlay.close(self)
    local gate=self.plugin.gate;local config=self.plugin.ui.config
    assert(config,"当前没有可用的排版设置")
    if gate then
        gate.native_session=true
        local original=gate:original(config,"onShowConfigMenu")
        local before=config.onCloseCallback
        config.onCloseCallback=function(this,...)
            config.onCloseCallback=before;gate.native_session=false;return before(this,...)
        end
        local ok,err=pcall(original,config)
        if not ok then config.onCloseCallback=before;gate.native_session=false;error(err) end
    else config:onShowConfigMenu() end
end
return App
