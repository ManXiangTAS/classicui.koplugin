-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local View={}
local routes={frontlight_settings='ǰ��',auto_light='�Զ���������',auto_light_memory='���ȼ���',auto_light_status='״̬����',auto_light_threshold='����������׼'}
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
 if not light then row('��ǰǰ��δ����ǰ�����');return true end
 local Device=require('device')
 if not Device:hasFrontlight() then row('��ǰ�豸û��ǰ��');return true end
 light:syncMode()
 if not route.light_checked then route.light_checked=true;light:probe() end
 local function action(fn)
  local ok,why=fn();if not ok then app:message(why or light.error or '����δ����Ч') end;app:render();return ok
 end
 local function value(text) local r=m.rows[#m.rows];r.value=tostring(text);r.value_width=160 end
 local function resume()
  if light.config.enabled and (light.config.off_locked or light.manual_hold or light.fault or not light.available) then
   row('�ָ��Զ�����',nil,function() action(function() return light:resumeAuto() end) end)
  end
 end
 m.help=function() app:message('�������������������⣬֮��ÿ 60 ����һ�Ρ�\n����������������Ķ����������������ȿ���Ϊ 0����ʾ�صơ��ﵽ������������׼����ʹ�����������ȡ�\n�ֶ�������ᱣ�����ѡ��ֱ�������仯ʹ�Զ�Ŀ�굵λ�ı䣻�ֶ��صƻ�һֱ���ֹرգ��ɵ㡰�ָ��Զ����⡱���¿�����\nǳɫ����ɫģʽ�ֱ𱣴�����ƫ�á�') end
 if route.id=='frontlight_settings' then
  row('����',nil,function() View.adjust(app) end);value((light:actual() or '��')..' / '..light.hi)
  if Device:hasNaturalLight() then
   row('ů��ɫ��',nil,function()
    app.native:refresh();local entry=app.native.catalog.entries.frontlight
    if entry then app.native:open({entry.node},'ǰ��');app.native:select(entry.node) else app:message('��ǰ�豸δ�ṩů���������') end
   end)
  end
  if not Device.hasLightSensor or not Device:hasLightSensor() then return true end
  local toggle=function() View.toggle(app) end
  row('�Զ�����',nil,toggle);m.rows[#m.rows].checked=light.config.enabled;m.rows[#m.rows].checkmark_callback=toggle
  if light.config.enabled then value(light:statusText()) end
  row('�Զ���������',nil,go('auto_light'));resume();return true
 end
 m.subtitle=light:isDark() and '��ɫģʽ' or 'ǳɫģʽ'
 if route.id=='auto_light_memory' then
  row('��ס�ֶ�����',nil,function() action(function() return light:setLearning(not light.config.learning) end) end);m.rows[#m.rows].checked=light.config.learning
  row('�Ѽ�ס�Ļ���',nil,function()
   local lines={};for _,p in ipairs(light:profile().memories) do lines[#lines+1]=string.format('%.1f lux��%d ��',p.lux,p.level) end
   app:message(#lines>0 and table.concat(lines,'\n') or '��û�м��䡣�ֶ��������ȶ� 3 �룬���ס��ǰ�����µ����ȡ�')
  end);value(#light:profile().memories..' ��')
  if #light:profile().memories>0 then row('������ȼ���',nil,function()
   app:confirm('�����ǰģʽ�����ȼ��䣿���������������ú���һģʽ�ļ���ᱣ����',function() action(function() return light:clearMemory() end) end)
  end) end
  return true
 end
 if route.id=='auto_light_status' then
  row('��ǰ״̬',nil,function() app:message(light:diagnosticText()) end);value(light:statusText())
  row('��⵱ǰ����',nil,function() light:checkNow();app:render();app:message(light:diagnosticText()) end)
  value(light.available and light.lux and string.format('%.1f lux',light.lux) or '������')
  resume();return true
 end
 if route.id=='auto_light_threshold' then
  m.help=function() app:message('�����նȴﵽ�����ֵʱ��ʹ�á����������ȡ�����ֵԽ�ߣ����������б��������ʱ��Խ����\n����ѡԤ�裬��������Ϊ�㹻�����Ļ����е㡰ʹ�õ�ǰ��������') end
  for _,entry in ipairs({{'���ڽ���',500},{'��������',1000},{'�չ⻷��',10000}}) do
   local amount=entry[2]
   row(entry[1],nil,function() action(function() return light:setCurve('threshold',amount) end) end);value(amount..' lux');m.rows[#m.rows].checked=light:curveOptions().threshold==amount
  end
  row('ʹ�õ�ǰ����',nil,function()
   local ok,why=light:probe();if not ok then app:message(why);return end
   action(function() return light:setCurve('threshold',math.floor(light.lux+.5)) end)
  end)
  row('�Զ����ն�',nil,function()
   app.adapter:promptText('����������׼��100�C200000 lux��',tostring(light:curveOptions().threshold),function(text)
    return action(function() return light:setCurve('threshold',tonumber(text)) end)
   end,{keep_on_error=true,input_type='number'})
  end);value(light:curveOptions().threshold..' lux');return true
 end
 row('��������',nil,function() View.calibrate(app,false) end);value(light:anchor() and (light:anchor()..' ��') or '��δ����')
 row('����������',nil,function() View.calibrate(app,false,'daylight') end);value(light:curveOptions().daylight==light.lo and '�ص�' or light:curveOptions().daylight..' ��')
 row('����������׼',nil,go('auto_light_threshold'));value(light:curveOptions().threshold..' lux')
 row('���ȼ���',nil,go('auto_light_memory'));value(light.config.learning and '����' or '�ر�')
 row('״̬����',nil,go('auto_light_status'))
 return true
end
return View
