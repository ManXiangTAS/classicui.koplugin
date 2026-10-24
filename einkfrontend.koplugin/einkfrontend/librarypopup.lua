-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- KoboUI library-header organization, rendered by this frontend's own widgets.
local Input=require("ui/widget/container/inputcontainer")
local Device=require("device")
local UI=require("ui/uimanager")
local GestureRange=require("ui/gesturerange")
local P=require("einkfrontend/paint");local S=P.s
local Browser=require("einkfrontend/browser")
local Popup=Input:extend{stop_events_propagation=true}
function Popup:init()
 self.dimen=Device.screen:getSize()
 self.ges_events={LibraryMenuTap={GestureRange:new{ges="tap",range=self.dimen}},LibraryMenuSwipe={GestureRange:new{ges="swipe",range=self.dimen}},LibraryMenuHold={GestureRange:new{ges="hold",range=self.dimen}}}
end
function Popup:close() UI:close(self,"ui") end
function Popup:onCloseWidget() if self.app.library_popup==self then self.app.library_popup=nil end end
function Popup:refresh()
 self.app:render();self.app:saveLibraryView();UI:setDirty(self,"ui")
end
function Popup:rows()
 local app=self.app;local rows={}
 local function add(text,checked,fn) rows[#rows+1]={text=text,checked=checked,callback=fn} end
 if self.kind=="filter" then
  add("全部（"..#app.library:list({query=app.browser.filter.query}).."）",not next(app.browser.filter.statuses),function()
   app.browser.filter.statuses={};app:resetLibraryPages();self:refresh()
  end)
  for _,state in ipairs(Browser.states) do local value=state
   add(value.."（"..#app.library:list({status=value,query=app.browser.filter.query}).."）",app.browser.filter.statuses[value],function()
    app.browser.filter.statuses[value]=not app.browser.filter.statuses[value] or nil;app:resetLibraryPages();self:refresh()
   end)
  end
 elseif self.kind=="sort" then
  for _,id in ipairs({"last_opened","recent","title","author"}) do local value=id
   add(Browser.sort_labels[value],app.library_sort==value,function()
    self:close();app.library_sort=value;app:resetLibraryPages();app:render();app:saveLibraryView()
   end)
  end
 else
  for _,entry in ipairs({{"封面视图","grid"},{"列表视图","list"}}) do local value=entry[2]
   add(entry[1],app.library_layout==value,function() self:close();app.library_layout=value;app:render();app:saveLibraryView() end)
  end
  if app.browser.active=="collections" then
   add("管理收藏",nil,function() self:close();app:go("collection_manager") end)
  end
  add("重新扫描书库",nil,function() self:close();app:scanLibrary(app.library.root or app.adapter:libraryRoot()) end)
  add("更换书库目录",nil,function()
   self:close();app.adapter:chooseLibraryRoot(app.library.root or app.adapter:libraryRoot(),function(path) app:safe(function() app:scanLibrary(path) end) end)
  end)
  if app.adapter:hasKindleLibrary() then add("Kindle 原生书库",nil,function() self:close();app:close();app.adapter:openKindleLibrary() end) end
 end
 return rows
end
function Popup:paintTo(bb,x,y)
 self.hits={};self.current_rows=self:rows()
 local w=math.min(self.dimen.w-S(32),S(286));local rh=S(44)
 local px=self.kind=="filter" and x+S(16) or x+self.dimen.w-w-S(16)
 local py=y+(self.app.screen and self.app.screen.header_h+self.app.screen.info_h or S(106))
 py=math.min(py,y+self.dimen.h-rh*#self.current_rows-S(12))
 self.box={x=px,y=py,w=w,h=rh*#self.current_rows}
 bb:paintRect(px,py,w,self.box.h,P.BB.COLOR_WHITE);bb:paintBorder(px,py,w,self.box.h,1,P.BB.COLOR_BLACK)
 for i,row in ipairs(self.current_rows) do
  local ry=py+(i-1)*rh
  P.button(self,bb,(row.checked and "✓ " or "    ")..row.text,px+S(5),ry,w-S(10),rh,row.callback,{size=14})
  if i<#self.current_rows then P.line(bb,px+S(12),ry+rh,w-S(24)) end
 end
end
function Popup:onLibraryMenuTap(_,ges)
 if not ges or not ges.pos then return true end
 if not P.activate(self,ges.pos) then self:close() end
 return true
end
function Popup:onLibraryMenuSwipe() return true end
function Popup:onLibraryMenuHold() return true end
function Popup:onKeyPress(key) if key:match({Device.input.group.Back}) then self:close() end;return true end
Popup.onKeyRepeat=Popup.onKeyPress
function Popup:onSetDimensions() self:close();return true end
return Popup
