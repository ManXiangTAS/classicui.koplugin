-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Current-document statistics: flush through the native owner, then query read-only.
local Input=require("ui/widget/container/inputcontainer")
local Device=require("device");local UI=require("ui/uimanager")
local GestureRange=require("ui/gesturerange")
local P=require("einkfrontend/paint");local S=P.s;local B=P.BB
local Stats=Input:extend{stop_events_propagation=true,covers_footer=true}
local function number(v) v=tonumber(v);return v and v==v and v>=0 and v or nil end
local function duration(value)
 if not value then return "—" end
 if value==0 then return "0 分钟" end
 local minutes=math.floor(value/60)
 if minutes<1 then return "不足 1 分钟" end
 if minutes<60 then return minutes.." 分钟" end
 return math.floor(minutes/60).." 小时 "..minutes%60 .." 分钟"
end
function Stats.model(app)
 local ui=app.plugin.ui;local doc=assert(ui.document);local props=ui.doc_props or {}
 local out={file=doc.file,title=props.display_title or props.title or doc.file:match("([^/]+)$"),page=ui:getCurrentPage(),pages=doc:getPageCount()}
 local native=ui.statistics;out.paused=not native or not native:isEnabledAndNotFrozen()
 local path=require("datastorage"):getSettingsDir().."/statistics.sqlite3"
 if require("libs/libkoreader-lfs").attributes(path,"mode")~="file" then return out end
 local conn
 local ok=pcall(function()
  -- Like the native statistics window, persist only already measured page turns.
  if native and native:isEnabledAndNotFrozen() then native:insertDB() end
  local md5=ui.doc_settings:readSetting("partial_md5_checksum")
  if not md5 then return end
  conn=require("lua-ljsqlite3/init").open(path,"ro");conn:set_busy_timeout(150)
  local statement
  if native and native.id_curr_book then
   statement=conn:prepare("SELECT id FROM book WHERE id=? AND md5=?")
   statement:bind(native.id_curr_book,md5)
  else
   statement=conn:prepare("SELECT id FROM book WHERE md5=? ORDER BY last_open DESC LIMIT 1")
   statement:bind(md5)
  end
  local row=statement:step();statement:close();local id=row and number(row[1])
  if not id then return end
  -- The native view rescales historical page numbers after a layout change.
  local total,pages,days,today=conn:rowexec("SELECT coalesce(sum(duration),0),count(DISTINCT page),count(DISTINCT date(start_time,'unixepoch','localtime')),coalesce(sum(CASE WHEN date(start_time,'unixepoch','localtime')=date('now','localtime') THEN duration ELSE 0 END),0) FROM page_stat WHERE duration>0 AND id_book="..id)
  out.seconds=number(total);out.read_pages=number(pages);out.days=number(days);out.today_seconds=number(today)
  out.sessions=number(conn:rowexec("SELECT count(*) FROM (SELECT start_time,lag(start_time+duration) OVER (ORDER BY start_time) AS previous_end FROM page_stat_data WHERE duration>0 AND id_book="..id..") WHERE previous_end IS NULL OR start_time-previous_end>1800"))
  out.average=out.sessions and out.sessions>0 and out.seconds/out.sessions or nil
  if native and out.read_pages and out.read_pages>0 then
   local left=doc:getTotalPagesLeft(out.page)
   if type(left)=="number" then out.remaining=native:getTimeForPages(left) end
  end
 end)
 if conn then pcall(conn.close,conn) end
 if not ok then out.unavailable=true end
 return out
end
function Stats:init()
 self.dimen=Device.screen:getSize();self.scroll=0
 self.ges_events={BookStatsTap={GestureRange:new{ges="tap",range=self.dimen}},BookStatsSwipe={GestureRange:new{ges="swipe",range=self.dimen}},
 BookStatsPan={GestureRange:new{ges="pan",range=self.dimen}},BookStatsPanRelease={GestureRange:new{ges="pan_release",range=self.dimen}}}
end
function Stats:refresh(feedback)
 self.data=Stats.model(self.app);UI:setDirty("all","ui")
 if feedback then
  UI:show(require("ui/widget/infomessage"):new{text=self.data.unavailable and "统计暂不可用，请稍后重试" or "已刷新 "..os.date("%H:%M"),timeout=2})
 end
end
function Stats:close() UI:close(self,"ui");UI:setDirty("all","ui") end
function Stats:onCloseWidget() if self.app.book_statistics==self then self.app.book_statistics=nil end end
function Stats:paintTo(bb,x,y)
 self.hits={};local w,h=self.dimen.w,self.dimen.h;local d=assert(self.data)
 self.panel_y=y+math.max(S(64),math.floor(h*.22));local py=self.panel_y
 bb:paintRect(x,py,w,y+h-py,B.COLOR_WHITE);P.rule(bb,x,py,w,2)
 P.label(bb,"本书阅读统计",x+S(20),py,w-S(150),S(60),20,true)
 P.refreshIcon(bb,x+w-S(110),py,S(48),S(60),20)
 self.hits[#self.hits+1]={x=x+w-S(110),y=py,w=S(48),h=S(60),callback=function() self:refresh(true) end,id="book_statistics_refresh"}
 P.centerIcon(bb,"close",x+w-S(58),py,S(58),S(60),S(25))
 self.hits[#self.hits+1]={x=x+w-S(58),y=py,w=S(58),h=S(60),callback=function() self:close() end,id="book_statistics_close"}
 local cy=py+S(60);P.label(bb,d.title,x+S(20),cy,w-S(40),S(48),16,true);cy=cy+S(48)
 P.rule(bb,x+S(20),cy,w-S(40))
 local rows={{"累计阅读",duration(d.seconds)},{"今日阅读",duration(d.today_seconds)},
 {"已读页数",d.read_pages and d.read_pages.." 页" or "—"},{"阅读天数",d.days and d.days.." 天" or "—"},
 {"阅读次数",d.sessions and d.sessions.." 次" or "—"},{"平均每次",duration(d.average)},
 {"预计剩余",d.remaining or "—"},{"当前位置",tostring(d.page).." / "..tostring(d.pages).." 页"}}
 self.rows=rows;local rowh=S(62);local footer=S(40);local vh=y+h-cy-footer
 self.list_area={x=x,y=cy,w=w,h=vh};self.scroll_max=math.max(0,#rows*rowh-vh);self.scroll=math.max(0,math.min(self.scroll,self.scroll_max))
 local clip=bb:viewport(x,cy,w,vh)
 for i=math.floor(self.scroll/rowh)+1,math.min(#rows,math.ceil((self.scroll+vh)/rowh)) do
  local ry=(i-1)*rowh-self.scroll
  P.label(clip,rows[i][1],S(20),ry,w*.38-S(20),rowh,18,true)
  P.label(clip,rows[i][2],w*.4,ry,w*.6-S(30),rowh,18,true)
  P.rule(clip,S(20),ry+rowh-S(2),w-S(40),1.2)
 end
 clip:free()
 if self.scroll_max>0 then
  local th=math.max(S(24),math.floor(vh*vh/(#rows*rowh)))
  bb:paintRect(x+w-S(8),cy,S(2),vh,B.COLOR_DARK_GRAY)
  bb:paintRect(x+w-S(10),cy+math.floor((vh-th)*self.scroll/self.scroll_max),S(6),th,B.COLOR_BLACK)
 end
 local fy=y+h-footer;P.rule(bb,x+S(20),fy,w-S(40))
 P.label(bb,d.unavailable and "统计暂不可用" or d.paused and "统计未启用或已冻结，显示已有记录" or "按 KOReader 有效翻页计时，当前停留页尚未计入",x+S(20),fy,w-S(40),S(34),14,true)
end
function Stats:scrollBy(delta) self.scroll=math.max(0,math.min(self.scroll_max or 0,self.scroll+delta));UI:setDirty(self,"ui") end
function Stats:onBookStatsTap(_,ges)
 if ges and ges.pos then
  if ges.pos.y<self.panel_y then self:close() else local fn=P.find(self,ges.pos);if fn then self.app:safe(fn) end end
 end
 return true
end
function Stats:onBookStatsSwipe(_,ges)
 if not ges then return true end
 if ges.pos and ges.pos.y<self.panel_y then if ges.direction=="south" then self.app:showControls() end
 elseif ges.direction=="north" then self:scrollBy(self.list_area.h*.7)
 elseif ges.direction=="south" then self:scrollBy(-self.list_area.h*.7) end
 return true
end
function Stats:onBookStatsPan(_,ges) if ges and ges.pos and self.list_area and ges.pos.y>=self.list_area.y and ges.relative then self.pan=ges.relative.y end;return true end
function Stats:onBookStatsPanRelease(_,ges) if self.pan then self:scrollBy(-(ges and ges.relative and ges.relative.y or self.pan));self.pan=nil end;return true end
function Stats:onKeyPress(key)
 if key:match({Device.input.group.Back}) then self:close()
 elseif key:match({Device.input.group.PgFwd}) then self:scrollBy(self.list_area.h*.7)
 elseif key:match({Device.input.group.PgBack}) then self:scrollBy(-self.list_area.h*.7) end
 return true
end
Stats.onKeyRepeat=Stats.onKeyPress
function Stats:onSetDimensions() self:init();UI:setDirty("all","ui");return true end
return Stats
