-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local View={}
local labels={enabled='启用翻页键',pressure='按压力度',haptic='震动反馈',gain='反馈强度'}
local gains={'弱','中','强','最强'}
function View.render(app,route,m,row,go)
 if route.id~='pagepress_settings' and route.id~='pagepress_choice' then return false end
 m.settings=true;m.title='翻页键';m.subtitle=''
 local service=app.pagepress
 if not service then row('当前设备不支持翻页键');return true end
 local function choose(key,value)
  local ok,why=service:change(key,value)
  if ok then app:back() else app:message(why) end
 end
 if route.id=='pagepress_settings' then
  for _,key in ipairs({'enabled','pressure','haptic','gain'}) do
   local k=key;local v,why=service:read(k)
   row(labels[k],nil,function()
    if v==nil then app:message(why) else app:go('pagepress_choice',k) end
   end)
   local r=m.rows[#m.rows];r.value_width=155
   if v==nil then r.value='不可用'
   elseif k=='enabled' then r.value=(v[1]==1 and v[2]==1) and '开' or (v[1]==0 and v[2]==0) and '关' or '部分开启'
   elseif k=='haptic' then r.value=v and '开' or '关'
   elseif k=='gain' then r.value=gains[v+1]
   else r.value=tostring(v) end
   if service.errors[k] then row('检查'..labels[k],nil,function() app:message(service.errors[k]) end) end
  end
  row('反转翻页方向',nil,function()
   require('ui/uimanager'):broadcastEvent(require('ui/event'):new('SwapPageTurnButtons'));app:render()
  end);m.rows[#m.rows].checked=G_reader_settings:isTrue('input_invert_page_turn_keys')
  row('关于翻页键设置',nil,function()
   app:message('按压力度越小越容易触发。100 / 150 / 200 是墨页提供的预设。\n设置在 KOReader 内生效，休眠或退出墨页时尝试恢复进入前的 Kindle 设置；唤醒后重新应用。\n左右两侧按键共用设置。真机效果待验证。')
  end)
 else
  local key=route.param
  if not labels[key] then row('未知设置');return true end
  m.title=labels[key]
  row('沿用 Kindle 设置',nil,function() choose(key,nil) end);m.rows[#m.rows].checked=service.config[key]==nil
  local choices
  if key=='pressure' then choices={{'轻按（100）',100},{'标准（150）',150},{'重按（200）',200}}
  elseif key=='gain' then choices={{gains[1],0},{gains[2],1},{gains[3],2},{gains[4],3}}
  else choices={{'开',true},{'关',false}} end
  for _,option in ipairs(choices) do
   local value=option[2];row(option[1],nil,function() choose(key,value) end)
   m.rows[#m.rows].checked=service.config[key]==value
  end
 end
 return true
end
return View
