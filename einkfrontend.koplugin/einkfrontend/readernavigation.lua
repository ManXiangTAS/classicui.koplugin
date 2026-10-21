-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Non-fullscreen reading navigation, using the native ToC and annotations.
local Input=require("ui/widget/container/inputcontainer")
local Device=require("device");local UI=require("ui/uimanager")
local GestureRange=require("ui/gesturerange")
local TextBox=require("ui/widget/textboxwidget");local Font=require("ui/font")
local P=require("einkfrontend/paint");local S=P.s;local B=P.BB
local Nav=Input:extend{stop_events_propagation=true,covers_footer=true}
local names={toc="目录",bookmarks="书签",annotations="标注",details="详情"}
function Nav:init()
 self.dimen=Device.screen:getSize();self.data=self.data or require("einkfrontend/navigationdata").new(self.app.plugin.ui)
 self.states=self.states or {toc={scroll=0,query=""},bookmarks={scroll=0,query=""},annotations={scroll=0,query=""},details={scroll=0,query=""}}
 self.collapsed=self.collapsed or {};self.view=self.view or "toc"
 self.ges_events={NavigationTap={GestureRange:new{ges="tap",range=self.dimen}},NavigationHold={GestureRange:new{ges="hold",range=self.dimen}},
 NavigationSwipe={GestureRange:new{ges="swipe",range=self.dimen}},NavigationPan={GestureRange:new{ges="pan",range=self.dimen}},NavigationPanRelease={GestureRange:new{ges="pan_release",range=self.dimen}}}
end
function Nav:clearText() if self.detail_box then self.detail_box:free();self.detail_box=nil end end
function Nav:close() UI:close(self,"ui");UI:setDirty("all","ui") end
function Nav:onCloseWidget() self:clearText();if self.app.navigation==self then self.app.navigation=nil end end
function Nav:setView(view,item)
 if view=="details" then
  local canonical=self.data:resolve(item)
  if self.view~="details" then self.return_view=self.view end
  self.detail_item=canonical;self.states.details.scroll=0;self:clearText()
 end
 self.view=view;self:refresh()
end
function Nav:refresh()
 self:clearText();UI:setDirty("all","ui")
end
function Nav:run(callback)
 local ok,why=pcall(callback)
 if not ok or why then self.app:message(why) end
 self:refresh();return ok,why
end
function Nav:search()
 local view=self.view;local state=self.states[view]
 self.app.adapter:promptText("搜索"..names[view],state.query,function(text)
  state.query=text;state.scroll=0;self:refresh()
 end)
end
function Nav:go(row,is_toc)
 self:close();self.data:jump(row,is_toc)
end
function Nav:details(row)
 self.return_view=self.view;self.detail_item=row.item;self.view="details";self.states.details.scroll=0;self:refresh()
end
function Nav:editNote()
 local item=self.detail_item
 self.app.adapter:promptText(item.note and "编辑笔记" or "添加笔记",item.note or "",function(text)
  self:run(function() return self.data:setNote(item,text) end)
 end,{multiline=true})
end
function Nav:editText()
 local item=self.detail_item
 self.app.adapter:promptText("编辑摘录文本",item.text or "",function(text)
  self:run(function() return self.data:setText(item,text) end)
 end,{multiline=true})
end
function Nav:remove()
 local item=self.detail_item
 self.app:confirm("删除这条书签或标注？",function()
  local ok=self:run(function() return self.data:remove(item) end)
  if ok then self.detail_item=nil;self.view=self.return_view or "bookmarks";self:refresh() end
 end)
end
function Nav:openNative()
 self:close();local ui=self.app.plugin.ui;local gate=self.app.plugin.gate
 local fn=function() return ui.bookmark:onShowBookmark() end
 if gate then gate:native(fn) else fn() end
end
function Nav:rows()
 local state=self.states[self.view]
 if self.view=="toc" then
  local rows,current,toc=self.data:tocRows(self.collapsed,state.query)
  if self.toc_source~=toc then
   self.toc_source=toc;self.collapsed={}
   -- Start expanded; remember user collapse choices without mutating native ToC.
   rows,current=self.data:tocRows(self.collapsed,state.query)
  end
  self.current_toc=current
  return rows
 end
 return self.data:annotationRows(self.view,state.query,state.reverse)
end
function Nav:toggleChapter(row)
 self.collapsed[row.index]=not self.collapsed[row.index] or nil;self:refresh()
end
function Nav:locateCurrent()
 self.states.toc.query="";self.collapsed={};local rows,current=self.data:tocRows(self.collapsed,"")
 for i,row in ipairs(rows) do if row.index==current then self.states.toc.scroll=math.max(0,(i-2)*S(72));break end end
 self:refresh()
end
local function paragraph(bb,text,x,y,w,h,size,bold)
 local widget=TextBox:new{text=tostring(text or ""),face=Font:getFace(bold and "smallinfofontbold" or "cfont",size),bold=bold,width=w,
  height=h,height_adjust=true,height_overflow_show_ellipsis=true,fgcolor=B.COLOR_BLACK}
 if #widget.vertical_string_list<=1 then widget:free();P.label(bb,text,x,y,w,h,size,bold)
 else widget:paintTo(bb,x,y+math.floor((h-widget:getSize().h)/2));widget:free() end
end
function Nav:paintDetails(bb,x,y,w,h)
 local item=self.data:resolve(self.detail_item);local state=self.states.details
 if not self.detail_box then
  local text="第 "..self.data.ui.bookmark:getBookmarkPageString(item.page).." 页"
  if item.chapter then text=text.." · "..item.chapter end
  if item.datetime then text=text.."\n"..item.datetime end
  text=text.."\n\n"..(item.text or "页面书签")
  if item.note then text=text.."\n\n笔记\n"..item.note end
  self.detail_box=TextBox:new{text=text,face=Font:getFace("smallinfofontbold",18),bold=true,width=w-S(48),fgcolor=B.COLOR_BLACK}
 end
 self.scroll_max=math.max(0,self.detail_box:getSize().h+S(32)-h);state.scroll=math.max(0,math.min(state.scroll,self.scroll_max))
 local clip=bb:viewport(x,y,w,h);self.detail_box:paintTo(clip,S(20),S(16)-state.scroll);clip:free()
end
function Nav:paintList(bb,x,y,w,h)
 local rows=self:rows();self.current_rows=rows;local state=self.states[self.view]
 local rowh=S(self.view=="toc" and 72 or 104);self.row_h=rowh
 self.scroll_max=math.max(0,#rows*rowh-h);state.scroll=math.max(0,math.min(state.scroll,self.scroll_max))
 local clip=bb:viewport(x,y,w,h)
 for i=math.floor(state.scroll/rowh)+1,math.min(#rows,math.ceil((state.scroll+h)/rowh)) do
  local row=rows[i];local ry=(i-1)*rowh-state.scroll;local indent=self.view=="toc" and S(math.min((row.depth or 1)-1,5)*18) or 0
  local left=S(20)+indent;local pagew=S(76);local contentw=w-left-pagew-S(36)
  if row.current then clip:paintRect(S(7),ry+S(12),S(4),rowh-S(24),B.COLOR_BLACK) end
  local hy=math.max(y,y+ry);local hh=math.max(0,math.min(y+h,y+ry+rowh)-hy)
  if self.view=="toc" then
   local show_toggle=row.children and state.query==""
   if show_toggle then
    P.centerIcon(clip,self.collapsed[row.index] and "control.expand" or "control.collapse",left,ry,S(30),rowh,S(22))
    self.hits[#self.hits+1]={x=x+left,y=hy,w=S(38),h=hh,callback=function() self:toggleChapter(row) end,id="toc_toggle_"..row.index}
   end
   left=left+S(36);contentw=contentw-S(36)
   paragraph(clip,row.title,left,ry+S(11),contentw,rowh-S(20),18,true)
  else
   paragraph(clip,row.title,left,ry+S(10),contentw,S(51),18,true)
   P.label(clip,row.note or row.chapter or (row.kind=="bookmark" and "页面书签" or "摘录"),left,ry+S(65),contentw,S(30),14,true)
   P.centerIcon(clip,"appbar.menu",w-S(43),ry,S(32),rowh,S(22))
   self.hits[#self.hits+1]={x=x+w-S(52),y=hy,w=S(52),h=hh,callback=function() self:details(row) end,id="annotation_details_"..row.index}
  end
  P.label(clip,row.page,w-pagew-S(20),ry,pagew-S(24),rowh,14,true,"center")
  P.rule(clip,S(20),ry+rowh-S(2),w-S(40),1.2)
  local toc=self.view=="toc"
  self.hits[#self.hits+1]={x=x+left,y=hy,w=w-left-S(toc and 12 or 52),h=hh,
   callback=function() self:go(row,toc) end,hold_callback=function()
    if toc then self.app:message(row.title) else self:details(row) end
   end,id="navigation_row_"..i}
 end
 clip:free()
 if #rows==0 then P.label(bb,state.query~="" and "没有匹配的结果" or (self.view=="toc" and "这本书没有目录" or self.view=="bookmarks" and "尚无页面书签" or "尚无摘录或笔记"),x+S(20),y+S(32),w-S(40),S(64),18,true,"center") end
end
function Nav:paintTo(bb,x,y)
 self.hits={};local w,h=self.dimen.w,self.dimen.h
 self.panel_y=y+math.max(S(64),math.floor(h*.22));local py=self.panel_y
 local panelh=y+h-py;bb:paintRect(x,py,w,panelh,B.COLOR_WHITE);P.rule(bb,x,py,w,2)
 local props=self.app.plugin.ui.doc_props or {};local title=props.display_title or props.title or "阅读导航"
 P.label(bb,names[self.view],x+S(20),py,w-S(86),S(60),20,true)
 P.centerIcon(bb,"close",x+w-S(58),py,S(58),S(60),S(25))
 self.hits[#self.hits+1]={x=x+w-S(58),y=py,w=S(58),h=S(60),callback=function() self:close() end,id="navigation_close"}
 local cy=py+S(60)
 if self.view=="details" then
  P.button(self,bb,"‹ 返回"..names[self.return_view or "bookmarks"],x+S(12),cy,w-S(24),S(54),function() self:setView(self.return_view or "bookmarks") end,{id="navigation_back"})
 elseif self.view=="toc" then
  P.label(bb,title,x+S(20),cy,w-S(40),S(44),16,true)
 else
  for i,tab in ipairs({"bookmarks","annotations"}) do
   local tw=math.min(S(100),(w-S(24))/2);local bx=x+S(12)+(i-1)*tw
   P.button(self,bb,names[tab],bx,cy,tw,S(54),function() self:setView(tab) end,{align="center",id="navigation_tab_"..tab})
   if self.view==tab then bb:paintRect(bx+S(16),cy+S(50),tw-S(32),S(3),B.COLOR_BLACK) end
  end
 end
 cy=cy+S(self.view=="toc" and 44 or 54);P.rule(bb,x+S(20),cy,w-S(40))
 if self.view=="details" then
  local item=self.detail_item
  local buttons={{"跳转",function() self:go({item=item},false) end,"jump"},{"笔记",function() self:editNote() end,"note"},
   {item.drawer and "改摘录" or "原生管理",function() if item.drawer then self:editText() else self:openNative() end end,"edit"},{"删除",function() self:remove() end,"delete"}}
  for i,a in ipairs(buttons) do P.button(self,bb,a[1],x+(i-1)*w/4,cy,w/4,S(54),a[2],{align="center",id="navigation_"..a[3]}) end
 else
  local state=self.states[self.view]
  local sy=cy+S(10);local searchw=w-S(204);local actionw=S(152)
  bb:paintBorder(x+S(20),sy,searchw,S(44),math.max(2,S(1.5)),B.COLOR_BLACK)
  P.centerIcon(bb,"appbar.search",x+S(22),sy,S(38),S(44),S(24))
  P.button(self,bb,state.query~="" and state.query or "搜索"..names[self.view].."…",x+S(62),sy,searchw-S(42),S(44),function() self:search() end,{size=16,id="navigation_search"})
  self.hits[#self.hits+1]={x=x+S(20),y=sy,w=S(42),h=S(44),callback=function() self:search() end,id="navigation_search_icon"}
  local label,fn,id
  if self.view=="toc" then label="定位当前章节";fn=function() self:locateCurrent() end;id="navigation_locate"
  elseif self.view=="bookmarks" then
   local bm=self.data.ui.bookmark;local marked=bm:isPageBookmarked(bm:getCurrentPageNumber())
   label=marked and "取消本页书签" or "添加本页书签";fn=function() self:run(function() self.data:toggleCurrent() end) end;id="navigation_toggle_bookmark"
  else label=state.reverse and "页码倒序" or "页码顺序";fn=function() state.reverse=not state.reverse;state.scroll=0;self:refresh() end;id="navigation_sort" end
  local ax=x+w-S(20)-actionw
  bb:paintRect(ax,sy,actionw,S(44),B.COLOR_BLACK)
  P.inkLabel(bb,label,ax,sy,actionw,S(44),16,true,B.COLOR_WHITE)
  self.hits[#self.hits+1]={x=ax,y=sy,w=actionw,h=S(44),callback=fn,id=id}
  self.action_bar={search={x=x+S(20),y=sy,w=searchw,h=S(44)},action={x=ax,y=sy,w=actionw,h=S(44)}}
 end
 cy=cy+S(self.view=="details" and 54 or 64);P.rule(bb,x+S(20),cy,w-S(40));local footer=S(44);local vh=y+h-cy-footer
 self.list_area={x=x,y=cy,w=w,h=vh}
 if self.view=="details" then self:paintDetails(bb,x,cy,w,vh) else self:paintList(bb,x,cy,w,vh) end
 local state=self.states[self.view]
 if self.scroll_max>0 then
  local content=vh+self.scroll_max;local thumb=math.max(S(24),math.floor(vh*vh/content))
  self.scroll_track={x=x+w-S(18),y=cy,w=S(18),h=vh,thumb=thumb}
  bb:paintRect(x+w-S(7),cy,S(2),vh,B.COLOR_DARK_GRAY)
  bb:paintRect(x+w-S(10),cy+math.floor((vh-thumb)*state.scroll/self.scroll_max),S(6),thumb,B.COLOR_BLACK)
 else self.scroll_track=nil end
 local fy=y+h-footer;P.rule(bb,x+S(20),fy,w-S(40))
 P.label(bb,self.view=="details" and "上下滑动查看完整内容" or tostring(#self.current_rows).." 项 · 轻点跳转，长按查看",x+S(20),fy,w*.65-S(20),footer,14,true)
 if self.view~="toc" then P.button(self,bb,"更多操作",x+w*.67,fy,w*.33-S(8),footer,function() self:openNative() end,{size=14,align="center",id="navigation_native"}) end
end
function Nav:scrollBy(delta)
 local state=self.states[self.view];state.scroll=math.max(0,math.min(self.scroll_max or 0,state.scroll+delta));UI:setDirty(self,"ui")
end
function Nav:onNavigationTap(_,ges)
 if not ges or not ges.pos then return true end
 if ges.pos.y<self.panel_y then self:close();return true end
 local fn=P.find(self,ges.pos);if fn then self.app:safe(fn) end;return true
end
function Nav:onNavigationHold(_,ges)
 if ges and ges.pos then local fn=P.find(self,ges.pos,true);if fn then self.app:safe(fn) end end;return true
end
function Nav:onNavigationPan(_,ges)
 if ges and ges.pos then
  local t=self.scroll_track
  if t and ges.pos.x>=t.x then
   local ratio=math.max(0,math.min(1,(ges.pos.y-t.y-t.thumb/2)/math.max(1,t.h-t.thumb)))
   self.states[self.view].scroll=ratio*self.scroll_max;UI:setDirty(self,"ui")
  elseif ges.pos.y>=self.list_area.y and ges.relative then self.pan=ges.relative.y end
 end
 return true
end
function Nav:onNavigationPanRelease(_,ges)
 if self.pan then self:scrollBy(-(ges and ges.relative and ges.relative.y or self.pan));self.pan=nil end;return true
end
function Nav:onNavigationSwipe(_,ges)
 if not ges then return true end
 if ges.pos and ges.pos.y<self.panel_y then if ges.direction=="south" then self.app:showControls() end
 elseif ges.direction=="north" then self:scrollBy(self.list_area.h*.7)
 elseif ges.direction=="south" then self:scrollBy(-self.list_area.h*.7) end
 return true
end
function Nav:onKeyPress(key)
 if key:match({Device.input.group.Back}) then if self.view=="details" then self:setView(self.return_view or "bookmarks") else self:close() end
 elseif key:match({Device.input.group.PgFwd}) then self:scrollBy(self.list_area.h*.7)
 elseif key:match({Device.input.group.PgBack}) then self:scrollBy(-self.list_area.h*.7) end
 return true
end
Nav.onKeyRepeat=Nav.onKeyPress
function Nav:onSetDimensions() self:clearText();self:init();UI:setDirty("all","ui");return true end
return Nav
