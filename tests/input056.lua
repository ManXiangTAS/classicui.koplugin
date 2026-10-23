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
local root=assert(os.getenv('EINK_PROJECT'));local out=root..'/test-results-056/';local variant=os.getenv('EINK_VARIANT')
local report={tests={},variant=variant,device='NOT_RUN'}
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function ticks() for _=1,20 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end end
FM:showFiles(assert(os.getenv('EINK_030_BOOKS')));local app=FM.instance.einkfrontend.app;ticks();app:open('input_method')
local IME=require('einkfrontend/pinyin');local Stock=require('einkfrontend/stockscreensaver')
local notices={};for _,win in ipairs(UI._window_stack) do if win.widget.text then notices[#notices+1]=win.widget end end
for _,notice in ipairs(notices) do UI:close(notice) end
local function dialog(options)
 options=options or {};options.title=options.title or '中英切换测试';options.input=options.input or ''
 options.buttons={{{text='关闭',callback=function() end}}}
 local d=require('ui/widget/inputdialog'):new(options);UI:show(d);d:onShowKeyboard();UI:forceRePaint()
 return d,d._input_widget,d._input_widget.keyboard
end
local function typecode(box,s) for c in s:gmatch('.') do box:addChars(c) end end
local function close(d) UI:close(d);ticks() end
local function hit(k,id)
 UI:forceRePaint();for _,h in ipairs(k._eink_pinyin.bar.hits) do if h.id==id then return h end end
end
local function tap(k,language)
 local h=assert(hit(k,'pinyin_language_'..language))
 assert(k:handleEvent(require('ui/event'):new('Gesture',{ges='tap',pos=require('ui/geometry'):new{x=h.x+h.w/2,y=h.y+h.h/2,w=0,h=0}})))
 UI:forceRePaint()
end
local function chinese()
 G_reader_settings:saveSetting('keyboard_layout','zh_CN');G_reader_settings:saveSetting('keyboard_layout_default','zh_CN')
end
check('One tap switches pending pinyin to literal English without losing committed Chinese',function()
 chinese();local d,b,k=dialog{input='中文 '};typecode(b,'nihao');local original=k._eink_pinyin
 local height=k.dimen.h;tap(k,'en')
 assert(original.closed and b:getText()=='中文 nihao' and k._eink_pinyin.language=='en' and k.dimen.h==height)
 typecode(b,' Hello, world!');assert(b:getText()=='中文 nihao Hello, world!' and k._eink_pinyin.code=='')
 UI:forceRePaint();Device.screen.bb:writePNG(out..'quick-en-'..variant..'.png');close(d)
end)
check('One tap returns from English to Chinese; selected text and cursor position are preserved',function()
 local d,b,k=dialog{input='Hello '};assert(k._eink_pinyin.language=='en')
 tap(k,'zh_CN');typecode(b,'zhongwen');b:addChars(' ');assert(b:getText()=='Hello 中文')
 UI:forceRePaint();Device.screen.bb:writePNG(out..'quick-zh-'..variant..'.png');close(d)
end)
check('English mode uses native English punctuation and uppercase keys',function()
 chinese();local d,b,k=dialog();tap(k,'en')
 assert(k.KEYS[5][3][2]~='。');k:addChar('A');k:addChar('.');k:addChar('B');k:addChar(',')
 assert(b:getText()=='A.B,');tap(k,'zh_CN');assert(type(k.KEYS[5][3][2])=='table' and k.KEYS[5][3][2][1]=='。');close(d)
end)
check('Language choice is persisted and remains selected with native remember-layout disabled',function()
 chinese();G_reader_settings:saveSetting('keyboard_remember_layout',false)
 local d,b,k=dialog();tap(k,'en');close(d)
 local saved=require('luasettings'):open(G_reader_settings.file)
 assert(saved:readSetting('keyboard_layout_default')=='en' and saved:readSetting('keyboard_layout')=='en')
 d,b,k=dialog();assert(k._eink_pinyin.language=='en');tap(k,'zh_CN');close(d)
 d,b,k=dialog();assert(k._eink_pinyin.language=='zh_CN');close(d)
 G_reader_settings:delSetting('keyboard_remember_layout')
end)
check('Mode controls remain available without candidates and never overlap candidate targets',function()
 chinese();local d,b,k=dialog();assert(hit(k,'pinyin_language_en') and hit(k,'pinyin_language_zh_CN'))
 typecode(b,'shi');UI:forceRePaint();local hits=k._eink_pinyin.bar.hits
 for i,a in ipairs(hits) do for j,c in ipairs(hits) do if i<j then
  assert(a.x+a.w<=c.x+.001 or c.x+c.w<=a.x+.001)
 end end end
 tap(k,'en');assert(hit(k,'pinyin_language_zh_CN') and not hit(k,'pinyin_1'));close(d)
end)
check('Repeated switching releases old input wrappers and old language callbacks are inert',function()
 chinese();local d,b,k=dialog();local old=hit(k,'pinyin_language_en').callback
 for i=1,20 do tap(k,i%2==1 and 'en' or 'zh_CN') end
 old();assert(k._eink_pinyin.language=='zh_CN');local count=0
 for keyboard in pairs(IME.states) do if keyboard==k then count=count+1 end end;assert(count==1)
 typecode(b,'nihao');tap(k,'zh_CN');assert(k._eink_pinyin.code=='nihao');b:addChars(' ');assert(b:getText()=='你好')
 local state=k._eink_pinyin;local after=hit(k,'pinyin_language_en').callback;close(d);after();assert(state.closed)
end)
check('Other language layouts and sensitive input fields retain the native keyboard',function()
 chinese();local d,b,k=dialog();k:setKeyboardLayout('fr');assert(not k._eink_pinyin);close(d)
 for _,options in ipairs({{input_type='number'},{text_type='password'},{input_type='literal'}}) do
  chinese();d,b,k=dialog(options);assert(not k._eink_pinyin);close(d)
 end
end)
check('Switching while editing in the middle keeps all surrounding text',function()
 chinese();local d,b,k=dialog{input='前后'};b:leftChar();typecode(b,'nihao');tap(k,'en')
 assert(b:getText()=='前nihao后');k:addChar('!');assert(b:getText()=='前nihao!后')
 tap(k,'zh_CN');typecode(b,'hao');b:addChars(' ');assert(b:getText()=='前nihao!好后');close(d)
end)
check('Chinese setup registers both languages even if the user previously selected another layout',function()
 G_reader_settings:saveSetting('keyboard_layouts',{'fr','zh_CN'});app:open('input_method')
 for _,r in ipairs(app.screen.model.rows) do if r.title=='切换到中文拼音键盘' then r.callback() end end
 local layouts=G_reader_settings:readSetting('keyboard_layouts');assert(layouts[1]=='fr' and layouts[2]=='zh_CN' and layouts[3]=='en')
 local d,b,k=dialog();tap(k,'en');tap(k,'zh_CN');close(d)
 require('einkfrontend/settings').search(app,'中英');local found=false
 for _,r in ipairs(app.screen.model.rows) do found=found or r.title=='中文输入法' end;assert(found)
end)
app:close();local f=assert(io.open(out..'input-'..variant..'.json','w'));f:write(require('json').encode(report));f:close();os.exit(0)
