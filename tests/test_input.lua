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
local function dialog(options)
 options=options or {};options.title=options.title or '拼音输入测试';options.input=options.input or ''
 options.buttons={{{text='关闭',callback=function() end}}}
 local d=require('ui/widget/inputdialog'):new(options);UI:show(d);d:onShowKeyboard();UI:forceRePaint()
 return d,d._input_widget,d._input_widget.keyboard
end
local function typecode(box,s) for c in s:gmatch('.') do box:addChars(c) end end
local function close(d) UI:close(d);ticks() end
check('Chinese typing shows clickable candidates; selecting a word replaces only preedit',function()
 local d,b,k=dialog{input='原文'};typecode(b,'nihao');local state=assert(k._eink_pinyin)
 assert(state.code=='nihao' and state.candidates[1]=='你好');UI:forceRePaint();local h
 for _,item in ipairs(state.bar.hits) do if item.id=='pinyin_1' then h=item end end
 assert(h,'No candidate hit; hits='..#state.bar.hits..' visible='..tostring(k.visible)..' code='..state.code..' candidates='..#state.candidates);assert(k:handleEvent(require('ui/event'):new('Gesture',{ges='tap',pos=require('ui/geometry'):new{x=h.x+1,y=h.y+1,w=0,h=0}})))
 assert(b:getText()=='原文你好' and state.code=='');close(d)
end)
check('Space selects first candidate; Enter retains literal spelling without submitting the dialog',function()
 local d,b,k=dialog();typecode(b,'zhongwen');b:addChars(' ');assert(b:getText()=='中文')
 typecode(b,'abc');b:addChars('\n');assert(b:getText()=='中文abc' and k._eink_pinyin.code=='');close(d)
end)
check('Backspace edits preedit; confirmation reads committed text; punctuation follows the chosen word',function()
 local d,b,k=dialog();typecode(b,'nih');b:delChar();assert(k._eink_pinyin.code=='ni')
 b:addChars('，');assert(b:getText()=='你，');typecode(b,'hao');assert(d:getInputText()=='你，好');close(d)
end)
check('Input edit callbacks can read text without breaking preedit; old candidate callbacks cannot commit a new query',function()
 local d,b,k=dialog();local reads={};b.edit_callback=function() reads[#reads+1]=b:getText() end
 typecode(b,'nihao');assert(k._eink_pinyin.code=='nihao' and reads[#reads]=='nihao')
 UI:forceRePaint();local callback
 for _,hit in ipairs(k._eink_pinyin.bar.hits) do if hit.id=='pinyin_1' then callback=hit.callback end end
 b:delChar();callback();assert(k._eink_pinyin.code=='niha')
 b:addChars('o');assert(d:getInputText()=='你好');close(d)
end)
check('Candidate paging clears stale hits and boundary pages stay bounded',function()
 local d,b,k=dialog();typecode(b,'shi');local state=k._eink_pinyin;assert(#state.candidates>4)
 UI:forceRePaint();state:pageBy(1);assert(state.page==1 and #state.bar.hits==0)
 state:pageBy(100);assert(state.page==math.floor((#state.candidates-1)/4));state:pageBy(-100);assert(state.page==0)
 close(d);state:commit('坏');state:pageBy(1);assert(state.closed and state.page==0)
end)
check('Separate input boxes never share composition; cursor motion commits before moving',function()
 local d,b,k=dialog();typecode(b,'ni');local d2,b2,k2=dialog();typecode(b2,'hao')
 assert(k._eink_pinyin.code=='ni' and k2._eink_pinyin.code=='hao');assert(b2:getText()=='好');close(d2)
 b:leftChar();assert(b:getText()=='你' and b.charpos==1);b:addChars('X');assert(b:getText()=='X你');close(d)
end)
check('Switching Chinese to English keeps quick switch available and reentering Chinese creates fresh state',function()
 local d,b,k=dialog();local original_height=k.dimen.h;typecode(b,'ni');k:setKeyboardLayout('en')
 assert(k._eink_pinyin.language=='en' and b:getText()=='你' and k.dimen.h==original_height)
 k:addChar('a');assert(b:getText()=='你a');k:setKeyboardLayout('zh_CN');assert(k._eink_pinyin and k.dimen.h==original_height)
 k:setLayer('Shift');assert(k._eink_pinyin and k.dimen.h==original_height);close(d)
end)
check('Password and numeric fields do not run either Chinese IME or candidate UI',function()
 for _,options in ipairs({{input_type='number'},{text_type='password'},{input_type='literal'}}) do
  local d,b,k=dialog(options);assert(not k._eink_pinyin and not b._py_wrapped)
  b:addChars('123');assert(b:getText()=='123');close(d)
 end
end)
check('External pinyin plugin and explicit opt-out keep the native layout intact',function()
 local loader=require('pluginloader');local saved=loader.enabled_plugins;loader.enabled_plugins={{name='pinyinime'}}
 assert(IME.external()=='pinyinime');local d,b,k=dialog();assert(not k._eink_pinyin);close(d);loader.enabled_plugins=saved
 G_reader_settings:saveSetting('eink_pinyin',false);d,b,k=dialog();assert(not k._eink_pinyin);close(d)
 G_reader_settings:saveSetting('eink_pinyin',true)
end)
check('Candidate UI fits viewport, stays above native keys and does not cover dialog buttons',function()
 local d,b,k=dialog();typecode(b,'zhongwen');UI:forceRePaint();local bar=k._eink_pinyin.bar
 assert(k.dimen.h<Device.screen:getHeight() and bar.dimen.y>=0 and bar.dimen.y+bar.dimen.h<=Device.screen:getHeight())
 assert(bar.dimen.y==k.dimen.y and d.button_table.dimen.y+d.button_table.dimen.h<=k.dimen.y)
 Device.screen.bb:writePNG(out..'pinyin-'..variant..'.png');close(d)
end)
check('Input and stock screensaver settings are scoped; global search finds the new input route',function()
 for _,category in ipairs(app.native.categories) do
  app:open('catalog_category',category[1]);local found=false
  for _,row in ipairs(app.screen.model.rows) do found=found or row.title=='中文输入法' end
  assert(found==(category[1]=='input'))
 end
 require('einkfrontend/settings').search(app,'候选词');local found=false
 for _,r in ipairs(app.screen.model.rows) do found=found or r.title=='中文输入法' end;assert(found)
 app:open('input_method');UI:forceRePaint();Device.screen.bb:writePNG(out..'input-settings-'..variant..'.png')
end)
check('Missing or empty stock image directories never change current settings',function()
 local before=G_reader_settings:readSetting('screensaver_type');local kindle={isKindle=function() return true end,supportsScreensaver=function() return true end}
 assert(not Stock.activate(G_reader_settings,'/does/not/exist',kindle));assert(G_reader_settings:readSetting('screensaver_type')==before)
 assert(not Stock.scan('/tmp\0test'));assert(not Stock.scan('relative'))
 assert(not Stock.supported({isKindle=function() return false end}))
 assert(not Stock.supported({isKindle=function() return true end,supportsScreensaver=function() return false end}))
end)
check('Stock image activation and preview use local artwork; restoration preserves later user changes',function()
 local dir=DS:getDataDir()..'/artwork';require('libs/libkoreader-lfs').mkdir(dir)
 local file=dir..'/bg_ss00.png';Device.screen.bb:writePNG(file);local img=assert(io.open(file,'rb'));local image_before=img:read('*a');img:close()
 local f=io.open(dir..'/._hidden.png','wb');f:write('x');f:close();f=io.open(dir..'/bad.txt','wb');f:write('x');f:close()
 local files=assert(Stock.scan(dir));assert(#files==1 and files[1]==file)
 G_reader_settings:saveSetting('screensaver_type','cover');G_reader_settings:delSetting('screensaver_show_message')
 local kindle={isKindle=function() return true end,supportsScreensaver=function() return true end}
 assert(Stock.activate(G_reader_settings,dir,kindle));assert(Stock.active(G_reader_settings))
 assert(not G_reader_settings:has('screensaver_show_message'))
 local screensaver=require('ui/screensaver');screensaver:setup();assert(screensaver.screensaver_type=='random_image' and screensaver.image_file==file and screensaver.show_message==false);screensaver:cleanup()
 local oldpaths=Stock.paths;Stock.paths={dir};local oldis,oldsupport=Device.isKindle,Device.supportsScreensaver
 Device.isKindle=kindle.isKindle;Device.supportsScreensaver=kindle.supportsScreensaver
 app.native:refresh();local entry=assert(app.native.catalog.entries.screensaver)
 local wallpaper;for _,item in ipairs(entry.node.sub_item_table) do if item.text==require('gettext')('Wallpaper') then wallpaper=item end end
 app.native:open({entry.node},'屏保');app.native:select(entry.node);app.native:select(assert(wallpaper))
 local found=false;for _,r in ipairs(app.screen.model.rows) do found=found or r.title=='使用 Kindle 原生屏保' end;assert(found)
 UI:forceRePaint();Device.screen.bb:writePNG(out..'stock-settings-'..variant..'.png')
 Device.isKindle=oldis;Device.supportsScreensaver=oldsupport;Stock.paths=oldpaths
 G_reader_settings:saveSetting('screensaver_img_background','black');assert(Stock.restore(G_reader_settings))
 assert(G_reader_settings:readSetting('screensaver_type')=='cover' and not G_reader_settings:has('screensaver_show_message'))
 assert(G_reader_settings:readSetting('screensaver_img_background')=='black' and not Stock.active(G_reader_settings));img=assert(io.open(file,'rb'));assert(img:read('*a')==image_before);img:close()
end)
check('Settings write failure rolls back stock configuration',function()
 local settings=require('luasettings'):open(DS:getDataDir()..'/failed.lua');settings:saveSetting('screensaver_type','cover')
 settings.flush=function() return false end
 local kindle={isKindle=function() return true end,supportsScreensaver=function() return true end}
 local ok=Stock.activate(settings,DS:getDataDir()..'/artwork',kindle);assert(not ok)
 assert(settings:readSetting('screensaver_type')=='cover' and not settings:has('eink_stock_screensaver') and not settings:has('screensaver_dir'))
end)
check('Final owner detach restores keyboard hooks and closed dialog candidates cannot type',function()
 app:open('input_method');local d,b,k=dialog();typecode(b,'ni');local state=k._eink_pinyin
 close(d);assert(state.closed and not k._eink_pinyin)
 IME.detach(app.plugin);assert(not IME.init_wrapper and next(IME.states)==nil)
 local d2,b2,k2=dialog();assert(not k2._eink_pinyin);close(d2);IME.install(app.plugin)
end)
app:close();local f=assert(io.open(out..'input-'..variant..'.json','w'));f:write(require('json').encode(report));f:close();os.exit(0)
