-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Reference decisions and pinned upstream sources: docs/��Դ�ο�����þ���.md.
local Browser={}
Browser.__index=Browser
Browser.sort_labels={title="����",author="����",last_opened="����Ķ�",recent="�ļ��޸�ʱ��"}
Browser.states={"δ��","�ڶ�","�����","����"}
local roots={books={id="books",param={}},authors={id="groups",param="authors"},
    series={id="groups",param="series"},collections={id="collections"}}

function Browser.copy(value,seen)
    if type(value)~="table" then return value end
    seen=seen or {};if seen[value] then return seen[value] end
    local out={};seen[value]=out;for k,v in pairs(value) do out[k]=Browser.copy(v,seen) end;return out
end

function Browser.tab(route)
    if type(route)~="table" then return end
    if route.id=="groups" then return (route.param=="authors" or route.param=="series") and route.param or nil end
    if route.id=="collections" then return "collections" end
    if route.id=="books" then
        local p=type(route.param)=="table" and route.param or {}
        return p.collection and "collections" or p.field=="authors" and "authors" or p.field=="series" and "series" or "books"
    end
    if route.id=="library" then return "books" end
end

local function tableOrEmpty(value) return type(value)=="table" and value or {} end
local function positive(value,default)
    return type(value)=="number" and value==value and value<math.huge and value>=1 and math.floor(value) or default
end
function Browser.route(route)
    if type(route)~="table" or not Browser.tab(route) then return end
    local out={id=route.id,page=positive(route.page,1)}
    if type(route.title)=="string" then out.title=route.title end
    if route.id=="groups" then out.param=route.param
    elseif route.id=="books" then
        if route.param~=nil and type(route.param)~="table" then return end
        local p=route.param or {};out.param={}
        if p.collection~=nil then if type(p.collection)~="string" then return end;out.param.collection=p.collection end
        if p.field~=nil then
            if (p.field~="authors" and p.field~="series") or type(p.value)~="string" then return end
            out.param.field=p.field;out.param.value=p.value
        end
        if type(p.query)=="string" then out.param.query=p.query end
        -- Local filters also belong to the reading return position.
        for _,state in ipairs(Browser.states) do if p.status==state then out.param.status=state end end
        if type(p.statuses)=="table" then
            out.param.statuses={}
            for _,state in ipairs(Browser.states) do if p.statuses[state]==true then out.param.statuses[state]=true end end
        end
    end
    return out
end

function Browser.new(settings)
    local data=tableOrEmpty(settings:readSetting("browser_state"))
    local old=tableOrEmpty(settings:readSetting("view_state"))
    local filter=tableOrEmpty(data.filter);local statuses={}
    for _,name in ipairs(Browser.states) do if tableOrEmpty(filter.statuses)[name]==true then statuses[name]=true end end
    local self=setmetatable({settings=settings,tabs={},active=roots[data.active] and data.active or "books",
        filter={statuses=statuses,query=type(filter.query)=="string" and filter.query or ""}},Browser)
    for name,root in pairs(roots) do
        local tab=tableOrEmpty(tableOrEmpty(data.tabs)[name])
        local stack=self:routes(tab.stack)
        local root_tab=stack[1] and Browser.tab(stack[1])
        if root_tab~=name then stack={Browser.route(root)} end
        local layout=tab.layout or (name=="books" and old.layout)
        local sort=tab.sort or (name=="books" and old.sort)
        self.tabs[name]={layout=tab.layout=="grid" and "grid" or tab.layout=="list" and "list" or
            (layout=="grid" and "grid" or layout=="list" and "list" or name=="books" and "grid" or "list"),
            sort=Browser.sort_labels[sort] and sort or "title",stack=stack}
    end
    return self
end

function Browser:label()
    local parts={}
    for _,s in ipairs(self.states) do if self.filter.statuses[s] then parts[#parts+1]=s end end
    return #parts>0 and table.concat(parts,"��") or "ȫ��"
end

function Browser:combined(local_filter)
    local out=Browser.copy(self.filter)
    for k,v in pairs(local_filter or {}) do out[k]=Browser.copy(v) end
    return out
end

function Browser:routes(stack)
    local routes={}
    for i,route in ipairs(tableOrEmpty(stack)) do
        if i>30 then break end
        local clean=Browser.route(route)
        if clean then routes[#routes+1]=clean end
    end
    while #routes>30 do table.remove(routes,1) end
    return routes
end

function Browser:remember(stack,layout,sort)
    local tab
    for i=#stack,1,-1 do
        tab=Browser.tab(stack[i]);if tab then break end
    end
    if not tab then return end
    self.active=tab
    self.tabs[tab]={layout=layout,sort=sort,stack=self:routes(stack)}
end

function Browser:save()
    self.settings:saveSetting("browser_state",{active=self.active,tabs=self.tabs,filter=self.filter})
    self.settings:flush()
end

return Browser
