-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- One isolated gutter for scrollable frontend lists (all values scale by DPI).
local P=require('einkfrontend/paint');local S=P.s
local R={}
function R.reserve() return S(60)+S(12) end -- content gap 12 + touch lane 44 + edge 16
function R.contains(t,pos)
 return t and pos and pos.x>=t.x and pos.x<t.x+t.w and pos.y>=t.y and pos.y<t.y+t.h
end
function R.paint(bb,x,y,w,h,value,maximum)
 if maximum<=0 then return nil end
 local t={x=x+w-S(60),y=y,w=S(44),h=h,value=value,maximum=maximum}
 local arrow=math.min(S(32),math.floor(h/4));local center=t.x+t.w/2
 t.track_y=y+arrow;t.track_h=h-2*arrow
 t.thumb_h=math.min(t.track_h,math.max(S(36),math.floor(t.track_h*h/(h+maximum))))
 t.thumb_y=t.track_y+math.floor((t.track_h-t.thumb_h)*value/maximum)
 P.centerIcon(bb,'chevron.up',t.x,y,t.w,arrow,S(20))
 P.centerIcon(bb,'chevron.down',t.x,y+h-arrow,t.w,arrow,S(20))
 bb:paintRect(center-S(1),t.track_y,S(2),t.track_h,P.BB.COLOR_DARK_GRAY)
 bb:paintRect(center-S(4),t.thumb_y,S(8),t.thumb_h,P.BB.COLOR_BLACK)
 return t
end
function R.tap(t,pos,page)
 if not R.contains(t,pos) then return nil end
 if pos.y<t.track_y then return math.max(0,t.value-page) end
 if pos.y>=t.track_y+t.track_h then return math.min(t.maximum,t.value+page) end
 return R.position(t,pos,t.thumb_h/2)
end
function R.position(t,pos,offset)
 local travel=t.track_h-t.thumb_h
 if travel<=0 then return 0 end
 return math.max(0,math.min(t.maximum,(pos.y-t.track_y-offset)/travel*t.maximum))
end
-- Lock the gesture to its starting lane. Crossing into the lane while swiping
-- a row must never suddenly seek to another part of the book or settings.
function R.pan(t,ges,drag)
 if drag==false then return nil,false end
 if not drag then
  local start=ges.start_pos or ges.pos
  if not R.contains(t,start) then return nil,false end
  local offset=start.y>=t.thumb_y and start.y<t.thumb_y+t.thumb_h and start.y-t.thumb_y or t.thumb_h/2
  drag={offset=offset,track=t}
 end
 drag.value=R.position(drag.track,ges.pos,drag.offset)
 return drag.value,drag
end
function R.release(drag)
 -- A lift only ends the drag: do not seek again from noisy release coordinates.
 if type(drag)=='table' then return drag.value end
end
function R.swipe(t,ges,drag)
 -- A quick pan ends as a swipe in KOReader. Its direction describes the
 -- finger, which is the reverse of content scrolling; never apply it twice.
 return type(drag)=='table' or R.contains(t,ges and ges.pos)
end
return R
