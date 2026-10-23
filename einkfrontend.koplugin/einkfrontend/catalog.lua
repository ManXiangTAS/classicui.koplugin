-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Capture registered native descriptors without consuming provider tables.
local Catalog={};Catalog.__index=Catalog
local function copy(value,seen)
    if type(value)~="table" then return value end
    seen=type(seen)=="table" and seen or {};if seen[value] then return seen[value] end
    local out={};seen[value]=out;for k,v in pairs(value) do out[k]=copy(v,seen) end;return out
end
local function actionable(node)
    return node.callback or node.callback_func or node.hold_callback or node.hold_callback_func
        or node.sub_item_table or node.sub_item_table_func or node.tap_input or node.tap_input_func
        or node.checked_func or node.text or node.text_func
end
function Catalog.new(ui,mapping,categories)
    return setmetatable({ui=ui,mapping=mapping or {},categories=categories or {},entries={},invalid_hints={}},Catalog)
end
function Catalog:refresh()
    local Sorter=require("ui/menusorter")
    local original=Sorter.mergeAndSort
    local capture,sorted,menu_order
    -- Narrow synchronous capture at the point after menu providers have registered their items.
    -- The native sorter mutates input tables; preserve a copy for the new renderer.
    local interceptor=function(sorter,prefix,items,order)
        capture=copy(items);menu_order=copy(order)
        if capture.screensaver then require('einkfrontend/stockscreensaver').extendMenu(capture.screensaver) end
        local safe,safe_order=copy(capture),copy(order)
        -- A user may remove a formerly valid parent from the active menu order.
        for id,value in pairs(sorter:readMSSettings(prefix) or {}) do safe_order[id]=copy(value) end
        local reachable={}
        local function walk(id)
            if reachable[id] then return end;reachable[id]=true
            for _,child in ipairs(safe_order[id] or {}) do walk(child) end
        end
        walk("KOMenu:menu_buttons")
        for id,node in pairs(safe) do
            if type(node)=="table" and node.sorting_hint and (not safe[node.sorting_hint] or not safe_order[node.sorting_hint] or not reachable[node.sorting_hint]) then
                self.invalid_hints[id]=node.sorting_hint
                safe.more_tools=safe.more_tools or {text="杂项"}
                safe_order.more_tools=safe_order.more_tools or {}
                safe.tools=safe.tools or {text="工具"};safe_order.tools=safe_order.tools or {}
                if not reachable.tools then
                    safe_order["KOMenu:menu_buttons"]=safe_order["KOMenu:menu_buttons"] or {}
                    local found=false;for _,id in ipairs(safe_order["KOMenu:menu_buttons"]) do if id=="tools" then found=true end end
                    if not found then table.insert(safe_order["KOMenu:menu_buttons"],"tools") end
                end
                if safe_order.tools then
                    local found=false;for _,key in ipairs(safe_order.tools) do if key=="more_tools" then found=true end end
                    if not found then table.insert(safe_order.tools,"more_tools") end
                end
                node.sorting_hint="more_tools"
            end
        end
        for id,node in pairs(safe) do if type(node)=="table" then node.id=id end end
        sorted=original(sorter,prefix,safe,safe_order);return sorted
    end
    self.invalid_hints={};Sorter.mergeAndSort=interceptor
    local ok,err=pcall(self.ui.menu.setUpdateItemTable,self.ui.menu)
    if Sorter.mergeAndSort==interceptor then Sorter.mergeAndSort=original end
    assert(ok,err);assert(capture,"Native catalog was not captured")
    self.entries={}
    for id,node in pairs(capture) do
        if type(node)=="table" and actionable(node) and id~="KOMenu:menu_buttons" then
            local destination=self.mapping[id]
            local reason
            if not destination then destination="misc";reason="unknown_item"
            elseif not self.categories[destination] then destination="misc";reason="missing_target_category" end
            if self.invalid_hints[id] then destination="misc";reason="missing_native_parent" end
            self.entries[id]={id=id,node=node,category=destination,fallback_reason=reason,original_hint=node.sorting_hint}
        end
    end
    self.sorted=sorted;self.order=menu_order;self.roots={}
    local known={}
    for id,children in pairs(menu_order) do known[id]=true;for _,child in ipairs(children) do known[child]=true end end
    local function category(node,inherited)
        local id=node.id
        if id and self.invalid_hints[id] then return "misc" end
        if id and self.mapping[id] then return self.categories[self.mapping[id]] and self.mapping[id] or "misc" end
        if id and capture[id] and not known[id] then return "misc" end
        return inherited or "misc"
    end
    local function prune(node,parent,target,top,seen)
        if type(node)~="table" or seen[node] then return {} end
        seen[node]=true
        local cat=category(node,parent)
        local children=node.sub_item_table or (#node>0 and node)
        local output={}
        if children then
            for _,child in ipairs(children) do
                for _,result in ipairs(prune(child,cat,target,false,seen)) do output[#output+1]=result end
            end
        end
        seen[node]=nil
        if cat==target and (not top or node.callback or node.callback_func or node.hold_callback or node.hold_callback_func) then
            local n=copy(node)
            if children then
                for k in ipairs(n) do n[k]=nil end
                n.sub_item_table=output
                if #output==0 and not n.callback and not n.sub_item_table_func then return {} end
            end
            return {n}
        end
        return output
    end
    local uid=0
    local function tag(nodes,seen)
        for _,node in ipairs(nodes or {}) do if type(node)=="table" and not seen[node] then
            seen[node]=true;uid=uid+1;node._eink_uid=uid
            tag(node.sub_item_table or (#node>0 and node),seen)
        end end
    end
    tag(sorted,{})
    for cat in pairs(self.categories) do
        local out={}
        for _,node in ipairs(sorted or {}) do
            for _,item in ipairs(prune(node,nil,cat,true,{})) do out[#out+1]=item end
        end
        self.roots[cat]=out
    end
    return self.entries
end
function Catalog:activate(node,host,hold)
    local enabled=node.enabled
    if type(node.enabled_func)=="function" then
        local ok,result=pcall(node.enabled_func)
        if not ok then return false,"availability_error" end
        enabled=result
    end
    if enabled==false then return false,"disabled" end
    -- Research proof delegates behavior to the actual native host rather than forging a callback receiver.
    -- Production may use its own compatible host, with explicit fallback for unsupported contracts.
    if hold then return pcall(host.onMenuHold,host,node,false) end
    return pcall(host.onMenuSelect,host,node)
end
function Catalog:audit()
    local expected,found={},{}
    local function walk(nodes,out,seen)
        for _,node in ipairs(nodes or {}) do if type(node)=="table" and not seen[node] then
            seen[node]=true
            if node.callback or node.callback_func or node.hold_callback or node.hold_callback_func or node.sub_item_table_func or node.tap_input or node.tap_input_func then out[node._eink_uid]=true end
            walk(node.sub_item_table or (#node>0 and node),out,seen)
        end end
    end
    walk(self.sorted,expected,{})
    for _,roots in pairs(self.roots) do walk(roots,found,{}) end
    local count,missing=0,{}
    for uid in pairs(expected) do count=count+1;if not found[uid] then missing[#missing+1]=uid end end
    return {static_action_nodes=count,missing=missing}
end
Catalog.copy=copy
return Catalog
