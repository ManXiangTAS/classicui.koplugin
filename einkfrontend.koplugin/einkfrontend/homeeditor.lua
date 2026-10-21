-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Input=require('ui/widget/container/inputcontainer')
local Device=require('device');local UI=require('ui/uimanager');local Gesture=require('ui/gesturerange')
local P=require('einkfrontend/paint');local S=P.s;local B=P.BB
local Layout=require('einkfrontend/homelayout');local Copy=require('einkfrontend/catalog').copy
local Equal=require('einkfrontend/adapter').equal
local Fit=require('einkfrontend/homefit')
local Editor=Input:extend{covers_fullscreen=true,stop_events_propagation=true}
function Editor:init()
 self.dimen=Device.screen:getSize();self.base=Copy(self.app.home_layout.config);self.draft=Copy(self.base)
 self.revision=0;self.query='';self.scroll=0;self.preview_scroll=0;self.selected=self.selected or 'currently'
 self.ges_events={EditorTap={Gesture:new{ges='tap',range=self.dimen}},EditorSwipe={Gesture:new{ges='swipe',range=self.dimen}}}
 self:refreshPreview()
end
function Editor:refreshPreview()
 if self.preview then self.preview:free();self.preview=nil end
 local layout=setmetatable({config=self.draft}, {__index=self.app.home_layout})
 local proxy=setmetatable({home_layout=layout}, {__index=self.app})
 local page={app=proxy,dimen=self.dimen,model={home=true,home_data=require('einkfrontend/home').model(proxy),route={scroll_y=self.preview_scroll}},hits={}}
 local bb=B.new(self.dimen.w,self.dimen.h,B.TYPE_BB8)
 require('einkfrontend/shell').home(page,bb,0,0)
 self.preview=bb;self.preview_max=0;self.preview_scroll=0;self.preview_fit=page.home_fit
 UI:setDirty(self,'ui')
end
function Editor:change(fn)
 local draft=Copy(self.draft);local ok,why=pcall(function() fn(draft);Layout.validate(draft) end)
 if not ok then self.app:message(why);return false,tostring(why) end
 local fits,reason=Fit.checkChange(self.draft,draft,self.dimen.w,Fit.viewport(self.dimen.h))
 if not fits then self.app:message(reason);return false,reason end
 self.draft=draft;self.revision=self.revision+1;self:refreshPreview();return true
end
function Editor:replaceDraft(config,revision)
 if revision~=self.revision then return false,'conflict' end
 local ok,why=pcall(Layout.validate,config);if not ok then return false,tostring(why) end
 local fits,reason=Fit.checkChange(self.draft,config,self.dimen.w,Fit.viewport(self.dimen.h));if not fits then return false,reason end
 self.draft=Copy(config);self.revision=self.revision+1;self:refreshPreview();return true
end
function Editor:save(keep_open)
 if not self.preview_fit.fits then return false,'本屏放不下全部部件，请先隐藏部分部件或调整宽度' end
 if not Equal(self.app.home_layout.config,self.base) then return false,'主页已在其他窗口修改，请关闭编辑器后重试' end
 local ok,why=self.app.home_layout:commit(self.draft)
 if not ok then return false,why end
 self.base=Copy(self.draft)
 if self.app.screen then self.app:render() end
 if not keep_open then self:close() end
 return true
end
function Editor:close() UI:close(self,'ui');UI:setDirty('all','ui') end
function Editor:requestClose()
 if Equal(self.base,self.draft) then self:close()
 else self.app:confirm('放弃尚未保存的主页修改？',function() self:close() end) end
end
function Editor:onCloseWidget()
 self.closed=true
 if self.server then self.server:stop();self.server=nil end
 if self.preview then self.preview:free();self.preview=nil end
 if self.app.home_editor==self then self.app.home_editor=nil end
end
function Editor:onSuspend() if self.server then self.server:stop();self.server=nil end end
function Editor:search()
 self.app.adapter:promptText('搜索主页部件',self.query,function(q) if self.closed then return end;self.query=q;self.scroll=0;UI:setDirty(self,'ui') end)
end
function Editor:rows()
 local rows={};local needle=self.query:lower()
 for _,widget in ipairs(self.draft.widgets) do
  local def=Layout.by_id[widget.id]
  local keywords=({weekly='七天 柱图 一周',streak='连续 天数',stats_table='统计 数据 表格',heatmap='热力值 日历',daily_goal='每日 目标 分钟',daypart='时段 分布 时间',currently='当前 最近 阅读',quote='名言 语录'})[widget.id] or ''
  if (def.name..' '..keywords..' '..widget.id):lower():find(needle,1,true) then rows[#rows+1]=widget end
 end
 return rows
end
function Editor:options()
 local id=self.selected;local rows={};local function add(label,fn) rows[#rows+1]={label,fn} end
 add('间距：'..(self.draft.spacing=='compact' and '紧凑' or '标准'),function() self:change(function(c) c.spacing=c.spacing=='compact' and 'standard' or 'compact' end) end)
 if id=='recent' or id=='tbr' then local key=id=='tbr' and 'tbr_count' or 'recent_count'
  add('书架：'..self.draft[key]..'本',function() self:change(function(c) c[key]=c[key]==3 and 5 or 3 end) end)
 elseif id=='heatmap' then add('热力图：'..self.draft.heatmap_weeks..'周',function() self:change(function(c) c.heatmap_weeks=({[6]=12,[12]=24,[24]=6})[c.heatmap_weeks] end) end)
 elseif id=='daily_goal' then add('目标：'..self.draft.daily_goal_minutes..'分钟',function()
  self.app.adapter:promptText('每日目标（分钟）',tostring(self.draft.daily_goal_minutes),function(text) if self.closed then return end;return self:change(function(c) c.daily_goal_minutes=tonumber(text) end) end,{keep_on_error=true}) end)
 elseif id=='quote' then add('编辑名言',function() self.app.adapter:promptText('名言（每行正文｜出处）',self.draft.quote_text,function(text) if self.closed then return end;return self:change(function(c) c.quote_text=text;c.quote_index=1 end) end,{multiline=true,keep_on_error=true}) end)
 end
 add('恢复布局',function() self.app:confirm('恢复默认布局？将保留名言内容。',function() self:change(function(c) c.widgets=Layout.defaults().widgets;c.spacing='standard' end) end) end)
 return rows
end
function Editor:mobile()
 if self.server then self.server:showAddress();return end
 require('ui/network/manager'):runWhenConnected(function()
  if self.closed then return end
  local ok,server=pcall(require('einkfrontend/homeweb').new,self)
  if ok then self.server=server;server:showAddress() else self.app:message('无法开启手机编辑：'..tostring(server)) end
 end)
end
function Editor:paintTo(bb,x,y)
 local w,h=self.dimen.w,self.dimen.h;self.hits={};bb:paintRect(x,y,w,h,B.COLOR_WHITE)
 if self.full_preview then
  bb:blitFrom(self.preview,x,y,0,0,w,h)
  P.button(self,bb,'返回编辑',x+w-S(120),y+S(42),S(116),S(52),function() self.full_preview=false;UI:setDirty(self,'ui') end,{id='editor_preview_back'})
  return
 end
 P.inkLabel(bb,'编辑主页',x+S(18),y,w*.42,S(54),20,true,nil,'left')
 P.button(self,bb,'手机编辑',x+w-S(240),y,S(130),S(54),function() self:mobile() end,{align='center',id='editor_mobile'})
 P.button(self,bb,'保存',x+w-S(110),y,S(60),S(54),function() local ok,why=self:save();if not ok then self.app:message(why) end end,{align='center',id='editor_save'})
 P.centerIcon(bb,'close',x+w-S(48),y,S(48),S(54),S(24))
 self.hits[#self.hits+1]={x=x+w-S(48),y=y,w=S(48),h=S(54),callback=function() self:requestClose() end,id='editor_close'}
 P.rule(bb,x,y+S(54),w)
 local ph=math.floor(h*.40);local pw=math.floor(ph*w/h);local px=x+math.floor((w-pw)/2);local py=y+S(60)
 local scaled=self.preview:scale(pw,ph);bb:blitFrom(scaled,px,py,0,0,pw,ph);scaled:free();bb:paintBorder(px,py,pw,ph,1,B.COLOR_BLACK)
 P.inkLabel(bb,'一屏预览',x+S(12),py,S(120),S(32),14,true,nil,'left')
 local fit=self.preview_fit
 P.inkLabel(bb,fit.visible..' / '..fit.requested..' 部件',x+S(12),py+S(34),S(120),S(28),13,true,nil,'left')
 if not fit.fits then P.inkLabel(bb,'超出 '..#fit.omitted..' 个',x+S(12),py+S(64),S(120),S(28),13,true,nil,'left') end
 self.preview_area={x=px,y=py,w=pw,h=ph}
 self.hits[#self.hits+1]={x=px,y=py,w=pw,h=ph,callback=function() self.full_preview=true;UI:setDirty(self,'ui') end,id='editor_preview'}
 local cy=py+ph+S(6)
 P.button(self,bb,self.query~='' and '搜索：'..self.query or '搜索主页部件',x+S(12),cy,w-S(64),S(42),function() self:search() end,{size=16,id='editor_search'})
 if self.query~='' then P.button(self,bb,'×',x+w-S(48),cy,S(42),S(42),function() self.query='';self.scroll=0;UI:setDirty(self,'ui') end,{align='center',id='editor_search_clear'}) end
 cy=cy+S(42);local options=self:options();local bottom=S(48);local viewh=math.max(S(40),y+h-cy-bottom);local rowh=S(52)
 local rows=self:rows();self.filtered=rows;self.list_max=math.max(0,#rows*rowh-viewh);self.scroll=math.max(0,math.min(self.scroll,self.list_max));self.list_area={x=x,y=cy,w=w,h=viewh}
 local clip=bb:viewport(x,cy,w,viewh)
 if #rows==0 then P.inkLabel(clip,'没有匹配的部件',S(20),0,w-S(40),S(52),18,true,nil,'left') end
 for i,widget in ipairs(rows) do
  local ry=(i-1)*rowh-self.scroll
  if ry+rowh>0 and ry<viewh then
   local id=widget.id;local active=self.selected==id
   if active then clip:paintRect(0,math.max(0,ry),S(3),math.min(rowh,viewh-math.max(0,ry)),B.COLOR_BLACK) end
   local prefix=widget.enabled and '✓ ' or '＋ '
   for _,missing in ipairs(self.preview_fit.omitted) do if missing==id then prefix='超出 ' end end
   P.inkLabel(clip,prefix..Layout.by_id[id].name,S(14),ry,w-S(238),rowh,16,true,nil,'left')
   local hy=math.max(cy,cy+ry);local hh=math.min(cy+viewh,cy+ry+rowh)-hy
   local function action(left,width,label,fn,hitid)
    P.inkLabel(clip,label,left,ry,width,rowh,16,true)
    self.hits[#self.hits+1]={x=x+left,y=hy,w=width,h=hh,callback=fn,id=hitid}
   end
   self.hits[#self.hits+1]={x=x,y=hy,w=w-S(226),h=hh,id='editor_select_'..id,callback=function() self.selected=id;UI:setDirty(self,'ui') end}
   action(w-S(226),S(56),widget.enabled and '隐藏' or '显示',function() self.selected=id;self:change(function(c) Layout.find(self.app.home_layout,id,c).enabled=not widget.enabled end) end,'editor_toggle_'..id)
   action(w-S(168),S(64),widget.span==2 and '整行' or '半行',function() self.selected=id;self:change(function(c) Layout.find(self.app.home_layout,id,c).span=widget.span==2 and 1 or 2 end) end,'editor_span_'..id)
   for delta=-1,1,2 do local move=delta
    action(w-S(move==-1 and 100 or 52),S(46),move==-1 and '↑' or '↓',function() self.selected=id;self:change(function(c)
     local item,index=Layout.find(self.app.home_layout,id,c);table.remove(c.widgets,index);table.insert(c.widgets,math.max(1,math.min(#c.widgets+1,index+move)),item)
    end) end,'editor_move_'..id..'_'..move)
   end
   P.rule(clip,S(12),ry+rowh-1,w-S(24))
  end
 end
 clip:free();local oy=y+h-bottom;P.rule(bb,x,oy,w)
 for i,option in ipairs(options) do local opt=option;P.button(self,bb,opt[1],x+(i-1)*w/#options,oy,w/#options,bottom,opt[2],{align='center',size=15,id='editor_option_'..i}) end
end
function Editor:onEditorTap(_,ges)
 if ges and ges.pos then local fn=P.find(self,ges.pos);if fn then self.app:safe(fn) end end;return true
end
function Editor:onEditorSwipe(_,ges)
 if not ges then return true end
 local delta=ges.direction=='north' and 1 or ges.direction=='south' and -1 or 0
 if self.full_preview or (ges.pos and self.preview_area and ges.pos.y<self.preview_area.y+self.preview_area.h) then
  return true
 else self.scroll=math.max(0,math.min(self.list_max or 0,self.scroll+delta*S(156)));UI:setDirty(self,'ui') end
 return true
end
function Editor:onSetDimensions()
 self.dimen=Device.screen:getSize();for _,seq in pairs(self.ges_events) do seq[1].range=self.dimen end
 self.preview_scroll=0;self.revision=self.revision+1;self:refreshPreview();return true
end
function Editor:onKeyPress(key) if key:match({Device.input.group.Back}) then self:requestClose() end;return true end
return Editor
