-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Native statistics are read only. Page counts use the native rescaled view;
-- seconds use raw events to avoid integer loss when pages are rescaled.
local Stats={}
function Stats.day(offset,now)
 local t=os.date("*t",now or os.time());t.hour=12;t.min=0;t.sec=0;t.day=t.day+(offset or 0);t.isdst=nil
 return os.date("%Y-%m-%d",os.time(t))
end
local function each(conn,sql,fn)
 local statement=conn:prepare(sql)
 local ok,err=pcall(function() while true do local row=statement:step();if not row then break end;fn(row) end end)
 statement:close();assert(ok,err)
end
function Stats.read(conn,now)
 now=now or os.time();local today=Stats.day(0,now)
 local out={daily={},hours={},today=today,periods={}}
 -- Ignore future/corrupt timestamps and nonpositive durations. No file or
 -- schema is created here; a missing native view is an unavailable state.
 each(conn,"SELECT date(start_time,'unixepoch','localtime'),sum(duration) FROM page_stat_data WHERE duration>0 AND start_time>0 AND start_time<="..math.floor(now).." GROUP BY 1",function(row)
  if row[1] then out.daily[row[1]]={seconds=tonumber(row[2]) or 0,pages=0} end
 end)
 each(conn,"SELECT date(start_time,'unixepoch','localtime'),count(DISTINCT id_book||':'||page) FROM page_stat WHERE duration>0 AND start_time>0 AND start_time<="..math.floor(now).." GROUP BY 1",function(row)
  if row[1] and out.daily[row[1]] then out.daily[row[1]].pages=tonumber(row[2]) or 0 end
 end)
 local recent=Stats.day(-167,now)
 each(conn,"SELECT strftime('%w',start_time,'unixepoch','localtime'),CAST(strftime('%H',start_time,'unixepoch','localtime') AS INTEGER)/4,sum(duration) FROM page_stat_data WHERE duration>0 AND start_time>0 AND start_time<="..math.floor(now).." AND date(start_time,'unixepoch','localtime')>='"..recent.."' GROUP BY 1,2",function(row)
  local weekday=(tonumber(row[1])+6)%7+1;local bin=tonumber(row[2])+1
  out.hours[weekday]=out.hours[weekday] or {};out.hours[weekday][bin]=tonumber(row[3]) or 0
 end)
 local dow=(tonumber(os.date('%w',now))+6)%7
 local starts={today=today,week=Stats.day(-dow,now),month=today:sub(1,7)..'-01',all='0000-01-01'}
 for key,start in pairs(starts) do
  local p={seconds=0,pages=0,days=0}
  for day,record in pairs(out.daily) do if day>=start and day<=today then
   p.seconds=p.seconds+record.seconds;p.pages=p.pages+record.pages;p.days=p.days+1
  end end
  out.periods[key]=p
 end
 out.weekly={};local rolling=0
 for i=1,7 do local date=Stats.day(i-7,now);local record=out.daily[date]
  out.weekly[i]={date=date,seconds=record and record.seconds or 0};rolling=rolling+out.weekly[i].seconds
 end
 out.average=rolling/7
 local offset=out.daily[today] and 0 or -1;local streak=0
 while out.daily[Stats.day(offset,now)] do streak=streak+1;offset=offset-1 end
 out.streak=streak;out.now=now
 return out
end
function Stats.time(seconds)
 local minutes=math.floor((seconds or 0)/60)
 if seconds and seconds>0 and minutes==0 then return '<1分' end
 return minutes>=60 and string.format('%d时%02d分',math.floor(minutes/60),minutes%60) or minutes..'分'
end
return Stats
