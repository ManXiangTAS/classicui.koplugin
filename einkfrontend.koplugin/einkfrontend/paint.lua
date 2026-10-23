-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local P={};local Device=require("device");local Font=require("ui/font")
P.BB=require("ffi/blitbuffer")
P.style=require("einkfrontend/style")
function P.s(n) return Device.screen:scaleBySize(n) end
function P.text(bb,text,x,y,w,size,bold,color)
 local t=require("ui/widget/textwidget"):new{text=tostring(text or ""),face=Font:getFace(bold and "smallinfofontbold" or "cfont",size or 16),max_width=math.max(1,w),bold=bold or false,padding=0,fgcolor=color or P.BB.COLOR_BLACK}
 t:paintTo(bb,x,y);t:free()
end
function P.centerText(bb,text,x,y,w,size,bold,color)
 local t=require("ui/widget/textwidget"):new{text=tostring(text or ""),face=Font:getFace(bold and "smallinfofontbold" or "cfont",size or 16),max_width=math.max(1,w),bold=bold or false,padding=0,fgcolor=color or P.BB.COLOR_BLACK}
 local tw=t:getSize().w;local tx=x+math.floor((w-tw)/2)
 t:paintTo(bb,tx,y);t:free();return tx,tw
end
function P.glyph(bb,text,x,y,size)
 local t=require("ui/widget/textwidget"):new{text=text,face=Font:getFace("symbols",size),padding=0}
 t:paintTo(bb,x,y);t:free()
end
function P.label(bb,text,x,y,w,h,size,bold,align,color)
 local t=require("ui/widget/textwidget"):new{text=tostring(text or ""),face=Font:getFace(bold and "smallinfofontbold" or "cfont",size or P.style.label),max_width=math.max(1,w),bold=bold or false,padding=0,fgcolor=color or P.BB.COLOR_BLACK}
 local dim=t:getSize();local tx=align=="center" and x+math.floor((w-dim.w)/2) or x
 local ty=y+math.floor((h-dim.h)/2);t:paintTo(bb,tx,ty);t:free()
 return {x=tx,y=ty,w=dim.w,h=dim.h,cy=ty+dim.h/2}
end
function P.centerIcon(bb,name,x,y,w,h,size)
 return P.inkIcon(bb,name,x,y,w,h,size,"toolbar")
end
-- Small, bounded metrics cache only: no borrowed image buffers are retained.
local ink_cache={};local ink_count=0
local function cachedInk(key,render)
 if ink_cache[key] then return ink_cache[key] end
 local bb=render();local left,top,right,bottom=bb:getWidth(),bb:getHeight(),-1,-1
 for py=0,bb:getHeight()-1 do for px=0,bb:getWidth()-1 do
  if bb:getPixel(px,py):getColor8().a<128 then
   left=math.min(left,px);right=math.max(right,px);top=math.min(top,py);bottom=math.max(bottom,py)
  end
 end end
 local bounds=right>=left and {x=left,y=top,w=right-left+1,h=bottom-top+1} or {x=0,y=0,w=bb:getWidth(),h=bb:getHeight()}
 bb:free()
 if ink_count>=96 then ink_cache={};ink_count=0 end
 ink_cache[key]=bounds;ink_count=ink_count+1;return bounds
end
local function inkPosition(bounds,x,y,w,h)
 local px=math.floor(x+w/2-bounds.x-(bounds.w-1)/2+.5)
 local py=math.floor(y+h/2-bounds.y-(bounds.h-1)/2+.5)
 return px,py,{x=px+bounds.x,y=py+bounds.y,w=bounds.w,h=bounds.h,
  cx=px+bounds.x+(bounds.w-1)/2,cy=py+bounds.y+(bounds.h-1)/2}
end
-- For enclosed controls, center the visible ink, not the SVG's padded canvas.
function P.inkIcon(bb,name,x,y,w,h,size,group)
 size=require("einkfrontend/icons").size(name,size,group)
 local bounds=cachedInk("icon:"..name..":"..size,function()
  local image=P.BB.new(size,size,P.BB.TYPE_BB8);image:paintRect(0,0,size,size,P.BB.COLOR_WHITE)
  P.icon(image,name,0,0,size);return image
 end)
 local px,py,metrics=inkPosition(bounds,x,y,w,h);P.icon(bb,name,px,py,size);return metrics
end
-- Font line boxes include bearings and leading. Short switch labels need their
-- actual glyph bounds centered in both axes, in either foreground color.
function P.inkLabel(bb,text,x,y,w,h,size,bold,color,align)
 text=tostring(text or "");size=size or P.style.label;w=math.max(1,w)
 local face=Font:getFace(bold and "smallinfofontbold" or "cfont",size)
 local widget=require("ui/widget/textwidget"):new{text=text,face=face,max_width=w,bold=bold or false,padding=0,fgcolor=P.BB.COLOR_BLACK}
 local pad=4;local dim=widget:getSize()
 local key="text:"..text..":"..tostring(face)..":"..w..":"..size..":"..tostring(bold)
 local bounds=cachedInk(key,function()
  local image=P.BB.new(math.ceil(dim.w+2*pad),math.ceil(dim.h+2*pad),P.BB.TYPE_BB8)
  image:paintRect(0,0,image:getWidth(),image:getHeight(),P.BB.COLOR_WHITE);widget:paintTo(image,pad,pad);return image
 end)
 local px,py,metrics=inkPosition(bounds,x,y,w,h)
 if align=="left" then px=math.floor(x-bounds.x+.5)
 elseif align=="right" then px=math.floor(x+w-bounds.x-bounds.w+.5) end
 metrics.x=px+bounds.x;metrics.cx=metrics.x+(bounds.w-1)/2
 if bb then widget.fgcolor=color or P.BB.COLOR_BLACK;widget:paintTo(bb,px+pad,py+pad) end
 widget:free();return metrics
end
function P.rule(bb,x,y,w,thickness) bb:paintRect(x,y,w,math.max(2,P.s(thickness or 1.5)),P.BB.COLOR_BLACK) end
function P.icon(bb,name,x,y,size)
 local file=require("einkfrontend/icons").file(name)
 local i=require("ui/widget/iconwidget"):new{file=file,icon=name,width=size,height=size,alpha=true}
 i:paintTo(bb,x,y);i:free()
end
-- Shared high-contrast status indicator; its box includes the percentage.
function P.battery(bb,percent,x,y,w,h)
 local value=tonumber(percent)
 if value and (value~=value or value<0 or value>100) then value=nil end
 local text=value and tostring(math.floor(value)).."%" or "—"
 local label=P.inkLabel(bb,text,x,y,w,h,16,true,nil,"right")
 local bw,bh=P.s(29),P.s(14);local by=y+math.floor((h-bh)/2)
 x=label.x-P.s(8)-bw-P.s(3)
 bb:paintBorder(x,by,bw,bh,math.max(2,P.s(1.5)),P.BB.COLOR_BLACK)
 bb:paintRect(x+bw,by+P.s(4),P.s(3),P.s(6),P.BB.COLOR_BLACK)
 if value then bb:paintRect(x+P.s(3),by+P.s(3),math.floor(P.s(23)*value/100),P.s(8),P.BB.COLOR_BLACK) end
 return {x=x,y=y,w=label.x+label.w-x,h=h,percent=value}
end
function P.statisticsIcon(bb,x,y,w,h)
 return P.centerIcon(bb,"statistics",x,y,w,h,P.s(28))
end
function P.refreshIcon(bb,x,y,w,h,size)
 return P.centerIcon(bb,"refresh",x,y,w,h,P.s(size or 20))
end
function P.line(bb,x,y,w,color) bb:paintRect(x,y,w,1,color or P.BB.COLOR_LIGHT_GRAY) end
function P.button(widget,bb,label,x,y,w,h,fn,opts)
 opts=opts or {};local metrics=P.label(bb,label,x+P.s(opts.pad or 8),y,w-P.s(16),h,opts.size or P.style.label,opts.bold~=false,opts.align,opts.disabled and P.BB.COLOR_DARK_GRAY or nil)
 widget.hits[#widget.hits+1]={x=x,y=y,w=w,h=h,callback=not opts.disabled and fn or nil,hold_callback=opts.hold,id=opts.id}
 return metrics
end
function P.find(widget,pos,hold)
 for _,hit in ipairs(widget.hits or {}) do
  if pos.x>=hit.x and pos.x<hit.x+hit.w and pos.y>=hit.y and pos.y<hit.y+hit.h then
   if hold then return hit.hold_callback,hit end
   return hit.callback,hit
  end
 end
end
-- A visual effect must never prevent the action or escape the frontend error
-- boundary. Kindle uses the same protected feedback path as other devices.
local function feedback(widget,hit,UI)
 local owner=widget.app or widget
 if owner._eink_feedback_failed or hit.feedback==false
  or (type(hit.id)=="string" and hit.id:match("_slider$"))
  or G_reader_settings:isFalse("flash_ui") then return end
 local screen=Device.screen
 local x,y,w,h,region,inverted
 local ok,err=pcall(function()
  x=math.max(0,math.ceil(hit.x));y=math.max(0,math.ceil(hit.y))
  w=math.min(screen:getWidth(),math.floor(hit.x+hit.w))-x
  h=math.min(screen:getHeight(),math.floor(hit.y+hit.h))-y
  if w<=0 or h<=0 then return end
  region=require("ui/geometry"):new{x=x,y=y,w=w,h=h}
  UI:forceRePaint()
  UI:widgetInvert(widget,x,y,w,h);inverted=true
  UI:setDirty(nil,"fast",region)
  UI:forceRePaint();UI:yieldToEPDC()
 end)
 -- Undo before the action can replace/close the page, including on failure.
 local restored,restore_err=pcall(function()
  if inverted then UI:widgetInvert(widget,x,y,w,h) end
  if region then UI:setDirty(nil,"ui",region) end
 end)
 if not ok or not restored then
  owner._eink_feedback_failed=true
  require("logger").warn("EInkFrontend: click feedback disabled:",ok and restore_err or err)
  -- If even undo failed, redraw the owning page instead of retrying inversion.
  if not restored then pcall(UI.setDirty,UI,widget,"ui") end
 end
end
function P.activate(widget,pos,hold)
 if not pos then return false end
 local fn,hit=P.find(widget,pos,hold)
 if not fn then return false end
 local UI=require("ui/uimanager")
 if widget.app and not UI:isWidgetShown(widget) then return false end
 local action=function()
  feedback(widget,hit,UI)
  fn(pos)
  UI:forceRePaint()
 end
 -- Include the final repaint in the same boundary as the callback.
 if widget.app then widget.app:safe(action) else action() end
 return true
end
return P
