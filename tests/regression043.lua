require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');local Settings=require('luasettings')
G_reader_settings=Settings:open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,reader_entry=true,full_takeover=true})
G_reader_settings:saveSetting('document_metadata_folder','dir')
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local Reader=require('apps/reader/readerui');local FM=require('apps/filemanager/filemanager')
local P=require('einkfrontend/paint');local S=P.s;local B=P.BB
local Layout=require('einkfrontend/homelayout');local Copy=require('einkfrontend/catalog').copy
local Equal=require('einkfrontend/adapter').equal;local Stats=require('einkfrontend/homestats')
local root=assert(os.getenv('EINK_PROJECT'));local books=assert(os.getenv('EINK_030_BOOKS'));local variant=os.getenv('EINK_VARIANT')
local output=root..'/test-results-043/';local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn) local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil};print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err) end
local function clear() local list={};for _,entry in ipairs(UI._window_stack) do if entry.widget.text then list[#list+1]=entry.widget end end;for _,w in ipairs(list) do UI:close(w) end end
local function shot(name,meta) clear();UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(output..file);meta=meta or {};meta.file=file;report.frames[#report.frames+1]=meta end
local function hit(widget,id) UI:forceRePaint();for _,h in ipairs(widget.hits) do if h.id==id then assert(h.callback,id);return h end end;error('missing hit '..id) end
local function activate(widget,id) return hit(widget,id).callback() end
local original=Layout.defaults();local settings=Settings:open(DS:getSettingsDir()..'/einkfrontend-home.lua')
check('Legacy seven-widget layout upgrades without resetting order quotes widths or writing the file',function()
 local legacy=Copy(original);legacy.version=1;legacy.heatmap_weeks=nil;legacy.daily_goal_minutes=nil
 while #legacy.widgets>7 do table.remove(legacy.widgets) end
 legacy.widgets[1],legacy.widgets[6]=legacy.widgets[6],legacy.widgets[1];legacy.widgets[1].enabled=true;legacy.widgets[1].span=1;legacy.quote_text='自己的名言｜我的笔记';legacy.quote_index=3
 settings:saveSetting('layout',legacy);settings:flush()
 local layout=Layout.new();assert(not layout.error and layout.config.version==2 and #layout.config.widgets==13)
 for i=1,7 do assert(Equal(legacy.widgets[i],layout.config.widgets[i])) end
 assert(layout.config.quote_text==legacy.quote_text and layout.config.quote_index==3)
 assert(Equal(Settings:open(settings.file):readSetting('layout'),legacy))
 for i=8,13 do assert(not layout.config.widgets[i].enabled) end
 assert(layout:commit(original))
end)
check('Missing duplicate or malformed legacy widgets remain explicit configuration errors',function()
 for _,kind in ipairs({'missing','duplicate','bad'}) do
  local c=Copy(original);c.version=1;while #c.widgets>7 do table.remove(c.widgets) end
  if kind=='missing' then table.remove(c.widgets,2) elseif kind=='duplicate' then c.widgets[2]=Copy(c.widgets[1]) else c.widgets[2].enabled='yes' end
  settings:saveSetting('layout',c);settings:flush();assert(Layout.new().error)
 end
 settings:saveSetting('layout',original);settings:flush()
end)
check('Calendar offsets remain consecutive through leap day and DST transitions',function()
 local function stamp(y,m,d) return os.time{year=y,month=m,day=d,hour=12,min=0,sec=0} end
 assert(Stats.day(-1,stamp(2024,3,1))=='2024-02-29');assert(Stats.day(1,stamp(2024,12,31))=='2025-01-01')
 assert(Stats.day(-1,stamp(2026,3,9))=='2026-03-08');assert(Stats.day(-1,stamp(2026,11,2))=='2026-11-01')
end)
Reader:doShowReader(books..'/navigation.epub');local r=assert(Reader.instance);local app=r.einkfrontend.app
check('TOC bookmarks and annotations share the exact boxed search and action geometry',function()
 local geometry
 for _,view in ipairs({'toc','bookmarks','annotations'}) do
  local nav=app:showNavigation(view);UI:forceRePaint();local g=nav.action_bar
  assert(g.search.h==S(44) and g.action.h==S(44) and g.search.y==g.action.y)
  local this={g.search.x,g.search.w,g.search.h,g.action.x,g.action.w,g.action.h}
  if geometry then assert(Equal(geometry,this)) else geometry=this end
  hit(nav,'navigation_search');hit(nav,'navigation_search_icon');assert(nav.list_area.y==g.search.y-S(10)+S(64))
  shot('navigation-'..view,{bar=g});nav:close()
 end
end)
check('Bookmark add remove search and annotation sort still work through their shared bar',function()
 local nav=app:showNavigation('bookmarks');activate(nav,'navigation_toggle_bookmark');assert(r.bookmark:isPageBookmarked(r.bookmark:getCurrentPageNumber()))
 activate(nav,'navigation_toggle_bookmark');assert(not r.bookmark:isPageBookmarked(r.bookmark:getCurrentPageNumber()))
 local prompt=app.adapter.promptText;app.adapter.promptText=function(_,_,_,fn) fn('测试') end
 activate(nav,'navigation_search_icon');app.adapter.promptText=prompt;assert(nav.states.bookmarks.query=='测试')
 nav:setView('annotations');activate(nav,'navigation_sort');assert(nav.states.annotations.reverse);nav:close()
end)
check('Aa tabs have no More loop and preserve distinct font and spacing controls with working Back',function()
 for _,tab in ipairs({'font','layout','themes','font_options','layout_options'}) do
  app:showReader(tab);local panel=app.reader_panel;UI:forceRePaint()
  for _,h in ipairs(panel.hits) do assert(h.id~='aa_more') end
  if tab=='font' then local entry=hit(panel,'aa_font_options');assert(entry.y+entry.h<=panel.dimen.h-S(P.style.toolbar_h)) end
  shot('aa-'..tab)
  if tab=='font_options' or tab=='layout_options' then
   assert(#panel.current_rows==3);panel.current_rows[1].callback();UI:forceRePaint();assert(panel.tab=='option')
   assert(panel.option_id==(tab=='font_options' and 'font_hinting' or 'word_spacing'))
   activate(panel,'aa_back');assert(panel.tab==tab);activate(panel,'aa_back');assert(panel.tab==(tab=='font_options' and 'font' or 'layout'))
  end
 end
 app:close()
end)
check('Battery ink ends at the same inset as clock ink at 0 9 34 100 and unknown percent',function()
 for _,value in ipairs({0,9,34,100,'unknown'}) do
  local w,h=Device.screen:getWidth(),S(52);local bb=B.new(w,h,B.TYPE_BB8);bb:paintRect(0,0,w,h,B.COLOR_WHITE)
  P.inkLabel(bb,'12:34',S(20),0,w*.3,h,16,true,nil,'left');P.battery(bb,value,w-S(20)-S(104),0,S(104),h)
  local left,right=w,-1
  for y=0,h-1 do for x=0,w-1 do if bb:getPixel(x,y):getColor8().a<128 then left=math.min(left,x);right=math.max(right,x) end end end
  assert(left==S(20) and w-1-right==S(20),tostring(left)..' '..tostring(w-1-right));bb:writePNG(output..'battery-'..tostring(value)..'-'..variant..'.png');bb:free()
 end
end)
app:close();r:onClose();FM:showFiles(books);app=FM.instance.einkfrontend.app
local conn=require('lua-ljsqlite3/init').open(DS:getSettingsDir()..'/statistics.sqlite3')
-- A real native schema/view created by ReaderStatistics, with isolated test data.
conn:exec('DELETE FROM page_stat_data; DELETE FROM book;')
conn:exec("INSERT INTO book(id,title,authors,pages,md5,total_read_time,total_read_pages) VALUES(1,'测试','原创',200,'one',0,0),(2,'测试二','原创',100,'two',0,0)")
-- Freeze only this fixture's statistics clock at local noon: running near
-- midnight must not turn today's seeded rows into accidental future events.
local fixture=os.date('*t');fixture.hour=12;fixture.min=0;fixture.sec=0;fixture.isdst=nil
local now=os.time(fixture);local read,day=Stats.read,Stats.day
Stats.read=function(db,at) return read(db,at or now) end
Stats.day=function(offset,at) return day(offset,at or now) end
local t=os.date('*t',now);t.hour=0;t.min=10;t.sec=0;t.isdst=nil;local base=os.time(t)
local function event(book,page,ts,duration,total) conn:exec(string.format('INSERT INTO page_stat_data(id_book,page,start_time,duration,total_pages) VALUES(%d,%d,%d,%d,%d)',book,page,ts,duration,total)) end
-- Raw page 1 in a 100-page old layout becomes pages 1 and 2 in book 1.
event(1,1,base,101,100);event(1,1,base+200,100,100);event(2,1,base+400,80,100)
local yesterday=os.date('*t',base);yesterday.day=yesterday.day-1;yesterday.isdst=nil;local past=os.time(yesterday)
event(1,1,past,60,100);event(1,2,past+100,0,100);event(1,3,now+90000,999,100)
check('Native statistics preserve seconds across page rescaling and count distinct book pages per day',function()
 local d=Stats.read(conn,math.max(now,base+500));assert(d.periods.today.seconds==281 and d.periods.today.pages==3)
 assert(d.periods.all.seconds==341 and d.periods.all.pages==5 and d.periods.all.days==2 and d.streak==2)
 assert(d.weekly[7].seconds==281 and d.weekly[6].seconds==60 and math.abs(d.average-341/7)<.001)
 local sum=0;for _,row in pairs(d.hours) do for _,v in pairs(row) do sum=sum+v end end;assert(sum==341)
end)
conn:close()
check('Half-width pairs always have equal heights including shelves and stats, with no overlaps',function()
 local widgets=require('einkfrontend/homewidgets')
 for _,a in ipairs(Layout.registry) do for _,b in ipairs(Layout.registry) do
  local c=Layout.defaults();for _,v in ipairs(c.widgets) do v.enabled=false end
  c.widgets={{id=a.id,enabled=true,span=1},{id=b.id,enabled=true,span=1},{id='clock',enabled=true,span=2}}
  local f=widgets.layout(c,Device.screen:getWidth());assert(f[1].y==f[2].y and f[1].h==f[2].h and f[3].y>f[1].y+f[1].h)
 end end
end)
check('All six dashboards read native data and render within a fixed viewport at full and half width',function()
 local layout=app.home_layout
 for _,span in ipairs({2,1}) do for _,def in ipairs(Layout.registry) do if def.stats then
  assert(layout:change(function(c) for _,v in ipairs(c.widgets) do v.enabled=v.id==def.id;v.span=span end end))
  app:open('home');UI:forceRePaint();assert(not app.screen.paint_fault and app.screen.model.home_data.dashboard)
  shot('home-statistics-'..span)
  local page=app.screen
  for _,frame in ipairs(page.widget_frames) do page:scrollBy(frame.y-page.scroll_y);UI:forceRePaint();assert(not page.paint_fault);shot('widget-'..frame.id..'-'..span) end
 end end end
 assert(layout:change(function(c) for _,v in ipairs(c.widgets) do v.enabled=v.id=='clock' or v.id=='quote';v.span=1 end end))
 app:open('home');shot('home-equal-clock-quote')
 local f=app.screen.widget_frames;assert(f[1].h==f[2].h and f[1].y==f[2].y)
end)
check('Heatmap ranges support full and half widths, day details and immediate refresh use actual rows',function()
 local layout=app.home_layout
 for _,span in ipairs({1,2}) do for _,weeks in ipairs({6,12,24}) do
  assert(layout:change(function(c) for _,v in ipairs(c.widgets) do v.enabled=v.id=='heatmap' or v.id=='daily_goal';v.span=span end;c.heatmap_weeks=weeks end))
  app:open('home');UI:forceRePaint();local page=app.screen;assert(not page.paint_fault)
  local message=app.message;local text;app.message=function(_,value) text=value end
  activate(page,'heatmap_'..Stats.day(0));app.message=message
  assert(text and text:find('4分',1,true) and text:find('3 页次',1,true))
 end end
 local db=require('lua-ljsqlite3/init').open(DS:getSettingsDir()..'/statistics.sqlite3')
 db:exec(string.format('INSERT INTO page_stat_data(id_book,page,start_time,duration,total_pages) VALUES(2,2,%d,120,100)',base+600));db:close()
 app:refreshHome();assert(app.screen.model.home_data.dashboard.periods.today.seconds==401);clear()
 local page=app.screen;local frame;for _,f in ipairs(page.widget_frames) do if f.id=='daily_goal' then frame=f end end
 page:scrollBy(frame.y-page.scroll_y);activate(page,'daily_goal_edit');assert(app.screen.model.title=='每日阅读目标')
end)
check('New modules and settings persist and reject invalid goal and heatmap values atomically',function()
 local layout=app.home_layout;assert(layout:change(function(c) c.daily_goal_minutes=45;c.heatmap_weeks=24 end))
 assert(Equal(Layout.new().config,layout.config));local before=Copy(layout.config)
 for _,v in ipairs({0,-1,1.5,1441,math.huge}) do assert(not layout:change(function(c) c.daily_goal_minutes=v end)) end
 assert(not layout:change(function(c) c.heatmap_weeks=9 end));assert(Equal(before,layout.config))
end)
check('Unavailable statistics show an unavailable state without creating a database',function()
 app:close();local path=DS:getSettingsDir()..'/statistics.sqlite3';assert(os.rename(path,path..'.held'))
 assert(app.home_layout:change(function(c) for _,v in ipairs(c.widgets) do v.enabled=v.id=='heatmap' end end))
 local data=require('einkfrontend/home').model(app);assert(data.stats_unavailable and not data.dashboard)
 assert(not require('libs/libkoreader-lfs').attributes(path));app:open('home');shot('home-no-statistics')
 assert(os.rename(path..'.held',path))
end)
check('Clock and quote only still avoid opening the statistics database',function()
 assert(app.home_layout:change(function(c) for _,v in ipairs(c.widgets) do v.enabled=v.id=='clock' or v.id=='quote' end end))
 local sqlite=require('lua-ljsqlite3/init');local open=sqlite.open;sqlite.open=function() error('unneeded database read') end
 local ok,data=pcall(require('einkfrontend/home').model,app);sqlite.open=open;assert(ok and not data.stats_unavailable)
end)
app:close();FM.instance:onClose()
local f=assert(io.open(output..'regression-'..variant..'.json','w'));f:write(require('json').encode(report));f:close()
print('PASS regression043 complete')
