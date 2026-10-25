-- Original project code. SPDX-License-Identifier: AGPL-3.0-or-later
local InputContainer = require("ui/widget/container/inputcontainer")
local Rail=require('einkfrontend/scrollrail')
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local ImageWidget = require("ui/widget/imagewidget")
local BB = require("ffi/blitbuffer")
local Paint=require("einkfrontend/paint")
local Screen = Device.screen
local Page = InputContainer:extend{ covers_fullscreen=true, stop_events_propagation=true }

function Page:init()
    self.dimen = Screen:getSize()
    self.ges_events = {
        FrontendHoldPan={ GestureRange:new{ges="hold_pan",range=self.dimen} },
        FrontendHoldRelease={ GestureRange:new{ges="hold_release",range=self.dimen} },
        FrontendTap = { GestureRange:new{ges="tap", range=self.dimen} },
        FrontendHold = { GestureRange:new{ges="hold", range=self.dimen} },
        FrontendSwipe = { GestureRange:new{ges="swipe", range=self.dimen} },
        FrontendPan = { GestureRange:new{ges="pan", range=self.dimen} },
        FrontendPanRelease = { GestureRange:new{ges="pan_release", range=self.dimen} },
    }
    self.focus_index = 1
    self:_layout()
end

function Page:_layout()
    if self.model and self.model.folder_import then return require('einkfrontend/foldercollectionpage').layout(self) end
    if self.model and self.model.home then
        self.header_h=Screen:scaleBySize(96);self.footer_h=Screen:scaleBySize(72);self.info_h=0
        self.viewport_h=self.dimen.h-self.header_h-self.footer_h;self.list_capacity=1;self.row_h=Screen:scaleBySize(72)
        return
    end
    if self.model and self.model.settings then
        self.header_h=Screen:scaleBySize(58);self.footer_h=0
        self.info_h=(self.model.subtitle or "")~="" and Screen:scaleBySize(40) or 0
        self.row_h=Screen:scaleBySize(72)
        self.viewport_h=self.dimen.h-self.header_h-self.info_h
        self.list_capacity=math.max(1,math.floor((self.dimen.h-self.header_h-self.footer_h-self.info_h)/self.row_h))
        return
    end
    self.header_h = Screen:scaleBySize(self.model and self.model.library and (self.model.library_root and 96 or 86) or 56)
    self.footer_h = Screen:scaleBySize(self.model and self.model.library and 116 or 106)
    self.info_h = Screen:scaleBySize(self.model and self.model.library and 52 or (self.model and self.model.toolbar and 126 or 52))
    self.row_h = Screen:scaleBySize(self.model and self.model.rich and 100 or 70)
    local height=self.dimen.h-self.header_h-self.footer_h-self.info_h
    self.viewport_h=height
    self.list_capacity = math.max(1, math.floor(height/self.row_h))
    self.grid_columns=math.max(2,math.min(5,math.floor(self.dimen.w/Screen:scaleBySize(165))))
    self.grid_rows=math.max(1,math.floor(height/Screen:scaleBySize(240)))
    self.grid_cell_h=math.floor(height/self.grid_rows)
    self.grid_capacity=self.grid_columns*self.grid_rows
end

local function sameHitModel(a,b)
    if not a or a==b or a.route~=b.route or a.title~=b.title or a.content_key~=b.content_key
        or a.settings~=b.settings or a.library~=b.library or a.home~=b.home or a.folder_import~=b.folder_import or #a.rows~=#b.rows then return false end
    for i,row in ipairs(a.rows) do
        local other=b.rows[i]
        for _,key in ipairs({'title','note','value','enabled','checked','book','group','detail','progress'}) do
            if row[key]~=other[key] then return false end
        end
    end
    return true
end
function Page:setModel(model)
    -- Preserve a still-identical row after a status-only native refresh (e.g.
    -- tap followed by hold), but never retain controls for changed content.
    if not sameHitModel(self.model,model) then self.hits={};self.settings_more_anchor=nil;self.scroll_track=nil;self.rail_drag=nil end
    self.model = model
    self:_layout()
    self.capacity=model.grid and self.grid_capacity or self.list_capacity
    self.model.page = math.max(1, math.min(model.page or 1, math.max(1, math.ceil(#model.rows/self.capacity))))
    if model.home then
        self.scroll_max=0;self.scroll_y=0;model.route.scroll_y=0;self.scroll_track=nil
    elseif model.settings then
        self.scroll_max=math.max(0,#model.rows*self.row_h-self.viewport_h)
        self.scroll_y=math.max(0,math.min(model.route.scroll_y or 0,self.scroll_max))
        model.route.scroll_y=self.scroll_y
    else self.scroll_y=0;self.scroll_max=0 end
    self.focus_index = math.min(self.focus_index or 1, math.max(1,#model.rows))
    UIManager:setDirty(self, "ui")
end

function Page:_text(bb, text, x, y, w, size, bold)
    local tw = TextWidget:new{ text=tostring(text or ""), face=Font:getFace(bold and "smallinfofontbold" or "cfont",size),
        max_width=math.max(1,w), bold=bold or false, padding=0 }
    tw:paintTo(bb,x,y)
    tw:free()
end

function Page:_paintLibraryHeader(bb,x,y)
    local S=Paint.s;local w=self.dimen.w;self.hits={}
    require("einkfrontend/shell").status(self,bb,x,y)
    local cy=y+S(42);local th=self.header_h-S(42)
    if self.model.library_root then
        local tw=math.min(S(76),(w-S(32))/4)
        for i,tab in ipairs({{"书籍","books"},{"作者","authors"},{"系列","series"},{"收藏","collections"}}) do
            local tx=x+S(16)+(i-1)*tw;local active=self.app.browser.active==tab[2]
            Paint.label(bb,tab[1],tx,cy,tw-S(6),th,18,true)
            if active then bb:paintRect(tx-S(4),cy+th-S(3),S(44),S(3),BB.COLOR_BLACK) end
            self.hits[#self.hits+1]={x=tx-S(6),y=cy,w=tw,h=th,callback=function() self.app:selectLibraryTab(tab[2]) end,id="tab_"..tab[2]}
        end
    else
        Paint.centerIcon(bb,"chevron.left",x,cy,S(46),th,S(24))
        Paint.label(bb,self.model.title,x+S(46),cy,w-S(62),th,18,true)
        self.hits[#self.hits+1]={x=x,y=cy,w=S(46),h=th,callback=function() self.app:back() end,id="library_back"}
    end
    Paint.rule(bb,x,y+self.header_h,w)
    cy=y+self.header_h;local left=w*.40;local right=w-S(86)
    Paint.button(self,bb,"筛选："..self.app.browser:label().."⌄",x+S(8),cy,left-S(8),self.info_h,function() self.app:showLibraryMenu("filter") end,{size=14,id="library_filter"})
    Paint.button(self,bb,"排序："..require("einkfrontend/browser").sort_labels[self.app.library_sort].."⌄",x+left,cy,right-left,self.info_h,function() self.app:showLibraryMenu("sort") end,{size=14,id="library_sort"})
    Paint.centerIcon(bb,"appbar.search",x+w-S(86),cy,S(42),self.info_h,S(22))
    Paint.button(self,bb,"",x+w-S(86),cy,S(42),self.info_h,function() self.app:searchLibrary() end,{id="library_search"})
    Paint.centerIcon(bb,"more",x+w-S(44),cy,S(44),self.info_h,S(22))
    self.hits[#self.hits+1]={x=x+w-S(44),y=cy,w=S(44),h=self.info_h,callback=function() self.app:showLibraryMenu("more") end,id="library_more"}
    Paint.line(bb,x,cy+self.info_h,w)
end

function Page:_paintSettings(bb,x,y)
    local w,h=self.dimen.w,self.dimen.h;local S=Paint.s;local B=BB
    bb:paintRect(x,y,w,h,B.COLOR_WHITE);self.hits={};self.row_layout={}
    if self.model.route.id~="settings" then
        Paint.inkIcon(bb,"chevron.left",x,y,S(46),self.header_h,S(24))
        self.hits[#self.hits+1]={x=x,y=y,w=S(46),h=self.header_h,callback=function() self.app:back() end,id="settings_back"}
    end
    local root=require('einkfrontend/context').allowed(self.app,'settings_popup')
    local scoped_search=require('einkfrontend/context').allowed(self.app,'page_search')
    local tx=root and S(20) or S(48)
    local reserved=((root or scoped_search) and 112 or 59)+(self.model.help and 48 or 0)
    local title=Paint.inkLabel(bb,self.model.title,x+tx,y,w-tx-S(reserved),self.header_h,Paint.style.title,true,nil,"left")
    local close=Paint.inkIcon(bb,"close",x+w-S(53),y,S(53),self.header_h,S(25))
    self.header_ink={title=title,close=close};self.settings_more_anchor=nil
    if root then
        self.header_ink.more=Paint.inkIcon(bb,"more",x+w-S(106),y,S(53),self.header_h,S(25))
        if self.app.settings_popup then bb:invertRect(x+w-S(106),y,S(53),self.header_h-S(2)) end
        local hit={x=x+w-S(106),y=y,w=S(53),h=self.header_h,callback=function() self.app:showSettingsMore() end,id="settings_more"}
        self.hits[#self.hits+1]=hit;self.settings_more_anchor=hit
    elseif scoped_search then
        self.header_ink.search=Paint.inkIcon(bb,'appbar.search',x+w-S(106),y,S(53),self.header_h,S(25))
        self.hits[#self.hits+1]={x=x+w-S(106),y=y,w=S(53),h=self.header_h,callback=function() self.app:searchPage() end,id='page_search'}
    end
    if self.model.help then
        local hx=math.min(x+w-S((root or scoped_search) and 153 or 100),title.x+title.w+S(12))
        self.header_ink.info=Paint.inkIcon(bb,'info',hx,y,S(40),self.header_h,S(20))
        self.hits[#self.hits+1]={x=hx,y=y,w=S(40),h=self.header_h,callback=self.model.help,id='settings_help'}
    end
    self.hits[#self.hits+1]={x=x+w-S(53),y=y,w=S(53),h=self.header_h,callback=function() self.app:dismiss() end,id="settings_close"}

    Paint.rule(bb,x,y+self.header_h-S(1.5),w,2)
    if self.model.folder_import then return require('einkfrontend/foldercollectionpage').paint(self,bb,x,y) end
    if self.info_h>0 then self:_text(bb,self.model.subtitle,x+S(20),y+self.header_h+S(10),w-S(48),14,false) end
    local top=y+self.header_h+self.info_h
    local content_w=w-(self.scroll_max>0 and Rail.reserve() or 0)
    local clip=bb:viewport(x,top,content_w,self.viewport_h)
    w=content_w
    local start=math.floor(self.scroll_y/self.row_h)+1
    local last=math.min(#self.model.rows,math.ceil((self.scroll_y+self.viewport_h)/self.row_h))
    for i=start,last do
        local r=self.model.rows[i];local ry=(i-1)*self.row_h-self.scroll_y
        local pad=S(20);local disabled=r.enabled==false;local ink=disabled and B.COLOR_DARK_GRAY or B.COLOR_BLACK
        local icon_metrics
        if r.icon then icon_metrics=Paint.inkIcon(clip,r.icon,pad,ry,S(28),self.row_h,S(28),"settings");pad=pad+S(46) end
        local vw=r.value and math.min(S(r.value_width or 125),w*.58) or S(24)
        local prefix=r.checkmark_callback and (r.checked and "☑ " or "☐ ") or (r.checked and "✓ " or "")
        local text_h=(r.note and r.note~="") and S(40) or self.row_h
        local label=prefix..r.title;local label_w=w-pad-vw-S(36);local shift=0
        local note_w=r.value and label_w or w-pad-S(52)
        if r.note and r.note~="" then
            local a=Paint.inkLabel(nil,label,pad,0,label_w,text_h,Paint.style.row,true,nil,"left")
            local b=Paint.inkLabel(nil,r.note,pad,S(40),note_w,self.row_h-S(40),Paint.style.secondary,false,nil,"left")
            shift=math.floor(self.row_h/2-(math.min(a.y,b.y)+math.max(a.y+a.h-1,b.y+b.h-1))/2+.5)
        end
        local label_metrics=Paint.inkLabel(clip,label,pad,ry+shift,label_w,text_h,Paint.style.row,true,ink,"left")
        local note_metrics,value_metrics,arrow_metrics
        if r.note and r.note~="" then note_metrics=Paint.inkLabel(clip,r.note,pad,ry+S(40)+shift,note_w,self.row_h-S(40),Paint.style.secondary,false,ink,"left") end
        if r.value then value_metrics=Paint.inkLabel(clip,r.value,w-vw-S(28),ry,vw-S(8),self.row_h,Paint.style.label,true,ink,"left") end
        if r.callback and not disabled then arrow_metrics=Paint.inkIcon(clip,"chevron.right",w-S(38),ry,S(24),self.row_h,S(24)) end
        self.row_layout[#self.row_layout+1]={index=i,icon=icon_metrics,label=label_metrics,note=note_metrics,value=value_metrics,arrow=arrow_metrics}

        Paint.rule(clip,S(20),ry+self.row_h-S(2),w-S(48),1.2)
        local hy=math.max(top,top+ry);local hh=math.max(0,math.min(y+h,top+ry+self.row_h)-hy)
        if r.checkmark_callback then
            self.hits[#self.hits+1]={x=x,y=hy,w=S(52),h=hh,callback=not disabled and r.checkmark_callback or nil,hold_callback=not disabled and r.hold_callback or nil,id="settings_check_"..i}
        end
        self.hits[#self.hits+1]={x=x,y=hy,w=w-S(20),h=hh,callback=not disabled and r.callback or nil,hold_callback=not disabled and r.hold_callback or nil,id="settings_row_"..i}
    end
    clip:free()
    self.scroll_track=Rail.paint(bb,x,top,self.dimen.w,self.viewport_h,self.scroll_y,self.scroll_max)
end

function Page:_paint(bb,x,y)
    if self.model.home then return require("einkfrontend/shell").home(self,bb,x,y) end
    if self.model.settings then return self:_paintSettings(bb,x,y) end
    local w,h = self.dimen.w,self.dimen.h
    bb:paintRect(x,y,w,h,BB.COLOR_WHITE)
    local p = Screen:scaleBySize(14)
    if self.model.library then
        self:_paintLibraryHeader(bb,x,y)
    else
    local back_w,native_w = Screen:scaleBySize(72),Screen:scaleBySize(104)
    self:_text(bb,"‹ 返回",x+p,y+p,back_w,18,true)
    self:_text(bb,self.model.title,x+back_w+p,y+p,w-back_w-native_w-3*p,22,true)
    self:_text(bb,"关闭",x+w-native_w,y+p,native_w-p,17,false)
    bb:paintRect(x,y+self.header_h,w,Screen:scaleBySize(2),BB.COLOR_BLACK)
    self:_text(bb,self.model.subtitle or "",x+p,y+self.header_h+p,w-2*p,15,false)
    self.hits = {
        {x=x,y=y,w=back_w+p,h=self.header_h,callback=function() self.app:back() end},
        {x=x+w-native_w,y=y,w=native_w,h=self.header_h,callback=function() self.app:dismiss() end},
        {x=x+back_w+p,y=y,w=w-back_w-native_w-p,h=self.header_h,callback=function()
            if self.model.path_depth>1 and self.model.route.id~="path" then self.app:go("path") end
        end},
    }
    if self.model.toolbar then
        for band,buttons in ipairs(self.model.toolbar) do
            local by=y+self.header_h+Screen:scaleBySize(32+(band-1)*44)
            local bw=w/#buttons
            for index,button in ipairs(buttons) do
                local bx=x+(index-1)*bw
                self:_text(bb,button[1],bx+p,by+Screen:scaleBySize(10),bw-2*p,15,band==1)
                self.hits[#self.hits+1]={x=bx,y=by,w=bw,h=Screen:scaleBySize(44),callback=button[2]}
            end
        end
        bb:paintRect(x,y+self.header_h+self.info_h-1,w,1,BB.COLOR_BLACK)
    end
    end
    local start = (self.model.page-1)*self.capacity+1
    for i=start,math.min(#self.model.rows,start+self.capacity-1) do
        local row=self.model.rows[i]
        if self.model.grid then
            local cellw=math.floor(w/self.grid_columns)
            local cx=x+((i-start)%self.grid_columns)*cellw
            local cy=y+self.header_h+self.info_h+math.floor((i-start)/self.grid_columns)*self.grid_cell_h
            local coverh=self.grid_cell_h-Screen:scaleBySize(76)
            local coverw=math.min(cellw-2*p,math.floor(coverh*0.68))
            local bx=cx+math.floor((cellw-coverw)/2)
            local cover=row.book and self.app.library:cover(row.book.file)
            if cover then
                local image=ImageWidget:new{image=cover,image_disposable=false,width=coverw,height=coverh,scale_factor=0}
                image:paintTo(bb,bx,cy);image:free()
            else
                bb:paintRect(bx,cy,coverw,coverh,BB.COLOR_BLACK)
                bb:paintRect(bx+2,cy+2,coverw-4,coverh-4,BB.COLOR_WHITE)
                self:_text(bb,row.title,bx+p,cy+math.floor(coverh/3),coverw-2*p,16,true)
                self:_text(bb,row.group and "分类" or "无封面",bx+p,cy+math.floor(coverh*2/3),coverw-2*p,13,false)
            end
            self:_text(bb,row.title,cx+p,cy+coverh+Screen:scaleBySize(8),cellw-2*p,16,true)
            self:_text(bb,not row.group and row.book and row.book.authors or "",cx+p,cy+coverh+Screen:scaleBySize(31),cellw-2*p,13,false)
            self:_text(bb,row.note,cx+p,cy+coverh+Screen:scaleBySize(51),cellw-2*p,12,false)
            self.hits[#self.hits+1]={x=cx,y=cy,w=cellw,h=self.grid_cell_h,callback=row.callback,hold_callback=row.hold_callback}
        else
            local ry=y+self.header_h+self.info_h+(i-start)*self.row_h
            local tx,tw=x+p,w-2*p
            if row.book and self.model.rich then
                local ch=Screen:scaleBySize(78)
                local cw=Screen:scaleBySize(52)
                local cover=self.app.library:cover(row.book.file)
                if cover then
                    local image=ImageWidget:new{image=cover,image_disposable=false,width=cw,height=ch,scale_factor=0}
                    image:paintTo(bb,x+p,ry+Screen:scaleBySize(8));image:free()
                else
                    bb:paintRect(x+p,ry+Screen:scaleBySize(8),cw,ch,BB.COLOR_BLACK)
                    bb:paintRect(x+p+2,ry+Screen:scaleBySize(8)+2,cw-4,ch-4,BB.COLOR_WHITE)
                    self:_text(bb,"书",x+p+Screen:scaleBySize(13),ry+Screen:scaleBySize(34),cw,17,false)
                end
                tx=tx+cw+p;tw=tw-cw-p
            end
            self:_text(bb,row.title,tx,ry+Screen:scaleBySize(10),tw,20,true)
            self:_text(bb,row.note or "",tx,ry+Screen:scaleBySize(40),tw,14,false)
            if self.model.rich then
                self:_text(bb,row.detail or "",tx,ry+Screen:scaleBySize(62),tw,13,false)
                if row.progress then
                    local bh=Screen:scaleBySize(4)
                    local by=ry+self.row_h-Screen:scaleBySize(9)
                    bb:paintRect(tx,by,tw,bh,BB.COLOR_LIGHT_GRAY)
                    bb:paintRect(tx,by,math.floor(tw*row.progress),bh,BB.COLOR_BLACK)
                end
            end
            bb:paintRect(x+p,ry+self.row_h-1,w-2*p,1,BB.COLOR_BLACK)
            if self.keyboard_focus and i==self.focus_index then
                bb:paintRect(x,ry,Screen:scaleBySize(4),self.row_h,BB.COLOR_BLACK)
            end
            self.hits[#self.hits+1]={x=x,y=ry,w=w,h=self.row_h,callback=row.callback,hold_callback=row.hold_callback}
        end
    end
    local fy=y+h-self.footer_h
    if self.model.library then
        local S=Paint.s;local pager=S(44)
        Paint.line(bb,x+S(16),fy,w-S(32))
        local pages=math.max(1,math.ceil(#self.model.rows/self.capacity))
        Paint.label(bb,self.app.library.job and "正在整理…" or tostring(self.model.library_count)..(self.app.browser.active=="books" and " 本书" or " 项"),x+S(16),fy,w*.4,pager,14,true)
        Paint.button(self,bb,"‹",x+w*.5,fy,w*.12,pager,function() self:turn(-1) end,{disabled=self.model.page==1,size=20})
        Paint.label(bb,self.model.page.." / "..pages,x+w*.65,fy,w*.2,pager,14,true)
        Paint.button(self,bb,"›",x+w*.84,fy,w*.14,pager,function() self:turn(1) end,{disabled=self.model.page==pages,size=20})
        require("einkfrontend/shell").nav(self,bb,x,fy+pager,"library")
        return
    end
    bb:paintRect(x,fy,w,Screen:scaleBySize(2),BB.COLOR_BLACK)
    local pages=math.max(1,math.ceil(#self.model.rows/self.capacity))
    self:_text(bb,"‹ 上页",x+p,fy+Screen:scaleBySize(8),w/4,16,false)
    self:_text(bb,string.format("%d / %d",self.model.page,pages),x+w/2-p,fy+Screen:scaleBySize(8),w/4,16,false)
    self:_text(bb,"下页 ›",x+w*3/4,fy+Screen:scaleBySize(8),w/4-p,16,false)
    self:_text(bb,self.app.status or "墨页 · 开发预览",x+p,fy+Screen:scaleBySize(35),w-2*p,13,false)
    self.hits[#self.hits+1]={x=x,y=fy,w=w/3,h=Screen:scaleBySize(62),callback=function() self:turn(-1) end}
    self.hits[#self.hits+1]={x=x+w*2/3,y=fy,w=w/3,h=Screen:scaleBySize(62),callback=function() self:turn(1) end}
    local nav_y=y+h-Screen:scaleBySize(44)
    bb:paintRect(x,nav_y,w,1,BB.COLOR_BLACK)
    for index,nav in ipairs({{"书库","library"},{"设置","settings"}}) do
        local nx=x+(index-1)*w/2
        self:_text(bb,nav[1],nx+p,nav_y+Screen:scaleBySize(12),w/2-2*p,18,true)
        local route=nav[2]
        self.hits[#self.hits+1]={x=nx,y=nav_y,w=w/2,h=Screen:scaleBySize(44),callback=function() self.app:go(route,nil,true) end}
    end
end

function Page:paintTo(bb,x,y)
    self.dimen.x,self.dimen.y=x,y
    local ok,err=pcall(self._paint,self,bb,x,y)
    if not ok and not self.paint_fault then
        self.paint_fault=true
        UIManager:nextTick(function() self.app:fail(err) end)
    end
end

function Page:onFrontendTap(ignored,ges)
    if ges and ges.pos then
        local value
        if self.model.settings and self.scroll_track then
            value=Rail.tap(self.scroll_track,ges.pos,self.viewport_h*.7)
        end
        if value then self:scrollBy(value-self.scroll_y) else Paint.activate(self,ges.pos) end
    end
    return true
end
function Page:onFrontendHold(ignored,ges)
    if ges and ges.pos then Paint.activate(self,ges.pos,true) end
    return true
end

function Page:scrollBy(delta)
    if self.model.home then self.scroll_y=0;self.scroll_max=0;self.model.route.scroll_y=0;return end
    local before=self.scroll_y
    self.scroll_y=math.max(0,math.min(self.scroll_max,math.floor(self.scroll_y+delta)))
    if self.scroll_y~=before then self.hits={} end
    self.model.route.scroll_y=self.scroll_y
    UIManager:setDirty(self,"ui")
end

function Page:turn(delta)
    if self.model.home then return end
    if self.model.settings then
        self:scrollBy(delta*(self.viewport_h-self.row_h))
        self.focus_index=math.min(#self.model.rows,math.ceil(self.scroll_y/self.row_h)+1)
        return
    end
    self.model.page=self.model.page+delta
    self:setModel(self.model)
    self.focus_index=(self.model.page-1)*self.capacity+1
    self.app:saveLibraryView()
end

function Page:onFrontendSwipe(ignored,ges)
 local rail_swipe=Rail.swipe(self.scroll_track,ges,self.rail_drag)
 self.rail_drag=nil;self.pan=nil;self.list_pan=nil;self.pan_delta=nil;self.dragging_scrollbar=nil
 if rail_swipe then return true end
    if ges and ges.direction=="south" and ges.pos and ges.pos.y<=self.header_h then
        self.app:safe(function() self.app:showControls() end);return true
    end
    if self.model.home then return true end
    if self.model.settings then
        if ges and (ges.direction=="north" or ges.direction=="south") then
            local amount=ges.distance or (self.viewport_h*.65)
            self:scrollBy((ges.direction=="north" and 1 or -1)*amount)
        end
        return true
    end
    if ges and (ges.direction=="west" or ges.direction=="north") then self:turn(1)
    elseif ges and (ges.direction=="east" or ges.direction=="south") then self:turn(-1) end
    return true
end

function Page:onFrontendPan(_,ges)
    if not self.model.settings or not ges then return true end
    if ges.pos then
        local value,drag=Rail.pan(self.scroll_track,ges,self.rail_drag)
        self.rail_drag=drag
        if value then self:scrollBy(value-self.scroll_y);self.pan_delta=nil;self.dragging_scrollbar=true
        elseif ges.relative then self.pan_delta=ges.relative.y end
    end
    return true
end
function Page:onFrontendPanRelease(_,ges)
 local final=Rail.release(self.rail_drag,ges);if final then self:scrollBy(final-self.scroll_y) end
    if self.model.settings and not self.dragging_scrollbar then
        local delta=ges and ges.relative and ges.relative.y or self.pan_delta
        if delta then self:scrollBy(-delta) end
    end
    self.pan_delta=nil;self.dragging_scrollbar=nil;self.rail_drag=nil;return true
end

function Page:onKeyPress(key)
    local group=Device.input.group
    if key:match({group.Back}) then self.app:safe(function() self.app:back() end)
    elseif key:match({group.PgFwd}) or key:match({"Right"}) then self:turn(1)
    elseif key:match({group.PgBack}) or key:match({"Left"}) then self:turn(-1)
    elseif key:match({"Down"}) or key:match({"Up"}) then
        self.keyboard_focus=true
        self.focus_index=math.max(1,math.min(#self.model.rows,self.focus_index+(key.Down and 1 or -1)))
        if self.model.settings then
            local row_top=(self.focus_index-1)*self.row_h
            if row_top<self.scroll_y then self:scrollBy(row_top-self.scroll_y)
            elseif row_top+self.row_h>self.scroll_y+self.viewport_h then self:scrollBy(row_top+self.row_h-self.viewport_h-self.scroll_y) end
        else self.model.page=math.floor((self.focus_index-1)/self.capacity)+1;self:setModel(self.model) end
    elseif key:match({{"Press","Enter"}}) then
        local row=self.model.rows[self.focus_index]
        if row and row.enabled~=false and row.callback then self.app:safe(row.callback) end
    end
    return true -- PagePress must not turn the underlying document.
end
Page.onKeyRepeat=Page.onKeyPress

function Page:onSetDimensions()
    self.dimen=Screen:getSize()
    self:_layout()
    for _,seq in pairs(self.ges_events) do seq[1].range=self.dimen end
    self:setModel(self.model)
    return true
end

function Page:clockRegions()
    if not self.model or not (self.model.home or self.model.library) then return {} end
    local S=Paint.s;local regions={Geom:new{x=self.dimen.x+S(16),y=self.dimen.y,w=S(150),h=S(42)}}
    if self.model.home then
        local frames=require("einkfrontend/homewidgets").layout(self.app.home_layout.config,self.dimen.w)
        local top=self.dimen.y+S(96);local bottom=self.dimen.y+self.dimen.h-S(72)
        for _,frame in ipairs(frames) do if frame.id=="clock" then
            local fy=top+frame.y-(self.scroll_y or 0)
            local visible=math.max(top,fy);local height=math.min(bottom,fy+frame.h)-visible
            if height>0 then regions[#regions+1]=Geom:new{x=self.dimen.x+frame.x,y=visible,w=frame.w,h=height} end
        end end
    end
    return regions
end
function Page:onShow()
    if self.clock_tick then return end
    self.clock_tick=function()
        if self.app.screen~=self then return end
        for _,region in ipairs(self:clockRegions()) do UIManager:setDirty(self,"ui",region) end
        UIManager:scheduleIn(60,self.clock_tick)
    end
    UIManager:scheduleIn(60-tonumber(os.date("%S")),self.clock_tick)
end
function Page:onCloseWidget()
    if self.clock_tick then UIManager:unschedule(self.clock_tick);self.clock_tick=nil end
    if self.app.screen==self and self.app.settings_popup then self.app.settings_popup:close() end
    if self.app.screen==self then self.app.screen=nil end
end
Page.onFrontendHoldPan=Page.onFrontendPan
Page.onFrontendHoldRelease=Page.onFrontendPanRelease
return Page
