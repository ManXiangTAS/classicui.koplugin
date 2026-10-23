-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Read-only home model from native history, sidecars and statistics database.
local Doc=require("docsettings")
local Home={}
local function number(v) v=tonumber(v);return v and v==v and v>=0 and v or nil end
function Home.capture(app)
 local ui=app.plugin.ui;if not ui.document or not ui.toc then return end
 local page=ui:getCurrentPage();local done=ui.toc:getChapterPagesDone(page);local count=ui.toc:getChapterPageCount(page)
 local record={file=ui.document.file,chapter=ui.toc:getTocTitleOfCurrentPage(),chapter_percent=type(done)=="number" and type(count)=="number" and count>0 and math.max(0,math.min(1,done/count)) or nil}
 if ui.statistics then
  local book_left=ui.document:getTotalPagesLeft(page);local chapter_left=ui.toc:getChapterPagesLeft(page)
  if type(book_left)=="number" then record.book_remaining=ui.statistics:getTimeForPages(book_left) end
  if type(chapter_left)=="number" then record.chapter_remaining=ui.statistics:getTimeForPages(chapter_left) end
 end
 app.library.settings:saveSetting("last_reading_detail",record);app.library.settings:flush()
end
function Home.model(app)
 local out={completed=0,total=#app.library.books}
 local layout=app.home_layout
 if layout and layout:enabled('reading_return') then
  local ok,value=pcall(app.book_value.summary,app.book_value)
  if ok then out.reading_return=value else out.reading_return_error=true end
 end
 local function enabled(id) return not layout or layout:enabled(id) end
 local current=enabled("currently") or enabled("reading_stats")
 local overview=enabled("overview")
 local recent=layout and layout:enabled("recent")
 local seen={}
 if current or overview or recent then for _,book in ipairs(app.library.books) do
  seen[book.file]=book
  if overview and app.library:status(book)=="已完成" then out.completed=out.completed+1 end
 end end
 if current then for _,entry in ipairs(require("readhistory").hist) do
  if not entry.dim and require("libs/libkoreader-lfs").attributes(entry.file,"mode")=="file" then
   local doc=Doc:open(entry.file);local props=doc:readSetting("doc_props") or {}
   out.book=seen[entry.file] or {file=entry.file,title=props.display_title or props.title or entry.text or entry.file:match("([^/]+)$"),authors=props.authors or "作者未知"}
   out.status,out.percent=app.library:status(out.book)
   out.md5=doc:readSetting("partial_md5_checksum");break
  end
 end end
 local detail=current and app.library.settings:readSetting("last_reading_detail")
 if type(detail)=="table" and out.book and detail.file==out.book.file then out.detail=detail end
 if recent then
  out.recent={};local added={}
  for _,entry in ipairs(require("readhistory").hist) do
   if not entry.dim and not added[entry.file] and require("libs/libkoreader-lfs").attributes(entry.file,"mode")=="file" then
    local props=Doc:open(entry.file):readSetting("doc_props") or {}
    out.recent[#out.recent+1]=seen[entry.file] or {file=entry.file,title=props.display_title or props.title or entry.text or entry.file:match("([^/]+)$"),authors=props.authors or "作者未知"}
    added[entry.file]=true;if #out.recent>=layout.config.recent_count then break end
   end
  end
 end
 if layout and layout:enabled("tbr") then
  local coll=require("readcollection").coll;local name=coll["To Be Read"] and "To Be Read" or coll["待读"] and "待读"
  out.tbr={}
  if name then for _,book in ipairs(app.library:collectionBooks(name)) do
   if app.library:inCollection(book.file,name) then out.tbr[#out.tbr+1]=book;if #out.tbr>=layout.config.tbr_count then break end end
  end end
 end
 local dashboard=false
 for _,def in ipairs(require("einkfrontend/homelayout").registry) do if def.stats and enabled(def.id) then dashboard=true;break end end
 if not overview and not enabled("reading_stats") and not dashboard then return out end
 local path=require("datastorage"):getSettingsDir().."/statistics.sqlite3"
 if require("libs/libkoreader-lfs").attributes(path,"mode")~="file" then out.stats_unavailable=true;return out end
 local conn
 local ok=pcall(function()
  conn=require("lua-ljsqlite3/init").open(path,"ro");conn:set_busy_timeout(150)
  if dashboard then out.dashboard=require("einkfrontend/homestats").read(conn) end
  if overview then out.total_seconds=number(conn:rowexec("SELECT sum(total_read_time) FROM book")) end
  if enabled("reading_stats") and out.md5 then
   local statement=conn:prepare("SELECT id,total_read_time,total_read_pages FROM book WHERE md5=? ORDER BY last_open DESC LIMIT 1")
   statement:bind(out.md5);local row=statement:step();statement:close()
   if row then
    local id=number(row[1]);out.book_seconds=number(row[2]);out.book_pages=number(row[3])
    if id then
     -- A new reading session starts after a gap of more than 30 minutes.
     out.sessions=number(conn:rowexec("SELECT count(*) FROM (SELECT start_time,lag(start_time+duration) OVER (ORDER BY start_time) AS previous_end FROM page_stat_data WHERE duration>0 AND id_book="..id..") WHERE previous_end IS NULL OR start_time-previous_end>1800"))
    end
   end
  end
 end)
 if conn then pcall(conn.close,conn) end
 if not ok then out.stats_unavailable=true;out.dashboard=nil end
 return out
end
return Home
