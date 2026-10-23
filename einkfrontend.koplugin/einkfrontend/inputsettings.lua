-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local View={}
function View.render(app,route,m,row,go)
 if route.id~='input_method' and route.id~='stock_screensaver' then return false end
 m.settings=true;m.subtitle=''
 if route.id=='input_method' then
  local IME=require('einkfrontend/pinyin');m.title='中文输入法'
  local external=IME.external()
  if external then row('使用外部输入法',nil,function() app:message('检测到 '..external..'，墨页候选栏已自动让位，请在该插件设置中调整输入方案。') end)
  else
   row('拼音候选与中英切换',nil,function()
    G_reader_settings:saveSetting('eink_pinyin',not IME.enabled());G_reader_settings:flush();app:render()
   end);m.rows[#m.rows].checked=IME.enabled()
  end
  row('切换到中文拼音键盘',nil,function()
   local layouts=G_reader_settings:readSetting('keyboard_layouts',{});local next_layouts={};local found=false
   local english=false
   for _,lang in ipairs(layouts) do next_layouts[#next_layouts+1]=lang;if lang=='zh_CN' then found=true end;if lang=='en' then english=true end end
   if not found then next_layouts[#next_layouts+1]='zh_CN' end
   if not english then next_layouts[#next_layouts+1]='en' end
   G_reader_settings:saveSetting('keyboard_layouts',next_layouts);G_reader_settings:saveSetting('keyboard_layout','zh_CN')
   G_reader_settings:saveSetting('keyboard_layout_default','zh_CN');G_reader_settings:flush();app:render()
  end);m.rows[#m.rows].checked=G_reader_settings:readSetting('keyboard_layout_default')=='zh_CN'
  row('试试输入',nil,function() app.adapter:promptText('试试拼音输入','',function() end) end)
  row('使用方法',nil,function() app:message('键盘上方直接点“中 / EN”切换中英文，深色表示当前模式，关闭输入框后仍记住选择。\n切到英文时保留尚未选字的拼音字母；已输入的汉字与英文保持原样。英文使用英文标点键位。\n中文输入全拼后点候选词；左右箭头翻页，空格选字，回车保留字母。暂不支持整句联想和双拼。\n数字、密码和目录框保持直接输入；地球图标可切换其他语言。') end)
 else
  local Stock=require('einkfrontend/stockscreensaver');m.title='Kindle 原生屏保'
  local state=G_reader_settings:readSetting('eink_stock_screensaver')
  local path,files,why=Stock.detect()
  if type(state)=='table' and state.path then local selected=Stock.scan(state.path);if selected then path=state.path;files=selected end end
  local function activate(selected)
   local ok,err=Stock.activate(G_reader_settings,selected)
   if ok then app:render() else app:message(err) end
  end
  row('使用 Kindle 自带图片',nil,function() if path then activate(path) else app:message(why) end end)
  m.rows[#m.rows].checked=Stock.active(G_reader_settings)
  if files then
   row('预览图片',nil,function()
    local image=require('ui/renderimage'):renderImageFile(files[1],false,nil,nil)
    if not image then return app:message('此图片无法读取') end
    local viewer=require('ui/widget/imageviewer'):new{image=image,title_text='Kindle 自带屏保',image_disposable=true}
    app:trackDialog(viewer);local UI=require('ui/uimanager');UI:show(viewer);UI:forceRePaint()
   end);m.rows[#m.rows].value=tostring(#files)..' 张'
  end
  row('图片目录',nil,function()
   app.adapter:promptText('屏保图片目录',path or Stock.paths[1],function(value)
    local ok,err=Stock.activate(G_reader_settings,value)
    if not ok then app:message(err);return false end
    app:render()
   end,{keep_on_error=true,input_type='literal'})
  end)
  row('恢复之前的屏保',nil,function()
   local ok,err=Stock.restore(G_reader_settings);if ok then app:render() else app:message(err) end
  end);m.rows[#m.rows].enabled=type(state)=='table'
  row('其他屏保设置',nil,function()
   app.native:refresh();local entry=app.native.catalog.entries.screensaver
   if entry then app.native:open({entry.node},'屏保');app.native:select(entry.node) else app:message('当前设备未提供原生屏保设置') end
  end)
 end
 return true
end
return View
