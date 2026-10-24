-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local View={}
function View.calibrate(app,enable_after)
 local light=app.autolight
 local ok,why=light:probe();if not ok then app:message(why);return end
 local token,err=light:beginCalibration();if not token then app:message(err);return end
 local dialog=require('einkfrontend/lightcalibration'):new{app=app,token=token,enable_after=enable_after}
 app:trackDialog(dialog);require('ui/uimanager'):show(dialog,'ui');return dialog
end
function View.render(app,route,m,row,go)
 if route.id~='auto_light' and route.id~='auto_light_memory' then return false end
 m.settings=true;m.title=route.id=='auto_light' and '自动前光' or '亮度记忆';m.subtitle=''
 local light=app.autolight
 if not light then row('当前前端未启用自动前光模块');return true end
 if not route.light_checked then route.light_checked=true;light:probe() end
 local function action(fn)
  local ok,why=fn();if not ok then app:message(why or light.error or '设置未能生效') end;app:render()
 end
 local function value(text) local r=m.rows[#m.rows];r.value=tostring(text);r.value_width=160 end
 m.help=function()
  app:message('先在最暗的阅读环境选定舒适亮度，再手动开启。\n自动补光会过滤短暂遮挡，逐档调整，不要求固定的暗处档位。\n开启记忆后，在墨页下拉面板里手动调整亮度，停留 3 秒会记住当前环境的偏好，并优先保持手动亮度 15 分钟。外部插件的改动只会暂停自动，不会学进偏好。\n手动关灯后保持关闭，须点“恢复自动”才会重新自动补光。休眠停止采样，唤醒后恢复。\n首次使用请遮挡、照射传感器，并点击“当前环境”核对读数变化。接口可读不等于本机已完成兼容性验证；若不可用会保留手动控制。')
 end
 if route.id=='auto_light_memory' then
  row('记住手动调整',nil,function() action(function() return light:setLearning(not light.config.learning) end) end)
  m.rows[#m.rows].checked=light.config.learning
  row('已记住的环境',nil);value(#light.config.memories..' 处')
  for _,p in ipairs(light.config.memories) do row(string.format('%.1f lux',p.lux),nil);value(p.level..' 档') end
  row('清除亮度记忆',nil,function()
   app:confirm('清除学到的环境亮度偏好？暗处基准亮度会保留。',function() action(function() return light:clearMemory() end) end)
  end)
  return true
 end
 row('自动前光',nil,function()
  if light.config.enabled then action(function() return light:setEnabled(false) end)
  else
   local ok,why=light:probe();if not ok then app:message(why);return end
   if not light.config.anchor then View.calibrate(app,true)
   else action(function() return light:setEnabled(true) end) end
  end
 end)
 m.rows[#m.rows].checked=light.config.enabled;value(light.available and light:statusText() or '不可用')
 row('最暗环境下的亮度',nil,function() View.calibrate(app,false) end)
 value(light.config.anchor and (light.config.anchor..' / '..light.hi) or '尚未校准')
 row('亮度记忆',nil,go('auto_light_memory'));value(light.config.learning and (#light.config.memories..' 处') or '未学习')
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
