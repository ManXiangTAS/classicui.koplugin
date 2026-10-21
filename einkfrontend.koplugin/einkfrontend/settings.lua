-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Native=require("einkfrontend/native")
local Settings={}
function Settings.render(app,route,m,row,go)
 local id=route.id
 if id=="settings" then
  m.title="设置";m.subtitle="";m.settings=true
  app.native:refresh()
  local icons={reading="reading",display="appbar.contrast",input="appbar.navigation",library="appbar.filebrowser",lookup="appbar.search",network="wifi",plugins="plugins",device="device",misc="misc",maintenance="maintenance"}
  for _,c in ipairs(app.native.categories) do
   row(c[2],"",go("catalog_category",c[1]));m.rows[#m.rows].icon=icons[c[1]]
  end
 elseif id=="catalog_category" then
  if not app.native.catalog.roots then app.native:refresh() end
  m.title=route.param;m.subtitle="";m.settings=true
  for _,list in ipairs({app.native.categories,Native.extra_categories}) do for _,c in ipairs(list) do if c[1]==route.param then m.title=c[2] end end end
  if route.param=="typography" then
   m.title="高级排版"
   row("原生页面配置","高级页面控件兼容入口",function() app:openNativeConfig() end)
  end
  if route.param=="library" or route.param=="network" then row("传书与书库",nil,go("transfer_settings")) end
  local nodes=app.native.catalog.roots[route.param] or {}
  if route.param=="input" and app.pagepress then row("翻页键",nil,go("pagepress_settings")) end
  if route.param=="device" or route.param=="network" then
   row("时间与日期",nil,go("clock_settings"))
  end
  if route.param=="maintenance" then
   row("前端开关与恢复",nil,go("frontend"))
   row("原生界面设置",nil,go("catalog_category","compatibility"))
   row("诊断与高级工具",nil,go("catalog_category","diagnostics"))
   row("退出与设备操作",nil,go("catalog_category","power"))
   row("关于",nil,go("about"))
  end
  for _,node in ipairs(nodes) do
   if node.id~="time" then
   row(Native.text(node),"",function() app.native:open(nodes,m.title);app.native:select(node) end)
   local r=m.rows[#m.rows];r.enabled=Native.enabled(node);r.checked=Native.checked(node)
   r.hold_callback=function() app.native:open(nodes,m.title);app.native:select(node,true) end
   if node.checkmark_callback then r.checkmark_callback=function() app.native:open(nodes,m.title);app.native:select(node,false,true) end end
   end
  end
  if #m.rows==0 then row("当前没有可用项目","") end
 elseif id=="native" then
  local host=app.native.host;m.settings=true;m.title=app.native.titles[#app.native.titles] or "设置";m.subtitle=""
  for _,node in ipairs(host and host.item_table or {}) do
   row(Native.text(node),"",function() app.native:select(node) end)
   local r=m.rows[#m.rows];r.enabled=Native.enabled(node);r.checked=Native.checked(node)
   r.hold_callback=function() app.native:select(node,true) end
   if node.checkmark_callback then r.checkmark_callback=function() app.native:select(node,false,true) end end
  end
  if #m.rows==0 then row("此页暂无可用项目","") end
 elseif id=="catalog_search" then
  m.settings=true;m.title="搜索设置";m.subtitle=route.param.query
  for _,result in ipairs(route.param.results) do
   if result.route then row(result.title,result.path,go(result.route,result.param))
   else row(Native.text(result.node),result.path,function()
    app.native:open({result.node},Native.text(result.node));app.native:select(result.node)
   end)
   m.rows[#m.rows].enabled=Native.enabled(result.node)
   end
  end
  if #m.rows==0 then row("没有匹配的设置","") end
 elseif id=="frontend" or id=="about" or id=="path" or id=="setting_search" or id=="setting" or id=="section" or id=="progress" then
  m.settings=true;return false
 else return false end
 return true
end
function Settings.search(app,query)
 app.native:refresh()
 local results={};local needle=query:match("^%s*(.-)%s*$"):lower()
 local function match(text) return tostring(text):lower():find(needle,1,true) end
 local function add(title,path,route,param,keywords)
  if match(title.." "..(keywords or "")) then results[#results+1]={title=title,path=path,route=route,param=param} end
 end
 add("传书与书库","书库与文件","transfer_settings",nil,"上传 传输 书籍 文件 目录 文件夹 路径 网页 Wi-Fi 重排 EPUB")
 add("时间与日期","设备与系统","clock_settings",nil,"网络同步时间 校时 时区 夏令时 timezone ntp")
 if app.pagepress then add("翻页键","触控与按键","pagepress_settings",nil,"PagePress 压感 按压力度 灵敏度 震动 振动 反馈 翻页 按键 Voyage") end
 add("前端开关与恢复","维护与恢复","frontend",nil,"停用 启动 接管 原生兼容")
 for _,c in ipairs(Native.extra_categories) do add(c[2],"维护与恢复","catalog_category",c[1]) end
 for _,def in ipairs(require("einkfrontend/homelayout").registry) do add(def.name,"主页 › 编辑主页","home_customize",def.id,"部件 布局") end
 for _,item in ipairs(require("einkfrontend/registry")) do
  if match(item.title.." "..(item.help or "")) then results[#results+1]={title=item.title,path=item.section=="files" and "维护与恢复 › 原生界面设置" or "阅读 › 排版",route="setting",param=item.id} end
 end
 local budget=2500;local seen={}
 local function walk(nodes,path,depth)
  if type(nodes)~="table" or depth>10 or budget<=0 then return end
  for _,node in ipairs(nodes) do if type(node)=="table" and not seen[node] and budget>0 then
   seen[node]=true;budget=budget-1;local title=Native.text(node)
   if match(title) then results[#results+1]={node=node,path=path} end
   local children=node.sub_item_table
   if not children and type(node.sub_item_table_func)=="function" then
    local ok,value=pcall(node.sub_item_table_func);if ok and type(value)=="table" then children=value end
   end
   if children then walk(children,path.." › "..title,depth+1) end
  end end
 end
 for _,list in ipairs({app.native.categories,Native.extra_categories,{{"typography","高级排版"}}}) do
  for _,c in ipairs(list) do walk(app.native.catalog.roots[c[1]] or {},c[2],0) end
 end
 app:go("catalog_search",{query=query,results=results})
end
return Settings
