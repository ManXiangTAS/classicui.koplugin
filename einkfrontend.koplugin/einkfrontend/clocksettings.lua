-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Clock=require('einkfrontend/clock');local View={}
function View.render(app,route,m,row,go)
 local id=route.id;if id~='clock_settings' and id~='clock_zones' and id~='clock_zone_list' then return false end
 m.settings=true
 local function choose(zone)
  local ok,why=app.clock:select(zone)
  if ok then
   local target
   for i=#app.stack,1,-1 do if app.stack[i].id=='clock_settings' then target=i;break end end
   if target then while #app.stack>target do table.remove(app.stack) end;app:render()
   else app:go('clock_settings',nil,true) end
  else app:message(why) end
 end
 if id=='clock_settings' then
  m.title='时间与日期';m.subtitle=''
  m.search_scope='clock'
  row('当前时间',nil);m.rows[#m.rows].value=os.date('%Y-%m-%d %H:%M');m.rows[#m.rows].value_width=245
  row('时区',nil,go('clock_zones'));m.rows[#m.rows].value=Clock.label(app.clock.config.zone);m.rows[#m.rows].value_width=200
  if app.clock.error then row('时区配置需修复',nil,function() app:message(app.clock.error) end) end
  local node,why=Clock.syncNode(app)
  row('立即同步时间与日期',nil,function()
   local ok,err=Clock.sync(app);if not ok then app:message(err) end
  end)
  -- Leave the action readable and actionable when unavailable so its reason
  -- is shown instead of silently hiding the feature on unsupported devices.
  row('手动时间与显示格式',nil,function()
   app.native:refresh();local entry=app.native.catalog.entries.time
   if entry then app.native:open({entry.node},'时间与日期');app.native:select(entry.node)
   else app:message('当前宿主未提供手动时间设置') end
  end)
  if not node then row('校时功能未就绪',nil,function() app:message(why) end) end
 elseif id=='clock_zones' then
  m.title='选择时区';m.subtitle='';m.search_scope='timezone'
  for index,zone in ipairs(Clock.common) do
   local selected=zone
   row(Clock.label(zone),nil,function() choose(selected) end)
   m.rows[#m.rows].checked=app.clock.config.zone==zone
   if index==1 then row('全部地区与搜索',nil,go('clock_zone_list','')) end
  end
 else
  local query=type(route.param)=='string' and route.param or ''
  m.title='全部时区';m.subtitle=query~='' and '搜索：'..query or '按英文城市名或国家代码搜索'
  row('搜索地区',query~='' and query or '例如：Shanghai、London、US',function()
   app.adapter:promptText('搜索地区 / 国家代码',query,function(text)
    route.param=text;route.page=1;route.scroll_y=0;app.screen.focus_index=1;app:render()
   end)
  end)
  local found=0
  for _,zone in ipairs(Clock.zones) do
   if (zone.id..' '..zone.label..' '..zone.country):lower():find(query:lower(),1,true) then
    local selected=zone.id;row(zone.label,zone.id..' · '..zone.country,function() choose(selected) end)
    m.rows[#m.rows].checked=app.clock.config.zone==zone.id;found=found+1
   end
  end
  if found==0 then row('没有匹配的地区','试试英文城市名或两位国家代码') end
 end
 return true
end
return View
