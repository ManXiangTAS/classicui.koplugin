require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');G_reader_settings=require('luasettings'):open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,full_takeover=true})
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local Event=require('ui/event')
local FM=require('apps/filemanager/filemanager');local Reader=require('apps/reader/readerui')
local P=require('einkfrontend/paint');local S=P.s;local Rail=require('einkfrontend/scrollrail')
local root=assert(os.getenv('EINK_PROJECT'));local books=assert(os.getenv('EINK_030_BOOKS'));local variant=assert(os.getenv('EINK_VARIANT'))
local out=assert(os.getenv('EINK_TEST_OUTPUT'))..'/';local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function shot(name)
 UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(out..file);report.frames[#report.frames+1]=file
end
local function find(w,id) UI:forceRePaint();for _,h in ipairs(w.hits or {}) do if h.id==id then return h end end end
local function center(h) return {x=h.x+h.w/2,y=h.y+h.h/2} end
local function tap(w,id) local h=assert(find(w,id),id);UI:sendEvent(Event:new('Gesture',{ges='tap',pos=require('ui/geometry'):new(center(h))})) end
local function railGeometry(w,t)
 assert(t and t.w==S(44));assert(math.abs((w.dimen.w-t.x-t.w)-S(16))<=1)
 for _,hit in ipairs(w.hits) do
  if hit.y<t.y+t.h and hit.y+hit.h>t.y then assert(hit.x+hit.w<=t.x-S(12),hit.id or 'overlap') end
 end
 assert(t.thumb_h>=math.min(S(36),t.track_h))
end
local function drag(w,t,handler,release,value)
 local start={x=t.x+t.w/2,y=t.thumb_y+t.thumb_h/2}
 local pos={x=start.x,y=value==0 and t.track_y-S(40) or t.track_y+t.track_h+S(40)}
 w[handler](w,nil,{pos=pos,start_pos=start,relative={x=0,y=pos.y-start.y}})
 UI:forceRePaint();w[release](w,nil,{pos=pos,relative={x=0,y=pos.y-start.y}});UI:forceRePaint()
end
local function stableRail(w,pan,release,swipe,read,maximum)
 for _,target in ipairs({0,maximum}) do
  UI:forceRePaint();local t=assert(w.scroll_track)
  local start={x=t.x+t.w/2,y=t.thumb_y+t.thumb_h/2}
  local finish={x=start.x,y=target==0 and t.track_y-S(40) or t.track_y+t.track_h+S(40)}
  w[pan](w,nil,{start_pos=start,pos=finish,relative={y=finish.y-start.y}})
  assert(read()==target);UI:forceRePaint()
  w[swipe](w,nil,{pos=start,end_pos=finish,direction=target==0 and 'north' or 'south',distance=math.abs(finish.y-start.y)})
  assert(read()==target and not w.rail_drag)
  -- Start the second drag in the rail, then lift elsewhere: no final seek.
  UI:forceRePaint();t=w.scroll_track;start={x=t.x+t.w/2,y=t.thumb_y+t.thumb_h/2}
  w[pan](w,nil,{start_pos=start,pos=finish,relative={y=finish.y-start.y}})
  w[release](w,nil,{pos={x=start.x,y=(t.track_y+t.track_h)/2}})
  assert(read()==target and not w.rail_drag)
 end
end
FM:showFiles(books);local app=FM.instance.einkfrontend.app
for _=1,30 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end
local close={};for _,e in ipairs(UI._window_stack) do if e.widget.text then close[#close+1]=e.widget end end;for _,w in ipairs(close) do UI:close(w) end
check('Fresh library buttons work before visiting home or settings, including after reopening',function()
 for cycle=1,3 do
  app:close();app:open('library');local fresh=app.screen
  assert(fresh.model.library and not fresh.model.home and not fresh.model.settings)
  for _,id in ipairs({'library_more','library_filter','library_sort'}) do
   tap(fresh,id);assert(app.library_popup);app.library_popup:close()
  end
  assert(fresh.viewport_h==fresh.dimen.h-fresh.header_h-fresh.footer_h-fresh.info_h)
 end
end)
check('Every layout initializes its viewport and replaces the previous layout height',function()
 local Page=require('einkfrontend/screen')
 local fresh=Page:new{app=app}
 assert(fresh.viewport_h==fresh.dimen.h-fresh.header_h-fresh.footer_h-fresh.info_h)
 for _,model in ipairs({{home=true},{settings=true,subtitle='test'},{library=true,library_root=true},
  {library=true,rich=true},{toolbar={}},{grid=true},{}}) do
  model.rows={};model.route={};fresh:setModel(model)
  assert(fresh.viewport_h==fresh.dimen.h-fresh.header_h-fresh.footer_h-fresh.info_h)
 end
end)
app:open('settings');local page=app.screen
check('Real settings More flashes only its rectangle and restores before the action',function()
 local hit=assert(find(page,'settings_more'));local pos=center(hit);local px,py=math.floor(hit.x+S(5)),math.floor(hit.y+S(5))
 local before=Device.screen.bb:getPixel(px,py):getColor8().a;local outside=Device.screen.bb:getPixel(2,2):getColor8().a
 local yield=UI.yieldToEPDC;local seen=0
 UI.yieldToEPDC=function()
  seen=seen+1;assert(not app.settings_popup);assert(Device.screen.bb:getPixel(px,py):getColor8().a==255-before)
  assert(Device.screen.bb:getPixel(2,2):getColor8().a==outside);shot('settings-pressed')
 end
 tap(page,'settings_more');UI.yieldToEPDC=yield
 assert(seen==1 and app.settings_popup);app.settings_popup:close();UI:forceRePaint()
 assert(Device.screen.bb:getPixel(px,py):getColor8().a==before)
end)
check('Root popup remains two rows; search is not copied into subpages',function()
 tap(page,'settings_more');local pop=app.settings_popup;assert(#pop.rows==2);tap(pop,'settings_popup_search')
 local dialog=UI._window_stack[#UI._window_stack].widget;UI:close(dialog);app:open('about');assert(not find(page,'settings_more'))
end)
local count=0
local function manySettings()
 app:open('about');local m=page.model;m.rows={}
 for i=1,40 do m.rows[i]={title='设置测试 '..i,value='值 '..i,icon='appbar.settings',callback=function() count=count+1 end} end
 m.route.scroll_y=0;page:setModel(m);UI:forceRePaint()
end
check('Scrollable settings have a 44-unit lane, 12-unit content gap and 16-unit edge inset',function()
 manySettings();railGeometry(page,page.scroll_track);shot('settings-scroll')
end)
check('Scrollbar arrow and track taps move settings without activating a row',function()
 local t=page.scroll_track;page:onFrontendTap(nil,{pos={x=t.x+t.w/2,y=t.y+t.h-S(2)}});UI:forceRePaint()
 assert(page.scroll_y>0 and count==0)
 t=page.scroll_track;page:onFrontendTap(nil,{pos={x=t.x+t.w/2,y=t.track_y+t.track_h-1}});UI:forceRePaint();assert(page.scroll_y==page.scroll_max and count==0)
end)
check('Dragging the settings thumb reaches both bounds and does not jump on initial grab',function()
 local t=page.scroll_track;local pos=center({x=t.x,y=t.thumb_y,w=t.w,h=t.thumb_h})
 page:onFrontendPan(nil,{pos=pos,start_pos=pos,relative={y=0}});assert(math.abs(page.scroll_y-page.scroll_max)<=1)
 page:onFrontendPanRelease(nil,{});drag(page,page.scroll_track,'onFrontendPan','onFrontendPanRelease',0);assert(page.scroll_y==0)
 drag(page,page.scroll_track,'onFrontendPan','onFrontendPanRelease',1);assert(page.scroll_y==page.scroll_max and count==0)
end)
check('A fast scrollbar drag stops at the bottom instead of becoming a reverse list swipe',function()
 manySettings();local t=page.scroll_track
 local start={x=t.x+t.w/2,y=t.thumb_y+t.thumb_h/2}
 local finish={x=start.x,y=t.track_y+t.track_h+S(40)}
 page:onFrontendPan(nil,{pos=finish,start_pos=start,relative={y=finish.y-start.y}});UI:forceRePaint()
 assert(page.scroll_y==page.scroll_max)
 page:onFrontendSwipe(nil,{direction='south',pos=start,end_pos=finish,distance=finish.y-start.y})
 assert(page.scroll_y==page.scroll_max and not page.rail_drag)
end)
check('Lifting a scrollbar drag does not seek again from a jittery release coordinate',function()
 manySettings();local t=page.scroll_track
 local start={x=t.x+t.w/2,y=t.thumb_y+t.thumb_h/2}
 page:onFrontendPan(nil,{pos={x=start.x,y=t.track_y+t.track_h+S(40)},start_pos=start,relative={y=S(400)}})
 assert(page.scroll_y==page.scroll_max)
 page:onFrontendPanRelease(nil,{pos=start})
 assert(page.scroll_y==page.scroll_max and not page.rail_drag)
end)
check('A content swipe crossing the scrollbar stays a content swipe',function()
 page:scrollBy(-page.scroll_y);UI:forceRePaint();local t=page.scroll_track
 page:onFrontendPan(nil,{start_pos={x=S(100),y=t.y+S(100)},pos={x=t.x+3,y=t.y+S(80)},relative={y=-S(20)}})
 assert(page.scroll_y==0);page:onFrontendPanRelease(nil,{relative={y=-S(20)}});assert(page.scroll_y==S(20))
end)
check('Disabled hits do not flash; explicit flash_ui off still executes exactly once',function()
 local yield=UI.yieldToEPDC;UI.yieldToEPDC=function() error('unexpected flash') end
 local w={hits={{x=0,y=0,w=20,h=20}}};assert(not P.activate(w,{x=1,y=1}))
 G_reader_settings:saveSetting('flash_ui',false);w.hits[1].callback=function() count=count+1 end;local before=count
 assert(P.activate(w,{x=1,y=1}) and count==before+1)
 G_reader_settings:delSetting('flash_ui');UI.yieldToEPDC=yield
end)
check('A feedback error restores the framebuffer and still runs the action once',function()
 UI:forceRePaint();local before=Device.screen.bb:getPixel(5,5):getColor8().a
 local yield=UI.yieldToEPDC;UI.yieldToEPDC=function() error('fixture') end
 local called=0;local w={hits={{x=0,y=0,w=20,h=20,callback=function() called=called+1 end}}}
 local ok=pcall(P.activate,w,{x=1,y=1})
 assert(ok and called==1 and w._eink_feedback_failed and Device.screen.bb:getPixel(5,5):getColor8().a==before)
 assert(P.activate(w,{x=1,y=1}) and called==2)
 UI.yieldToEPDC=yield;UI:forceRePaint()
end)
check('Kindle feedback inverts and restores before the action, respecting flash_ui',function()
 local isKindle,invert,yield=Device.isKindle,UI.widgetInvert,UI.yieldToEPDC
 Device.isKindle=function() return true end
 UI:forceRePaint();local before=Device.screen.bb:getPixel(5,5):getColor8().a
 local inversions,yields=0,0
 UI.widgetInvert=function(self,...) inversions=inversions+1;return invert(self,...) end
 local called=0;local w={hits={{x=0,y=0,w=20,h=20,callback=function() called=called+1 end}}}
 UI.yieldToEPDC=function()
  yields=yields+1;assert(called==0 and inversions==1)
  assert(Device.screen.bb:getPixel(5,5):getColor8().a==255-before)
 end
 w.hits[1].callback=function()
  assert(Device.screen.bb:getPixel(5,5):getColor8().a==before)
  called=called+1
 end
 G_reader_settings:saveSetting('flash_ui',true);assert(P.activate(w,{x=1,y=1}))
 assert(called==1 and inversions==2 and yields==1 and not w._eink_feedback_failed)
 G_reader_settings:saveSetting('flash_ui',false);assert(P.activate(w,{x=1,y=1}))
 assert(called==2 and inversions==2 and yields==1 and not w._eink_feedback_failed)
 G_reader_settings:delSetting('flash_ui');Device.isKindle=isKindle;UI.widgetInvert=invert;UI.yieldToEPDC=yield
end)
check('A Kindle feedback failure restores pixels and still executes the action once',function()
 local isKindle,yield=Device.isKindle,UI.yieldToEPDC
 Device.isKindle=function() return true end
 UI:forceRePaint();local before=Device.screen.bb:getPixel(5,5):getColor8().a
 UI.yieldToEPDC=function() error('Kindle feedback fixture') end
 local called=0;local w={hits={{x=0,y=0,w=20,h=20,callback=function() called=called+1 end}}}
 assert(P.activate(w,{x=1,y=1}) and called==1 and w._eink_feedback_failed)
 assert(Device.screen.bb:getPixel(5,5):getColor8().a==before)
 Device.isKindle=isKindle;UI.yieldToEPDC=yield;UI:forceRePaint()
end)
check('Failure before the highlight cannot discard the button action',function()
 local paint=UI.forceRePaint;local calls,actions=0,0
 UI.forceRePaint=function(self) calls=calls+1;if calls==1 then error('pre-highlight paint fixture') end;return paint(self) end
 local w={hits={{x=0,y=0,w=20,h=20,callback=function() actions=actions+1 end}}}
 assert(P.activate(w,{x=1,y=1}) and actions==1 and w._eink_feedback_failed)
 UI.forceRePaint=paint
end)
check('Post-action paint errors are contained by the frontend error boundary',function()
 local paint=UI.forceRePaint;local captured,actions
 local fake={safe=function(_,fn) local ok,err=pcall(fn);assert(not ok);captured=err end}
 local w=require('ui/widget/container/widgetcontainer'):new{app=fake,hits={{x=0,y=0,w=20,h=20,feedback=false,callback=function() actions=true;UI.forceRePaint=function() error('post-action paint fixture') end end}}}
 UI:show(w)
 assert(P.activate(w,{x=1,y=1}) and actions and tostring(captured):find('post%-action paint fixture'))
 UI.forceRePaint=paint;UI:close(w);UI:forceRePaint()
end)
check('Changing route discards old rail and row hits before the next paint',function()
 manySettings();app:open('settings');assert(not page.scroll_track and not next(page.hits));UI:forceRePaint()
end)
check('Quick control feedback follows the circle and leaves its corners and label unchanged',function()
 app:showControls();local controls=app.controls;UI:forceRePaint()
 local hit=assert(find(controls,'control_settings'));local c=assert(hit.feedback_circle)
 local cx,cy=math.floor(c.cx),math.floor(c.cy);local corner_x,corner_y=cx-math.floor(c.r),cy-math.floor(c.r)
 local label_x,label_y=cx,cy+S(42)
 local before=Device.screen.bb:getPixel(cx,cy):getColor8().a
 local corner=Device.screen.bb:getPixel(corner_x,corner_y):getColor8().a
 local label=Device.screen.bb:getPixel(label_x,label_y):getColor8().a
 local yield=UI.yieldToEPDC;local seen=0
 UI.yieldToEPDC=function()
  seen=seen+1
  assert(Device.screen.bb:getPixel(cx,cy):getColor8().a==255-before)
  assert(Device.screen.bb:getPixel(corner_x,corner_y):getColor8().a==corner)
  assert(Device.screen.bb:getPixel(label_x,label_y):getColor8().a==label)
  shot('controls-circle-pressed')
 end
 tap(controls,'control_settings');UI.yieldToEPDC=yield
 assert(seen==1 and not app.controls and app.screen.model.settings)
end)
check('A circular feedback failure restores its original pixels before executing once',function()
 UI:forceRePaint();local before=Device.screen.bb:getPixel(10,10):getColor8().a
 local yield=UI.yieldToEPDC;UI.yieldToEPDC=function() error('circle feedback fixture') end
 local calls=0;local w={hits={{x=0,y=0,w=25,h=25,feedback_circle={cx=10,cy=10,r=8},callback=function()
  assert(Device.screen.bb:getPixel(10,10):getColor8().a==before);calls=calls+1
 end}}}
 assert(P.activate(w,{x=10,y=10}) and calls==1 and w._eink_feedback_failed)
 UI.yieldToEPDC=yield
end)
check('Home remains a fixed viewport; editor list has its own independent rail',function()
 app:open('home');UI:forceRePaint();assert(page.scroll_max==0 and not page.scroll_track)
 app:showHomeEditor();local ed=app.home_editor;UI:forceRePaint();railGeometry(ed,ed.scroll_track);shot('home-editor-scroll')
 drag(ed,ed.scroll_track,'onEditorPan','onEditorPanRelease',1);assert(ed.scroll==ed.list_max)
 stableRail(ed,'onEditorPan','onEditorPanRelease','onEditorSwipe',function() return ed.scroll end,ed.list_max)
 ed:close();app:open('home');UI:forceRePaint();assert(page.scroll_max==0)
end)
app:close();Reader:doShowReader(books..'/navigation.epub');app=Reader.instance.einkfrontend.app
check('Font picker rail is operable and selection rows stay outside its lane',function()
 app:showReader('fonts');local panel=app.reader_panel;UI:forceRePaint();railGeometry(panel,panel.scroll_track);shot('fonts-scroll')
 local font=app.adapter:read('font_face');drag(panel,panel.scroll_track,'onReaderPan','onReaderPanRelease',1)
 assert(panel.list_scroll==panel.list_max and app.adapter:read('font_face')==font)
 local t=panel.scroll_track;panel:onReaderTap(nil,{pos={x=t.x+t.w/2,y=t.y+1}});assert(panel.list_scroll<panel.list_max)
 stableRail(panel,'onReaderPan','onReaderPanRelease','onReaderSwipe',function() return panel.list_scroll end,panel.list_max)
end)
check('Switching font panel tab drops stale rail and dragging state immediately',function()
 local panel=app.reader_panel;panel:setTab('layout');assert(not panel.scroll_track and not panel.rail_drag);UI:forceRePaint();assert(not panel.scroll_track)
 tap(panel,'aa_close');assert(not app.reader_panel)
end)
check('Hold-drag moves the font list while lifting preserves the last drag position',function()
 app:showReader('fonts');local panel=app.reader_panel;UI:forceRePaint();local t=panel.scroll_track
 local start={x=t.x+t.w/2,y=t.thumb_y+t.thumb_h/2}
 UI:sendEvent(Event:new('Gesture',{ges='hold_pan',start_pos=require('ui/geometry'):new(start),pos=require('ui/geometry'):new{x=start.x,y=t.track_y+t.track_h+S(40)},relative={y=t.track_h}}))
 UI:sendEvent(Event:new('Gesture',{ges='hold_release',pos=require('ui/geometry'):new(start)}))
 assert(panel.list_scroll==panel.list_max and not panel.rail_drag);panel:close()
end)
check('Long saved-theme grids also reserve the gutter without covering either column',function()
 local records=app.themes.records;app.themes.records={}
 for i=1,24 do app.themes.records[i]={id='fixture'..i,name='测试主题 '..i,values=app.typography:defaults()} end
 app:showReader('themes');local panel=app.reader_panel;UI:forceRePaint();railGeometry(panel,panel.scroll_track)
 drag(panel,panel.scroll_track,'onReaderPan','onReaderPanRelease',1);assert(panel.list_scroll==panel.list_max)
 panel:close();app.themes.records=records
end)
check('Closed overlay hits cannot flash or invoke their old action',function()
 app:showReader('font');local panel=app.reader_panel;local h=assert(find(panel,'aa_close'));panel:close()
 assert(not P.activate(panel,center(h)))
end)
check('TOC rail has separate spacing and arrow taps do not jump the document',function()
 app:showNavigation('toc');local nav=app.navigation;UI:forceRePaint();railGeometry(nav,nav.scroll_track);shot('toc-scroll')
 local before=Reader.instance.document:getXPointer();local t=nav.scroll_track
 nav:onNavigationTap(nil,{pos={x=t.x+t.w/2,y=t.y+t.h-1}});assert(nav.states.toc.scroll>0 and Reader.instance.document:getXPointer()==before)
 UI:forceRePaint();drag(nav,nav.scroll_track,'onNavigationPan','onNavigationPanRelease',1);assert(nav.states.toc.scroll==nav.scroll_max and Reader.instance.document:getXPointer()==before)
 stableRail(nav,'onNavigationPan','onNavigationPanRelease','onNavigationSwipe',function() return nav.states.toc.scroll end,nav.scroll_max)
end)
check('TOC content swipe crossing into its rail does not become a seek',function()
 local nav=app.navigation;nav:scrollBy(-nav.states.toc.scroll);UI:forceRePaint();local t=nav.scroll_track
 nav:onNavigationPan(nil,{start_pos={x=S(100),y=t.y+S(100)},pos={x=t.x+2,y=t.y+S(80)},relative={y=-S(20)}})
 assert(nav.states.toc.scroll==0);nav:onNavigationPanRelease(nil,{relative={y=-S(20)}});assert(nav.states.toc.scroll==S(20));nav:close()
end)
check('Statistics use the same rail; closing via a flashing button leaves no overlay',function()
 app:showBookStatistics();local stats=app.book_statistics;UI:forceRePaint()
 if stats.scroll_max>0 then railGeometry(stats,stats.scroll_track);shot('statistics-scroll');drag(stats,stats.scroll_track,'onBookStatsPan','onBookStatsPanRelease',1);assert(stats.scroll==stats.scroll_max)
  stableRail(stats,'onBookStatsPan','onBookStatsPanRelease','onBookStatsSwipe',function() return stats.scroll end,stats.scroll_max)
 end
 tap(stats,'book_statistics_close');assert(not app.book_statistics)
end)
check('Kindle reopen cycles keep real home/settings/reader buttons operable',function()
 local isKindle=Device.isKindle;Device.isKindle=function() return true end
 for cycle=1,3 do
  app:close();Reader.instance:onClose()
  FM:showFiles(books);app=FM.instance.einkfrontend.app;app:open('settings')
  tap(app.screen,'settings_more');assert(app.settings_popup);tap(app.settings_popup,'settings_popup_search')
  local dialog=UI._window_stack[#UI._window_stack].widget;UI:close(dialog)
  app:close();FM.instance:onClose()
  Reader:doShowReader(books..'/navigation.epub');app=Reader.instance.einkfrontend.app
  app:showReader('fonts');tap(app.reader_panel,'aa_close');assert(not app.reader_panel and app.plugin.active)
 end
 Device.isKindle=isKindle
end)
app:close();Reader.instance:onClose()
local f=assert(io.open(out..'interaction-'..variant..'.json','w'));f:write(require('json').encode(report));f:close();os.exit(0)
