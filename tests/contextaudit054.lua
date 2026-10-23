require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage')
G_reader_settings=require('luasettings'):open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,full_takeover=true})
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
G_reader_settings:saveSetting('document_metadata_folder','dir')
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local Key=require('device/key')
local FM=require('apps/filemanager/filemanager');local Reader=require('apps/reader/readerui')
local P=require('einkfrontend/paint');local S=P.s;local Context=require('einkfrontend/context')
local root=assert(os.getenv('EINK_PROJECT'));local books=assert(os.getenv('EINK_030_BOOKS'))
local variant=assert(os.getenv('EINK_VARIANT'));local out=root..'/test-results-054/'
local report={tests={},matrix={},variant=variant,device='NOT_RUN'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function hit(w,id)
 UI:forceRePaint();for _,h in ipairs(w.hits or {}) do if h.id==id then return h end end
end
local function ticks() for _=1,30 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end end
FM:showFiles(books);local app=FM.instance.einkfrontend.app;ticks()
local remove={};for _,win in ipairs(UI._window_stack) do if win.widget.text then remove[#remove+1]=win.widget end end
for _,w in ipairs(remove) do UI:close(w) end
check('Menu scope matrix covers the settings root every category details library and Home',function()
 local routes={{'settings'},{'home'},{'library'},{'frontend'},{'about'},{'clock_settings'},{'clock_zones'},{'clock_zone_list','Shanghai'},{'transfer_settings'}}
 for _,category in ipairs(app.native.categories) do routes[#routes+1]={'catalog_category',category[1]} end
 for _,category in ipairs(require('einkfrontend/native').extra_categories) do routes[#routes+1]={'catalog_category',category[1]} end
 for _,route in ipairs(routes) do
  app:open(unpack(route));local page=app.screen;UI:forceRePaint()
  local settings=route[1]=='settings';local library=page.model.library==true
  assert((hit(page,'settings_more')~=nil)==settings)
  assert((not not Context.allowed(app,'settings_popup'))==settings)
  assert((not not Context.allowed(app,'library_popup'))==library)
  if not settings then assert(app:showSettingsMore()==nil) end
  if not library then assert(app:showLibraryMenu('more')==nil) end
  report.matrix[#report.matrix+1]={route=route[1],param=route[2],settings_more=settings,library_menu=library,reader=false}
 end
end)
check('Invalid menu kind and reader-only actions cannot open unrelated settings in file manager',function()
 app:open('library');local page=app.screen;local route=app.stack[#app.stack]
 assert(not app:showLibraryMenu('unknown') and not app:showReader('font') and not app:showNavigation('toc') and not app:showBookStatistics())
 assert(app.screen==page and app.stack[#app.stack]==route)
end)
check('Collection search keeps its scoped magnifier without inheriting the settings More menu',function()
 app.library:createCollection('审查收藏甲');app.library:createCollection('审查收藏乙')
 local book={file=books..'/navigation.epub',title='测试书籍'}
 for _,route in ipairs({{'collection_manager'},{'collection_members','审查收藏甲'},{'book_collections',book}}) do
  app:open(unpack(route));assert(hit(app.screen,'page_search') and not hit(app.screen,'settings_more'))
  assert(Context.allowed(app,'page_search') and not app:showSettingsMore())
 end
 app:open('collection_manager');hit(app.screen,'page_search').callback()
 local dialog=UI._window_stack[#UI._window_stack].widget;assert(dialog.title=='搜索当前页面')
 dialog:setInputText('审查收藏乙');dialog.buttons[1][2].callback()
 assert(#app.screen.model.rows==1 and app.screen.model.rows[1].title=='审查收藏乙')
 app:open('settings');assert(not hit(app.screen,'page_search') and app:searchPage()==nil)
end)
check('Collection management appears only on the collection tab; library menu does not gain settings shortcuts',function()
 app:open('library')
 for _,tab in ipairs({'books','authors','series','collections'}) do
  app:selectLibraryTab(tab);local popup=app:showLibraryMenu('more');UI:forceRePaint();local manage=false
  for _,r in ipairs(popup.current_rows) do manage=manage or r.text=='管理收藏';assert(r.text~='搜索' and r.text~='重启 KOReader') end
  assert(manage==(tab=='collections'));popup:close()
 end
end)
check('Header popups close when route or library tab changes and old row hit areas are cleared immediately',function()
 app:open('library');local popup=app:showLibraryMenu('sort');UI:forceRePaint();assert(#popup.hits>0)
 app:go('catalog_category','device');assert(not app.library_popup and #app.screen.hits==0)
 app:open('library');app:showLibraryMenu('filter');app:selectLibraryTab('authors');assert(not app.library_popup)
 app:open('settings');app:showSettingsMore();app:go('about');assert(not app.settings_popup and #app.screen.hits==0)
end)
check('Confirmations cannot act after navigation or after cancel and cannot execute twice',function()
 app:open('settings');local actions=0;local box=app:confirm('测试确认',function() actions=actions+1 end)
 app:go('about');assert(not UI:isWidgetShown(box));box.ok_callback();assert(actions==0)
 app:open('settings');box=app:confirm('测试取消',function() actions=actions+1 end);box.cancel_callback();box.ok_callback();assert(actions==0);UI:close(box)
 box=app:confirm('测试一次',function() actions=actions+1 end);box.ok_callback();box.ok_callback();assert(actions==1);UI:close(box)
end)
check('Continuous scrollbar dragging remains responsive between repaints while row hits are invalidated',function()
 app:open('clock_zone_list','');local page=app.screen;UI:forceRePaint();local track=assert(page.scroll_track)
 page:onFrontendPan(nil,{pos={x=track.x+1,y=track.y+track.h*.25},relative={y=1}});local first=page.scroll_y
 assert(#page.hits==0 and page.scroll_track==track)
 page:onFrontendPan(nil,{pos={x=track.x+1,y=track.y+track.h*.75},relative={y=2}})
 assert(page.scroll_y>first);local position=page.scroll_y;page:onFrontendPanRelease(nil,{relative={y=300}})
 assert(page.scroll_y==position)
end)
check('Text inputs reject stale callbacks but preserve retry on validation failure',function()
 app:open('settings');local values={};local dialog=app.adapter:promptText('测试输入','原值',function(s) values[#values+1]=s end)
 local submit=dialog.buttons[1][2].callback;app:open('home');assert(not UI:isWidgetShown(dialog));submit();assert(#values==0 and app.screen.model.home)
 local attempts=0;dialog=app.adapter:promptText('重试','',function(s) attempts=attempts+1;if s=='' then return false end;values[#values+1]=s end,{keep_on_error=true})
 submit=dialog.buttons[1][2].callback;submit();assert(attempts==1 and UI:isWidgetShown(dialog));dialog:setInputText('有效');submit();submit()
 assert(attempts==2 and #values==1 and values[1]=='有效' and not UI:isWidgetShown(dialog))
end)
check('File chooser confirmation cannot change the root after its source page closes',function()
 app:open('library');local chosen=0;local chooser=app.adapter:chooseLibraryRoot(books,function() chosen=chosen+1 end)
 -- chooseLibraryRoot returns no public object; retrieve the real native window.
 chooser=UI._window_stack[#UI._window_stack].widget;local callback=chooser.onConfirm
 app:open('settings');assert(not UI:isWidgetShown(chooser));callback(books);assert(chosen==0)
end)
check('Mobile editor firewall rules precede terminal rules and partial setup rolls back',function()
 app:open('home');local editor=app:showHomeEditor();local Web=require('einkfrontend/homeweb')
 local kindle,execute=Device.isKindle,os.execute;local calls={};Device.isKindle=function() return true end
 os.execute=function(command) calls[#calls+1]=command;return #calls==2 and 1 or 0 end
 local ok=pcall(Web.new,editor,{ip='127.0.0.1'});Device.isKindle=kindle;os.execute=execute
 assert(not ok and #calls==3 and calls[1]:find('iptables -I INPUT',1,true) and calls[2]:find('iptables -I OUTPUT',1,true) and calls[3]:find('iptables -D INPUT',1,true))
 editor:close()
end)
check('Mobile sessions reject expired closed-editor and stopped requests without changing layout',function()
 app:open('home');local editor=app:showHomeEditor();local Web=require('einkfrontend/homeweb')
 local web=Web.new(editor,{ip='127.0.0.1',no_firewall=true});editor.server=web
 local headers={host=web.host,authorization='Bearer '..web.token};local revision=editor.revision
 assert(web:request('GET','/api/layout',headers,''):find(' 200 ',1,true))
 web.expires=0;assert(web:request('GET','/api/layout',headers,''):find(' 401 ',1,true));web:stop()
 assert(web:request('GET','/api/layout',headers,''):find(' 401 ',1,true) and editor.revision==revision)
 web=Web.new(editor,{ip='127.0.0.1',no_firewall=true});editor.server=web;editor:close()
 assert(web:request('GET','/api/layout',{},''):find(' 401 ',1,true))
end)

Reader:doShowReader(books..'/navigation.epub');local reader=assert(Reader.instance);app=reader.einkfrontend.app
check('Font layout and theme entries remain distinct and have no recursive More fallback',function()
 for _,tab in ipairs({'font','layout','themes'}) do
  local panel=app:showReader(tab);UI:forceRePaint();assert(panel.tab==tab and not hit(panel,'aa_more'))
  for _,r in ipairs(panel.current_rows or {}) do assert(r.title~='更多') end
 end
 local panel=app:showReader('font');assert(hit(panel,'aa_font_options'));hit(panel,'aa_font_options').callback();UI:forceRePaint()
 assert(panel.tab=='font_options' and #panel.current_rows==3);panel.current_rows[1].callback();assert(panel.option_id=='font_hinting')
 panel:setTab('layout');hit(panel,'aa_layout_options').callback();UI:forceRePaint()
 assert(panel.tab=='layout_options' and #panel.current_rows==3);panel.current_rows[1].callback();assert(panel.option_id=='word_spacing')
 panel:close()
end)
check('Theme management More has a disjoint hit area and never applies a theme on edge taps',function()
 local ok,id=app.themes:create('审查主题',app.typography:snapshot());assert(ok,id)
 local panel=app:showReader('themes');panel:setTab('theme_list')
 for _,fraction in ipairs({0,.5,.99}) do
  panel:setTab('theme_list');local more=assert(hit(panel,'aa_row_more_1'));local main=assert(hit(panel,'aa_row_1'))
  assert(main.x+main.w<=more.x)
  local fn=assert(P.find(panel,{x=more.x+math.max(1,more.w*fraction),y=more.y+more.h/2}));fn()
  assert(panel.tab=='theme_manage' and panel.theme_id==id)
 end
 panel:close()
end)
check('Hardware Back and on-screen Back follow the same actual parent and close top-level panels',function()
 local panel=app:showReader('font');local theme=app.themes.records[1];panel.theme_id=theme.id;panel.option_id='font_hinting';panel.option_parent='font_options'
 for _,pair in ipairs({{'fonts','font'},{'font_options','font'},{'layout_options','layout'},{'theme_manage','theme_list'},{'theme_list','themes'},{'option','font_options'}}) do
  panel:setTab(pair[1]);panel:onKeyPress(Key:new('Back',{}));assert(panel.tab==pair[2])
  panel:setTab(pair[1]);hit(panel,'aa_back').callback();assert(panel.tab==pair[2])
 end
 for _,tab in ipairs({'font','layout','themes','menu'}) do panel=app:showReader(tab);panel:onKeyPress(Key:new('Back',{}));assert(not app.reader_panel) end
end)
check('Reader tab and navigation switches discard old control hits before the next repaint',function()
 local panel=app:showReader('font');assert(hit(panel,'font_size_plus'));panel:setTab('layout')
 assert(#panel.hits==0 and #panel.sliders==0 and not panel.pending_adjustment)
 local nav=app:showNavigation('toc');UI:forceRePaint();assert(#nav.hits>0);nav:setView('bookmarks');assert(#nav.hits==0);nav:close()
end)
check('A prompt from a closed reader panel cannot save a theme into a different context',function()
 local panel=app:showReader('themes');local before=#app.themes.records;panel:themeSave()
 local dialog=UI._window_stack[#UI._window_stack].widget;dialog:setInputText('不应保存')
 panel:close();dialog.buttons[1][2].callback();assert(#app.themes.records==before and not UI:isWidgetShown(dialog))
end)
reader:onClose();if FM.instance then FM.instance:onClose() end
FM:showFiles(books);app=FM.instance.einkfrontend.app;app:open('settings')
check('Disabling the frontend closes owned dialogs and prevents stale callbacks and menus from reopening it',function()
 local actions=0;local dialog=app.adapter:promptText('停用测试','值',function() actions=actions+1 end);local accept=dialog.buttons[1][2].callback
 local box=app:confirm('停用确认',function() actions=actions+1 end)
 FM.instance.einkfrontend:stopPlugin();assert(not UI:isWidgetShown(dialog) and not UI:isWidgetShown(box));accept();box.ok_callback()
 assert(actions==0 and not app.screen and not app:open('settings') and not app:showSettingsMore() and not app:showControls() and not app:showHomeEditor())
end)
FM.instance:onClose()
local file=assert(io.open(out..'context-audit-'..variant..'.json','w'));file:write(require('json').encode(report));file:close()
print('COMPLETE '..variant)
