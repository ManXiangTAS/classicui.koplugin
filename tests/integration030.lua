require("setupkoenv")
package.path="plugins/einkfrontend.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
local DS=require("datastorage")
G_reader_settings=require("luasettings"):open(DS:getDataDir().."/settings.reader.lua")
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
G_reader_settings:saveSetting("language","zh_CN");require("gettext").changeLang("zh_CN")
G_reader_settings:saveSetting("eink_frontend",{auto_open=false,reader_entry=true,full_takeover=true})
G_reader_settings:saveSetting("document_metadata_folder","dir")
require("logger"):setLevel(require("logger").levels.warn)
local Device=require("device");require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager");local Event=require("ui/event");local Key=require("device/key")
local FM=require("apps/filemanager/filemanager");local Reader=require("apps/reader/readerui")
local Doc=require("docsettings");local Equal=require("einkfrontend/adapter").equal;local Copy=require("einkfrontend/catalog").copy
local mode=arg[1];local root=assert(os.getenv("EINK_PROJECT"));local dir=assert(os.getenv("EINK_030_BOOKS"))
local variant=os.getenv("EINK_VARIANT");local report={mode=mode,variant=variant,device="NOT_RUN",tests={},audits={}}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and "PASS" or "FAIL",error=not ok and tostring(err) or nil}
 print((ok and "PASS " or "FAIL ")..name..(not ok and (": "..tostring(err)) or ""));if not ok then error(err) end
end
local function shot(name)
 local remove={};for _,w in ipairs(UI._window_stack) do if w.widget.text then remove[#remove+1]=w.widget end end
 for _,w in ipairs(remove) do UI:close(w) end
 UI:forceRePaint();assert(not (FM.instance and FM.instance.einkfrontend.app.screen and FM.instance.einkfrontend.app.screen.paint_fault));Device.screen:shot(root.."/test-results-030/"..name.."-"..variant..".png")
end
local function open(name) Reader:doShowReader(dir.."/"..(name or "A.epub"));local r=assert(Reader.instance);return r,assert(r.einkfrontend) end
local function close() if Reader.instance then Reader.instance:onClose() end end
local function audit(app)
 app.native:refresh();local a=app.native.catalog:audit();report.audits[#report.audits+1]=a;assert(a.static_action_nodes>0);assert(#a.missing==0,"Registered action nodes lost: "..#a.missing)
end
if mode=="catalog" then
 FM:showFiles(dir);local fm=assert(FM.instance);local p=assert(fm.einkfrontend);local app=p.app
 check("FileManager ShowMenu and keyboard route to the new settings without a native menu",function()
  assert(p.gate.active);fm.menu:onShowMenu();assert(app.screen.model.title=="设置" and #app.screen.model.rows==10 and not fm.menu.menu_container)
  app:close();fm.menu:onKeyPressShowMenu();assert(app.screen and not fm.menu.menu_container);shot("settings-integrated")
 end)
 check("Default entry opens Kobo library with two shell destinations and no native exit header",function()
  app:close();p:onEInkFrontendOpen();assert(app.screen.model.library and app.stack[1].id~="home")
  app:scanLibrary(dir)
  for _=1,200 do UI:shiftScheduledTasksBy(-require("ui/time").s(.02));UI:_checkTasks();if not app.library.job then break end end
  assert(not app.library.job and #app.library.books==3);app:selectLibraryTab("books");shot("kobo-library-grid")
  local hits={};for _,h in ipairs(app.screen.hits) do if h.id then hits[h.id]=true end end
  assert(hits.tab_books and hits.tab_authors and hits.tab_series and hits.tab_collections and hits.library_filter and hits.library_sort and hits.library_more)
  assert(app.screen.footer_h==Device.screen:scaleBySize(116) and hits.shell_library and hits.shell_home)
 end)
 check("Kobo filter and sort popovers operate in place and preserve the shell",function()
  app:showLibraryMenu("filter");shot("kobo-library-filter");local popup=app.library_popup
  popup.current_rows[2].callback();assert(app.browser.filter.statuses["未读"] and app.library_popup==popup)
  popup.current_rows[1].callback();assert(not next(app.browser.filter.statuses));popup:close()
  app:showLibraryMenu("sort");shot("kobo-library-sort");app.library_popup.current_rows[1].callback()
  assert(not app.library_popup and app.library_sort=="last_opened" and app.screen.model.library)
  app:showLibraryMenu("more");shot("kobo-library-more");app.library_popup.current_rows[2].callback()
  assert(app.library_layout=="list" and app.screen.model.library);shot("kobo-library-list")
 end)
 check("Closing settings restores the exact author destination and library view",function()
  app:selectLibraryTab("authors");app:go("books",{field="authors",value="作者甲"});app.library_layout="list";app:render()
  app:open("settings");UI:forceRePaint();local P=require("einkfrontend/paint")
  local fn=P.find(app.screen,{x=app.screen.dimen.w-P.s(20),y=P.s(20)});assert(fn);fn()
  assert(app.screen and app.screen.model.library and not fm.menu.menu_container)
  assert(app.stack[#app.stack].param.value=="作者甲" and app.library_layout=="list");shot("settings-close-library")
 end)
 check("Back from root settings and library never reveals the native file manager",function()
  app:open("settings");app.screen:onKeyPress(Key:new("Back",{}));assert(app.screen and app.screen.model.library)
  app:selectLibraryTab("books");app.screen:onKeyPress(Key:new("Back",{}));assert(app.screen and app.screen.model.library)
 end)
 check("Top tap is inert and top swipe alone opens device controls with an independent settings action",function()
  app:close();fm.menu:onTapShowMenu({pos={x=20,y=0}});assert(not app.screen and not app.controls and not fm.menu.menu_container)
  fm.menu:onSwipeShowMenu({direction="south",pos={x=20,y=0}});assert(app.controls and not app.screen and not fm.menu.menu_container)
  UI:forceRePaint();local P=require("einkfrontend/paint");local fn;for _,h in ipairs(app.controls.hits) do if h.id=="control_settings" then fn=h.callback end end
  assert(fn);fn();assert(app.screen.model.title=="设置" and not app.controls);app:dismiss();assert(app.screen.model.library)
 end)
 check("Closing a native plugin callback returns to the replacement library",function()
  local called=0;local node={text="关闭后返回",callback=function() called=called+1 end}
  app.native:open({node},"插件测试");app.native:select(node)
  assert(called==1 and app.screen and app.screen.model.library and not fm.menu.menu_container)
 end)
 check("Every static registered FileManager action remains reachable in a category",function() audit(app) end)
 local calls={build=0,tap=0,hold=0,disabled=0}
 fm.menu:registerToMainMenu({name="eink030_fixture",addToMainMenu=function(_,items)
  items.eink030_fixture={text="集成测试插件",sorting_hint="missing_plugin_parent",sub_item_table_func=function()
   calls.build=calls.build+1
   return {{text_func=function() return "测试开关 "..calls.tap end,checked_func=function() return calls.tap%2==1 end,
    callback=function(host) assert(host.updateItems and host.item_table_stack);calls.tap=calls.tap+1;host:updateItems() end,
    hold_callback=function(host,item) assert(host and item.text_func);calls.hold=calls.hold+1 end},
    {text="禁用项",enabled_func=function() return false end,callback=function() calls.disabled=calls.disabled+1 end}}
  end}
  items.eink030_missing_target={text="目标分类失效",sorting_hint="more_tools",callback=function() end}
 end})
 app.native.catalog.mapping.eink030_missing_target="missing_category"
 local menu_order=require("ui/elements/filemanager_menu_order");menu_order.eink030_disconnected_parent={}
 fm.menu:registerToMainMenu({name="eink030_disconnected",addToMainMenu=function(_,items)
  items.eink030_disconnected_parent={text="未连接父级"}
  items.eink030_disconnected_child={text="原父级已断开",sorting_hint="eink030_disconnected_parent",callback=function() end}
 end})
 check("Missing plugin parent and missing target category automatically fall back to Misc",function()
  app.native:refresh();assert(app.native.catalog.entries.eink030_fixture.category=="misc");assert(app.native.catalog.entries.eink030_missing_target.category=="misc");assert(app.native.catalog.entries.eink030_disconnected_child.fallback_reason=="missing_native_parent");assert(calls.build==0)
  app:go("catalog_category","misc");shot("misc-integrated");audit(app)
 end)
 check("Lazy plugin branch opens in the replacement page using a real TouchMenu receiver",function()
  local node=app.native.catalog.entries.eink030_fixture.node
  app.native:open({node},"杂项");app.native:select(node);assert(calls.build==1 and #app.native.host.item_table==2)
  app.native:select(app.native.host.item_table[1]);assert(calls.tap==1);assert(app.screen.model.rows[1].checked);shot("plugin-submenu-integrated")
 end)
 check("Plugin hold, disabled state and parent navigation preserve native contracts",function()
  app.native:select(app.native.host.item_table[1],true);assert(calls.hold==1)
  assert(not app.native:select(app.native.host.item_table[2]));assert(calls.disabled==0)
  app:back();assert(#app.native.host.item_table==1);app:back();assert(not app.native.host)
 end)
 check("Checkbox-only callbacks retain their separate hit target and native selection semantics",function()
  local calls=0;local node={text="独立复选框",checked_func=function() return calls%2==1 end,checkmark_callback=function() calls=calls+1 end}
  app.native:open({node},"复选框测试");UI:forceRePaint()
  local page=app.screen;local paint=require("einkfrontend/paint")
  local action=paint.find(page,{x=paint.s(20),y=page.header_h+paint.s(20)})
  assert(action);action();assert(calls==1 and app.screen.model.rows[1].checked)
  app:close()
 end)
 check("Holding a control without a hold action never executes its tap callback",function()
  local paint=require("einkfrontend/paint");local count=0
  local w={hits={{x=0,y=0,w=50,h=50,callback=function() count=count+1 end}}}
  local fn=paint.find(w,{x=10,y=10},true);assert(fn==nil and count==0)
 end)
 check("Full takeover can be switched off and on immediately through recovery settings",function()
  local function toggle()
   app:open("frontend")
   for _,row in ipairs(app.screen.model.rows) do if row.title:find("全菜单接管",1,true) then row.callback();return end end
   error("Missing takeover switch")
  end
  toggle();assert(not p.gate.active and not p:option("full_takeover",true));app:close()
  fm.menu:onShowMenu();assert(fm.menu.menu_container and not app.screen);fm.menu:onCloseFileManagerMenu()
  toggle();assert(p.gate.active and p:option("full_takeover",true));app:close()
  fm.menu:onShowMenu();assert(app.screen and not fm.menu.menu_container);app:close()
 end)
 check("Late registered plugins appear after catalog refresh",function()
  fm.menu:registerToMainMenu({name="eink030_late",addToMainMenu=function(_,items) items.eink030_late={text="后注册扩展",sorting_hint="more_tools",callback=function() end} end})
  app.native:refresh();assert(app.native.catalog.entries.eink030_late.category=="misc");audit(app)
 end)
 check("Search indexes native descriptions without evaluating lazy branches",function()
  local before=calls.build;require("einkfrontend/settings").search(app,"集成测试插件")
  assert(#app.screen.model.rows==1 and calls.build==before)
 end)
 check("Native compatibility session closes back to active interception",function()
  app:close();p.gate:openNative();assert(p.gate.native_session and fm.menu.menu_container and not app.screen)
  fm.menu:onCloseFileManagerMenu();assert(not p.gate.native_session)
  fm.menu:onShowMenu();assert(app.screen and not fm.menu.menu_container);app:close()
 end)
 check("Routing exception restores native methods and disables session interception",function()
  app.open=function() error("injected route failure") end
  fm.menu:onShowMenu();assert(not p.active and not p.gate.active and fm.menu.menu_container)
  assert(rawget(fm.menu,"onShowMenu")==nil)
  fm.menu:onCloseFileManagerMenu()
 end)
 fm:onClose()
elseif mode=="typography" then
 local r,p=open();local app=p.app;local t=app.typography
 check("Reader compound menu and Aa open one bottom panel while upward swipe opens book statistics",function()
  r.menu:onPressMenu();assert(app.reader_panel and not r.menu.menu_container and not r.config.config_dialog)
  app.reader_panel:close();r.config:onShowConfigMenu();assert(app.reader_panel and app.reader_panel.tab=="font")
  r.config:onSwipeShowConfigMenu({direction="north"});assert(app.book_statistics and not app.reader_panel)
  app.book_statistics:close();r.menu:onShowMenu();assert(app.screen and not r.menu.menu_container);app:close()
 end)
 check("Reader top tap opens a reading bar and dismissing settings returns to the same document",function()
  app:close();local page=r.document:getXPointer();r.menu:onTapShowMenu({pos={x=20,y=0}})
  assert(app.reader_topbar and not app.screen and not app.reader_panel and not r.menu.menu_container)
  shot("reader-topbar-integrated")
  r.menu:onSwipeShowMenu({direction="south",pos={x=20,y=0}});assert(app.controls and not app.screen)
  app.controls:close();app:open("settings");app:dismiss();assert(not app.screen and Reader.instance==r and r.document:getXPointer()==page)
 end)
 check("Every static registered EPUB action remains reachable after menu partitioning",function() audit(app) end)
 check("Bottom Aa exposes the complete advanced native typography category",function()
  app:showReader("layout");UI:forceRePaint()
  local hit
  for _,h in ipairs(app.reader_panel.hits) do if h.id=="advanced_typography" then hit=h end end
  assert(hit);hit.callback();assert(not app.reader_panel and app.screen.model.title=="高级排版")
  local roots=app.native.catalog.roots.typography;assert(roots and #roots>0 and #app.screen.model.rows==#roots+1)
  app:close()
 end)
 check("Bottom font, layout and themes render without turning the underlying document",function()
  app:showReader("font");local page=r:getCurrentPage();UI:forceRePaint()
  app.reader_panel:onKeyPress(Key:new("RPgFwd",{}));assert(r:getCurrentPage()==page);shot("aa-integrated")
  app:showReader("layout");shot("layout-integrated");app:showReader("themes");shot("themes-empty-integrated")
 end)
 local values=t:snapshot();values.font_size=31;values.line_spacing=125;values.page_margins={11,15,13,17};values.embedded_css=false
 check("Multi-field typography applies actual font, spacing and four margins and verifies disk values",function()
  local ok,why=t:apply(values,false,nil);assert(ok,why);assert(Equal(t:snapshot(),values));local d=Doc:open(r.document.file)
  assert(Equal(d:readSetting("copt_h_page_margins"),{11,13}));assert(d:readSetting("copt_t_page_margin")==15 and d:readSetting("copt_b_page_margin")==17)
 end)
 local id
 check("Named theme snapshots persist independently and reject empty or duplicate names",function()
  local ok,result=app.themes:create("通勤阅读",values);assert(ok,result);id=result
  local count=#app.themes.records;assert(not app.themes:create("  ",values));assert(not app.themes:create("通勤阅读",values));assert(#app.themes.records==count)
  values.page_margins[1]=99;assert(app.themes:find(id).values.page_margins[1]==11)
 end)
 check("Editing a book does not modify the theme, and applying the theme restores the full snapshot",function()
  assert(t:change("font_size",35));assert(app.themes:find(id).values.font_size==31)
  local stored=Copy(app.themes:find(id).values);assert(t:apply(stored,false,id));assert(t.meta.theme_id==id);assert(Equal(t:snapshot(),stored))
  app:showReader("themes");shot("themes-integrated");app.reader_panel:themeManage(id);shot("theme-management-integrated")
 end)
 check("Missing-font and invalid-margin themes reject the transaction before changing the book",function()
  local before=t:snapshot();local invalid=Copy(before);invalid.font_face="__FONT_NOT_INSTALLED__";assert(not t:apply(invalid,false,nil));assert(Equal(t:snapshot(),before))
  invalid=Copy(before);invalid.page_margins={1,2,3,-1};assert(not t:apply(invalid,false,nil));assert(Equal(t:snapshot(),before))
 end)
 check("Theme rename update and delete keep independent book values",function()
  local extra,other=app.themes:create("临时主题",t:snapshot());assert(extra)
  assert(app.themes:rename(other,"夜读排版"));assert(not app.themes:rename(other,"通勤阅读"));local modified=t:snapshot();modified.font_size=40
  assert(app.themes:update(other,modified));assert(t:snapshot().font_size==31);assert(app.themes:delete(other));assert(not app.themes:find(other));assert(t:snapshot().font_size==31)
 end)
 check("Theme file write failure preserves both the old in-memory and on-disk library",function()
  local before=Copy(app.themes.records);local flush=app.themes.settings.flush
  app.themes.settings.flush=function() error("injected theme write failure") end
  local ok=app.themes:create("保存失败的主题",t:snapshot());assert(not ok);app.themes.settings.flush=flush
  assert(Equal(app.themes.records,before));assert(Equal(require("einkfrontend/themes").new().records,before))
 end)
 check("Book save failure restores the live typography and inheritance metadata",function()
  local before=t:snapshot();local meta=Copy(t.meta);local flush=r.doc_settings.flush
  r.doc_settings.flush=function() error("injected document write failure") end
  local changed=Copy(before);changed.font_size=36;local ok=t:apply(changed,false,nil);r.doc_settings.flush=flush
  assert(not ok);assert(Equal(t:snapshot(),before));assert(Equal(t.meta,meta));r:saveSettings()
 end)
 G_reader_settings:saveSetting("eink030_theme_id",id);G_reader_settings:flush();close()
 local rb,pb=open("B.epub");local tb=pb.app.typography
 check("Restoring inheritance keeps reading progress and cleans cached override keys before flush",function()
  pb.adapter:gotoPercent(50);local before=rb.rolling:getLastPercent();local ok,why=tb:restore();assert(ok,why)
  assert(math.abs(rb.rolling:getLastPercent()-before)<.06)
  local disk=Doc:open(rb.document.file);assert(not disk:has("copt_font_size") and disk:readSetting("eink_frontend_typography").inherit.font_size)
 end)
 check("Editing one inherited field preserves inheritance for all other managed fields",function()
  assert(tb:change("line_spacing",135));assert(not tb.meta.inherit.line_spacing and tb.meta.inherit.font_size)
  assert(Doc:open(rb.document.file):readSetting("copt_line_spacing")==135)
 end)
 check("Defaults save and later inherited font changes do not overwrite an explicit spacing value",function()
  assert(tb:saveDefaults());local next_size=pb.adapter:read("font_size")+2
  G_reader_settings:saveSetting("copt_font_size",next_size);G_reader_settings:flush();tb:onReady()
  assert(pb.adapter:read("font_size")==next_size and pb.adapter:read("line_spacing")==135)
  assert(tb:restore());G_reader_settings:saveSetting("eink030_inherit_expected",next_size+2);G_reader_settings:flush()
 end)
 close()
elseif mode=="restart" then
 local r,p=open();local id=G_reader_settings:readSetting("eink030_theme_id")
 check("Theme and applied document values survive a fresh KOReader process",function()
  local theme=assert(p.app.themes:find(id));assert(theme.name=="通勤阅读" and theme.values.font_size==31)
  assert(p.adapter:read("font_size")==31 and Equal(p.app.typography:snapshot(),theme.values));assert(p.app.typography.meta.theme_id==id)
 end)
 close();local expected=assert(G_reader_settings:readSetting("eink030_inherit_expected"));G_reader_settings:saveSetting("copt_font_size",expected);G_reader_settings:flush()
 r,p=open("B.epub")
 check("Explicit inheritance follows a changed global default after process restart",function()
  assert(p.app.typography.meta.inherit.font_size);assert(p.adapter:read("font_size")==expected)
 end)
 close()
elseif mode=="library_navigation" then
 local function ticks()
  for _=1,30 do UI:shiftScheduledTasksBy(-require("ui/time").s(.02));UI:_checkTasks() end
 end
 FM:showFiles(dir);local p=assert(FM.instance.einkfrontend);local app=p.app;app:open();app:scanLibrary(dir);ticks()
 app:selectLibraryTab("books");app.library_layout="grid";app:render()
 check("Holding a book opens its details and Back returns to the Kobo library",function()
  UI:forceRePaint();local page=app.screen
  local hit;for _,h in ipairs(page.hits) do if h.hold_callback then hit=h;break end end
  assert(hit);page:onFrontendHold(nil,{pos={x=hit.x+10,y=hit.y+10}})
  assert(app.stack[#app.stack].id=="book");app:back();assert(app.screen.model.library)
 end)
 check("Tapping a book cover opens the actual reader directly",function()
  UI:forceRePaint();local page=app.screen
  local hit;for _,h in ipairs(page.hits) do if h.hold_callback then hit=h;break end end
  assert(hit);page:onFrontendTap(nil,{pos={x=hit.x+10,y=hit.y+10}});ticks()
  assert(Reader.instance and Reader.instance.document and not FM.instance)
 end)
 check("Native reader Home returns to the plugin library even when automatic startup is disabled",function()
  local rp=assert(Reader.instance.einkfrontend);assert(not rp:option("auto_open",true))
  rp.app:showControls();UI:forceRePaint();local hit
  for _,h in ipairs(rp.app.controls.hits) do if h.id=="return_library" then hit=h end end
  assert(not hit);Reader.instance:onHome();ticks()
  local returned=assert(FM.instance.einkfrontend.app);assert(returned.screen and returned.screen.model.library and not Reader.instance)
  assert(not FM.instance.menu.menu_container);shot("reader-return-kobo-library")
 end)
 if FM.instance then FM.instance:onClose() end
elseif mode=="style_navigation" then
 local P=require("einkfrontend/paint");local S=P.s
 FM:showFiles(dir);local app=assert(FM.instance.einkfrontend.app);app:open("settings")
 check("Settings use a fixed bold header and a scroll viewport with no pagination footer",function()
  shot("settings-bold-032");assert(app.screen.footer_h==0 and app.screen.model.page==1)
  for _,hit in ipairs(app.screen.hits) do assert(hit.id and hit.id:find("settings_",1,true)) end
 end)
 local called,held=0,0
 local parent={text="滚动测试插件",sub_item_table_func=function()
  local rows={}
  for i=1,40 do local value=i
   rows[i]={text="设置选项 "..i,keep_menu_open=true,enabled_func=function() return value~=12 end,
    callback=function(host) called=value;assert(host.item_table_stack);host:updateItems() end,
    hold_callback=function() held=value end}
  end
  rows[5]={text="第五项子菜单",sub_item_table={{text="返回父级以检查滚动位置",callback=function() end}}}
  return rows
 end}
 app.native:open({parent},"插件设置");app.native:select(parent)
 check("Vertical swipe moves settings content continuously while the header remains fixed",function()
  local page=app.screen;UI:forceRePaint();assert(page.scroll_max>0)
  local original=page.header_h
  page:onFrontendSwipe(nil,{direction="north",distance=S(143),pos={x=S(50),y=page.header_h+S(20)}})
  assert(page.scroll_y==S(143) and page.header_h==original and page.model.page==1);shot("settings-scroll-swipe-032")
  page:onFrontendSwipe(nil,{direction="south",distance=S(143),pos={x=S(50),y=page.header_h+S(20)}});assert(page.scroll_y==0)
 end)
 check("Partial-row pan preserves native tap hold and disabled-state callbacks",function()
  local page=app.screen;page:onFrontendPan(nil,{relative={x=0,y=-S(105)},pos={x=S(50),y=page.header_h+S(80)}})
  page:onFrontendPanRelease(nil,{});assert(page.scroll_y==S(105));UI:forceRePaint()
  local pos={x=S(45),y=page.header_h+S(10)};page:onFrontendTap(nil,{pos=pos});assert(called==2)
  page:onFrontendHold(nil,{pos=pos});assert(held==2);shot("settings-scroll-partial-032")
  page:scrollBy(11*page.row_h-page.scroll_y);UI:forceRePaint();page:onFrontendTap(nil,{pos=pos});assert(called==2)
 end)
 check("Scrollbar reaches the final native setting and clamps at both ends",function()
  local page=app.screen;UI:forceRePaint();local t=assert(page.scroll_track)
  page:onFrontendPan(nil,{pos={x=t.x+2,y=t.y+t.h+S(100)},relative={x=0,y=-20}});page:onFrontendPanRelease(nil,{})
  assert(page.scroll_y==page.scroll_max);UI:forceRePaint()
  page:onFrontendTap(nil,{pos={x=S(45),y=page.dimen.h-S(10)}});assert(called==40);shot("settings-scroll-bottom-032")
  page:scrollBy(-999999);assert(page.scroll_y==0)
 end)
 check("Returning from a native submenu restores its parent scroll position",function()
  local page=app.screen;page:scrollBy(4*page.row_h);local saved=page.scroll_y
  app.native:select(app.native.host.item_table[5]);assert(app.screen.scroll_y==0)
  app:back();assert(app.screen.scroll_y==saved and #app.native.host.item_table==40)
 end)
 check("Quick-control labels are larger black text centered below their actual icons",function()
  app:showControls();UI:forceRePaint();assert(#app.controls.action_layout>=3)
  for _,layout in ipairs(app.controls.action_layout) do assert(math.abs(layout.label_x+layout.label_w/2-layout.cx)<=1) end
  shot("quick-controls-contrast-032");app.controls:close()
 end)
 app:close();FM.instance:onClose()
 local r,p=open();app=p.app
 check("Reading top tap opens chrome without creating native menus or moving the document",function()
  local before=r.document:getXPointer();local zone
  for _,z in ipairs(p.zones) do if z.id=="einkfrontend_reader_topbar" then zone=z end end
  assert(zone);zone.handler();assert(app.reader_topbar and not app.screen and not app.reader_panel)
  app.reader_topbar:onKeyPress(Key:new("RPgFwd",{}));assert(r.document:getXPointer()==before)
  shot("reader-topbar-032");app.reader_topbar:onReaderTopTap(nil,{pos={x=S(40),y=Device.screen:getHeight()-S(50)}})
  assert(not app.reader_topbar and r.document:getXPointer()==before)
 end)
 check("Top reading bar opens Aa and book statistics while Settings stays in quick controls",function()
  app:showReaderTopbar();UI:forceRePaint();local bar=app.reader_topbar;local hit
  for _,h in ipairs(bar.hits) do if h.id=="reader_aa" then hit=h end end
  assert(hit);bar:onReaderTopTap(nil,{pos={x=hit.x+5,y=hit.y+5}});assert(app.reader_panel and not app.reader_topbar)
  app:showReaderTopbar();app.reader_topbar:action("statistics");assert(app.book_statistics and not app.reader_topbar)
  app:showControls();UI:forceRePaint();local controls=app.controls;local settings
  for _,h in ipairs(controls.hits) do if h.id=="control_settings" then settings=h end end
  assert(settings);settings.callback();assert(app.screen.model.settings and not app.controls)
  app:dismiss();assert(not app.screen and Reader.instance==r)
 end)
 check("Top-bar navigation uses native document data and search keeps its feature window",function()
  for _,event in ipairs({"ShowToc","ShowBookmark","ShowFulltextSearchInput"}) do
   app:showReaderTopbar();local count=#UI._window_stack;app.reader_topbar:action(event)
   assert(not app.reader_topbar and #UI._window_stack>=count)
   local remove={};for _,window in ipairs(UI._window_stack) do if window.widget~=r then remove[#remove+1]=window.widget end end
   for _,widget in ipairs(remove) do UI:close(widget) end
  end
 end)
 check("Top bar and quick controls switch cleanly and font lists scroll without footer pages",function()
  app:showReaderTopbar();app.reader_topbar:onReaderTopSwipe(nil,{direction="south"});assert(app.controls and not app.reader_topbar)
  app:showReader("font");assert(not app.controls);app.reader_panel:setTab("fonts");UI:forceRePaint()
  local panel=app.reader_panel;assert(panel.list_area and panel.list_max>0)
  panel:onReaderSwipe(nil,{direction="north"});assert(panel.list_scroll>0);shot("aa-font-scroll-032")
  app:close()
 end)
 check("Reading top-bar return goes to the plugin library even with automatic startup disabled",function()
  app:showReaderTopbar();app.reader_topbar:action("library")
  for _=1,40 do UI:shiftScheduledTasksBy(-require("ui/time").s(.02));UI:_checkTasks() end
  assert(FM.instance and FM.instance.einkfrontend.app.screen.model.library and not Reader.instance)
  shot("reader-topbar-library-return-032");FM.instance:onClose()
 end)
elseif mode=="fixes033" then
 local P=require("einkfrontend/paint");local S=P.s;local Time=require("ui/time")
 FM:showFiles(dir);local fm=FM.instance;local fp=fm.einkfrontend;local app=fp.app
 check("Settings icons and text share measured vertical centers and the title has no breadcrumb target",function()
  app:open("settings");UI:forceRePaint()
  for _,row in ipairs(app.screen.row_layout) do if row.icon then assert(math.abs(row.icon.cy-row.label.cy)<=1) end end
  for _,hit in ipairs(app.screen.hits) do assert(hit.id~="settings_title") end
  local count=#app.stack;app.screen:onFrontendTap(nil,{pos={x=Device.screen:getWidth()/2,y=S(25)}});assert(#app.stack==count)
 end)
 check("Settings is a standalone quick action with its own centered icon and label",function()
  app:showControls();UI:forceRePaint();local found
  for _,a in ipairs(app.controls.action_layout) do if a.id=="control_settings" then found=a end end
  assert(found and found.label=="设置" and math.abs(found.label_x+found.label_w/2-found.cx)<=1)
  for _,h in ipairs(app.controls.hits) do if h.id=="control_settings" then assert(h.y>S(50));h.callback();break end end
  assert(app.screen.model.title=="设置" and not app.controls);app:close()
 end)
 check("Native opening notices retain delay timeout dismissability and callback while restyled",function()
  local done=0;local Info=require("ui/widget/infomessage")
  local notice=Info:new{text="正在打开《测试书甲》……",timeout=.15,show_delay=.05,dismissable=false,dismiss_callback=function() done=done+1 end}
  assert(notice._eink_notice and notice.movable[1].radius==0 and not notice.dismissable and notice.face.orig_size==P.style.label)
  UI:show(notice);assert(notice.invisible)
  UI:shiftScheduledTasksBy(-Time.s(.06));UI:_checkTasks();assert(not notice.invisible and done==0)
  UI:forceRePaint();Device.screen:shot(root.."/test-results-030/native-opening-notice-033-"..variant..".png")
  UI:shiftScheduledTasksBy(-Time.s(.2));UI:_checkTasks();assert(done==1 and not notice._timeout_func)
  for _,win in ipairs(UI._window_stack) do assert(win.widget~=notice) end
 end)
 check("Native toast masks history and input propagation remain intact with the shared style",function()
  local Toast=require("ui/widget/notification");local mask=G_reader_settings:readSetting("notification_sources_to_show_mask")
  G_reader_settings:saveSetting("notification_sources_to_show_mask",0)
  assert(not Toast:notify("应被过滤",Toast.SOURCE_OTHER));assert(Toast:notify("排版已保存",Toast.SOURCE_ALWAYS_SHOW))
  local notice=UI._window_stack[#UI._window_stack].widget
  assert(notice._eink_notice and notice.face.orig_size==P.style.label and notice.toast)
  assert(Toast:getPastMessages()[1]:find("排版已保存",1,true))
  UI:forceRePaint();Device.screen:shot(root.."/test-results-030/native-toast-033-"..variant..".png")
  assert(notice:onKeyPress(Key:new("Back",{}))==false and not notice._timeout_func)
  G_reader_settings:saveSetting("notification_sources_to_show_mask",mask)
 end)
 check("Notice style hooks restore on takeover disable and preserve another live owner",function()
  local N=require("einkfrontend/notices");local Info=require("ui/widget/infomessage");local original=N.info_original;local other={}
  N.install(other);N.detach(fp);assert(Info.init==N.info_wrapper);N.detach(other);assert(Info.init==original)
  N.install(fp);assert(Info.init==N.info_wrapper)
 end)
 check("Notice hooks coexist with a later wrapper through disable and re-enable",function()
  local N=require("einkfrontend/notices");local Info=require("ui/widget/infomessage");local original=N.info_original
  local ours=Info.init;local calls=0;local foreign=function(widget,...) calls=calls+1;return ours(widget,...) end
  Info.init=foreign;N.detach(fp);assert(Info.init==foreign)
  local notice=Info:new{text="停用时保留第三方处理"};assert(not notice._eink_notice);notice:free()
  N.install(fp);notice=Info:new{text="重新启用通知样式"};assert(notice._eink_notice and calls==2);notice:free()
  N.detach(fp);assert(Info.init==foreign);Info.init=original;N.install(fp)
 end)
 fm:onClose();local r,p=open();app=p.app;local t=app.typography
 local function countPanels()
  local n=0;for _,win in ipairs(UI._window_stack) do if win.widget._eink_overlay then n=n+1 end end;return n
 end
 check("Repeated gestures reuse one visible panel even after losing a cached reference",function()
  local before=r.document:getXPointer();app:showControls();local first=app.controls
  for _=1,20 do r.menu:onSwipeShowMenu({direction="south",pos={x=20,y=0}});assert(app.controls==first and countPanels()==1) end
  app.controls=nil;app:showControls();assert(app.controls==first and countPanels()==1)
  app:showReader("font");local panel=app.reader_panel;assert(countPanels()==1)
  for _,tab in ipairs({"font","layout","themes","menu","font"}) do app:showReader(tab);assert(app.reader_panel==panel and countPanels()==1) end
  app:showReaderTopbar();assert(countPanels()==1 and not app.reader_panel);app:showControls();local latest=app.controls
  first:onCloseWidget();assert(app.controls==latest and countPanels()==1 and r.document:getXPointer()==before)
  app:close();assert(countPanels()==0)
 end)
 check("Shrinking Aa to layout redraws the document where the taller panel used to be",function()
  app:showReader("font");shot("overlap-font-033");app.reader_panel:setTab("layout");shot("overlap-layout-036")
  app:close();app:showReader("layout");shot("overlap-layout-clean-036");app:close()
 end)
 check("Font contrast and quarter-step weight controls apply live engine settings and persist",function()
  app:showReader("font");UI:forceRePaint();local panel=app.reader_panel
  for _,id in ipairs({"font_gamma","font_base_weight"}) do
   local slider;for _,s in ipairs(panel.sliders) do if s.id==id then slider=s end end;assert(slider)
   local pos={x=slider.x+slider.w*.67,y=slider.y+slider.h/2};local value=panel:sliderValue(pos,slider)
   panel:onReaderPan(nil,{pos=pos});assert(panel.pending_adjustment and panel.pending_adjustment.id==id)
   panel:onReaderPanRelease(nil,{});assert(not panel.pending_adjustment and p.adapter:read(id)==value)
   assert(Doc:open(r.document.file):readSetting("copt_"..id)==value);UI:forceRePaint()
  end
  assert(panel.dimen.h-panel.panel_y>=math.min(S(P.style.panel_font_h),panel.dimen.h-S(P.style.toolbar_h)-S(64))+S(P.style.toolbar_h)-1)
  local cy;for _,m in ipairs(panel.toolbar_layout) do if cy then assert(math.abs(cy-m.cy)<=1) end;cy=m.cy end
  app:close()
 end)
 local values=t:snapshot();values.font_gamma=30;values.font_base_weight=1.25;values.word_spacing={135,80};values.word_expansion=6;values.cjk_width_scaling=112;values.embedded_fonts=true
 local id
 check("Thirteen-field themes restore all new typography values and independent table snapshots",function()
  local ok,why=t:apply(values,false);assert(ok,why)
  assert(math.abs(r.document:getGammaLevel()-1.9)<.001)
  local created,result=app.themes:create("完整排版033",t:snapshot());assert(created,result);id=result
  for _,entry in ipairs({{"font_gamma",15},{"font_base_weight",-.5},{"word_spacing",{90,60}},{"word_expansion",0},{"cjk_width_scaling",100},{"embedded_fonts",false}}) do assert(t:change(entry[1],entry[2])) end
  assert(t:apply(app.themes:find(id).values,false,id));assert(Equal(t:snapshot(),values))
  local d=Doc:open(r.document.file);assert(Equal(d:readSetting("copt_word_spacing"),{135,80}) and d:readSetting("copt_font_base_weight")==1.25)
  assert(app.themes:find(id).schema==2)
  r:handleEvent(Event:new("SetFontBaseWeight",1.5));assert(not t.meta.theme_id and p.adapter:read("font_base_weight")==1.5)
  assert(t:apply(values,false,id));G_reader_settings:saveSetting("eink033_theme_id",id);G_reader_settings:flush()
 end)
 check("Invalid contrast weight and word-spacing values reject the transaction without partial changes",function()
  local before=t:snapshot()
  for _,entry in ipairs({{"font_gamma",57},{"font_base_weight",1.1},{"word_spacing",{135,24}},{"word_expansion",21},{"cjk_width_scaling",151}}) do
   local bad=Copy(before);bad[entry[1]]=entry[2];assert(not t:apply(bad,false));assert(Equal(t:snapshot(),before))
  end
 end)
 check("Legacy seven-field themes preserve new adjustments until explicitly updated",function()
  local before=t:snapshot();local legacy={};for i=1,7 do local key=t.fields[i];legacy[key]=Copy(before[key]) end;legacy.font_size=before.font_size+1
  assert(t:apply(legacy,false));assert(t:matches(legacy))
  for i=8,#t.fields do local key=t.fields[i];assert(Equal(t:snapshot()[key],before[key])) end
  assert(t:apply(values,false,id));assert(app.themes:update(id,t:snapshot()));assert(Equal(app.themes:find(id).values,values))
 end)
 check("New typography fields roll back together when a document save fails",function()
  local before=t:snapshot();local flush=r.doc_settings.flush;r.doc_settings.flush=function() error("injected033 write failure") end
  local changed=Copy(before);changed.font_gamma=15;changed.font_base_weight=-1;changed.word_spacing={95,70}
  local ok=t:apply(changed,false);r.doc_settings.flush=flush;assert(not ok and Equal(t:snapshot(),before));r:saveSettings()
 end)
 check("Separated Aa spacing options expose word spacing without a nested More action",function()
  app:showReader("layout_options");UI:forceRePaint();local panel=app.reader_panel;assert(#panel.current_rows==3)
  panel.current_rows[1].callback();UI:forceRePaint();assert(panel.option_id=="word_spacing" and panel.tab=="option")
  local prompt=p.adapter.promptText;p.adapter.promptText=function(_,_,initial,callback) assert(initial=="135 80");callback("140 85") end
  panel.current_rows[3].callback();p.adapter.promptText=prompt;assert(Equal(p.adapter:read("word_spacing"),{140,85}))
  assert(t:apply(values,false,id));panel:setTab("layout_options");shot("aa-spacing-033");app:close()
 end)
 check("New typography defaults and inheritance clean all newly managed sidecar keys",function()
  local old=Copy(G_reader_settings.data);assert(t:saveDefaults())
  local defaults=t:defaults();for i=8,#t.fields do local key=t.fields[i];assert(Equal(defaults[key],values[key])) end
  assert(t:restore());local disk=Doc:open(r.document.file)
  for i=8,#t.fields do local key=t.fields[i];assert(t.meta.inherit[key] and not disk:has("copt_"..key)) end
  G_reader_settings.data=old;G_reader_settings:flush();assert(t:apply(values,false,id))
 end)
 close();local rb,pb=open("B.epub");local tb=pb.app.typography
 check("New inherited typography fields save intent before a later process reads changed defaults",function()
  assert(tb:restore());G_reader_settings:saveSetting("copt_font_gamma",25);G_reader_settings:saveSetting("copt_font_base_weight",.75)
  G_reader_settings:saveSetting("copt_word_spacing",{145,75});G_reader_settings:flush();rb:saveSettings()
  assert(not Doc:open(rb.document.file):has("copt_font_gamma"))
 end)
 close()
elseif mode=="fixes033_restart" then
 local r,p=open();local id=G_reader_settings:readSetting("eink033_theme_id");local values=assert(p.app.themes:find(id)).values
 check("New contrast weight spacing and embedded-font theme data survive a fresh process",function()
  assert(values.font_gamma==30 and values.font_base_weight==1.25 and Equal(values.word_spacing,{135,80}) and values.embedded_fonts)
  assert(Equal(p.app.typography:snapshot(),values) and p.app.typography.meta.theme_id==id)
 end)
 close();r,p=open("B.epub")
 check("Contrast weight and word spacing inherit changed defaults across process restart",function()
  local values=p.app.typography:snapshot();assert(values.font_gamma==25 and values.font_base_weight==.75 and Equal(values.word_spacing,{145,75}))
  assert(p.app.typography.meta.inherit.font_gamma and math.abs(r.document:getGammaLevel()-1.45)<.001)
 end)
 close()
elseif mode=="navigation034" then
 local P=require("einkfrontend/paint");local S=P.s
 local r,p=open("navigation.epub");local app=p.app
 local function hit(id)
  UI:forceRePaint();local nav=assert(app.navigation)
  for _,h in ipairs(nav.hits) do if h.id==id then return h,nav end end
  error("Missing hit: "..id)
 end
 local function tap(id)
  local h,nav=hit(id);nav:onNavigationTap(nil,{pos={x=h.x+h.w/2,y=h.y+h.h/2}})
 end
 check("Reading footer contains exactly Theme Font Layout in the requested order",function()
  app:showReader("menu");UI:forceRePaint();local panel=app.reader_panel
  assert(Equal(panel.toolbar_buttons,{"主题","字体","排版"}) and #panel.toolbar_layout==3)
  for _,tab in ipairs({"themes","font","layout"}) do
   local h;for _,v in ipairs(panel.hits) do if v.id=="reader_bottom_"..tab then h=v end end
   assert(h);panel:onReaderTap(nil,{pos={x=h.x+h.w/2,y=h.y+h.h/2}});assert(panel.tab==tab);UI:forceRePaint()
  end
  shot("reader-bottom-three-034");app:close()
 end)
 check("Native TOC entry opens a non-fullscreen scrolling sheet over the actual book",function()
  local before=r.document:getXPointer();r:handleEvent(Event:new("ShowToc"));UI:forceRePaint();local nav=app.navigation
  assert(nav and nav.view=="toc" and nav.panel_y>=S(64) and not nav.covers_fullscreen and nav.scroll_max>0 and #nav.current_rows==36)
  assert(r.document:getXPointer()==before and not r.toc.toc_menu);shot("toc-sheet-034")
 end)
 check("Nested TOC expands and collapses through its real hit target without changing native data",function()
  local nav=app.navigation;local before=Copy(r.toc.toc)
  tap("toc_toggle_1");UI:forceRePaint();assert(#nav.current_rows==34 and Equal(r.toc.toc,before))
  tap("toc_toggle_1");UI:forceRePaint();assert(#nav.current_rows==36);shot("toc-expanded-034")
 end)
 check("TOC search finds nested entries even below a collapsed parent",function()
  local nav=app.navigation;nav.collapsed[1]=true
  local prompt=p.adapter.promptText;p.adapter.promptText=function(_,_,_,callback) callback("第1章 · 第2节") end
  tap("navigation_search");p.adapter.promptText=prompt;UI:forceRePaint()
  assert(#nav.current_rows==1 and nav.current_rows[1].depth==2);shot("toc-search-034")
  nav.states.toc.query="";nav.collapsed={};nav:refresh()
 end)
 check("TOC scrolling and PagePress move the sheet rather than the underlying document",function()
  local nav=app.navigation;UI:forceRePaint();local before=r.document:getXPointer()
  nav:onNavigationSwipe(nil,{direction="north",pos={x=S(100),y=nav.list_area.y+S(30)}});assert(nav.states.toc.scroll>0)
  nav:onKeyPress(Key:new("LPgFwd",{}));assert(r.document:getXPointer()==before)
  nav:scrollBy(-999999);UI:forceRePaint()
 end)
 check("TOC chapter selection jumps using real xpointers and preserves a back location",function()
  local nav=app.navigation;local target=nav.current_rows[4].item;local expected=r.document:getPageFromXPointer(target.xpointer)
  local stack=#r.link.location_stack;tap("navigation_row_4")
  assert(not app.navigation and r:getCurrentPage()==expected and #r.link.location_stack==stack+1)
  r:handleEvent(Event:new("ShowToc"));tap("navigation_locate");UI:forceRePaint();assert(app.navigation.current_toc>=4)
  app:close()
 end)
 check("Page bookmarks are added by the custom sheet and saved in the native sidecar",function()
  r:handleEvent(Event:new("ShowBookmark"));UI:forceRePaint();assert(app.navigation.view=="bookmarks")
  local before=#r.annotation.annotations;tap("navigation_toggle_bookmark")
  assert(#r.annotation.annotations==before+1 and #Doc:open(r.document.file):readSetting("annotations")==before+1)
  UI:forceRePaint();assert(#app.navigation.current_rows==1);shot("bookmark-sheet-034")
 end)
 local data=app.navigation.data;local positions={}
 for page=1,math.min(r.document:getPageCount(),20),2 do
  r.bookmark:toggleBookmark(page);positions[#positions+1]=r.document:getPageXPointer(page)
 end
 r.annotation:addItem{page=positions[1],pos0=positions[1],pos1=positions[2],drawer="lighten",text="这是一条用于验证摘录、笔记与排序的原始标注。",datetime="2026-10-20 10:00:01"}
 r.annotation:addItem{page=positions[3],pos0=positions[3],pos1=positions[4],drawer="lighten",text="第二条测试摘录",note="已有笔记",datetime="2026-10-20 10:00:02"}
 data:save();app.navigation:refresh()
 check("Independent bookmark and annotation views filter native items without modifying their stored order",function()
  local before=Copy(r.annotation.annotations);tap("navigation_tab_annotations");UI:forceRePaint()
  local nav=app.navigation;assert(#nav.current_rows==2);tap("navigation_sort");UI:forceRePaint()
  assert(nav.current_rows[1].pageno>=nav.current_rows[2].pageno and Equal(r.annotation.annotations,before));shot("annotations-sheet-034")
 end)
 local edited
 check("Annotation details use a scrollable sheet and edits persist through the native annotation path",function()
  local nav=app.navigation;local row=nav.current_rows[1];edited=row.item
  nav:details(row);UI:forceRePaint();assert(nav.detail_box and nav.view=="details");shot("annotation-details-034")
  local prompt=p.adapter.promptText;p.adapter.promptText=function(_,title,initial,callback,options) assert(options.multiline);callback("新笔记\n第二行") end
  tap("navigation_note");p.adapter.promptText=prompt
  assert(edited.note=="新笔记\n第二行");local canonical,index=data:resolve(edited)
  assert(Doc:open(r.document.file):readSetting("annotations")[index].note==edited.note)
  G_reader_settings:saveSetting("eink034_note_datetime",edited.datetime);G_reader_settings:flush()
 end)
 check("Excerpt editing and note removal keep highlight identity and annotation count",function()
  local before=#r.annotation.annotations;assert(data:setText(edited,"校订后的摘录")==nil)
  data:setNote(edited,"");assert(not edited.note and r.bookmark.getBookmarkType(edited)=="highlight" and #r.annotation.annotations==before)
  data:setNote(edited,"新笔记\n第二行");app.navigation:refresh()
 end)
 check("Long annotation text scrolls within the sheet without moving the reader or losing content",function()
  local nav=app.navigation;local long=string.rep("完整笔记内容必须保留，不能只显示第一行。\n",90)
  data:setNote(edited,long);nav:refresh();UI:forceRePaint();assert(nav.scroll_max>0)
  local before=r.document:getXPointer();nav:onNavigationSwipe(nil,{direction="north",pos={x=S(100),y=nav.list_area.y+S(20)}})
  assert(nav.states.details.scroll>0 and r.document:getXPointer()==before)
  assert(edited.note==long);shot("annotation-long-note-034");data:setNote(edited,"新笔记\n第二行");nav:refresh()
 end)
 check("Filtered sorted delete confirmation removes the selected annotation and no other item",function()
  local nav=app.navigation;nav:setView("annotations");UI:forceRePaint();local victim=nav.current_rows[2].item
  assert(victim~=edited);nav:details(nav.current_rows[2]);local before=#r.annotation.annotations
  local confirm=app.confirm;app.confirm=function(_,_,callback) callback() end
  tap("navigation_delete");app.confirm=confirm
  assert(#r.annotation.annotations==before-1 and not pcall(data.resolve,data,victim));assert(data:resolve(edited))
  assert(#Doc:open(r.document.file):readSetting("annotations")==before-1)
 end)
 check("Native annotation detail entry is intercepted and Back restores its new list",function()
  app:close();local _,index=data:resolve(edited);r.bookmark:showBookmarkDetails(index);UI:forceRePaint()
  assert(app.navigation and app.navigation.view=="details" and app.navigation.detail_item==edited)
  app.navigation:onKeyPress(Key:new("Back",{}));assert(app.navigation.view~="details");app:close()
 end)
 check("Navigation panels participate in overlay mutual exclusion and close outside without flipping a page",function()
  r:handleEvent(Event:new("ShowBookmark"));local before=r.document:getXPointer();UI:forceRePaint();local nav=app.navigation
  nav:onNavigationTap(nil,{pos={x=S(30),y=S(20)}});assert(not app.navigation and r.document:getXPointer()==before)
  app:showReader("font");r:handleEvent(Event:new("ShowToc"));assert(app.navigation and not app.reader_panel)
  app:showControls();assert(not app.navigation and app.controls);app:close()
 end)
 check("Explicit native management remains available and disabling takeover restores native TOC",function()
  r:handleEvent(Event:new("ShowBookmark"));app.navigation:openNative();assert(not app.navigation and r.bookmark.bookmark_menu)
  r.bookmark.bookmark_menu[1].close_callback();assert(not r.bookmark.bookmark_menu)
  p.gate:restore();r.toc:onShowToc();assert(r.toc.toc_menu);r.toc.toc_menu.close_callback()
  p:installTakeover();r.toc:onShowToc();assert(app.navigation);app:close()
 end)
 close()
elseif mode=="navigation034_restart" then
 local r,p=open("navigation.epub");local stamp=G_reader_settings:readSetting("eink034_note_datetime")
 check("Custom bookmark notes and excerpts survive a new real reader process",function()
  local found;for _,item in ipairs(r.annotation.annotations) do if item.datetime==stamp then found=item end end
  assert(found and found.note=="新笔记\n第二行" and found.text=="校订后的摘录")
  r.bookmark:onShowBookmark();UI:forceRePaint();assert(p.app.navigation.view=="bookmarks")
  p.app.navigation:setView("annotations");UI:forceRePaint();assert(#p.app.navigation.current_rows==1);shot("annotation-restart-034")
 end)
 close()
elseif mode=="navigation034_pdf" then
 local r,p=open("sample.pdf");local app=p.app
 check("PDF contents and bookmark sheet use page numbers and preserve the same three footer entries",function()
  app:showReader("menu");UI:forceRePaint();assert(Equal(app.reader_panel.toolbar_buttons,{"主题","字体","排版"}))
  r.toc:onShowToc();UI:forceRePaint();assert(app.navigation and app.navigation.view=="toc");shot("pdf-toc-sheet-034")
  r.bookmark:onShowBookmark();UI:forceRePaint();local nav=app.navigation
  nav.data:toggleCurrent();nav:refresh();UI:forceRePaint();assert(#nav.current_rows==1 and type(nav.current_rows[1].item.page)=="number")
  local row=nav.current_rows[1];nav:go(row,false);assert(r:getCurrentPage()==row.item.page and not app.navigation)
 end)
 close()
elseif mode=="home034" then
 local P=require("einkfrontend/paint");local S=P.s;local Home=require("einkfrontend/home")
 FM:showFiles(dir);local fm=FM.instance;local app=fm.einkfrontend.app
 app:open("library");app:scanLibrary(dir)
 for _=1,300 do UI:shiftScheduledTasksBy(-require("ui/time").s(.02));UI:_checkTasks();if not app.library.job then break end end
 check("Library shell has live time battery status and exactly Library Home navigation",function()
  shot("kobo-shell-library-034");assert(app.screen.status_layout.clock:match("%d%d:%d%d"))
  assert(app.screen.status_layout.battery==app.adapter:deviceStatus().battery and Equal(app.screen.shell_navigation,{"library","home"}))
  local hit;for _,h in ipairs(app.screen.hits) do if h.id=="shell_home" then hit=h end end;assert(hit)
  app.screen:onFrontendTap(nil,{pos={x=hit.x+hit.w/2,y=hit.y+hit.h/2}});assert(app.screen.model.home and app.stack[1].id=="home")
 end)
 check("Home reads native history and completion data rather than using example books or figures",function()
  local model=app.screen.model.home_data;local history=require("readhistory").hist
  assert(model.book and model.book.file==history[1].file and model.total==#app.library.books)
  shot("kobo-home-native-034");assert(Equal(app.screen.shell_navigation,{"library","home"}));for _,h in ipairs(app.screen.hits) do assert(h.id~="shell_controls" and h.id~="shell_search") end
 end)
 check("Home and library keep the exact nested library destination and settings close returns to Home",function()
  app:open("library");app:selectLibraryTab("authors");app:go("books",{field="authors",value="作者甲"});app.library_layout="list";app:render()
  app:open("home");app:open("settings");app:dismiss();assert(app.screen.model.home)
  app:open("library");assert(app.stack[#app.stack].param.value=="作者甲" and app.library_layout=="list")
 end)
 check("Home scroll and clock lifecycle preserve the shell and do not create duplicate tasks",function()
  app:open("home");UI:forceRePaint();local page=app.screen;local task=page.clock_tick;assert(task)
  page:onFrontendSwipe(nil,{direction="north",distance=S(180),pos={x=S(100),y=S(150)}})
  assert(page.scroll_y>=0 and page.scroll_y<=page.scroll_max);page:onShow();assert(page.clock_tick==task)
  app:close();assert(not page.clock_tick)
 end)
 fm:onClose()
 local r,p=open("navigation.epub");app=p.app
 r.rolling:onGotoPercent(45);Home.capture(app);local details=app.library.settings:readSetting("last_reading_detail")
 check("Home chapter snapshot comes from actual current chapter and native reading progress",function()
  assert(details.file==r.document.file and details.chapter and details.chapter_percent>=0 and details.chapter_percent<=1)
 end)
 local path=r.document.file;app.library.settings:delSetting("last_reading_detail");app.library.settings:flush()
 close();FM:showFiles(dir);app=FM.instance.einkfrontend.app
 check("Closing the real reader captures chapter details for the next Home without a manual snapshot",function()
  local saved=app.library.settings:readSetting("last_reading_detail");assert(saved and saved.file==path and saved.chapter_percent)
 end)
 local md5=Doc:open(path):readSetting("partial_md5_checksum");local db=require("datastorage"):getSettingsDir().."/statistics.sqlite3"
 local SQ3=require("lua-ljsqlite3/init");local conn=SQ3.open(db)
 local stmt=conn:prepare("INSERT OR REPLACE INTO book(title,authors,md5,last_open,total_read_time,total_read_pages) VALUES(?,?,?,?,?,?)")
 stmt:bind("目录与标注测试书","作者乙",md5,os.time(),600,20):step();stmt:close();local id=conn:rowexec("SELECT last_insert_rowid()")
 for i,entry in ipairs({{1,1000,120},{2,1150,180},{3,5000,300}}) do
  local insert=conn:prepare("INSERT INTO page_stat_data(id_book,page,start_time,duration,total_pages) VALUES(?,?,?,?,?)")
  insert:bind(id,entry[1],entry[2],entry[3],100):step();insert:close()
 end
 conn:close()
 check("Home reads real statistics schema in read-only mode and computes defined session averages",function()
  app:open("home");local model=app.screen.model.home_data
  assert(model.book.file==path and model.book_seconds==600 and model.book_pages==20 and model.sessions==2 and model.total_seconds>=600)
  shot("kobo-home-statistics-034")
 end)
 check("Missing statistics data displays unavailable values without creating a database",function()
  assert(os.rename(db,db..".hidden"));local model=Home.model(app)
  assert(not model.book_seconds and not model.total_seconds and not require("libs/libkoreader-lfs").attributes(db))
  assert(os.rename(db..".hidden",db))
 end)
 check("An empty native history renders an honest Home placeholder",function()
  local history=require("readhistory");local saved=history.hist;history.hist={}
  local model=Home.model(app);assert(not model.book)
  app:open("home");shot("kobo-home-empty-034");history.hist=saved
 end)
 check("Home continue-reading hit opens the actual recent book",function()
  app:open("home");UI:forceRePaint();local hit;for _,h in ipairs(app.screen.hits) do if h.id=="home_continue" then hit=h end end
  assert(hit);app.screen:onFrontendTap(nil,{pos={x=hit.x+hit.w/2,y=hit.y+hit.h/2}})
  for _=1,30 do UI:shiftScheduledTasksBy(-require("ui/time").s(.05));UI:_checkTasks() end
  assert(Reader.instance and Reader.instance.document.file==path)
 end)
 close();if FM.instance then FM.instance:onClose() end
elseif mode=="regression036" then
 local P=require("einkfrontend/paint");local S=P.s;local Stats=require("einkfrontend/bookstatistics")
 FM:showFiles(dir);local app=FM.instance.einkfrontend.app
 local function hit(widget,id)
  UI:forceRePaint();for _,h in ipairs(widget.hits) do if h.id==id then return h end end
  error("Missing hit: "..id)
 end
 local function tapTop(id)
  local bar=assert(app.reader_topbar);local h=hit(bar,id)
  bar:onReaderTopTap(nil,{pos={x=h.x+h.w/2,y=h.y+h.h/2}})
 end
 check("Home and Library status remove duplicate search and menu actions but retain live battery",function()
  local original=app.adapter.deviceStatus
  app.adapter.deviceStatus=function(self) local v=original(self);v.battery=34;return v end
  for _,route in ipairs({"home","library"}) do
   app:open(route);UI:forceRePaint();assert(app.screen.status_layout.battery==34)
   for _,h in ipairs(app.screen.hits) do assert(h.id~="shell_search" and h.id~="shell_controls") end
   shot("status-only-"..route.."-036")
  end
  app.adapter.deviceStatus=original
 end)
 check("Dropdown battery is legible in the file manager without colliding with actions",function()
  local original=app.adapter.deviceStatus;app.adapter.deviceStatus=function(self) local v=original(self);v.battery=0;return v end
  app:showControls();UI:forceRePaint();assert(app.controls.battery_layout.percent==0)
  assert(app.controls.battery_layout.x+app.controls.battery_layout.w<=Device.screen:getWidth())
  shot("dropdown-battery-empty-036");app:close();app.adapter.deviceStatus=original
 end)
 FM.instance:onClose();local r,p=open("navigation.epub");app=p.app
 check("Reading dropdown retains the battery without an origin shortcut",function()
  local original=app.adapter.deviceStatus;app.adapter.deviceStatus=function(self) local v=original(self);v.battery=100;return v end
  app:showControls();local controls=app.controls;UI:forceRePaint();assert(controls.battery_layout.percent==100)
  for _,h in ipairs(controls.hits) do assert(h.id~="return_library") end
  shot("dropdown-battery-reader-036");app.adapter.deviceStatus=original;app:close()
 end)
 check("TOC has no bookmark annotation tabs and uses an input box plus a distinct locate button",function()
  app:showNavigation("toc");local nav=app.navigation;UI:forceRePaint()
  for _,h in ipairs(nav.hits) do assert(not (h.id or ""):match("^navigation_tab_")) end
  local search=hit(nav,"navigation_search");local locate=hit(nav,"navigation_locate")
  assert(search.x+search.w<locate.x and locate.h>=S(40) and nav.list_area.y>=locate.y+locate.h)
  local before=r.document:getXPointer();local prompt=app.adapter.promptText
  app.adapter.promptText=function(_,title,_,callback) assert(title=="搜索目录");callback("第1章 · 第2节") end
  search.callback();app.adapter.promptText=prompt;UI:forceRePaint();assert(#nav.current_rows==1)
  locate.callback();UI:forceRePaint();assert(nav.states.toc.query=="" and #nav.current_rows==36 and r.document:getXPointer()==before)
  shot("toc-controls-036");app:close()
 end)
 check("Reader bar shares bookmark annotation navigation and exposes statistics without redundant actions",function()
  app:showReaderTopbar();local bar=app.reader_topbar;UI:forceRePaint()
  hit(bar,"reader_statistics");hit(bar,"reader_ShowBookmark")
  for _,h in ipairs(bar.hits) do assert(h.id~="reader_annotations" and h.id~="reader_more" and not (h.id or ""):match("^reader_overflow_")) end
  shot("reader-direct-actions-036");tapTop("reader_ShowBookmark");assert(app.navigation and app.navigation.view=="bookmarks" and not app.reader_topbar)
  app:showReaderTopbar();tapTop("reader_ShowBookmark");assert(app.navigation.view=="bookmarks")
  app:showReaderTopbar();tapTop("reader_ShowToc");assert(app.navigation.view=="toc")
  app:close()
 end)
 local db=require("datastorage"):getSettingsDir().."/statistics.sqlite3";local SQ3=require("lua-ljsqlite3/init")
 local native=assert(r.statistics);native:insertDB();local id=assert(native.id_curr_book)
 local conn=SQ3.open(db);conn:exec("DELETE FROM page_stat_data WHERE id_book="..id)
 local date=os.date("*t");date.hour=0;date.min=0;date.sec=0;local day=os.time(date)
 for _,v in ipairs({{1,day+3600,120},{2,day+3750,180},{3,day+7800,300}}) do
  local st=conn:prepare("INSERT INTO page_stat_data(id_book,page,start_time,duration,total_pages) VALUES(?,?,?,?,?)")
  st:bind(id,v[1],v[2],v[3],r.document:getPageCount()):step();st:close()
 end
 local other=conn:prepare("INSERT INTO book(title,authors,md5,last_open,pages,total_read_time,total_read_pages) VALUES(?,?,?,?,?,?,?)")
 other:bind("另一本文本","其他作者","not-this-book",os.time(),100,9999,80):step();other:close()
 local otherid=tonumber(conn:rowexec("SELECT last_insert_rowid()"))
 conn:exec("INSERT INTO page_stat_data(id_book,page,start_time,duration,total_pages) VALUES("..otherid..",1,"..(day+9000)..",9999,100)");conn:close()
 check("Book statistics use the actual current document and never include another book's time",function()
  app:showReaderTopbar();tapTop("reader_statistics");local panel=app.book_statistics;local model=panel.data
  assert(not model.unavailable and model.file==r.document.file and model.seconds==600 and model.today_seconds==600)
  assert(model.read_pages==3 and model.days==1 and model.sessions==2 and model.average==300)
  assert(not app.reader_topbar and not app.reader_panel and not app.navigation)
  shot("book-statistics-native-036")
 end)
 check("Opening statistics flushes native pending page turns once and leaves the book position intact",function()
  local before=r.document:getXPointer();native.page_stat[5]={{day+12000,60}}
  app:showBookStatistics();assert(app.book_statistics.data.seconds==660 and app.book_statistics.data.sessions==3)
  app:showBookStatistics();assert(app.book_statistics.data.seconds==660 and r.document:getXPointer()==before)
  local c=SQ3.open(db,"ro");assert(tonumber(c:rowexec("SELECT sum(duration) FROM page_stat_data WHERE id_book="..id))==660);c:close()
 end)
 check("Statistics scrolls and PagePress without moving the underlying book",function()
  UI:forceRePaint();local panel=app.book_statistics;assert(panel.scroll_max>0)
  local before=r.document:getXPointer();panel:onBookStatsSwipe(nil,{direction="north",pos={x=S(100),y=panel.list_area.y+S(20)}})
  assert(panel.scroll>0);panel:onKeyPress(Key:new("LPgFwd",{}));assert(r.document:getXPointer()==before)
  shot("book-statistics-scrolled-036");panel:onKeyPress(Key:new("Back",{}));assert(not app.book_statistics)
 end)
 check("Disabled statistics retain historic data and a missing database is not created",function()
  local enabled=native.settings.is_enabled;native.settings.is_enabled=false
  local result=Stats.model(app);assert(result.paused and result.seconds==660)
  assert(os.rename(db,db..".hidden036"));result=Stats.model(app)
  assert(not result.seconds and not require("libs/libkoreader-lfs").attributes(db,"mode"))
  assert(os.rename(db..".hidden036",db));native.settings.is_enabled=enabled
 end)
 check("A statistics identity mismatch cannot display another document's figures",function()
  local saved=native.id_curr_book;native.id_curr_book=otherid
  local enabled=native.settings.is_enabled;native.settings.is_enabled=false
  local model=Stats.model(app);assert(not model.seconds)
  native.id_curr_book=saved;native.settings.is_enabled=enabled
 end)
 check("Statistics and other transient panels remain mutually exclusive during repeated transitions",function()
  local before=r.document:getXPointer()
  for _=1,10 do
   app:showBookStatistics();app:showControls();app:showNavigation("toc");app:showReader("font");app:showReaderTopbar()
   local n=0;for _,win in ipairs(UI._window_stack) do if win.widget._eink_overlay then n=n+1 end end
   assert(n==1 and not app.book_statistics and not app.controls and not app.navigation and not app.reader_panel)
  end
  assert(r.document:getXPointer()==before);app:close()
 end)
 close();r,p=open("sample.pdf");app=p.app
 check("PDF uses the same current-book statistics sheet and keeps the three Aa entries",function()
  app:showBookStatistics();UI:forceRePaint();assert(app.book_statistics.data.file==r.document.file and app.book_statistics.data.pages==r.document:getPageCount())
  shot("book-statistics-pdf-036");app:showReader("menu");UI:forceRePaint()
  assert(Equal(app.reader_panel.toolbar_buttons,{"主题","字体","排版"}) and not app.book_statistics)
 end)
 close()
elseif mode=="regression037" then
 local P=require("einkfrontend/paint");local S=P.s;local rc=require("readcollection");local SQ=require("lua-ljsqlite3/init")
 FM:showFiles(dir);local app=FM.instance.einkfrontend.app
 app:open("library");app:scanLibrary(dir)
 for _=1,300 do UI:shiftScheduledTasksBy(-require("ui/time").s(.02));UI:_checkTasks();if not app.library.job then break end end
 local function hit(widget,id)
  UI:forceRePaint();for _,h in ipairs(widget.hits) do if h.id==id then return h end end;error("Missing hit "..id)
 end
 local function row(title)
  for _,v in ipairs(app.screen.model.rows) do if v.title==title then return v end end;error("Missing row "..title)
 end
 local function read(path) local f=assert(io.open(path,"rb"));local data=f:read("*a");f:close();return data end
 local file=dir.."/A.epub";local collection_path=DS:getSettingsDir().."/collection.lua"
 check("Only the Collections overflow offers management and opens an actual manager",function()
  for _,tab in ipairs({"books","authors","series","collections"}) do
   app:selectLibraryTab(tab);app:showLibraryMenu("more");UI:forceRePaint();local found
   for _,v in ipairs(app.library_popup.current_rows) do if v.text=="管理收藏" then found=v end end
   assert((found~=nil)==(tab=="collections"))
   if found then found.callback();assert(app.stack[#app.stack].id=="collection_manager" and app.screen.model.settings)
   else app.library_popup:close() end
  end
 end)
 check("To Be Read is displayed in Chinese without renaming or changing native membership",function()
  if not rc.coll["To Be Read"] then app.library:createCollection("To Be Read") end
  app.library:setCollection(file,"To Be Read",true)
  app:selectLibraryTab("collections");local title=row("待读");title.callback()
  assert(app.screen.model.title=="待读" and app.stack[#app.stack].param.collection=="To Be Read")
  assert(rc.coll["To Be Read"][file] and not rc.coll["待读"])
  app:go("book_collections",app.library.books[1]);local labels={}
  for _,v in ipairs(app.screen.model.rows) do labels[#labels+1]=v.title end
  assert(table.concat(labels):find("待读",1,true) and not table.concat(labels):find("To Be Read",1,true))
 end)
 check("Collection members can be added and removed through the scrolling manager and saved natively",function()
  app.library:createCollection("管理测试");app:go("collection_members","管理测试")
  local target=app.screen.model.rows[1];local chosen=app.library:collectionBooks("管理测试")[1].file
  target.callback();assert(rc:isFileInCollection(chosen,"管理测试"))
  local disk=require("luasettings"):open(collection_path):readSetting("管理测试");assert(#disk==1 and disk[1].file==chosen)
  app.screen.model.rows[1].callback();assert(not rc:isFileInCollection(chosen,"管理测试"))
  assert(#require("luasettings"):open(collection_path):readSetting("管理测试")==0)
  app.library:setCollection(file,"管理测试",true)
  shot("collection-members-037")
 end)
 check("Existing members outside the indexed library remain available for removal",function()
  local outside=DS:getDataDir().."/outside.epub";local f=assert(io.open(outside,"wb"));f:write(read(file));f:close()
  app.library:setCollection(outside,"管理测试",true);local found
  for _,book in ipairs(app.library:collectionBooks("管理测试")) do if book.file==outside then found=book end end
  assert(found);app.library:setCollection(outside,"管理测试",false);assert(not rc:isFileInCollection(outside,"管理测试"))
 end)
 check("Rename preserves native settings membership defaults and saved collection destinations",function()
  rc.coll_settings["管理测试"].default=true;rc.coll_default="管理测试";rc:write()
  app.library.settings:saveSetting("return_stack",{{id="books",param={collection="管理测试"}}})
  app:go("collection_manage","管理测试");local prompt=app.adapter.promptText
  app.browser.tabs.collections.stack={{id="collections"},{id="books",param={collection="管理测试"},page=2}}
  app.adapter.promptText=function(_,title,initial,callback) assert(title=="重命名收藏" and initial=="管理测试");callback("已重命名") end
  row("重命名").callback();app.adapter.promptText=prompt
  assert(not rc.coll["管理测试"] and rc.coll["已重命名"][file] and rc.coll_default=="已重命名" and rc.coll_settings["已重命名"].default)
  assert(app.stack[#app.stack].param=="已重命名" and app.browser.tabs.collections.stack[2].param.collection=="已重命名")
  assert(app.library.settings:readSetting("return_stack")[1].param.collection=="已重命名")
  shot("collection-manager-037")
 end)
 check("Invalid duplicate names and silent save failures preserve both disk and live collections",function()
  local before=read(collection_path);assert(not pcall(app.library.editCollection,app.library,"已重命名","To Be Read"))
  assert(not pcall(app.library.editCollection,app.library,"已重命名","   "))
  local write=rc.write;rc.write=function() end
  assert(not pcall(app.library.editCollection,app.library,"已重命名","不能保存"));rc.write=write
  assert(read(collection_path)==before and rc.coll["已重命名"][file] and not rc.coll["不能保存"] and rc.coll_default=="已重命名")
 end)
 check("Deleting a collection requires confirmation and preserves files while default Favorites stay protected",function()
  app.library:createCollection("将删除");app.library:setCollection(file,"将删除",true)
  app:go("collection_manage","将删除");local confirm=app.confirm;local pending
  app.confirm=function(_,text,callback) assert(text:find("书籍文件会保留",1,true));pending=callback end
  row("删除收藏").callback();assert(pending and rc.coll["将删除"])
  pending();app.confirm=confirm;assert(not rc.coll["将删除"] and read(file)~="" and app.stack[#app.stack].id=="collection_manager")
  assert(not require("luasettings"):open(collection_path):has("将删除"))
  assert(not pcall(app.library.editCollection,app.library,rc.default_collection_name,nil))
  assert(not pcall(app.library.editCollection,app.library,rc.default_collection_name,"改默认"))
  app:go("collection_manage",rc.default_collection_name)
  for _,v in ipairs(app.screen.model.rows) do assert(v.title~="删除收藏" and v.title~="重命名") end
 end)
 check("Home refresh immediately reloads changed native statistics without resetting scroll or browser state",function()
  local db=DS:getSettingsDir().."/statistics.sqlite3";local c=SQ.open(db)
  c:exec("UPDATE book SET total_read_time=1200");c:close()
  app:open("home");local before=app.screen.model.home_data.total_seconds;app.stack[1].scroll_y=S(50);app:render();UI:forceRePaint()
  local scroll=app.stack[1].scroll_y;local tabs=Copy(app.browser.tabs)
  c=SQ.open(db);c:exec("UPDATE book SET total_read_time=total_read_time+120");c:close()
  local old=app.screen.model.home_data;hit(app.screen,"home_statistics_refresh").callback()
  assert(app.screen.model.home_data~=old and app.screen.model.home_data.total_seconds>before)
  assert(app.stack[1].scroll_y==scroll and Equal(app.browser.tabs,tabs));shot("home-refresh-037")
 end)
 FM.instance:onClose();local r,p=open("navigation.epub");app=p.app
 check("One bookmark action provides both bookmark and annotation tabs without a second toolbar icon",function()
  app:showReaderTopbar();local bar=app.reader_topbar
  local h=hit(bar,"reader_ShowBookmark");for _,v in ipairs(bar.hits) do assert(v.id~="reader_annotations") end
  h.callback();assert(app.navigation and app.navigation.view=="bookmarks")
  hit(app.navigation,"navigation_tab_annotations").callback();assert(app.navigation.view=="annotations")
  hit(app.navigation,"navigation_tab_bookmarks").callback();assert(app.navigation.view=="bookmarks")
  app:showReaderTopbar();shot("reader-toolbar-037");app:close()
 end)
 check("Book refresh flushes pending native reading records exactly once without moving the document",function()
  app:showBookStatistics();local panel=app.book_statistics;local native=r.statistics
  local before=panel.data.seconds or 0;local xp=r.document:getXPointer()
  native.page_stat[7]={{os.time()-300,60}}
  hit(panel,"book_statistics_refresh").callback();assert(panel.data.seconds==before+60)
  hit(panel,"book_statistics_refresh").callback();assert(panel.data.seconds==before+60 and r.document:getXPointer()==xp)
  assert(app.book_statistics==panel and not app.reader_panel and not app.navigation);shot("book-refresh-037")
 end)
 check("Home and book statistics no longer render the thirty-minute explanatory notice",function()
  local label=P.label;local rendered={}
  P.label=function(bb,text,...) rendered[#rendered+1]=tostring(text);return label(bb,text,...) end
  UI:setDirty("all","ui");UI:forceRePaint()
  app:close();app:open("home");UI:forceRePaint();P.label=label
  local text=table.concat(rendered,"\n");assert(not text:find("30分钟",1,true) and not text:find("30 分钟",1,true))
  app:close()
 end)
 close()
elseif mode=="regression037_restart" then
 FM:showFiles(dir);local app=FM.instance.einkfrontend.app;local rc=require("readcollection")
 check("Collection rename default and membership changes survive a fresh KOReader process",function()
  assert(rc.coll["已重命名"] and rc.coll["已重命名"][dir.."/A.epub"] and rc.coll_default=="已重命名")
  assert(not rc.coll["管理测试"] and not rc.coll["将删除"] and not rc.coll["不能保存"])
  assert(rc.coll["To Be Read"][dir.."/A.epub"] and app.library:collectionLabel("To Be Read")=="待读")
 end)
 FM.instance:onClose()
elseif mode=="notice_transitions" then
 local N=require("einkfrontend/notices");local Info=require("ui/widget/infomessage");local P=require("einkfrontend/paint")
 local function ticks() for _=1,30 do UI:shiftScheduledTasksBy(-require("ui/time").s(.02));UI:_checkTasks() end end
 FM:showFiles(dir);local fm=FM.instance;local app=fm.einkfrontend.app;app:open("library")
 local original=Info.init;local native_original=N.info_original
 local captured={};local show=UI.show;local stage="library-pdf"
 UI.show=function(self,widget,...)
  if widget.movable and widget.timeout==0 then
   captured[#captured+1]={widget=widget,text=widget.text,styled=widget._eink_notice,stage=stage,
    no_host=not FM.instance and not Reader.instance,bold=widget.movable[1][1][3].bold,invisible=widget.invisible}
  end
  local result=show(self,widget,...)
  if widget.movable and widget.timeout==0 and not widget.invisible then
   UI:forceRePaint();Device.screen:shot(root.."/test-results-030/actual-opening-"..stage.."-"..variant..".png")
  end
  return result
 end
 check("Actual Library to PDF opening notice is styled during the host ownership gap",function()
  app:openLibraryBook({file=dir.."/sample.pdf"})
  local item=assert(captured[#captured]);local widget=item.widget
  assert(item.stage==stage and item.styled and item.no_host and item.bold and item.text:find("sample.pdf",1,true))
  assert(widget.timeout==0 and not widget.invisible and widget.face.orig_size==P.style.label)
  assert(widget.movable[1].radius==0 and widget.movable[1].bordersize>=2 and widget._timeout_func)
  ticks();assert(Reader.instance and Reader.instance.document.file==dir.."/sample.pdf")
  assert(not next(N.handoffs) and N.owners[Reader.instance.einkfrontend] and Info.init==N.info_wrapper)
 end)
 check("Actual reader switch keeps native opening text lifecycle and style until the next reader owns it",function()
  stage="reader-epub";Reader.instance:switchDocument(dir.."/A.epub")
  local item=assert(captured[#captured]);assert(item.stage==stage and item.styled and item.no_host and item.bold)
  assert(item.text:find("A.epub",1,true));ticks()
  assert(Reader.instance.document.file==dir.."/A.epub" and not next(N.handoffs))
 end)
 check("Seamless native reload preserves the invisible opening notice instead of flashing it",function()
  stage="seamless";Reader.instance:reloadDocument(nil,true)
  local item=assert(captured[#captured]);assert(item.stage==stage and item.styled and item.invisible)
  ticks();assert(Reader.instance.document.file==dir.."/A.epub" and not next(N.handoffs))
 end)
 check("An abandoned reader switch releases all transition ownership and restores native methods",function()
  Reader.instance:switchDocument(dir.."/missing-notice-test.epub");assert(not Reader.instance and next(N.handoffs))
  ticks();assert(not next(N.handoffs) and not next(N.owners) and Info.init==native_original)
 end)
 UI.show=show
 -- Close the native missing-file warning without touching any document.
 local notices={};for _,win in ipairs(UI._window_stack) do if win.widget.text then notices[#notices+1]=win.widget end end
 for _,widget in ipairs(notices) do UI:close(widget) end
 FM:showFiles(dir);fm=FM.instance;local owner=fm.einkfrontend;app=owner.app
 check("Explicit disable cancels a pending handoff immediately and cannot reinstall styling later",function()
  local token=assert(N.handoff(owner));N.detach(owner,true)
  assert(not next(N.handoffs) and Info.init==native_original)
  ticks();assert(Info.init==native_original and not N.owners[token]);N.install(owner)
 end)
 check("Fixed-height reports and explicit fonts retain their requested layout",function()
  local font=require("ui/font"):getFace("infont",14)
  local widget=Info:new{text="自定义诊断报告",height=P.s(120),face=font}
  assert(not widget._eink_notice and widget.face==font);widget:free()
 end)
 check("The native delayed notification callback is still invoked exactly once after style handoff",function()
  local done=0;local widget=Info:new{text="打开完成",timeout=.1,show_delay=.02,dismiss_callback=function() done=done+1 end}
  assert(widget._eink_notice and widget.movable[1][1][3].bold)
  UI:show(widget);ticks();assert(done==1 and not widget._timeout_func and not widget._delayed_show_action)
 end)
 fm:onClose();ticks();assert(Info.init==native_original and not next(N.owners) and not next(N.handoffs))
elseif mode=="regression035" then
 local P=require("einkfrontend/paint");local S=P.s;local BB=P.BB
 local function ticks() for _=1,30 do UI:shiftScheduledTasksBy(-require("ui/time").s(.02));UI:_checkTasks() end end
 local function opened(file)
  local r=assert(Reader.instance);assert(r.document.file==file);return r,r.einkfrontend.app
 end
 local r,p=open("A.epub");close()
 FM:showFiles(dir);local app=FM.instance.einkfrontend.app;app:open("library");app:scanLibrary(dir);ticks();app:open("home")
 local file=dir.."/A.epub";local cache=assert(app.library:cover(file));local raw=BB.tostring(cache)
 local function pixelCrop(x,y,w,h)
  local copy=BB.new(w,h,Device.screen.bb:getType());copy:blitFrom(Device.screen.bb,0,0,x,y,w,h)
  local data=BB.tostring(copy);copy:free();return data
 end
 local function homePixels()
  UI:forceRePaint();return pixelCrop(S(20),S(118),math.min(S(126),Device.screen:getWidth()*.25),S(184))
 end
 local function libraryPixels()
  UI:forceRePaint();local page=app.screen;local i
  for index,row in ipairs(page.model.rows) do if row.book and row.book.file==file then i=index end end
  assert(i);local start=(page.model.page-1)*page.capacity+1;local cw=math.floor(page.dimen.w/page.grid_columns)
  local ch=page.grid_cell_h-S(76);local width=math.min(cw-2*S(14),math.floor(ch*.68))
  return pixelCrop(((i-start)%page.grid_columns)*cw+math.floor((cw-width)/2),page.header_h+page.info_h+math.floor((i-start)/page.grid_columns)*page.grid_cell_h,width,ch)
 end
 local first
 check("Home renders a real cached cover repeatedly without freeing or altering the shared source",function()
  local detail=app.library.settings:readSetting("last_reading_detail");assert(detail and detail.file==file)
  first=homePixels();assert(cache:getAllocated()==1 and BB.tostring(cache)==raw)
  for _=1,30 do UI:setDirty("all","ui");assert(homePixels()==first);assert(cache:getAllocated()==1 and BB.tostring(cache)==raw) end
  shot("home-cover-stable-035")
 end)
 check("Forty Home Library cycles preserve both page images and the shared cached cover bytes",function()
  app:open("library");app:selectLibraryTab("books");app.library_layout="grid";app.browser.filter={statuses={},query=""};app:render()
  local library=libraryPixels()
  for _=1,40 do
   app:open("home");assert(homePixels()==first);assert(cache:getAllocated()==1 and BB.tostring(cache)==raw)
   app:open("library");assert(libraryPixels()==library);assert(app.library:cover(file)==cache and cache:getAllocated()==1 and BB.tostring(cache)==raw)
  end
  shot("library-cover-after-cycles-035")
 end)
 check("Only the cover cache releases originals during eviction and closed caches reload cleanly",function()
  local lfs=require("libs/libkoreader-lfs");local folder=dir.."/cover-cycle";lfs.mkdir(folder)
  local input=assert(io.open(file,"rb"));local bytes=input:read("*a");input:close()
  for i=1,13 do local target=folder.."/copy"..i..".epub";local out=assert(io.open(target,"wb"));out:write(bytes);out:close();assert(app.library:cover(target)) end
  assert(cache:getAllocated()==0);app.library:clearCovers();assert(#app.library.cover_order==0)
  local loaded=assert(app.library:cover(file));assert(loaded:getAllocated()==1 and BB.tostring(loaded)==raw)
  app:open("home");assert(homePixels()==first);assert(loaded:getAllocated()==1)
 end)
 check("Home book opens and the top return action restores Home and its saved scroll position",function()
  UI:forceRePaint();local page=app.screen;page:scrollBy(S(80));local scroll=page.scroll_y
  app:openRecentBook(file);ticks();r,app=opened(file)
  assert(app:readingReturnLabel()=="主页");local origin=app:readingOrigin();assert(origin.shell=="home" and origin.home_route.scroll_y==scroll)
  app:showReaderTopbar();app.reader_topbar:action("library");ticks();app=FM.instance.einkfrontend.app
  assert(app.screen.model.home and app.screen.scroll_y==scroll and not Reader.instance);shot("home-return-origin-035")
 end)
 check("Nested library source restores category layout and second-page position after reading",function()
  app:open("library");app:scanLibrary(dir);ticks();app:selectLibraryTab("authors");app:go("books",{field="authors",value="作者甲"})
  app.library_layout="list";app:render();app.screen:turn(1);UI:forceRePaint();assert(app.screen.model.page==2)
  local page=app.screen;local target=page.model.rows[page.capacity+1].book
  app:openLibraryBook(target);ticks();r,app=opened(target.file);assert(app:readingReturnLabel()=="书库")
  app:showControls();UI:forceRePaint();local hit
  for _,h in ipairs(app.controls.hits) do if h.id=="return_library" then hit=h end end;assert(not hit);r:onHome();ticks()
  app=FM.instance.einkfrontend.app;assert(app.screen.model.library and app.screen.model.page==2 and app.library_layout=="list" and app.stack[#app.stack].param.value=="作者甲")
 end)
 check("Native reader Home return also restores a matching Home source with auto startup disabled",function()
  app:open("home");app:openRecentBook(file);ticks();r,app=opened(file);r:onHome();ticks()
  app=FM.instance.einkfrontend.app;assert(app.screen and app.screen.model.home and not Reader.instance)
 end)
 check("An unrelated directly opened book does not inherit a previous book Home destination",function()
  app:close();FM.instance:onClose();r,p=open("B.epub");app=p.app
  assert(app:readingReturnLabel()=="书库");app:returnToOrigin();ticks();app=FM.instance.einkfrontend.app;assert(app.screen.model.library)
 end)
 check("Home origin is serialized with book identity for a fresh reader process",function()
  app:open("home");UI:forceRePaint();app:rememberReadingOrigin(file)
  local disk=require("luasettings"):open(app.library.settings.file):readSetting("return_context")
  assert(disk.file==file and disk.shell=="home" and disk.home_route.id=="home")
  app:close();FM.instance:onClose()
 end)
elseif mode=="regression035_restart" then
 local r,p=open("A.epub");local app=p.app
 check("A fresh process reads the saved Home provenance and restores it through native return",function()
  assert(app:readingReturnLabel()=="主页");r:onHome()
  for _=1,30 do UI:shiftScheduledTasksBy(-require("ui/time").s(.02));UI:_checkTasks() end
  app=FM.instance.einkfrontend.app;assert(app.screen and app.screen.model.home)
  shot("home-origin-restart-035");FM.instance:onClose()
 end)
elseif mode=="pdf" then
 local r,p=open("sample.pdf");local app=p.app
 check("PDF menu capture preserves every static action and filters unsupported typography",function()
  audit(app);r.config:onShowConfigMenu();UI:forceRePaint();assert(app.reader_panel.tab=="pdf");assert(not app.typography:available());shot("pdf-panel-integrated")
 end)
 check("Advanced PDF configuration opens only in an explicit compatibility session",function()
  app:openNativeConfig();assert(r.config.config_dialog and p.gate.native_session);r.config:onCloseConfigMenu();assert(not p.gate.native_session)
  r.config:onShowConfigMenu();assert(app.reader_panel and not r.config.config_dialog);app:close()
 end)
 close()
end
local f=assert(io.open(root.."/test-results-030/"..mode.."-"..variant..".json","w"));f:write(require("rapidjson").encode(report));f:close();print("COMPLETE "..mode)
