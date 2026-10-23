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
local root=assert(os.getenv('EINK_PROJECT'));local out=root..'/test-results-057/';local variant=os.getenv('EINK_VARIANT')
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
local C=require('einkfrontend/updatecore')
local ok,result=pcall(C.fetch,'0.5.0-test.5','testing')
print('NETWORK',ok,require('json').encode(result))
assert(ok and result and C.newer(result.version,'0.5.0-test.5'))
os.exit(0)
