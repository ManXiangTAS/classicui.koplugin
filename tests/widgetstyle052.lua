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
local UI=require('ui/uimanager');local B=require('ffi/blitbuffer');local Font=require('ui/font')
local Frame=require('ui/widget/container/framecontainer');local Progress=require('ui/widget/progresswidget')
local Span=require('ui/widget/rectspan');local Size=require('ui/size')
local root=assert(os.getenv('EINK_PROJECT'));local variant=assert(os.getenv('EINK_VARIANT'))
local out=root..'/test-results-052/';local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local observed={};local frame_native,progress_native=Frame.paintTo,Progress.paintTo
Frame.paintTo=function(w,...)
 observed[#observed+1]={widget=w,radius=w.radius,kind='frame'}
 return frame_native(w,...)
end
Progress.paintTo=function(w,...)
 observed[#observed+1]={widget=w,radius=w.radius,kind='progress'}
 return progress_native(w,...)
end
local baseline_frame,baseline_progress=Frame.paintTo,Progress.paintTo
local Style=require('einkfrontend/widgetstyle');local N=require('einkfrontend/notices')
local function check(name,fn)
 local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err)
end
local function ticks()
 for _=1,30 do UI:shiftScheduledTasksBy(-require('ui/time').s(.02));UI:_checkTasks() end
end
local function shot(name)
 UI:forceRePaint();local file=name..'-'..variant..'.png'
 Device.screen:shot(out..file);report.frames[#report.frames+1]=file
end
local function walk(w,fn,seen)
 if type(w)~='table' then return end
 seen=seen or {};if seen[w] then return end;seen[w]=true;fn(w)
 for _,child in ipairs(w) do walk(child,fn,seen) end
end
local function standard(name,create)
 check('Standard control: '..name,function()
  local w=create();local before={}
  walk(w,function(child) before[child]={radius=rawget(child,'radius'),border=child.bordersize} end)
  observed={};UI:show(w);UI:forceRePaint()
  assert(#observed>0,'no common renderer reached')
  for _,paint in ipairs(observed) do
   assert(not paint.radius or paint.radius==0,'rounded rectangular frame reached renderer: '..name)
  end
  for child,state in pairs(before) do
   assert(rawget(child,'radius')==state.radius and child.bordersize==state.border,'presentation leaked into widget state')
  end
  shot(name);UI:close(w)
 end)
end

local old=Frame:new{radius=Size.radius.window,padding=0,Span:new{width=120,height=60}}
local native=B.new(160,100,B.TYPE_BB8);native:paintRect(0,0,160,100,B.COLOR_WHITE)
old:paintTo(native,10,10)
local FM=require('apps/filemanager/filemanager')
FM:showFiles(assert(os.getenv('EINK_030_BOOKS')));local fm=FM.instance;local owner=fm.einkfrontend
ticks()
local transient={};for _,entry in ipairs(UI._window_stack) do if entry.widget.text then transient[#transient+1]=entry.widget end end
for _,widget in ipairs(transient) do UI:close(widget) end
owner.app:open('settings')
check('Active frontend installs only two shared renderer hooks',function()
 assert(next(N.owners) and next(Style.owners) and #Style.records==2)
 assert(Frame.paintTo~=baseline_frame and Progress.paintTo~=baseline_progress)
end)
check('Existing frames gain square black corners without layout or radius mutation',function()
 local radius=old.radius;local size=old:getSize()
 local bb=B.new(160,100,B.TYPE_BB8);bb:paintRect(0,0,160,100,B.COLOR_WHITE);old:paintTo(bb,10,10)
 assert(bb:getPixel(10,10):getColor8().a==0 and native:getPixel(10,10):getColor8().a>0)
 assert(old.radius==radius and old:getSize().w==size.w and old:getSize().h==size.h)
 bb:free();native:free()
end)

local Info=require('ui/widget/infomessage')
standard('info',function() return Info:new{text='正在打开文件“测试书籍.epub”…',dismissable=false} end)
standard('info-fixed',function() return Info:new{text=string.rep('固定高度报告，保留滚动。\n',18),height=Device.screen:scaleBySize(110)} end)
standard('info-monospace',function() return Info:new{text='diagnostic: value = 123\n保留等宽字体',monospace_font=true} end)
standard('info-custom-font',function() return Info:new{text='调用方指定的字号',face=Font:getFace('infont',14)} end)
standard('info-image',function()
 local image=B.new(32,32,B.TYPE_BB8);image:paintRect(0,0,32,32,B.COLOR_BLACK)
 return Info:new{text='含图片的提示也采用直角',image=image,image_width=32,image_height=32}
end)
standard('confirm',function() return require('ui/widget/confirmbox'):new{text='是否将这本书加入收藏？',ok_text='加入收藏',cancel_text='取消',ok_callback=function() end} end)
standard('multi-confirm',function() return require('ui/widget/multiconfirmbox'):new{text='同名书籍已存在',choice1_text='保留两本',choice2_text='跳过',choice1_callback=function() end,choice2_callback=function() end} end)
standard('button-dialog',function() return require('ui/widget/buttondialog'):new{title='书籍操作',buttons={{{text='打开',callback=function() end},{text='收藏',callback=function() end}},{{text='关闭',callback=function() end}}}} end)
standard('input',function() return require('ui/widget/inputdialog'):new{title='新建收藏',input='我的书单',buttons={{{text='保存',callback=function() end}}}} end)
standard('multi-input',function() return require('ui/widget/multiinputdialog'):new{title='连接设置',fields={{text='阅读器',description='名称'},{text='8080',description='端口',input_type='number'}},buttons={{{text='保存',callback=function() end}}}} end)
standard('spin',function() return require('ui/widget/spinwidget'):new{title_text='调整数值',value=5,value_min=0,value_max=10,callback=function() end} end)
standard('double-spin',function() return require('ui/widget/doublespinwidget'):new{title_text='左右边距',left_value=10,right_value=10,callback=function() end} end)
standard('date',function() return require('ui/widget/datetimewidget'):new{title_text='设置日期',year=2026,month=10,day=23,callback=function() end} end)
standard('radio',function() return require('ui/widget/radiobuttonwidget'):new{title_text='选择阅读方式',radio_buttons={{{text='翻页',provider=1,checked=true}},{{text='滚动',provider=2}}},callback=function() end} end)
standard('text-viewer',function() return require('ui/widget/textviewer'):new{title='说明与诊断',text=string.rep('详细说明。\n',20),text_type='code'} end)
standard('menu',function() return require('ui/widget/menu'):new{title='插件菜单',width=math.floor(Device.screen:getWidth()*.7),height=math.floor(Device.screen:getHeight()*.6),is_popout=true,item_table={{text='插件操作',callback=function() end},{text='更多设置'}}} end)
standard('progress-dialog',function() return require('ui/widget/progressbardialog'):new{title='正在下载书籍',subtitle='已接收 35%',progress_max=100,dismiss_text='停止下载？'} end)
standard('font-chooser',function() return require('ui/widget/fontchooser'):new{title='界面字体',font_file='NotoSansCJKsc-Regular.otf',callback=function() end} end)
standard('image-viewer',function()
 local image=B.new(160,120,B.TYPE_BB8);image:paintRect(0,0,160,120,B.COLOR_LIGHT_GRAY)
 return require('ui/widget/imageviewer'):new{image=image,title_text='图片预览'}
end)
standard('open-with',function() return require('ui/widget/openwithdialog'):new{title='选择阅读引擎',input='',readonly=true,radio_buttons={{{text='EPUB',provider={provider='crengine'},checked=true}},{{text='PDF',provider={provider='mupdf'}}}},buttons={{{text='打开',callback=function() end}}}} end)
standard('dictionary',function() return require('ui/widget/dictquicklookup'):new{ui=fm,word='阅读',results={{dict='测试词典',word='阅读',definition='阅读：看书报并理解其内容。',is_html=false}}} end)
standard('frontlight',function() return require('ui/widget/frontlightwidget'):new{} end)
standard('toggle',function() return require('ui/widget/toggleswitch'):new{toggle={'关闭','开启'},position=1} end)

check('Notification timeout closes once and overlapping toasts remain separate',function()
 local Toast=require('ui/widget/notification');local a=Toast:new{text='已保存',timeout=.1};local b=Toast:new{text='书库已刷新',timeout=.1}
 UI:show(a);UI:show(b);UI:forceRePaint()
 assert(b.frame.dimen.y>=a.frame.dimen.y+a.frame.dimen.h)
 ticks();assert(not UI:isWidgetShown(a) and not UI:isWidgetShown(b))
end)
check('Delayed and nondismissable notices retain their lifecycle',function()
 local calls=0;local w=Info:new{text='等待处理完成',show_delay=.02,timeout=.1,dismissable=false,dismiss_callback=function() calls=calls+1 end}
 UI:show(w);assert(not w.ges_events.TapClose and not w.key_events.AnyKeyPressed);ticks()
 assert(calls==1 and not UI:isWidgetShown(w) and not w._timeout_func and not w._delayed_show_action)
end)
check('Confirmation cancel and accept retain separate callbacks and close once',function()
 local yes,no=0,0;local Confirm=require('ui/widget/confirmbox')
 for _,text in ipairs({'取消','确认'}) do
  local w=Confirm:new{text='确认操作',cancel_text='取消',ok_text='确认',ok_callback=function() yes=yes+1 end,cancel_callback=function() no=no+1 end}
  UI:show(w);UI:forceRePaint();local button
  walk(w,function(child) if child.text==text and child.onTapSelectButton then button=child end end)
  assert(button);button:onTapSelectButton();assert(not UI:isWidgetShown(w))
 end
 assert(yes==1 and no==1)
end)
check('Buttons preserve feedback colors, inherited radius and disabled actions',function()
 local Button=require('ui/widget/button');local calls=0
 for _,colored in ipairs({false,true}) do
  local w=Button:new{text='操作',width=160,background=colored and B.COLOR_GRAY or nil,callback=function() calls=calls+1 end}
  UI:show(w);UI:forceRePaint()
  local bg,fg=w.frame.background:getColor8().a,w.label_widget.fgcolor:getColor8().a
  for _=1,3 do
   observed={};w:_doFeedbackHighlight()
   for _,p in ipairs(observed) do assert(not p.radius or p.radius==0) end
   w:_undoFeedbackHighlight(false)
   assert(w.frame.background:getColor8().a==bg and w.label_widget.fgcolor:getColor8().a==fg)
   assert(w.frame.radius==nil and not w.frame.invert)
  end
  UI:close(w)
 end
 local w=Button:new{text='不可用',enabled=false,callback=function() calls=calls+1 end}
 UI:show(w);UI:forceRePaint();w:onTapSelectButton();assert(calls==0);UI:close(w)
end)
check('Input reinit and keyboard layout retain text and square frames',function()
 local Input=require('ui/widget/inputdialog');local w=Input:new{title='搜索',input='原来的文字',buttons={{{text='搜索',callback=function() end}}}}
 UI:show(w);w:onShowKeyboard();w:setInputText('更新后的文字');w:reinit();UI:show(w);UI:forceRePaint()
 assert(w:getInputText()=='更新后的文字')
 local keyboard=w._input_widget.keyboard;local key
 walk(keyboard,function(child) if child.keyboard==keyboard and child.callback then key=child end end)
 assert(key,'native keyboard key missing')
 observed={};local layout=require('ui/widget/keyboardlayoutdialog'):new{parent=key,keyboard_state={}}
 UI:show(layout);UI:forceRePaint();for _,p in ipairs(observed) do assert(not p.radius or p.radius==0) end
 shot('keyboard-layout');UI:close(layout);UI:close(w)
end)
check('Explicit circular frames and plugin opt-outs retain their shapes',function()
 local circle=Frame:new{radius=30,bordersize=0,padding=0,Span:new{width=60,height=60}}
 local custom=Frame:new{radius=9,_eink_keep_shape=true,padding=0,Span:new{width=120,height=60}}
 local bb=B.new(200,200,B.TYPE_BB8);observed={};circle:paintTo(bb,0,0);custom:paintTo(bb,0,70)
 assert(observed[1].radius==30 and observed[2].radius==9)
 circle._eink_force_square=true;circle:paintTo(bb,0,0);assert(observed[3].radius==0 and circle.radius==30)
 circle:free();custom:free();bb:free()
end)
check('Progress values and inherited rounding survive repeated paints',function()
 local w=Progress:new{width=160,height=20,percentage=.35}
 local bb=B.new(200,100,B.TYPE_BB8);observed={};local radius=rawget(w,'radius');w:paintTo(bb,0,0);w:paintTo(bb,0,30)
 assert(w.percentage==.35 and rawget(w,'radius')==radius and observed[1].radius==0 and observed[2].radius==0)
 w:free();bb:free()
end)
check('A child paint error restores the original frame radius and propagates',function()
 local w=Frame:new{radius=11,padding=0,Span:new{width=120,height=60}}
 w[1].paintTo=function() error('intentional child paint failure') end
 local bb=B.new(200,100,B.TYPE_BB8);local ok,err=pcall(w.paintTo,w,bb,0,0)
 assert(not ok and tostring(err):find('intentional child paint failure',1,true) and w.radius==11)
 w:free();bb:free()
end)
check('Plugin-created standard frames inherit styling without registering an adapter',function()
 local PluginWindow=require('ui/widget/container/inputcontainer'):extend{}
 function PluginWindow:init() self[1]=Frame:new{radius=17,padding=0,Span:new{width=220,height=90}} end
 local w=PluginWindow:new{};observed={};UI:show(w);UI:forceRePaint()
 local seen=false;for _,p in ipairs(observed) do if p.widget==w[1] then assert(p.radius==0);seen=true end end
 assert(seen and w[1].radius==17);UI:close(w)
end)
check('Multiple owners, later third-party wrappers and reinstall remain reversible',function()
 local extra={};Style.install(extra);N.detach(owner,true)
 assert(next(Style.owners));Style.detach(extra)
 assert(Frame.paintTo==baseline_frame and Progress.paintTo==baseline_progress)
 Style.install(extra);local own=Frame.paintTo;local calls=0
 local foreign=function(w,...) calls=calls+1;return own(w,...) end
 Frame.paintTo=foreign;Style.detach(extra);assert(Frame.paintTo==foreign)
 local bb=B.new(200,100,B.TYPE_BB8);observed={};old:paintTo(bb,0,0);assert(observed[1].radius==old.radius)
 Style.install(extra);observed={};old:paintTo(bb,0,0);assert(observed[1].radius==0 and calls==2)
 Style.detach(extra);assert(Frame.paintTo==foreign);Frame.paintTo=baseline_frame
 N.install(owner);bb:free()
end)
check('Reader transitions keep common controls styled and final close restores native',function()
 local Reader=require('apps/reader/readerui');local books=assert(os.getenv('EINK_030_BOOKS'))
 Reader:doShowReader(books..'/navigation.epub');local reader=assert(Reader.instance)
 observed={};local w=require('ui/widget/skimtowidget'):new{ui=reader};UI:show(w);UI:forceRePaint()
 for _,p in ipairs(observed) do assert(not p.radius or p.radius==0) end
 shot('skim');UI:close(w);reader:onClose();ticks()
 if FM.instance then FM.instance:onClose() end;ticks()
 assert(not next(Style.owners) and Frame.paintTo==baseline_frame and Progress.paintTo==baseline_progress)
end)
old:free()
local f=assert(io.open(out..'widgets-'..variant..'.json','w'));f:write(require('json').encode(report));f:close()
print('COMPLETE '..variant)
