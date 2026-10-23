require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');G_reader_settings=require('luasettings'):open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,full_takeover=true})
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true});G_reader_settings:saveSetting('keyboard_layout','zh_CN')
G_reader_settings:saveSetting('keyboard_layouts',{'zh_CN','en'});G_reader_settings:saveSetting('virtual_keyboard_enabled',true)
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local FM=require('apps/filemanager/filemanager')
local root=assert(os.getenv('EINK_PROJECT'));local out=assert(os.getenv('EINK_TEST_OUTPUT'))..'/';local variant=os.getenv('EINK_VARIANT')
local report={tests={},variant=variant,device='NOT_RUN'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function ticks() for _=1,20 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end end
FM:showFiles(assert(os.getenv('EINK_030_BOOKS')));local app=FM.instance.einkfrontend.app;ticks();app:open('input_method')
local IME=require('einkfrontend/pinyin');local Stock=require('einkfrontend/stockscreensaver')
local tr= require('gettext');local lfs=require('libs/libkoreader-lfs')
local stockdir=DS:getDataDir()..'/stock';local customdir=DS:getDataDir()..'/custom';lfs.mkdir(stockdir);lfs.mkdir(customdir)
Device.screen.bb:writePNG(stockdir..'/stock.png');Device.screen.bb:writePNG(customdir..'/custom.png')
local originalKindle,originalSupport,paths=Device.isKindle,Device.supportsScreensaver,Stock.paths
local options={screensaver_show_message=true,screensaver_img_background='black',screensaver_stretch_images=true,screensaver_rotate_auto_for_best_fit=false,screensaver_cycle_images_alphabetically=true}
local wallpaper,stock,random,cover
local function loadmenu()
 app.native:refresh();local node=assert(app.native.catalog.entries.screensaver).node
 for _,item in ipairs(node.sub_item_table) do if item.text==tr('Wallpaper') then wallpaper=item end end
 stock,random,cover=nil,nil,nil
 for _,item in ipairs(wallpaper.sub_item_table) do
  if item.id=='eink_stock_wallpaper' then stock=item
  elseif item.text==tr('Show random image from folder on sleep screen') then random=item
  elseif item.text==tr('Show book cover on sleep screen') then cover=item end
 end
 return node
end
local function preserved() for key,value in pairs(options) do assert(G_reader_settings:readSetting(key)==value,key) end end
local function select(item) assert(app.native:select(item));UI:forceRePaint() end
local function openwallpaper()
 local node=loadmenu();app:open('catalog_category','device');app.native:open({node},'屏保');select(node);select(wallpaper)
end
check('Non-Kindle menus have no stock option; device category has no separate stock page',function()
 Device.isKindle=function() return false end;loadmenu();assert(not stock)
 for _,c in ipairs(app.native.categories) do
  app:open('catalog_category',c[1]);for _,row in ipairs(app.screen.model.rows) do assert(row.title~='Kindle 原生屏保' and row.title~='使用 Kindle 原生屏保') end
 end
end)
check('Kindle option is scoped to Wallpaper and refresh does not duplicate or mutate native providers',function()
 Device.isKindle=function() return true end;Device.supportsScreensaver=function() return true end;Stock.paths={stockdir}
 for _=1,3 do
  loadmenu();assert(stock and random and cover)
  local count=0;for _,item in ipairs(wallpaper.sub_item_table) do if item.id=='eink_stock_wallpaper' then count=count+1 end end;assert(count==1)
  Stock.extendMenu({sub_item_table={wallpaper}});count=0;for _,item in ipairs(wallpaper.sub_item_table) do if item.id=='eink_stock_wallpaper' then count=count+1 end end;assert(count==1)
 end
 for _,item in ipairs(require('ui/elements/screensaver_menu')) do
  for _,child in ipairs(item.sub_item_table or {}) do assert(child.id~='eink_stock_wallpaper') end
 end
end)
check('Native menu selection enables random stock images and preserves all display preferences',function()
 G_reader_settings:saveSetting('screensaver_type','random_image');G_reader_settings:saveSetting('screensaver_dir',customdir)
 for key,value in pairs(options) do G_reader_settings:saveSetting(key,value) end
 openwallpaper();select(stock);assert(Stock.active(G_reader_settings));assert(not random.checked_func());preserved()
 assert(G_reader_settings:readSetting('screensaver_dir')==stockdir)
 local screensaver=require('ui/screensaver');screensaver:setup();assert(screensaver.screensaver_type=='random_image' and screensaver.image_file==stockdir..'/stock.png' and screensaver.show_message);screensaver:cleanup()
 Device.screen.bb:writePNG(out..'wallpaper-'..variant..'.png')
end)
check('Choosing custom random images restores prior folder and clears stock selection',function()
 select(random);assert(not Stock.active(G_reader_settings) and random.checked_func())
 assert(G_reader_settings:readSetting('screensaver_dir')==customdir and not G_reader_settings:has('eink_stock_screensaver'));preserved()
end)
check('Choosing cover exits stock mode; a second activation restores latest custom preferences',function()
 select(stock);select(cover);assert(G_reader_settings:readSetting('screensaver_type')=='cover' and not Stock.active(G_reader_settings))
 assert(G_reader_settings:readSetting('screensaver_dir')==customdir);preserved()
 select(stock);G_reader_settings:saveSetting('screensaver_dir',customdir)
 assert(not Stock.active(G_reader_settings) and random.checked_func());select(stock);select(random)
 assert(G_reader_settings:readSetting('screensaver_type')=='random_image' and G_reader_settings:readSetting('screensaver_dir')==customdir);preserved()
end)
check('Missing image directory reports failure without changing wallpaper or closing its page',function()
 local before=require('json').encode(G_reader_settings:readSetting('eink_stock_screensaver'))
 Stock.paths={stockdir..'/missing'};select(stock);assert(not Stock.active(G_reader_settings))
 assert(G_reader_settings:readSetting('screensaver_dir')==customdir and before==require('json').encode(G_reader_settings:readSetting('eink_stock_screensaver')))
 assert(app.native.host.item_table==wallpaper.sub_item_table);preserved()
 local dialog=UI._window_stack[#UI._window_stack].widget;assert(dialog.text:find('未找到',1,true));UI:close(dialog);Stock.paths={stockdir}
end)
check('Legacy independent screen settings migrate without retaining hidden display overrides',function()
 local backup={screensaver_type={present=true,value='cover'},screensaver_dir={present=true,value=customdir},screensaver_show_message={present=true,value=true},screensaver_img_background={present=true,value='black'},screensaver_stretch_images={present=true,value=true}}
 local applied={screensaver_type='random_image',screensaver_dir=stockdir,screensaver_show_message=false,screensaver_img_background='white',screensaver_stretch_images=false}
 for key,value in pairs(applied) do G_reader_settings:saveSetting(key,value) end
 G_reader_settings:saveSetting('screensaver_stretch_images',true) -- user edited this after activation
 G_reader_settings:saveSetting('eink_stock_screensaver',{version=1,path=stockdir,backup=backup,applied=applied})
 assert(stock.checked_func());select(stock);preserved();local state=G_reader_settings:readSetting('eink_stock_screensaver');assert(state.applied.screensaver_show_message==nil)
 select(cover);assert(G_reader_settings:readSetting('screensaver_type')=='cover' and G_reader_settings:readSetting('screensaver_dir')==customdir);preserved()
end)
check('Global settings search finds the same nested Wallpaper choice without independent route',function()
 require('einkfrontend/settings').search(app,'Kindle');local count=0

 for _,row in ipairs(app.screen.model.rows) do if row.title=='使用 Kindle 原生屏保' then count=count+1;assert(row.subtitle==nil or not row.subtitle:find('stock_screensaver',1,true)) end end;assert(count==1,'stock search matches='..count)
 Device.supportsScreensaver=function() return false end;assert(not stock.enabled_func());Device.supportsScreensaver=function() return true end
end)
check('Reader gets the same Wallpaper option and switching away preserves display settings',function()
 app:close();require('apps/reader/readerui'):doShowReader(assert(os.getenv('EINK_030_BOOKS'))..'/navigation.epub')
 app=assert(require('apps/reader/readerui').instance).einkfrontend.app;openwallpaper();select(stock);preserved();select(cover);preserved()
 app:close();require('apps/reader/readerui').instance:onClose()
end)
Device.isKindle=originalKindle;Device.supportsScreensaver=originalSupport;Stock.paths=paths
if FM.instance then FM.instance:onClose() end
local f=assert(io.open(out..'wallpaper-'..variant..'.json','w'));f:write(require('json').encode(report));f:close();os.exit(0)
