-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- PocketBook-inspired controls, capability-filtered for the actual device.
local Input=require("ui/widget/container/inputcontainer")
local GestureRange=require("ui/gesturerange")
local Device=require("device");local UI=require("ui/uimanager")
local P=require("einkfrontend/paint");local S=P.s;local B=P.BB
local Controls=Input:extend{stop_events_propagation=true}
function Controls:init()
 self.dimen=Device.screen:getSize();self.panel_h=math.min(self.dimen.h-S(90),S(56+math.ceil(#self:actions()/3)*116+(self.app.adapter:deviceStatus().frontlight and (174+(self:hasAutoLight() and 44 or 0)) or 0)+44))
 self.ges_events={ControlTap={GestureRange:new{ges="tap",range=self.dimen}},ControlSwipe={GestureRange:new{ges="swipe",range=self.dimen}},
 ControlPan={GestureRange:new{ges="pan",range=self.dimen}}}
end
function Controls:hasAutoLight() return self.app.autolight and Device.hasLightSensor and Device:hasLightSensor() end
function Controls:close() UI:close(self,"ui");UI:setDirty("all","ui") end
function Controls:onCloseWidget() if self.app.controls==self then self.app.controls=nil end end
function Controls:actions()
 local app=self.app;local state=app.adapter:deviceStatus()
 local actions={}
 if state.wifi then actions[#actions+1]={"Wi-Fi",function() self:close();app.adapter:showWifi() end,icon="wifi"} end
 actions[#actions+1]={"夜间模式",function() app.adapter:toggleNightMode();UI:setDirty("all","full") end,icon="night",checked=state.night}
 actions[#actions+1]={"屏幕旋转",function()
  local mode=Device.screen:getRotationMode();self:close();app.adapter:dispatch("SetRotationMode",(mode+1)%4)
 end,icon="appbar.rotation"}
 actions[#actions+1]={"全屏刷新",function() UI:setDirty("all","full") end,icon="cre.render.reload.alpha"}
 actions[#actions+1]={"设置",function() self:close();app:open("settings") end,icon="appbar.settings",id="control_settings"}
 return actions
end
function Controls:paintTo(bb,x,y)
 self.hits={};self.action_layout={};local w=self.dimen.w
 bb:paintRect(x,y,w,self.panel_h,B.COLOR_WHITE)
 P.text(bb,os.date("%m月%d日  %H:%M"),x+S(20),y+S(17),w-S(150),18,true)
 self.battery_layout=P.battery(bb,self.app.adapter:deviceStatus().battery,x+w-S(20)-S(104),y,S(104),S(52))
 local actions=self:actions();local columns=3;local cw=(w-S(32))/columns
 local rows=math.ceil(#actions/columns);local base=56+rows*116
 for i,a in ipairs(actions) do
  local row=math.floor((i-1)/columns);local count=math.min(columns,#actions-row*columns)
  local cx=math.floor(x+w/2+(i-row*columns-(count+1)/2)*cw+.5);local cy=y+S(92+row*116)
  local radius=S(26);bb:paintCircle(cx,cy,radius,B.COLOR_BLACK,math.max(2,S(1.5)))
  local icon=P.inkIcon(bb,a.icon,cx-radius,cy-radius,2*radius,2*radius,S(34),"controls")
  if a.checked then P.rule(bb,cx-S(13),cy+S(28),S(26),2) end
  local m=P.label(bb,a[1],cx-cw/2,cy+S(32),cw,S(36),P.style.label,true,"center")
  self.action_layout[#self.action_layout+1]={label=a[1],cx=cx,cy=cy,radius=radius,icon=icon,label_x=m.x,label_w=m.w,id=a.id}
  self.hits[#self.hits+1]={x=cx-cw/2,y=cy-S(34),w=cw,h=S(104),callback=a[2],id=a.id,
   feedback_circle={cx=cx,cy=cy,r=radius}}
 end
 local state=self.app.adapter:deviceStatus()
 if state.frontlight then
  local power=Device:getPowerDevice();local on=power:isFrontlightOn()
  P.rule(bb,x+S(20),y+S(base),w-S(40),1.2)
  P.text(bb,"前光",x+S(20),y+S(base+18),w-S(100),18,true)
  local tx,ty,tw,th=x+w-S(70),y+S(base+11),S(48),S(29)
  bb:paintRoundedRect(tx,ty,tw,th,B.COLOR_BLACK,S(14))
  if not on then bb:paintRoundedRect(tx+S(2),ty+S(2),tw-2*S(2),th-2*S(2),B.COLOR_WHITE,S(12)) end
  local ink=P.inkLabel(bb,on and "开" or "关",tx,ty,tw,th,P.style.label,true,on and B.COLOR_WHITE or B.COLOR_BLACK)
  self.frontlight_layout={x=tx,y=ty,w=tw,h=th,on=on,ink=ink}
  self.hits[#self.hits+1]={x=x+w-S(90),y=y+S(base+3),w=S(90),h=S(46),callback=function()
   power:toggleFrontlight();power:updateResumeFrontlightState();UI:setDirty(self,"ui")
   if self.app.autolight then self.app.autolight:manual(power:frontlightIntensity(),false) end
  end}
  P.text(bb,"亮度",x+S(20),y+S(base+62),w*.5,P.style.label,true)
  P.text(bb,tostring(state.intensity),x+w-S(60),y+S(base+62),S(42),P.style.label,true)
  local sx,sy,sw=x+S(60),y+S(base+110),w-S(120)
  P.centerText(bb,"−",x+S(10),sy-S(15),S(40),24,true)
  P.centerText(bb,"+",x+w-S(50),sy-S(15),S(40),24,true)
  P.rule(bb,sx,sy,sw,3)
  local ratio=(state.intensity-state.low)/math.max(1,state.high-state.low);local kx=math.floor(sx+ratio*sw)
  bb:paintCircle(kx,sy+S(1),S(12),B.COLOR_BLACK);bb:paintCircle(kx,sy+S(1),S(10),B.COLOR_WHITE)
  self.slider={x=sx,y=sy-S(20),w=sw,h=S(40)}
  self.hits[#self.hits+1]={x=sx,y=sy-S(20),w=sw,h=S(40),feedback=false,callback=function(pos) self:setLight(pos) end}
  self.hits[#self.hits+1]={x=x,y=sy-S(22),w=S(55),h=S(44),callback=function() self.app.adapter:setFrontlight(math.max(state.low,self.app.adapter:deviceStatus().intensity-1));UI:setDirty(self,"ui") end}
  self.hits[#self.hits+1]={x=x+w-S(55),y=sy-S(22),w=S(55),h=S(44),callback=function() self.app.adapter:setFrontlight(math.min(state.high,self.app.adapter:deviceStatus().intensity+1));UI:setDirty(self,"ui") end}
  if self:hasAutoLight() then
   local ay=y+S(base+144)
   P.rule(bb,x+S(20),ay,w-S(40),1)
   P.label(bb,'自动前光',x+S(20),ay,w/2,S(44),P.style.label,true)
   P.label(bb,self.app.autolight:statusText()..'  ›',x+w/2,ay,w/2-S(20),S(44),P.style.label,false,'center')
   self.hits[#self.hits+1]={x=x+S(12),y=ay,w=w-S(24),h=S(44),id='control_auto_light',callback=function() self:close();self.app:open('auto_light') end}
  end
 end
 P.icon(bb,"chevron.up",x+w/2-S(17),y+self.panel_h-S(35),S(34))
 self.hits[#self.hits+1]={x=x,y=y+self.panel_h-S(42),w=w,h=S(42),callback=function() self:close() end}
 P.rule(bb,x,y+self.panel_h-S(2),w,2)
end

function Controls:setLight(pos)
 local s=self.slider;local state=self.app.adapter:deviceStatus()
 local value=state.low+math.floor(math.max(0,math.min(1,(pos.x-s.x)/s.w))*(state.high-state.low)+.5)
 self.app.adapter:setFrontlight(value);UI:setDirty(self,"ui")
end
function Controls:onControlTap(_,ges)
 if not ges or not ges.pos then return true end
 if ges.pos.y>=self.panel_h then self:close();return true end
 P.activate(self,ges.pos);return true
end
function Controls:onControlPan(_,ges)
 if ges and ges.pos and self.slider and ges.pos.y>=self.slider.y and ges.pos.y<=self.slider.y+self.slider.h then self.app:safe(function() self:setLight(ges.pos) end) end;return true
end
function Controls:onControlSwipe(_,ges) if ges and ges.direction=="north" then self:close() end;return true end
function Controls:onKeyPress(key) if key:match({Device.input.group.Back}) then self:close() end;return true end
Controls.onKeyRepeat=Controls.onKeyPress
function Controls:onSetDimensions() self:init();UI:setDirty(self,"full");return true end
return Controls
