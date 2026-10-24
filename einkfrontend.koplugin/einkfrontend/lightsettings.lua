-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local View={}
function View.toggle(app)
 local light=app.autolight;if not light then return false end
 local enabled=not light.config.enabled
 if enabled and not light:anchor() then
  local actual=light:actual()
  if actual==nil or actual<=light.lo then app:message('请先在设置 → 显示与刷新 → 前光中选择暗处亮度。');return false end
 end
 local ok,why=light:setEnabled(enabled)
 if not ok then app:message(why) end
 if app.screen then app:render() end
 return ok
end
function View.adjust(app)
 local token,why=app.autolight:beginCalibration();if not token then app:message(why);return end
 local dialog=require('einkfrontend/lightcalibration'):new{app=app,token=token,manual=true}
 app:trackDialog(dialog);require('ui/uimanager'):show(dialog,'ui');return dialog
end
function View.calibrate(app,enable_after)
 local light=app.autolight
 local ok,why=light:probe();if not ok then app:message(why);return end
 local token,err=light:beginCalibration();if not token then app:message(err);return end
 local dialog=require('einkfrontend/lightcalibration'):new{app=app,token=token,enable_after=enable_after}
 app:trackDialog(dialog);require('ui/uimanager'):show(dialog,'ui');return dialog
end
function View.render(app,route,m,row,go)
 if route.id~='frontlight_settings' and route.id~='auto_light' and route.id~='auto_light_memory' then return false end
 m.settings=true;m.title=route.id=='auto_light_memory' and '亮度记忆' or '前光';m.subtitle=''
 local light=app.autolight
 if not light then row('当前前端未启用自动前光模块');return true end
 light:syncMode()
 if not route.light_checked then route.light_checked=true;light:probe() end
 local function action(fn)
  local ok,why=fn();if not ok then app:message(why or light.error or '设置未能生效') end;app:render()
 end
 local function value(text) local r=m.rows[#m.rows];r.value=tostring(text);r.value_width=160 end
 m.help=function()
  app:message('下拉面板的“自动调光”复选框只负责开关，校准和记忆在本页调整。首次开启以当前非零亮度作为起点；建议在最暗阅读环境校准舒适亮度。\n浅色与深色模式分别记住校准和环境偏好；清除记忆只影响当前模式。\n手动调光稳定 3 秒后学习，手动亮度优先保持 15 分钟；关灯后保持关闭。休眠停止采样，唤醒后恢复。\n首次请遮挡、照射传感器，点“当前环境”核对 Lux 变化；接口不可用时保留手动控制。')
 end
 if route.id=='auto_light_memory' then
  row('记住手动调整',nil,function() action(function() return light:setLearning(not light.config.learning) end) end)
  m.rows[#m.rows].checked=light.config.learning
  row('当前模式',nil);value(light:isDark() and '深色模式' or '浅色模式')
  row('已记住的环境',nil);value(#light:profile().memories..' 处')
  for _,p in ipairs(light:profile().memories) do row(string.format('%.1f lux',p.lux),nil);value(p.level..' 档') end
  row('清除当前模式记忆',nil,function()
   app:confirm('清除当前模式的环境亮度偏好？暗处校准与另一模式的记忆会保留。',function() action(function() return light:clearMemory() end) end)
  end)
  return true
 end
 local Device=require('device')
 if not Device:hasFrontlight() then row('当前设备没有前光');return true end
 row('亮度',nil,function() View.adjust(app) end);value((light:actual() or '—')..' / '..light.hi)
 if Device:hasNaturalLight() then
  row('暖光色温',nil,function()
   app.native:refresh();local entry=app.native.catalog.entries.frontlight
   if entry then app.native:open({entry.node},'前光');app.native:select(entry.node) else app:message('当前设备未提供暖光设置入口') end
  end)
 end
 local toggle=function() View.toggle(app) end
 row('自动调光',nil,toggle)
 m.rows[#m.rows].checked=light.config.enabled;m.rows[#m.rows].checkmark_callback=toggle
 value(light.available and light:statusText() or '不可用')
 if not Device.hasLightSensor or not Device:hasLightSensor() then
  row('当前设备没有环境光传感器','手动亮度和设备支持的暖光仍可调整');return true
 end
 row('当前模式',nil);value(light:isDark() and '深色模式' or '浅色模式')
 row('最暗环境下的亮度',nil,function() View.calibrate(app,false) end)
 value(light:anchor() and (light:anchor()..' / '..light.hi) or '尚未校准')
 row('亮度记忆',nil,go('auto_light_memory'));value(light.config.learning and (#light:profile().memories..' 处') or '未学习')
 if light.config.enabled and (light.config.off_locked or light.pause_until or light.fault or not light.available) then
  row('恢复自动',nil,function() action(function() return light:resumeAuto() end) end)
 end
 row('当前环境',nil,function()
  light:probe();app:render()
  if not light.available then app:message(light.reason or '环境光暂不可用') end
 end)
 value(light.available and light.lux and string.format('%.1f lux',light.lux) or '不可用')
 row('光感接口',nil,function() app:message(light.reason or light.error or '接口可读；请通过遮挡和照射测试确认读数随环境变化。') end)
 value(light.available and (light.sensor.backend=='lipc' and 'Kindle 光感' or 'IIO 光感') or '点此查看原因')
 return true
end
return View
