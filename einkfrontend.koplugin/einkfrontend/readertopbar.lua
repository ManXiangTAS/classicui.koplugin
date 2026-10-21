-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Kindle-inspired reading chrome. The underlying document is never replaced.
local Input=require("ui/widget/container/inputcontainer")
local Device=require("device")
local UI=require("ui/uimanager")
local GestureRange=require("ui/gesturerange")
local P=require("einkfrontend/paint");local S=P.s;local B=P.BB
local Bar=Input:extend{stop_events_propagation=true}
function Bar:init()
 self.dimen=Device.screen:getSize();self.panel_h=S(156)
 self.ges_events={ReaderTopTap={GestureRange:new{ges="tap",range=self.dimen}},ReaderTopSwipe={GestureRange:new{ges="swipe",range=self.dimen}},ReaderTopHold={GestureRange:new{ges="hold",range=self.dimen}}}
end
function Bar:close() UI:close(self,"ui");UI:setDirty("all","ui") end
function Bar:onCloseWidget() if self.app.reader_topbar==self then self.app.reader_topbar=nil end end
function Bar:action(id)
 self:close()
 if id=="library" then self.app:returnToOrigin()
 elseif id=="aa" then self.app:showReader("font")
 elseif id=="statistics" then self.app:showBookStatistics()
 else self.app.adapter:dispatch(id) end
end
function Bar:paintTo(bb,x,y)
 self.hits={};local w=self.dimen.w
 bb:paintRect(x,y,w,self.panel_h,B.COLOR_WHITE)
 P.inkLabel(bb,os.date("%H:%M"),x+S(20),y,w*.3,S(36),18,true,nil,"left")
 P.centerIcon(bb,"chevron.down",x+w/2-S(38),y,S(76),S(36),S(24))
 self.hits[#self.hits+1]={x=x+w/2-S(38),y=y,w=S(76),h=S(36),callback=function() self.app:showControls() end,id="reader_quick_controls"}
 local status=self.app.adapter:deviceStatus()
 self.battery_layout=P.battery(bb,status.battery,x+w-S(20)-S(104),y,S(104),S(36))
 local ty=y+S(39);local toolbar_h=S(54)
 P.centerIcon(bb,"chevron.left",x,ty,S(46),toolbar_h,S(25))
 P.label(bb,self.app:readingReturnLabel(),x+S(46),ty,S(72),toolbar_h,18,true)
 self.hits[#self.hits+1]={x=x,y=ty,w=S(120),h=toolbar_h,callback=function() self:action("library") end,id="reader_return_library"}
 local buttons={{"aa","Aa"},{"ShowToc","appbar.menu"},{"ShowBookmark","bookmark"},{"ShowFulltextSearchInput","appbar.search"},{"statistics","statistics"}}
 local cw=math.min(S(54),(w-S(132))/#buttons)
 for i,button in ipairs(buttons) do
  local bx=x+w-#buttons*cw+(i-1)*cw;local id=button[1]
  if id=="aa" then P.label(bb,button[2],bx,ty,cw,toolbar_h,20,true,"center")
  elseif id=="statistics" then P.statisticsIcon(bb,bx,ty,cw,toolbar_h)
  else P.centerIcon(bb,button[2],bx,ty,cw,toolbar_h,S(26)) end
  self.hits[#self.hits+1]={x=bx,y=ty,w=cw,h=toolbar_h,callback=function() self:action(id) end,id="reader_"..id}
 end
 P.rule(bb,x,y+S(96),w,1.5)
 local props=self.app.plugin.ui.doc_props or {}
 local title=props.display_title or props.title or self.app.plugin.ui.document.file:match("([^/]+)$")
 P.text(bb,title,x+S(20),y+S(116),w-S(40),18,true)
 P.rule(bb,x,y+self.panel_h-S(2),w,2)

end
function Bar:onReaderTopTap(_,ges)
 if ges and ges.pos then
  local fn=P.find(self,ges.pos)
  if fn then self.app:safe(fn) else self:close() end
 end
 return true
end
function Bar:onReaderTopSwipe(_,ges)
 if ges and ges.direction=="south" then self.app:safe(function() self.app:showControls() end)
 elseif ges and ges.direction=="north" then self:close() end
 return true
end
function Bar:onReaderTopHold() return true end
function Bar:onKeyPress(key) if key:match({Device.input.group.Back}) then self:close() end;return true end
Bar.onKeyRepeat=Bar.onKeyPress
function Bar:onSetDimensions() self:init();UI:setDirty(self,"ui");return true end
return Bar
