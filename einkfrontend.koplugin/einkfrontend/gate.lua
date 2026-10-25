-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Reversible instance-only entry interception; no KOReader core files changed.
local Gate={};Gate.__index=Gate
function Gate.new(ui,route)
    return setmetatable({ui=ui,route=route,records={},active=true,native_depth=0},Gate)
end
function Gate:restore()
    self.active=false
    for i=#self.records,1,-1 do
        local r=self.records[i]
        if rawget(r.object,r.key)==r.wrapper then r.object[r.key]=r.raw end
    end
end
function Gate:native(callback)
    self.native_depth=self.native_depth+1
    local ok,result=pcall(callback)
    self.native_depth=self.native_depth-1
    if not ok then error(result) end
    return result
end
function Gate:wrap(object,key,destination,direction)
    local original=object and object[key]
    if type(original)~="function" then return end
    local record={object=object,key=key,raw=rawget(object,key),original=original}
    record.wrapper=function(this,...)
        local args={...}
        local gesture=args[1]
        if not self.active or self.native_depth>0 or self.native_session or (direction and (not gesture or gesture.direction~=direction)) then
            return original(this,...)
        end
        local ok,why=pcall(self.route,destination,key,unpack(args))
        if ok then return true end
        -- Routing failed: restore the instance and delegate this call to native behavior.
        require('logger').err('EInkFrontend route failed:',destination,why)
        self:restore()
        if self.onFailure then pcall(self.onFailure) end
        return original(this,...)
    end
    object[key]=record.wrapper;self.records[#self.records+1]=record
end
function Gate:original(object,key)
    for _,r in ipairs(self.records) do if r.object==object and r.key==key then return r.original end end
    return object[key]
end
function Gate:openNative()
    self.native_session=true
    local ok,result=pcall(self:original(self.ui.menu,"onShowMenu"),self.ui.menu)
    if not ok then self.native_session=false;error(result) end
    return result
end
function Gate:install()
    local menu=self.ui.menu
    self:wrap(menu,"onShowMenu","settings")
    self:wrap(menu,"onMenuSearch","settings_search")
    self:wrap(menu,"onKeyPressShowMenu","settings")
    self:wrap(menu,"onTapShowMenu",self.ui.document and "reader_top" or "ignore_top_tap")
    self:wrap(menu,"onSwipeShowMenu","controls","south")
    if self.ui.document then
        self:wrap(self.ui,"onHome","library")
        self:wrap(self.ui.toc,"onShowToc","toc")
        self:wrap(self.ui.bookmark,"onShowBookmark","bookmarks")
        self:wrap(self.ui.bookmark,"showBookmarkDetails","annotation_details")
        -- Compound native handlers otherwise open both top and bottom menus.
        self:wrap(menu,"onPressMenu","reader_top")
        -- Typography is opened explicitly by Aa, never by native bottom tap events.
        self:wrap(self.ui.config,"onShowConfigMenu","ignore_config_tap")
        self:wrap(self.ui.config,"onTapShowConfigMenu","ignore_config_tap")
        self:wrap(self.ui.config,"onSwipeShowConfigMenu","book_statistics","north")
    end
    local key=self.ui.document and "onCloseReaderMenu" or "onCloseFileManagerMenu"
    local original=menu[key]
    if original then
        local record={object=menu,key=key,raw=rawget(menu,key),original=original}
        record.wrapper=function(this,...)
            local result=original(this,...);self.native_session=false;return result
        end
        menu[key]=record.wrapper;self.records[#self.records+1]=record
    end
    return self
end
return Gate
