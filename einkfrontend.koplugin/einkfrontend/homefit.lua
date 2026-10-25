-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- One bounded canvas. Minimum sizes protect text; surplus is shared by rows.
local S=require('einkfrontend/paint').s
local Layout=require('einkfrontend/homelayout')
local Copy=require('einkfrontend/catalog').copy
local Equal=require('einkfrontend/adapter').equal
local Fit={}
function Fit.viewport(height) return math.max(1,height-S(168)) end
function Fit.plan(config,width,height)
 height=math.max(1,math.floor(height or Fit.viewport(require('device').screen:getSize().h)))
 local pad=S(20);local gap=config.spacing=='compact' and S(8) or S(16)
 local available=math.max(2,width-pad*2);local half=math.floor((available-gap)/2)
 local rows={};local pending;local requested=0
 local function sizes(widget)
  local narrow=(widget.span==1 and half or available)<S(300)
  local mins={currently=144,reading_stats=narrow and 136 or 100,
   overview=narrow and 176 or 132,recent=narrow and (Layout.shelfCount(config,'recent')==5 and 316 or 228) or 160,
   tbr=narrow and (Layout.shelfCount(config,'tbr')==5 and 316 or 228) or 160,
   quote=120,clock=96,heatmap=156,stats_table=204,weekly=154,streak=150,daypart=198,daily_goal=138,reading_return=narrow and 226 or 208}
  local minimum=S(mins[widget.id]);local preferred=S(Layout.by_id[widget.id].height)
  if widget.id=='recent' or widget.id=='tbr' then preferred=narrow and S(Layout.shelfCount(config,widget.id)==5 and 380 or 280) or S(208) end
  return minimum,math.max(minimum,preferred)
 end
 for _,widget in ipairs(config.widgets) do if widget.enabled then
  requested=requested+1;local minimum,preferred=sizes(widget)
  local item={id=widget.id,min=minimum,preferred=preferred,span=widget.span}
  if widget.span==2 then pending=nil;rows[#rows+1]={items={item},min=minimum,preferred=preferred}
  elseif pending then
   pending.items[2]=item;pending.min=math.max(pending.min,minimum);pending.preferred=math.max(pending.preferred,preferred);pending=nil
  else pending={items={item},min=minimum,preferred=preferred};rows[#rows+1]=pending end
 end end
 local needed=math.max(0,(#rows-1)*gap)
 for _,r in ipairs(rows) do needed=needed+r.min end
 local fits=needed<=height;local body_h=height-(fits and 0 or S(30))
 local selected={};local used=0;local natural=0
 for _,r in ipairs(rows) do
  local next_h=used+(#selected>0 and gap or 0)+r.min
  if next_h>body_h then break end
  selected[#selected+1]=r;used=next_h;natural=natural+r.preferred
 end
 local room=math.max(0,body_h-math.max(0,(#selected-1)*gap))
 local minimum=used-math.max(0,(#selected-1)*gap);local fraction=natural>minimum and math.min(1,(room-minimum)/(natural-minimum)) or 0
 local frames={};local shown={};local y=0
 for _,r in ipairs(selected) do
  local h=r.min+math.floor((r.preferred-r.min)*fraction)
  for col,item in ipairs(r.items) do
   frames[#frames+1]={id=item.id,x=pad+(col-1)*(half+gap),y=y,w=item.span==2 and available or half,h=h}
   shown[item.id]=true
  end
  y=y+h+gap
 end
 local omitted={};for _,widget in ipairs(config.widgets) do if widget.enabled and not shown[widget.id] then omitted[#omitted+1]=widget.id end end
 return frames,math.max(0,y>0 and y-gap or 0),{fits=fits,needed=needed,available=height,body_h=body_h,requested=requested,visible=#frames,omitted=omitted}
end
local function onlyHides(before,after)
 if #before.widgets~=#after.widgets then return false end
 local hidden=false
 for i,widget in ipairs(after.widgets) do
  local old=before.widgets[i]
  if widget.enabled~=old.enabled then
   if old.enabled~=true or widget.enabled~=false then return false end
   hidden=true
  end
 end
 if not hidden then return false end
 -- Restore just the enabled flags for comparison. Width, order, options and
 -- every other field must be unchanged before granting this recovery path.
 local restored=Copy(after)
 for i,widget in ipairs(restored.widgets) do widget.enabled=before.widgets[i].enabled end
 return Equal(before,restored)
end
function Fit.checkChange(before,after,width,height)
 -- Removing a half-width widget can re-pair later rows and increase height.
 -- Always let users hide widgets so they can continue reducing an overflow;
 -- explicit editor saves still require the final preview to fit one screen.
 if onlyHides(before,after) then return true end
 local _,_,old=Fit.plan(before,width,height);local _,_,new=Fit.plan(after,width,height)
 if not new.fits and new.needed>old.needed then return false,'主页空间不足，请先隐藏部件或改成半行，再添加新部件' end
 return true
end
return Fit
