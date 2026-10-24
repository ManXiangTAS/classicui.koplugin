-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Input=require('ui/widget/container/inputcontainer')
local GestureRange=require('ui/gesturerange')
local Device=require('device');local UI=require('ui/uimanager')
local P=require('einkfrontend/paint');local S=P.s;local B=P.BB
local Dialog=Input:extend{modal=true,stop_events_propagation=true}
function Dialog:init()
 self.dimen=Device.screen:getSize()
 self.ges_events={}
 for name,gesture in pairs({LightCalibrationTap='tap',LightCalibrationPan='pan',LightCalibrationSwipe='swipe'}) do
  self.ges_events[name]={GestureRange:new{ges=gesture,range=self.dimen}}
 end
end
function Dialog:close() UI:close(self,'ui') end
function Dialog:onCloseWidget()
 self.app.autolight:finishCalibration(self.token,false)
 if self.app.screen then self.app:render();UI:setDirty(self.app.screen,'ui') end
end
function Dialog:adjust(value)
 local light=self.app.autolight
 value=math.max(self.token.low,math.min(self.token.high,value))
 if not light:preview(self.token,value) then self.app:message(light.error or '校准已结束');self:close();return end
 UI:setDirty(self,'ui')
end
function Dialog:apply()
 local light=self.app.autolight
 local accepted=self.manual and light:finishManual(self.token) or (not self.manual and light:finishCalibration(self.token,true))
 if accepted then
  if self.enable_after then local ok,why=light:setEnabled(true);if not ok then self.app:message(why) end end
 else self.app:message(light.error or '校准未保存') end
 self:close()
end
function Dialog:paintTo(bb,x,y)
 local w=self.dimen.w;local h=math.min(S(330),self.dimen.h-S(24));local top=y+math.floor((self.dimen.h-h)/2)
 local left=x+S(12);local width=w-S(24);self.box={x=left,y=top,w=width,h=h};self.hits={}
 bb:paintRect(left,top,width,h,B.COLOR_WHITE);bb:paintBorder(left,top,width,h,S(2),B.COLOR_BLACK)
 P.label(bb,self.manual and '亮度' or (self.token.kind=='daylight' and '明亮处亮度' or '暗处亮度'),left+S(20),top+S(14),width-S(40),S(45),22,true)
 P.rule(bb,left+S(20),top+S(65),width-S(40),1)
 P.label(bb,self.manual and '调整当前前光亮度。' or (self.token.kind=='daylight' and '明亮环境使用的亮度；0 表示关灯。' or '在最暗的阅读环境选择舒适亮度。'),left+S(20),top+S(78),width-S(40),S(34),17,false)
 P.label(bb,'取消会恢复原来的亮度。',left+S(20),top+S(112),width-S(40),S(34),17,false)
 local sx,sy,sw=left+S(76),top+S(190),width-S(152)
 self.slider={x=sx,y=sy-S(24),w=sw,h=S(48)}
 P.rule(bb,sx,sy,sw,2)
 local light=self.app.autolight;local kx=sx+sw*(self.token.value-self.token.low)/math.max(1,self.token.high-self.token.low)
 bb:paintCircle(kx,sy,S(12),B.COLOR_BLACK);bb:paintCircle(kx,sy,S(10),B.COLOR_WHITE)
 P.inkLabel(bb,tostring(self.token.value),kx-S(28),sy-S(38),S(56),S(22),16,false)
 P.label(bb,'−',left+S(12),sy-S(26),S(52),S(52),28,true,'center')
 P.label(bb,'+',left+width-S(64),sy-S(26),S(52),S(52),28,true,'center')
 local function hit(px,py,pw,ph,id,fn,feedback)
  self.hits[#self.hits+1]={x=px,y=py,w=pw,h=ph,id=id,callback=fn,feedback=feedback}
 end
 hit(left+S(8),sy-S(28),S(60),S(56),'light_minus',function() self:adjust(self.token.value-1) end)
 hit(left+width-S(68),sy-S(28),S(60),S(56),'light_plus',function() self:adjust(self.token.value+1) end)
 hit(sx,sy-S(24),sw,S(48),'light_slider',function(pos) self:setFromPosition(pos) end,false)
 local by=top+h-S(72);local bw=(width-S(60))/2
 for i,label in ipairs({'取消','确认并保存'}) do
  local bx=left+S(20)+(i-1)*(bw+S(20))
  bb:paintBorder(bx,by,bw,S(48),S(2),B.COLOR_BLACK)
  P.label(bb,label,bx,by,bw,S(48),18,true,'center')
  hit(bx,by,bw,S(48),i==1 and 'light_cancel' or 'light_apply',i==1 and function() self:close() end or function() self:apply() end)
 end
end
function Dialog:setFromPosition(pos)
 local s=self.slider;local l=self.app.autolight
 self:adjust(self.token.low+math.floor(math.max(0,math.min(1,(pos.x-s.x)/s.w))*(self.token.high-self.token.low)+.5))
end
function Dialog:onLightCalibrationTap(_,ges) P.activate(self,ges and ges.pos);return true end
function Dialog:onLightCalibrationPan(_,ges)
 if ges and ges.pos and self.slider and ges.pos.y>=self.slider.y and ges.pos.y<=self.slider.y+self.slider.h then self:setFromPosition(ges.pos) end
 return true
end
function Dialog:onLightCalibrationSwipe() return true end
function Dialog:onKeyPress(key) if key:match({Device.input.group.Back}) then self:close() end;return true end
Dialog.onKeyRepeat=Dialog.onKeyPress
function Dialog:onSetDimensions() self:close();return false end
function Dialog:onSuspend() self:close() end
return Dialog
