require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage')
G_reader_settings=require('luasettings'):open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,full_takeover=true})
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local Event=require('ui/event');local Key=require('device/key')
local FM=require('apps/filemanager/filemanager');local Reader=require('apps/reader/readerui')
local P=require('einkfrontend/paint');local S=P.s
local root=assert(os.getenv('EINK_PROJECT'));local books=assert(os.getenv('EINK_030_BOOKS'))
local variant=assert(os.getenv('EINK_VARIANT'));local out=root..'/test-results-053/'
local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function shot(name)
 UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(out..file);report.frames[#report.frames+1]=file
end
local function find(widget,id)
 UI:forceRePaint();for _,h in ipairs(widget.hits or {}) do if h.id==id then return h end end
end
local function tap(menu,id)
 local h=assert(find(menu,id));menu:onSettingsPopupTap(nil,{pos={x=h.x+h.w/2,y=h.y+h.h/2}})
end
local function button(w,text)
 if type(w)~='table' then return end
 if w.text==text and w.onTapSelectButton then return w end
 for _,c in ipairs(w) do local b=button(c,text);if b then return b end end
end
FM:showFiles(books);local app=FM.instance.einkfrontend.app
for _=1,30 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end
local close={};for _,entry in ipairs(UI._window_stack) do if entry.widget.text then close[#close+1]=entry.widget end end
for _,w in ipairs(close) do UI:close(w) end
app:open('settings');local page=app.screen
check('Only the settings root has More; subpages keep Back Close and optional Help',function()
 assert(find(page,'settings_more') and not find(page,'settings_back'))
 local routes={{'catalog_category','reading'},{'catalog_category','maintenance'},{'frontend'},{'about'},
  {'clock_settings'},{'clock_zones'},{'clock_zone_list','Shanghai'},{'transfer_settings'}}
 for _,route in ipairs(routes) do
  app:open(unpack(route));assert(not find(page,'settings_more') and not page.header_ink.more)
  assert(find(page,'settings_back') and find(page,'settings_close') and app:showSettingsMore()==nil)
 end
 app:open('settings');assert(find(page,'settings_more'))
end)
check('More opens an anchored two-row popup without replacing the settings page',function()
 local route=app.stack[#app.stack];local hit=assert(find(page,'settings_more'));hit.callback()
 local popup=assert(app.settings_popup);UI:forceRePaint()
 assert(app.screen==page and app.stack[#app.stack]==route and page.model.title=='设置')
 assert(#popup.rows==2 and popup.rows[1].text=='搜索' and popup.rows[2].text=='重启 KOReader')
 assert(not popup.buttons and popup.box.h==2*S(52) and popup.box.w<page.dimen.w/2)
 assert(popup.box.y==hit.y+hit.h and popup.box.x+popup.box.w==hit.x+hit.w)
 shot('settings-more-popup');popup:close()
end)
check('An outside tap closes without opening the underlying row and restores identical pixels',function()
 shot('settings-before');local route=app.stack[#app.stack];local scroll=page.scroll_y
 local popup=app:showSettingsMore();UI:forceRePaint()
 popup:onSettingsPopupTap(nil,{pos={x=S(30),y=page.header_h+S(36)}})
 assert(not app.settings_popup and app.stack[#app.stack]==route and page.scroll_y==scroll)
 shot('settings-after')
 local function bytes(name) local f=assert(io.open(out..name..'-'..variant..'.png','rb'));local b=f:read('*a');f:close();return b end
 assert(bytes('settings-before')==bytes('settings-after'))
end)
check('Tapping More again dismisses the popup without reopening or activating a shortcut',function()
 local popup=app:showSettingsMore();local h=assert(find(page,'settings_more'))
 popup:onSettingsPopupTap(nil,{pos={x=h.x+h.w/2,y=h.y+h.h/2}})
 assert(not app.settings_popup and page.model.route.id=='settings')
end)
check('Search closes the popup and searches all settings',function()
 local prompt=app.adapter.promptText;local called=false
 app.adapter.promptText=function(_,title,initial,accept)
  assert(title=='搜索全部设置' and initial=='' and not app.settings_popup);called=true;accept('传书')
 end
 tap(app:showSettingsMore(),'settings_popup_search');app.adapter.promptText=prompt
 assert(called and page.model.route.id=='catalog_search' and #page.model.rows>0 and not find(page,'settings_more'))
 local found=false;for _,row in ipairs(page.model.rows) do if row.title=='传书与书库' then found=true end end;assert(found)
 shot('settings-search-results');app:open('settings')
end)
check('Restart asks for confirmation; cancel does nothing; accept flushes before restart',function()
 local flush,restart=UI.flushSettings,UI.restartKOReader;local actions={}
 UI.flushSettings=function() actions[#actions+1]='flush' end
 UI.restartKOReader=function() actions[#actions+1]='restart' end
 for _,accept in ipairs({false,true}) do
  tap(app:showSettingsMore(),'settings_popup_restart');UI:forceRePaint()
  local confirm=UI._window_stack[#UI._window_stack].widget
  assert(not app.settings_popup and confirm.text:find('保存设置并重启',1,true) and #actions==0)
  local target=assert(button(confirm,accept and confirm.ok_text or confirm.cancel_text));target:onTapSelectButton()
  assert(not UI:isWidgetShown(confirm) and page.model.route.id=='settings')
 end
 assert(#actions==2 and actions[1]=='flush' and actions[2]=='restart')
 UI.flushSettings=flush;UI.restartKOReader=restart
end)
check('Repeated opens deduplicate; Back closes; rotation reaches the underlying page',function()
 local popup=app:showSettingsMore();assert(app:showSettingsMore()==popup)
 local count=0;for _,entry in ipairs(UI._window_stack) do if entry.widget._eink_overlay=='settings_popup' then count=count+1 end end;assert(count==1)
 popup:onKeyPress(Key:new('Back',{}));assert(not app.settings_popup)
 popup=app:showSettingsMore();local dimensions=page.onSetDimensions;local reached=0
 page.onSetDimensions=function(self,...) reached=reached+1;return dimensions(self,...) end
 UI:broadcastEvent(Event:new('SetDimensions',Device.screen:getSize()));page.onSetDimensions=dimensions
 assert(not app.settings_popup and reached==1)
end)
check('Navigation suspend and close discard the menu and clear its active button',function()
 app:showSettingsMore();app:go('catalog_category','device');assert(not app.settings_popup and not find(page,'settings_more'))
 app:open('settings');local popup=app:showSettingsMore();popup:onSuspend();assert(not app.settings_popup)
 app:showSettingsMore();app:close();assert(not app.settings_popup and not app.screen)
end)
check('Library Home and reading panels do not acquire the settings More menu',function()
 for _,route in ipairs({'library','home'}) do app:open(route);assert(not find(app.screen,'settings_more') and not app:showSettingsMore()) end
 Reader:doShowReader(books..'/navigation.epub');app=assert(Reader.instance).einkfrontend.app
 app:showReader('font');assert(not app.settings_popup and app:showSettingsMore()==nil)
 app:open('settings');assert(find(app.screen,'settings_more'));local popup=app:showSettingsMore();UI:forceRePaint()
 assert(popup.box.h==2*S(52));shot('reader-settings-more-popup')
 app:close();Reader.instance:onClose()
end)
if FM.instance then FM.instance:onClose() end
local file=assert(io.open(out..'settings-popup-'..variant..'.json','w'));file:write(require('json').encode(report));file:close()
print('COMPLETE '..variant)
