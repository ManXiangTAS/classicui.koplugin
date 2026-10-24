-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local View={}
local routes={frontlight_settings='前光',auto_light='自动调光设置',auto_light_memory='亮度记忆',auto_light_status='状态与检测',auto_light_threshold='明亮环境标准'}
function View.toggle(app)
 local light=app.autolight;if not light then return false end
 local ok,why=light:setEnabled(not light.config.enabled)
 if not ok then app:message(why) end
 if app.screen then app:render() end
 return ok
end
function View.adjust(app)
 local token,why=app.autolight:beginCalibration();if not token then app:message(why);return end
 local dialog=require('einkfrontend/lightcalibration'):new{app=app,token=token,manual=true}
 app:trackDialog(dialog);require('ui/uimanager'):show(dialog,'ui');return dialog
end
function View.calibrate(app,enable_after,kind)
 local light=app.autolight
 local token,err=light:beginCalibration(kind);if not token then app:message(err);return end
 local dialog=require('einkfrontend/lightcalibration'):new{app=app,token=token,enable_after=enable_after}
 app:trackDialog(dialog);require('ui/uimanager'):show(dialog,'ui');return dialog
end
function View.render(app,route,m,row,go)
 if not routes[route.id] then return false end
 m.settings=true;m.title=routes[route.id];m.subtitle=''
 local light=app.autolight
 if not light then row('当前前端未启用前光控制');return true end
 local Device=require('device')
 if not Device:hasFrontlight() then row('当前设备没有前光');return true end
 light:syncMode()
 if not route.light_checked then route.light_checked=true;light:probe() end
 local function action(fn)
  local ok,why=fn();if not ok then app:message(why or light.error or '设置未能生效') end;app:render();return ok
 end
 local function value(text) local r=m.rows[#m.rows];r.value=tostring(text);r.value_width=160 end
 local function resume()
  if light.config.enabled and (light.config.off_locked or light.manual_hold or light.fault or not light.available) then
   row('恢复自动调光',nil,function() action(function() return light:resumeAuto() end) end)
  end
 end
 m.help=function() app:message('开启后立即按环境调光，之后每 60 秒检测一次。\n暗处亮度用于最暗的阅读环境；明亮处亮度可设为 0，表示关灯。达到“明亮环境标准”后，使用明亮处亮度。\n手动调亮后会保持你的选择，直到环境变化使自动目标档位改变；手动关灯会一直保持关闭，可点“恢复自动调光”重新开启。\n浅色和深色模式分别保存亮度偏好。') end
 if route.id=='frontlight_settings' then
  row('亮度',nil,function() View.adjust(app) end);value((light:actual() or '—')..' / '..light.hi)
  if Device:hasNaturalLight() then
   row('暖光色温',nil,function()
    app.native:refresh();local entry=app.native.catalog.entries.frontlight
    if entry then app.native:open({entry.node},'前光');app.native:select(entry.node) else app:message('当前设备未提供暖光设置入口') end
   end)
  end
  if not Device.hasLightSensor or not Device:hasLightSensor() then return true end
  local toggle=function() View.toggle(app) end
  row('自动调光',nil,toggle);m.rows[#m.rows].checked=light.config.enabled;m.rows[#m.rows].checkmark_callback=toggle
  if light.config.enabled then value(light:statusText()) end
  row('自动调光设置',nil,go('auto_light'));resume();return true
 end
 m.subtitle=light:isDark() and '深色模式' or '浅色模式'
 if route.id=='auto_light_memory' then
  row('记住手动调整',nil,function() action(function() return light:setLearning(not light.config.learning) end) end);m.rows[#m.rows].checked=light.config.learning
  row('已记住的环境',nil,function()
   local lines={};for _,p in ipairs(light:profile().memories) do lines[#lines+1]=string.format('%.1f lux：%d 档',p.lux,p.level) end
   app:message(#lines>0 and table.concat(lines,'\n') or '还没有记忆。手动调整后稳定 3 秒，会记住当前环境下的亮度。')
  end);value(#light:profile().memories..' 处')
  if #light:profile().memories>0 then row('清除亮度记忆',nil,function()
   app:confirm('清除当前模式的亮度记忆？暗处、明亮处设置和另一模式的记忆会保留。',function() action(function() return light:clearMemory() end) end)
  end) end
  return true
 end
 if route.id=='auto_light_status' then
  row('当前状态',nil,function() app:message(light:diagnosticText()) end);value(light:statusText())
  row('检测当前环境',nil,function() light:checkNow();app:render();app:message(light:diagnosticText()) end)
  value(light.available and light.lux and string.format('%.1f lux',light.lux) or '不可用')
  resume();return true
 end
 if route.id=='auto_light_threshold' then
  m.help=function() app:message('环境照度达到这个数值时，使用“明亮处亮度”。数值越高，明亮环境中保留补光的时间越长。\n可以选预设，或在你认为足够明亮的环境中点“使用当前环境”。') end
  for _,entry in ipairs({{'室内较亮',500},{'明亮房间',1000},{'日光环境',10000}}) do
   local amount=entry[2]
   row(entry[1],nil,function() action(function() return light:setCurve('threshold',amount) end) end);value(amount..' lux');m.rows[#m.rows].checked=light:curveOptions().threshold==amount
  end
  row('使用当前环境',nil,function()
   local ok,why=light:probe();if not ok then app:message(why);return end
   action(function() return light:setCurve('threshold',math.floor(light.lux+.5)) end)
  end)
  row('自定义照度',nil,function()
   app.adapter:promptText('明亮环境标准（100–200000 lux）',tostring(light:curveOptions().threshold),function(text)
    return action(function() return light:setCurve('threshold',tonumber(text)) end)
   end,{keep_on_error=true,input_type='number'})
  end);value(light:curveOptions().threshold..' lux');return true
 end
 row('暗处亮度',nil,function() View.calibrate(app,false) end);value(light:anchor() and (light:anchor()..' 档') or '尚未设置')
 row('明亮处亮度',nil,function() View.calibrate(app,false,'daylight') end);value(light:curveOptions().daylight==light.lo and '关灯' or light:curveOptions().daylight..' 档')
 row('明亮环境标准',nil,go('auto_light_threshold'));value(light:curveOptions().threshold..' lux')
 row('亮度记忆',nil,go('auto_light_memory'));value(light.config.learning and '开启' or '关闭')
 row('状态与检测',nil,go('auto_light_status'))
 return true
end
return View
