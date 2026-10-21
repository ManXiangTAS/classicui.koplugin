-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Kobo-inspired home/library chrome and reading record layout.
local P=require("einkfrontend/paint");local S=P.s;local B=P.BB
local Shell={}
function Shell.status(page,bb,x,y)
 local app=page.app;local w=page.dimen.w;local h=S(42);local status=app.adapter:deviceStatus()
 P.inkLabel(bb,os.date("%H:%M"),x+S(20),y,w*.4,h,16,true,nil,"left")
 local percent=status.battery
 P.battery(bb,percent,x+w-S(20)-S(104),y,S(104),h)
 page.status_layout={clock=os.date("%H:%M"),battery=percent,height=h}
end
function Shell.nav(page,bb,x,y,active)
 local w=page.dimen.w;local h=S(72)
 P.rule(bb,x,y,w,1.5);page.shell_navigation={}
 for i,entry in ipairs({{"书库","library","book.opened"},{"主页","home","home"}}) do
  local left=x+(i-1)*w/2;local center=left+w/4
  P.centerIcon(bb,entry[3],center-S(18),y+S(7),S(36),S(28),S(25))
  P.label(bb,entry[1],left,y+S(35),w/2,S(32),16,true,"center")
  if active==entry[2] then bb:paintRect(center-S(34),y+S(1),S(68),S(3),B.COLOR_BLACK) end
  local route=entry[2];page.shell_navigation[i]=route
  page.hits[#page.hits+1]={x=left,y=y,w=w/2,h=h,callback=function() page.app:open(route) end,id="shell_"..route}
 end
end
function Shell.home(page,bb,x,y)
 local app=page.app;local w,h=page.dimen.w,page.dimen.h
 bb:paintRect(x,y,w,h,B.COLOR_WHITE);page.hits={};Shell.status(page,bb,x,y)
 local title=P.label(bb,"主页",x+S(20),y+S(42),S(82),S(52),20,true)
 local edit_x=title.x+title.w+S(4)
 P.centerIcon(bb,"edit",edit_x,y+S(42),S(44),S(52),S(20))
 page.hits[#page.hits+1]={x=edit_x,y=y+S(42),w=S(44),h=S(52),callback=function() app:go("home_customize") end,id="home_customize"}
 P.refreshIcon(bb,x+w-S(64),y+S(42),S(44),S(52),20)
 page.hits[#page.hits+1]={x=x+w-S(64),y=y+S(42),w=S(44),h=S(52),callback=function() app:refreshHome() end,id="home_statistics_refresh"}
 page.home_title_metrics=title;page.home_edit_x=edit_x
 P.rule(bb,x+S(20),y+S(94),w-S(40))
 require("einkfrontend/homewidgets").home(page,bb,x,y)
 Shell.nav(page,bb,x,y+h-S(72),"home")
end
return Shell
