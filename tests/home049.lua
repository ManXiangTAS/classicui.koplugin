require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');local Settings=require('luasettings');local json=require('json')
G_reader_settings=Settings:open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,full_takeover=true})
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local FM=require('apps/filemanager/filemanager');local Reader=require('apps/reader/readerui')
local P=require('einkfrontend/paint');local S=P.s;local Layout=require('einkfrontend/homelayout');local Fit=require('einkfrontend/homefit')
local Copy=require('einkfrontend/catalog').copy;local Equal=require('einkfrontend/adapter').equal;local Stats=require('einkfrontend/homestats')
local root=assert(os.getenv('EINK_PROJECT'));local variant=os.getenv('EINK_VARIANT');local books=assert(os.getenv('EINK_030_BOOKS'))
local output=root..'/test-results-049/';local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn) local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil};print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err) end
local function clear() local notices={};for _,e in ipairs(UI._window_stack) do if e.widget.text then notices[#notices+1]=e.widget end end;for _,w in ipairs(notices) do UI:close(w) end end
local function shot(name) clear();UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(output..file);report.frames[#report.frames+1]={file=file} end
local function config(ids,span)
 local c=Layout.defaults();for _,v in ipairs(c.widgets) do v.enabled=false end
 local list={};for _,id in ipairs(ids) do local v=Layout.find(nil,id,c);v.enabled=true;v.span=span or 2;list[#list+1]=v end
 for _,v in ipairs(c.widgets) do if not v.enabled then list[#list+1]=v end end;c.widgets=list;return c
end
local function bounded(page)
 assert(not page.paint_fault);assert(page.scroll_y==0 and page.scroll_max==0 and page.model.route.scroll_y==0)
 assert(page.home_content_h<=page.viewport_h and not page.scroll_track)
 local frames=page.widget_frames
 for i,a in ipairs(frames) do
  assert(a.x>=S(20) and a.y>=0 and a.x+a.w<=page.dimen.w-S(20)+1 and a.y+a.h<=page.home_fit.body_h)
  for j=i+1,#frames do local b=frames[j];assert(a.x+a.w<=b.x or b.x+b.w<=a.x or a.y+a.h<=b.y or b.y+b.h<=a.y) end
 end
 for _,hit in ipairs(page.hits) do
  if hit.id~='home_customize' and hit.id~='home_statistics_refresh' and not hit.id:match('^shell_') then
   local inside=false
   for _,f in ipairs(frames) do if hit.x>=f.x and hit.x+hit.w<=f.x+f.w+1 and hit.y>=S(96)+f.y and hit.y+hit.h<=S(96)+f.y+f.h+1 then inside=true end end
   assert(inside,'hit outside its widget: '..hit.id)
  end
 end
end
Reader:doShowReader(books..'/A.epub');Reader.instance:onClose();FM:showFiles(books)
local app=FM.instance.einkfrontend.app;local layout=app.home_layout
assert(layout:commit(Layout.defaults()));app:open('home')
check('Default home fits the exact bounded body in portrait and landscape',function()
 UI:forceRePaint();bounded(app.screen);assert(app.screen.home_fit.fits and #app.screen.widget_frames==3);shot('home-fixed-default')
end)
check('All half-width pairings retain equal row heights and fit without overlaps',function()
 local size=Device.screen:getSize()
 for _,a in ipairs(Layout.registry) do for _,b in ipairs(Layout.registry) do
  local c=Layout.defaults();c.widgets={{id=a.id,enabled=true,span=1},{id=b.id,enabled=true,span=1}}
  local frames,_,fit=Fit.plan(c,size.w,Fit.viewport(size.h));assert(fit.fits and #frames==2)
  assert(frames[1].h==frames[2].h and frames[1].y==frames[2].y and frames[1].x+frames[1].w<frames[2].x)
 end end
end)
check('Legacy scroll offsets wheel swipes pans PagePress and key repeat cannot scroll the home',function()
 local page=app.screen;page.model.route.scroll_y=999999;app:render();UI:forceRePaint()
 for _,delta in ipairs({1000,-1000}) do page:scrollBy(delta);page:turn(delta) end
 for _,direction in ipairs({'north','south','west','east'}) do page:onFrontendSwipe(nil,{direction=direction,pos={x=S(100),y=S(200)},distance=900}) end
 page:onFrontendPan(nil,{relative={y=-900}});page:onFrontendPanRelease(nil,{relative={y=-900}})
 local Key=require('device/key');page:onKeyPress(Key:new('LPgFwd',{}));page:onKeyRepeat(Key:new('LPgBack',{}))
 UI:forceRePaint();bounded(page);assert(app.screen==page and page.model.home)
end)
local function dashboard()
 local now=os.time();local d={now=now,today=Stats.day(0,now),streak=7,average=1200,daily={},weekly={},hours={},periods={}}
 for _,id in ipairs({'today','week','month','all'}) do d.periods[id]={seconds=3600,pages=120,days=12} end
 for i=1,7 do local day=Stats.day(i-7,now);d.weekly[i]={date=day,seconds=i*300};d.daily[day]={seconds=i*300,pages=i*4};d.hours[i]={300,120,0,600,1000,480} end
 return d
end
check('Every module renders at full and half width inside its allocated cell',function()
 for _,span in ipairs({1,2}) do for _,def in ipairs(Layout.registry) do
  assert(layout:commit(config({def.id},span)));app:open('home');app.screen.model.home_data.dashboard=dashboard();UI:forceRePaint();bounded(app.screen)
  assert(#app.screen.widget_frames==1 and app.screen.widget_frames[1].id==def.id)
  shot('module-'..def.id..'-'..span)
 end end
end)
check('Every renderer also accepts its minimum height without drawing beyond the owned cell',function()
 local Widgets=require('einkfrontend/homewidgets');local size=Device.screen:getSize()
 local all=Layout.defaults();for _,w in ipairs(all.widgets) do w.enabled=true end
 local all_layout=setmetatable({config=all},{__index=layout});local all_app=setmetatable({home_layout=all_layout},{__index=app})
 local data=require('einkfrontend/home').model(all_app);data.dashboard=dashboard();assert(data.book and #data.recent>0)
 data.tbr={data.recent[1],data.recent[1],data.recent[1],data.recent[1],data.recent[1]}
 for _,span in ipairs({1,2}) do for _,def in ipairs(Layout.registry) do
  local c=config({def.id},span);local _,_,info=Fit.plan(c,size.w,Fit.viewport(size.h));local frames=Fit.plan(c,size.w,info.needed)
  assert(#frames==1 and frames[1].h==info.needed)
  local proxy=setmetatable({home_layout={config=c}},{__index=app});local page={app=proxy,model={home_data=data},scroll_y=0,hits={}}
  local bb=P.BB.new(size.w,info.needed,P.BB.TYPE_BB8);bb:paintRect(0,0,size.w,info.needed,P.BB.COLOR_WHITE)
  Widgets.paint(page,bb,frames[1],0,0,0,info.needed)
  for _,hit in ipairs(page.hits) do assert(hit.y>=0 and hit.y+hit.h<=info.needed) end
  local file='minimum-'..def.id..'-'..span..'-'..variant..'.png';bb:writePNG(output..file);bb:free();report.frames[#report.frames+1]={file=file}
 end end
end)
check('Mixed dashboard shrinks content to one screen while preserving readable minimum rows',function()
 local c=config({'currently','daily_goal','heatmap','weekly'},1)
 assert(layout:commit(c));app:open('home');app.screen.model.home_data.dashboard=dashboard();UI:forceRePaint();bounded(app.screen)
 assert(app.screen.home_fit.fits and #app.screen.widget_frames==4);shot('home-fixed-mixed')
end)
check('Legacy overfull layouts preserve every saved module and clearly report the ones outside the screen',function()
 local c=Layout.defaults();for _,w in ipairs(c.widgets) do w.enabled=true end
 assert(layout:commit(c));local saved=Copy(c);app:open('home');UI:forceRePaint();bounded(app.screen)
 assert(not app.screen.home_fit.fits and #app.screen.home_fit.omitted>0);assert(Equal(Layout.new().config,saved));shot('home-legacy-overfull')
end)
check('Editor cannot save overflow but allows progressive reduction without deleting legacy preferences',function()
 local editor=app:showHomeEditor();assert(not editor.preview_fit.fits);assert(not editor:save(true))
 local needed=editor.preview_fit.needed;assert(editor:change(function(c) for _,w in ipairs(c.widgets) do w.span=1 end end));assert(editor.preview_fit.needed<=needed)
 assert(editor:change(function(c) for _,w in ipairs(c.widgets) do w.enabled=w.id=='currently' end end))
 assert(editor.preview_fit.fits and editor:save(true));assert(Layout.new():enabled('currently'));editor:close()
end)
check('Native editor rejects extra modules atomically and keeps its full preview fixed',function()
 assert(layout:commit(Layout.defaults()));app:open('home');local editor=app:showHomeEditor()
 local before=Copy(editor.draft);local revision=editor.revision
 local ok,why=editor:change(function(c) for _,w in ipairs(c.widgets) do w.enabled=true end end)
 assert(not ok and why:find('空间不足',1,true));assert(Equal(before,editor.draft) and editor.revision==revision)
 editor.full_preview=true;local preview=editor.preview
 editor:onEditorSwipe(nil,{direction='north',pos={x=100,y=200}});assert(editor.preview==preview and editor.preview_scroll==0 and editor.preview_max==0)
 editor.full_preview=false;shot('home-editor-fixed');editor:close()
end)
check('Legacy individual widget settings enforce capacity and reject invalid config without crashing',function()
 assert(layout:commit(Layout.defaults()));local before=Copy(layout.config)
 local ok,why=layout:change(function(c) for _,w in ipairs(c.widgets) do w.enabled=true end end)
 assert(not ok and why:find('空间不足',1,true) and Equal(before,layout.config))
 assert(not layout:change(function(c) c.widgets[1].id='bad' end));assert(Equal(before,layout.config))
end)
check('LAN editor shares the fixed viewport and rejects overcapacity requests without changing revisions',function()
 local editor=app:showHomeEditor();local web=require('einkfrontend/homeweb').new(editor,{ip='127.0.0.1',no_firewall=true});editor.server=web
 local headers={host=web.host,authorization='Bearer '..web.token,['content-type']='application/json'}
 local r=web:request('GET','/api/layout',headers);local data=require('rapidjson').decode(r:match('\r\n\r\n(.*)'))
 assert(data.fit.fits and data.fit.visible==3 and not data.dirty)
 local config_=Copy(editor.draft);for _,w in ipairs(config_.widgets) do w.enabled=true end
 r=web:request('POST','/api/layout',headers,require('rapidjson').encode{config=config_,revision=editor.revision})
 assert(r:find('400 Bad Request',1,true) and editor.revision==0 and Equal(editor.draft,editor.base))
 local first=web:request('GET','/api/preview',headers);local offset=web:request('GET','/api/preview?offset=999999',headers)
 assert(offset:find('X-Preview-Offset: 0',1,true) and offset:find('X-Preview-Max: 0',1,true))
 assert(first:match('\r\n\r\n(.*)')==offset:match('\r\n\r\n(.*)'))
 assert(not web.html:find('预览下移',1,true) and not web.html:find('预览上移',1,true));editor:close();assert(web.stopped)
end)
check('Editor dimension changes invalidate old mobile revisions and remeasure the bounded preview',function()
 local editor=app:showHomeEditor();local before=editor.revision;editor:onSetDimensions()
 assert(editor.revision==before+1 and editor.preview_scroll==0 and editor.preview_max==0)
 assert(editor.ges_events.EditorTap[1].range==editor.dimen)
 assert(not editor:replaceDraft(editor.draft,before));editor:close()
end)
check('Statistics refresh and settings scrolling remain functional alongside fixed home',function()
 app:open('home');app:refreshHome();UI:forceRePaint();bounded(app.screen)
 require('einkfrontend/settings').search(app,'');local page=app.screen;page:scrollBy(500);assert(page.model.settings and page.scroll_y>0);app:open('home');UI:forceRePaint();bounded(app.screen)
end)
check('Book shelf opens a real book and returns to the same fixed home without stale scroll',function()
 assert(layout:commit(config({'recent'},2)));app:open('home');UI:forceRePaint()
 local selected;for _,h in ipairs(app.screen.hits) do if h.id=='home_recent_1' then selected=h end end;assert(selected)
 selected.callback();UI:_checkTasks();UI:_checkTasks();local r=assert(Reader.instance)
 assert(r.einkfrontend.app:readingReturnLabel()=='主页');r.einkfrontend.app:returnToOrigin();UI:_checkTasks();UI:_checkTasks()
 app=assert(FM.instance.einkfrontend.app);layout=app.home_layout;UI:forceRePaint();assert(app.screen.model.home);bounded(app.screen)
end)
app:close();FM.instance:onClose()
local f=assert(io.open(output..'regression-'..variant..'.json','w'));f:write(json.encode(report));f:close();print('COMPLETE '..variant)
