-- SPDX-License-Identifier: AGPL-3.0-or-later
local P=require('einkfrontend/paint');local S=P.s;local B=P.BB
local W={}
function W.paint(bb,w,h,data)
 P.label(bb,'阅读回报',0,0,w,S(32),18,true)
 if not data then P.label(bb,'记录暂不可用',0,S(40),w,h-S(40),16,true,'center');return end
 local narrow=w<S(300);local radius=math.min(S(narrow and 57 or 68),math.floor((h-S(70))/2))
 local cx=narrow and math.floor(w/2) or radius+S(14);local cy=S(40)+radius
 bb:paintCircle(cx,cy,radius,B.COLOR_BLACK,math.max(1,S(1)))
 local ratio=math.max(0,math.min(1,(data.percent or 0)/100));local thick=S(8)
 for angle=0,math.floor(360*ratio) do if ratio>0 then
  local radians=(angle-90)*math.pi/180
  bb:paintCircle(math.floor(cx+radius*math.cos(radians)+.5),math.floor(cy+radius*math.sin(radians)+.5),math.max(2,math.floor(thick/2)),B.COLOR_BLACK)
 end end
 local percent=data.percent and (data.percent>=10000 and string.format('%.1f万%%',data.percent/10000) or tostring(data.percent)..'%') or '—'
 P.inkLabel(bb,percent,cx-radius+S(4),cy-S(32),2*radius-S(8),S(44),data.percent and data.percent>=1000 and 25 or 32,true)
 P.inkLabel(bb,data.comment,cx-radius+S(2),cy+S(12),2*radius-S(4),S(28),13,true)
 local money=require('einkfrontend/bookvalue').money
 if narrow then
  local top=cy+radius+S(12)
  P.label(bb,'已读 ¥'..money(data.total),0,top,w,S(25),14,true,'center')
  P.label(bb,data.investment and '投入 ¥'..money(data.investment) or '轻点设置购机投入',0,top+S(27),w,S(24),13,true,'center')
 else
  local left=cx+radius+S(30);local width=w-left
  P.label(bb,'已读书籍价值',left,S(44),width,S(30),14,true)
  P.label(bb,'¥'..money(data.total),left,S(78),width,S(44),28,true)
  P.label(bb,data.investment and '购机投入 ¥'..money(data.investment) or '轻点设置购机投入',left,S(128),width,S(28),14,true)
  P.label(bb,data.priced..' 本已计入 · '..data.missing..' 本待补价格',left,S(162),width,S(28),13,true)
 end
end
return W
