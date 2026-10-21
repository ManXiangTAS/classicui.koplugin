-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Independent monochrome dashboard, inspired by SimpleUI's module categories.
local P=require('einkfrontend/paint');local S=P.s;local B=P.BB
local Stats=require('einkfrontend/homestats');local Layout=require('einkfrontend/homelayout')
local W={}
local function label(bb,text,x,y,w,h,size,align) P.inkLabel(bb,text,x,y,math.max(1,w),h,size or 14,true,nil,align or 'left') end
local function shade(value,maximum)
 if value<=0 then return B.COLOR_WHITE end
 local colors={B.Color8(205),B.Color8(150),B.Color8(80),B.COLOR_BLACK}
 return colors[math.min(4,math.max(1,math.ceil(value/math.max(1,maximum)*4)))]
end
local function square(bb,x,y,w,h,value,maximum)
 bb:paintRect(x,y,w,h,shade(value,maximum));bb:paintBorder(x,y,w,h,math.max(1,S(0.6)),B.COLOR_BLACK)
end
function W.paint(bb,id,w,h,data,config,hit,show,editGoal)
 label(bb,Layout.by_id[id].name,0,0,w,S(40),18)
 if not data then label(bb,'暂无可用阅读统计',0,S(54),w,S(48),16);return end
 if id=='stats_table' then
  local namew=w*.26;local timew=w*.44;local rowh=S(43)
  label(bb,'周期',0,S(42),namew,rowh,14)
  label(bb,'阅读时长',namew,S(42),timew,rowh,14,'right')
  label(bb,'页次',namew+timew,S(42),w-namew-timew,rowh,14,'right')
  for i,entry in ipairs({{'today','今天'},{'week','本周'},{'month','本月'},{'all','累计'}}) do
   local y=S(42)+i*rowh;local record=data.periods[entry[1]]
   P.rule(bb,0,y,w,1);label(bb,entry[2],0,y,namew,rowh,14)
   label(bb,Stats.time(record.seconds),namew,y,timew,rowh,14,'right')
   label(bb,tostring(record.pages),namew+timew,y,w-namew-timew,rowh,14,'right')
  end
 elseif id=='heatmap' then
  local weeks=config.heatmap_weeks;local gap=S(3);local labelw=S(20)
  local size=math.min(S(18),math.floor((w-labelw-gap*(weeks-1))/weeks));size=math.max(2,size)
  local today=data.today;local dow=(tonumber(os.date('%w',data.now))+6)%7
  local first=-(weeks-1)*7-dow;local max=1
  for date,r in pairs(data.daily) do if date>=Stats.day(first,data.now) and date<=today then max=math.max(max,r.seconds) end end
  for c=0,weeks-1 do for r=0,6 do
   local date=Stats.day(first+c*7+r,data.now);local record=data.daily[date]
   if date<=today then
    local cx,cy=labelw+c*(size+gap),S(48)+r*(size+gap)
    square(bb,cx,cy,size,size,record and record.seconds or 0,max)
    if hit then hit('heatmap_'..date,cx,cy,size,size,function()
     show(date..'\n阅读 '..Stats.time(record and record.seconds or 0)..' · '..(record and record.pages or 0)..' 页次')
    end) end
   end
  end end
  for _,r in ipairs({0,2,4,6}) do label(bb,({'一','二','三','四','五','六','日'})[r+1],0,S(48)+r*(size+gap),labelw-S(2),size,10) end
  local by=S(48)+7*(size+gap)+S(5)
  label(bb,weeks..'周 · 深色表示更久',0,by,w,S(24),12)
 elseif id=='weekly' then
  local max=1;for _,d in ipairs(data.weekly) do max=math.max(max,d.seconds) end
  local charttop=S(72);local charth=S(110);local column=w/7
  label(bb,'日均 '..Stats.time(data.average),0,S(40),w,S(28),14)
  for i,d in ipairs(data.weekly) do
   local height=math.floor(charth*d.seconds/max);local left=math.floor((i-1)*column+column*.2);local bw=math.max(2,math.floor(column*.6))
   if height>0 then bb:paintRect(left,charttop+charth-height,bw,height,B.COLOR_BLACK) end
   label(bb,d.date:sub(6),math.floor((i-1)*column),charttop+charth+S(8),math.floor(column),S(24),10,'center')
   if hit then hit('weekly_'..d.date,math.floor((i-1)*column),charttop,math.floor(column),charth+S(32),function() show(d.date..'\n阅读 '..Stats.time(d.seconds)) end) end
  end
  P.rule(bb,0,charttop+charth,w,1)
 elseif id=='streak' then
  local entries={{data.streak,'连续阅读天数'},{data.periods.month.days,'本月阅读天数'},{data.periods.all.days,'累计阅读天数'}}
  for i,entry in ipairs(entries) do local y=S(46)+(i-1)*S(48)
   label(bb,entry[2],0,y,w*.76,S(40),14);label(bb,tostring(entry[1]),w*.76,y,w*.24,S(40),22,'right')
  end
 elseif id=='daypart' then
  local labelw=S(22);local gap=S(4);local cw=math.floor((w-labelw-5*gap)/6);local rh=S(18);local max=1
  for _,row in pairs(data.hours) do for _,v in pairs(row) do max=math.max(max,v) end end
  for c=1,6 do label(bb,tostring((c-1)*4),labelw+(c-1)*(cw+gap),S(40),cw,S(22),11,'center') end
  for r=1,7 do
   local y=S(66)+(r-1)*(rh+gap);label(bb,({'一','二','三','四','五','六','日'})[r],0,y,labelw-S(2),rh,11)
   for c=1,6 do
    local value=data.hours[r] and data.hours[r][c] or 0;local hour=(c-1)*4;local weekday=r
    square(bb,labelw+(c-1)*(cw+gap),y,cw,rh,value,max)
    if hit then hit('daypart_'..r..'_'..c,labelw+(c-1)*(cw+gap),y,cw,rh,function()
     show('近24周 · 周'..({'一','二','三','四','五','六','日'})[weekday]..' '..hour..'—'..(hour+4)..'时\n阅读 '..Stats.time(value))
    end) end
   end
  end
  label(bb,'近24周 · 每格4小时',0,S(222),w,S(18),11)
 elseif id=='daily_goal' then
  local seconds=data.periods.today.seconds;local target=config.daily_goal_minutes*60;local ratio=math.min(1,seconds/target)
  label(bb,Stats.time(seconds)..' / '..config.daily_goal_minutes..'分',0,S(48),w,S(40),20)
  bb:paintBorder(0,S(102),w,S(12),S(1),B.COLOR_BLACK)
  local fill=math.floor((w-S(2))*ratio);if fill>0 then bb:paintRect(S(1),S(103),fill,S(10),B.COLOR_BLACK) end
  label(bb,seconds>=target and '今日目标已完成' or '还需 '..Stats.time(target-seconds),0,S(128),w,S(32),14)
  if hit then hit('daily_goal_edit',0,0,w,h,editGoal) end
 end
end
return W
