-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Contextual bottom controls: the document remains visible behind this widget.
local Input=require("ui/widget/container/inputcontainer")
local Device=require("device")
local UI=require("ui/uimanager")
local GestureRange=require("ui/gesturerange")
local P=require("einkfrontend/paint");local S=P.s;local B=P.BB
local Equal=require("einkfrontend/adapter").equal
local Registry=require("einkfrontend/registry")
local Copy=require("einkfrontend/catalog").copy
local Panel=Input:extend{stop_events_propagation=true,covers_footer=true}
function Panel:init()
 self.dimen=Device.screen:getSize();self.page=self.page or 1
 self.ges_events={ReaderTap={GestureRange:new{ges="tap",range=self.dimen}},ReaderHold={GestureRange:new{ges="hold",range=self.dimen}},
 ReaderSwipe={GestureRange:new{ges="swipe",range=self.dimen}},ReaderPan={GestureRange:new{ges="pan",range=self.dimen}},ReaderPanRelease={GestureRange:new{ges="pan_release",range=self.dimen}}}
end
function Panel:close() UI:close(self,"ui");UI:setDirty("all","ui") end
function Panel:onCloseWidget() if self.app.reader_panel==self then self.app.reader_panel=nil end end
function Panel:viewChanged() self.hits={};self.sliders={};self.list_area=nil;self.list_pan=nil;self.page=1;self.list_scroll=0;self.pending_font=nil;self.pending_adjustment=nil;UI:setDirty("all","ui") end
function Panel:setTab(tab) self.tab=tab;self:viewChanged() end
function Panel:parentTab()
 if self.tab=='option' then return self.option_parent or 'layout_options' end
 return ({fonts='font',font_options='font',layout_options='layout',theme_manage='theme_list',theme_list='themes'})[self.tab]
end
function Panel:back()
 local parent=self:parentTab()
 if parent then self:setTab(parent) else self:close() end
end
function Panel:change(id,value)
 local ok,why=self.app.typography:change(id,value)
 if not ok then self.app:message(why) end
 self.pending_font=nil;self.pending_adjustment=nil;UI:setDirty("all","ui")
 return ok,why
end
function Panel:source()
 local t=self.app.typography
 if not t or not t.meta then return "" end
 local id=t.meta.theme_id;local theme=id and self.app.themes:find(id)
 if theme and t:matches(theme.values) then return "主题 · "..theme.name end
 if id=="builtin:default" and t:matches(t:defaults()) then return "主题 · 默认" end
 if id then return "本书 · 已调整" end
 local inherited=false;for _,v in pairs(t.meta.inherit) do inherited=inherited or v end
 return inherited and "本书 · 继承默认" or "仅这本书"
end
function Panel:themeSave()
 local values=self.app.typography:snapshot()
 self.app.adapter:promptText("保存排版主题（1—24字）",self.draft_name or "",function(name) self.app:safe(function()
  self.draft_name=name
  local ok,id=self.app.themes:create(name,values)
  if not ok then self.app:message(id);return end
  self.draft_name=nil;self.app.typography.meta.theme_id=id;self.app.plugin.ui:saveSettings();self:setTab("themes")
 end) end)
end
function Panel:themeApply(id)
 local theme=assert(self.app.themes:find(id),"主题已不存在")
 local ok,why=self.app.typography:apply(theme.values,false,id)
 if not ok then self.app:message(why) end
 self:setTab("themes");UI:setDirty("all","ui");return ok,why
end
function Panel:themeManage(id) self.theme_id=id;self:setTab("theme_manage") end
function Panel:themeChoices()
 local t=self.app.typography
 local out={{id="builtin:default",name="默认",builtin=true,values=t:defaults()}}
 for _,theme in ipairs(self.app.themes.records) do out[#out+1]=theme end
 local selected
 for _,entry in ipairs(out) do
  if t.meta.theme_id==entry.id and t:matches(entry.values) then selected=entry.id;break end
 end
 if not selected and t:matches(out[1].values) then selected=out[1].id end
 return out,selected
end
function Panel:drawThemes(bb,x,y,w,h)
 local choices,selected=self:themeChoices();self.theme_tiles={}
 local footer=S(112);local viewh=math.max(S(80),h-footer);local rowh=S(92)
 self.list_area={x=x,y=y,w=w,h=viewh};self.list_max=math.max(0,math.ceil(#choices/2)*rowh-viewh)
 self.list_scroll=math.max(0,math.min(self.list_scroll or 0,self.list_max))
 local clip=bb:viewport(x,y,w,viewh)
 for i,entry in ipairs(choices) do
  local cx=S(30)+(i-1)%2*w/2;local ry=math.floor((i-1)/2)*rowh-self.list_scroll
  if ry<viewh and ry+rowh>0 then
   local side=S(44);local iy=ry+math.floor((rowh-side)/2);local active=selected==entry.id
   -- Like the reference: a compact outlined sample at left, plain name at right.
   clip:paintBorder(cx,iy,side,side,S(1.5),B.COLOR_BLACK,S(6))
   P.inkIcon(clip,"appbar.textsize",cx,iy,side,side,S(28))
   if active then
    clip:paintRect(cx-S(8),iy-S(8),S(23),S(22),B.COLOR_WHITE)
    P.inkLabel(clip,"✓",cx-S(13),iy-S(14),S(35),S(30),24,true)
   end
   local tx=cx+side+S(14);local tw=w/2-side-S(60)
   P.inkLabel(clip,entry.name,tx,active and ry+S(12) or ry,tw,active and S(44) or rowh,19,true,nil,"left")
   if active then P.inkLabel(clip,"当前主题",tx,ry+S(50),tw,S(28),15,false,nil,"left") end
   local hy=math.max(y,y+ry);local hh=math.min(y+viewh,y+ry+rowh)-hy
   local chosen=entry
   self.hits[#self.hits+1]={x=x+(i-1)%2*w/2,y=hy,w=w/2,h=hh,id="theme_"..entry.id,callback=function()
    local ok,why=self.app.typography:apply(chosen.values,chosen.builtin==true,chosen.id)
    if not ok then self.app:message(why) end;UI:setDirty("all","ui")
   end}
   self.theme_tiles[#self.theme_tiles+1]={id=entry.id,selected=active,x=x+cx,y=y+iy,w=side,h=side}
  end
 end
 clip:free()
 local fy=y+h-footer
 bb:paintBorder(x+S(24),fy+S(8),w-S(48),S(48),S(1.5),B.COLOR_BLACK)
 P.button(self,bb,"保存当前设置",x+S(24),fy+S(8),w-S(48),S(48),function() self:themeSave() end,{align="center",id="theme_save"})
 P.rule(bb,x,fy+S(72),w)
 P.button(self,bb,"管理主题",x+S(20),fy+S(72),w-S(40),S(40),function() self:setTab("theme_list") end,{id="theme_manage"})
 P.centerIcon(bb,"chevron.right",x+w-S(50),fy+S(72),S(30),S(40),S(24))
end
function Panel:rows()
 local app=self.app;local rows={};local function row(title,note,fn,more) rows[#rows+1]={title=title,note=note,callback=fn,more=more} end
 if self.tab=="fonts" then
  local face=app.adapter:read("font_face")
  for _,choice in ipairs(app.adapter:choices("font_face")) do local value=choice[1]
   row((value==face and "✓ " or "")..choice[2],nil,function() self:change("font_face",value);self:setTab("font") end)
  end
 elseif self.tab=="theme_list" then
  for _,theme in ipairs(app.themes.records) do local id=theme.id
   local matched=app.typography.meta.theme_id==id and app.typography:matches(theme.values)
   local v=theme.values
   row((matched and "✓ " or "")..theme.name,(v.font_face or "字体").." · "..tostring(v.font_size).." · 行距 "..tostring(v.line_spacing).."%"..(not v.font_gamma and " · 旧主题" or ""),
    function() self:themeApply(id) end,function() self:themeManage(id) end)
  end
  if #rows==0 then row("尚未保存主题",app.themes.error) end
 elseif self.tab=="theme_manage" then
  local theme=assert(app.themes:find(self.theme_id),"主题已不存在");local id=theme.id
  row("套用："..theme.name,nil,function() self:themeApply(id) end)
  row("重命名",nil,function() app.adapter:promptText("重命名主题",theme.name,function(name) app:safe(function()
   local ok,why=app.themes:rename(id,name);if not ok then app:message(why) end;UI:setDirty(self,"ui")
  end) end) end)
  row("用当前排版更新",nil,function() app:confirm("用当前排版更新主题“"..theme.name.."”？",function()
   local ok,why=app.themes:update(id,app.typography:snapshot());if not ok then app:message(why) end;self:setTab("themes")
  end) end)
  row("删除主题",nil,function() app:confirm("删除主题“"..theme.name.."”？当前书籍的排版保留。",function()
   local ok,why=app.themes:delete(id);if not ok then app:message(why) else
    if app.typography.meta.theme_id==id then app.typography.meta.theme_id=nil;app.plugin.ui:saveSettings() end
    self:setTab("themes")
   end
  end) end)
  row("返回主题列表",nil,function() self:setTab("theme_list") end)
 elseif self.tab=="font_options" or self.tab=="layout_options" then
  local ids=self.tab=="font_options" and {"font_hinting","font_kerning","embedded_fonts"} or {"word_spacing","word_expansion","cjk_width_scaling"}
  for _,id in ipairs(ids) do
   local item=Registry.by_id[id];local value,_,why=app.adapter:read(id)
   row(item.title,why or app:valueText(item,value),not why and function() self.option_id=id;self.option_parent=self.tab;self:setTab("option") end or nil)
  end
 elseif self.tab=="option" then
  local id=self.option_id;local item=Registry.by_id[id];local value=app.adapter:read(id)
  row("‹ 返回"..(self.option_parent=="font_options" and "字体选项" or "字距选项"),nil,function() self:setTab(self.option_parent or "layout_options") end)
  row(item.title.."："..app:valueText(item,value),item.help)
  if item.kind=="number" then
   row("减少 "..item.step,nil,function() self:change(id,math.max(item.min,value-item.step)) end)
   row("增加 "..item.step,nil,function() self:change(id,math.min(item.max,value+item.step)) end)
   row("自定义数值",item.min.."—"..item.max,function() app.adapter:promptText(item.title,tostring(value),function(text) app:safe(function() self:change(id,tonumber(text)) end) end) end)
  elseif item.kind=="pair" then
   row("自定义词间距","缩放 / 收缩（%）",function() app.adapter:promptText("缩放 收缩（%）",table.concat(value," "),function(text) app:safe(function()
    local pair={};for token in text:gmatch("%S+") do pair[#pair+1]=tonumber(token) or -1 end;self:change(id,pair)
   end) end) end)
  else
   for _,choice in ipairs(item.kind=="toggle" and {{false,"关闭"},{true,"开启"}} or app.adapter:choices(id)) do
    local v=choice[1];row((Equal(v,value) and "✓ " or "")..choice[2],nil,function() self:change(id,v) end)
   end
  end
 elseif self.tab=="pdf" then
  row("页面裁边、缩放与重排","打开完整页面排版兼容页",function() app:openNativeConfig() end)
  row("页面显示与阅读偏好",nil,function() self:close();app:open("settings") end)
 end
 return rows
end
function Panel:drawList(bb,x,y,w,h)
 local rows=self:rows();self.current_rows=rows
 local footer=0
 local rowh=S(72);local viewh=h-footer
 self.list_area={x=x,y=y,w=w,h=viewh};self.list_max=math.max(0,#rows*rowh-viewh)
 self.list_scroll=math.max(0,math.min(self.list_scroll or 0,self.list_max));self.capacity=math.max(1,math.floor(viewh/rowh))
 local clip=bb:viewport(x,y,w,viewh);local start=math.floor(self.list_scroll/rowh)+1
 for i=start,math.min(#rows,math.ceil((self.list_scroll+viewh)/rowh)) do
  local r=rows[i];local ry=(i-1)*rowh-self.list_scroll
  P.label(clip,r.title,S(20),ry,w-S(r.more and 88 or 48),r.note and S(40) or rowh,P.style.label,true)
  if r.note then P.label(clip,r.note,S(20),ry+S(40),w-S(76),rowh-S(40),P.style.secondary,true) end
  P.rule(clip,S(20),ry+rowh-S(2),w-S(48),1.2)
  local hy=math.max(y,y+ry);local hh=math.max(0,math.min(y+viewh,y+ry+rowh)-hy)
  self.hits[#self.hits+1]={x=x,y=hy,w=w-(r.more and S(70) or S(18)),h=hh,callback=r.callback,hold_callback=r.more,id='aa_row_'..i}
  if r.more then
   P.text(clip,"⋯",w-S(60),ry+S(15),S(42),22,true)
   self.hits[#self.hits+1]={x=x+w-S(70),y=hy,w=S(48),h=hh,callback=r.more,id='aa_row_more_'..i}
  end
 end
 clip:free()
 if self.list_max>0 then
  local th=math.max(S(24),math.floor(viewh*viewh/(#rows*rowh)))
  bb:paintRect(x+w-S(10),y,S(2),viewh,B.COLOR_DARK_GRAY)
  bb:paintRect(x+w-S(12),y+math.floor((viewh-th)*self.list_scroll/self.list_max),S(6),th,B.COLOR_BLACK)
 end

end

function Panel:drawSlider(bb,id,label,x,y,w,h)
 local item=Registry.by_id[id];local pending=self.pending_adjustment
 local value=pending and pending.id==id and pending.value or self.app.adapter:read(id)
 local high=id=="font_size" and math.max(72,value) or item.max
 local text=id=="font_gamma" and self.app.adapter:gammaLabel(value) or tostring(value)
 P.label(bb,label,x+S(20),y,w*.5,S(34),P.style.label,true)
 P.label(bb,text,x+w-S(100),y,S(80),S(34),P.style.label,true,"center")
 local sy=y+S(34);local sh=h-S(34)
 P.button(self,bb,"−",x+S(8),sy,S(52),sh,function() self:change(id,math.max(item.min,self.app.adapter:read(id)-item.step)) end,{size=24,align="center",id=id.."_minus"})
 P.button(self,bb,"+",x+w-S(60),sy,S(52),sh,function() self:change(id,math.min(item.max,self.app.adapter:read(id)+item.step)) end,{size=24,align="center",id=id.."_plus"})
 local sx,sw=x+S(76),w-S(152);local ly=sy+math.floor(sh/2)
 P.rule(bb,sx,ly,sw,3)
 local kx=math.floor(sx+(value-item.min)/(high-item.min)*sw)
 bb:paintCircle(kx,ly,S(10),B.COLOR_BLACK);bb:paintCircle(kx,ly,S(7),B.COLOR_WHITE)
 local slider={id=id,x=sx,y=sy,w=sw,h=sh,low=item.min,high=high,step=item.step}
 self.sliders[#self.sliders+1]=slider;if id=="font_size" then self.slider=slider end
 self.hits[#self.hits+1]={x=sx,y=sy,w=sw,h=sh,callback=function(pos) self:change(id,self:sliderValue(pos,slider)) end,id=id.."_slider"}
end
function Panel:paintTo(bb,x,y)
 self.hits={};self.sliders={};self.slider=nil;self.list_area=nil;self.list_max=nil
 local w,h=self.dimen.w,self.dimen.h;local toolbar=S(P.style.toolbar_h);local ty=y+h-toolbar
 local can=self.app.typography and self.app.typography:available()
 if not can and self.tab~="menu" then self.tab="pdf" end
 local height=0
 if self.tab=="font" then height=S(P.style.panel_font_h)
 elseif self.tab=="layout" then height=S(P.style.panel_layout_h)
 elseif self.tab=="themes" then height=S(440)
 elseif self.tab~="menu" then height=S(400) end
 height=math.min(height,h-toolbar-S(64));self.panel_y=ty-height
 if height>0 then
  local py=self.panel_y;bb:paintRect(x,py,w,height,B.COLOR_WHITE);P.rule(bb,x,py,w,2)
  if can then
   local titles={font="字体",fonts="选择字体",layout="排版",themes="主题",theme_manage="主题管理",theme_list="管理主题",font_options="字体选项",layout_options="字距选项",option=Registry.by_id[self.option_id] and Registry.by_id[self.option_id].title or "排版选项"}
   local back=self:parentTab()
   if back then
    P.centerIcon(bb,"chevron.left",x,py,S(44),S(54),S(24))
    self.hits[#self.hits+1]={x=x,y=py,w=S(44),h=S(54),callback=function() self:back() end,id="aa_back"}
   end
   local left=back and S(48) or S(20)
   P.label(bb,titles[self.tab] or "排版",x+left,py,w-left-S(60),S(54),20,true)
  else P.label(bb,"页面排版",x+S(20),py,w-S(80),S(54),P.style.label,true) end
  P.centerIcon(bb,"close",x+w-S(54),py,S(54),S(54),S(24));self.hits[#self.hits+1]={x=x+w-S(54),y=py,w=S(54),h=S(54),callback=function() self:close() end,id="aa_close"}
  P.rule(bb,x+S(16),py+S(54),w-S(32))
  local cy=py+S(54)
  if self.tab=="font" then
   local scale=math.min(1,(height-S(54))/S(368));local function F(n) return math.floor(S(n)*scale) end
   P.button(self,bb,"字体",x+S(12),cy,w-S(24),F(64),function() self:setTab("fonts") end,{id="aa_font_face"})
   P.label(bb,self.app.adapter:read("font_face").." ›",x+w*.28,cy,w*.72-S(24),F(64),P.style.label,true)
   P.rule(bb,x+S(20),cy+F(64),w-S(40))
   self:drawSlider(bb,"font_size","字号",x,cy+F(64),w,F(92))
   self:drawSlider(bb,"font_gamma","对比度",x,cy+F(156),w,F(80))
   self:drawSlider(bb,"font_base_weight","字重",x,cy+F(236),w,F(80))
   P.button(self,bb,"字体选项 ›",x+S(12),cy+F(316),w-S(24),F(52),function() self:setTab("font_options") end,{id="aa_font_options"})
  elseif self.tab=="layout" then
   local value=self.app.adapter:read("line_spacing");P.label(bb,"行距",x+S(20),cy,w*.3,S(72),18,true)
   local margins=self.app.adapter:read("page_margins")
   for ri,entries in ipairs({{{110,"紧凑"},{120,"标准"},{140,"宽松"}},{{8,"窄"},{12,"标准"},{18,"宽"}}}) do
    local ry=cy+(ri-1)*S(72);if ri==2 then P.label(bb,"页边距",x+S(20),ry,w*.3,S(72),18,true) end
    local bw=math.min(S(78),w*.2)
    for i,entry in ipairs(entries) do local v=entry[1];local bx=x+w-3*(bw+S(6))+(i-1)*(bw+S(6))-S(14)
     local selected=ri==1 and value==v or ri==2 and Equal(margins,{v,v,v,v})
     bb:paintBorder(bx,ry+S(10),bw,S(52),S(selected and 3 or 1.5),B.COLOR_BLACK)
     P.button(self,bb,entry[2],bx,ry+S(10),bw,S(52),function() self:change(ri==1 and "line_spacing" or "page_margins",ri==1 and v or {v,v,v,v}) end,{align="center"})
    end
   end
   local css=self.app.adapter:read("embedded_css")
   P.button(self,bb,"书内样式："..(css and "开启" or "关闭"),x+S(12),cy+S(154),w*.52,S(58),function() self:change("embedded_css",not css) end)
   P.button(self,bb,"高级排版 ›",x+w*.54,cy+S(154),w*.46-S(12),S(58),function() self.app.native:refresh();self.app:open("catalog_category","typography") end,{id="advanced_typography"})
   P.button(self,bb,"字距选项 ›",x+S(12),cy+S(212),w-S(24),S(52),function() self:setTab("layout_options") end,{id="aa_layout_options"})
  elseif self.tab=="themes" then self:drawThemes(bb,x,cy,w,height-S(54))
  else self:drawList(bb,x,cy,w,height-S(54)) end

 end
 bb:paintRect(x,ty,w,toolbar,B.COLOR_WHITE);P.rule(bb,x,ty,w,2)
 local buttons={{"主题","themes"},{"字体","font"},{"排版","layout"}}
 self.toolbar_layout={};self.toolbar_buttons={}
 for i,b in ipairs(buttons) do
  local tab=b[2];local bw=w/3;local target=not can and tab=="layout" and "pdf" or tab
  self.toolbar_layout[i]=P.button(self,bb,b[1],x+(i-1)*bw,ty,bw,toolbar,function() self:setTab(target) end,
   {size=P.style.toolbar,disabled=i<3 and not can,bold=true,align="center",id="reader_bottom_"..b[2]})
  self.toolbar_buttons[i]=b[1]
  local active=self.tab==target or tab=="font" and (self.tab=="fonts" or self.tab=="font_options" or self.tab=="option" and self.option_parent=="font_options") or tab=="layout" and (self.tab=="layout_options" or self.tab=="option" and self.option_parent=="layout_options") or tab=="themes" and (self.tab=="theme_manage" or self.tab=="theme_list")
  if active then bb:paintRect(x+(i-.5)*bw-S(24),ty+toolbar-S(10),S(48),S(3),B.COLOR_BLACK) end
 end
end
function Panel:sliderValue(pos,slider)
 local s=slider or self.slider;local value=s.low+math.floor((pos.x-s.x)/s.w*(s.high-s.low)/s.step+.5)*s.step
 return math.max(s.low,math.min(s.high,value))
end
function Panel:onReaderTap(_,ges)
 if not ges or not ges.pos then return true end
 local fn=P.find(self,ges.pos)
 if fn then self.app:safe(function() fn(ges.pos) end)
 elseif ges.pos.y<self.panel_y then self:close() end
 return true
end
function Panel:onReaderHold(_,ges)
 if ges and ges.pos then local fn=P.find(self,ges.pos,true);if fn then self.app:safe(fn) end end;return true
end
function Panel:onReaderPan(_,ges)
 if ges and ges.pos then
  local selected=self.pending_adjustment and self.pending_adjustment.slider
  if not selected then for _,slider in ipairs(self.sliders or {}) do
   if ges.pos.y>=slider.y and ges.pos.y<slider.y+slider.h then selected=slider;break end
  end end
  if selected then
   self.pending_adjustment={id=selected.id,value=self:sliderValue(ges.pos,selected),slider=selected}
   UI:setDirty(self,"ui");return true
  end
 end
 if self.list_area and ges and ges.relative then self.list_pan=ges.relative.y end
 return true
end
function Panel:onReaderPanRelease(_,ges)
 if self.pending_adjustment then local pending=self.pending_adjustment;self.app:safe(function() self:change(pending.id,pending.value) end)
 elseif self.list_max and (self.list_pan or (ges and ges.relative)) then
  local delta=ges and ges.relative and ges.relative.y or self.list_pan
  self.list_scroll=math.max(0,math.min(self.list_max,(self.list_scroll or 0)-(delta or 0)));UI:setDirty(self,"ui")
 end
 self.list_pan=nil;return true
end
function Panel:turn(delta)
 if self.list_area then self.list_scroll=math.max(0,math.min(self.list_max or 0,(self.list_scroll or 0)+delta*self.list_area.h*.65)) end
 UI:setDirty(self,"ui")
end
function Panel:onReaderSwipe(_,ges)
 if ges and ges.direction=="south" and ges.pos and ges.pos.y<S(60) then self.app:safe(function() self.app:showControls() end)
 elseif ges and self.list_area and ges.direction=="north" then self:turn(1)
 elseif ges and self.list_area and ges.direction=="south" then self:turn(-1)
 elseif ges and ges.direction=="west" then self:turn(1)
 elseif ges and ges.direction=="east" then self:turn(-1)
 elseif ges and ges.direction=="south" then self:close() end
 return true
end
function Panel:onKeyPress(key)
 if key:match({Device.input.group.Back}) then self:back()
 elseif key:match({Device.input.group.PgFwd}) then self:turn(1)
 elseif key:match({Device.input.group.PgBack}) then self:turn(-1) end
 return true
end
Panel.onKeyRepeat=Panel.onKeyPress
function Panel:onSetDimensions() self:init();UI:setDirty(self,"full");return true end
return Panel
