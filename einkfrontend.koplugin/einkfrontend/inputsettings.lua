-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local View={}
function View.render(app,route,m,row,go)
 if route.id~='input_method' then return false end
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
 end
 return true
end
return View
