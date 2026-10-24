-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Native=require("einkfrontend/native")
local Settings={}
function Settings.render(app,route,m,row,go)
 local id=route.id
 if id=="settings" then
  m.title="����";m.subtitle="";m.settings=true
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
   m.title="�߼��Ű�"
   row("ԭ��ҳ������",nil,function() app:openNativeConfig() end)
  end
  if route.param=="library" or route.param=="network" then row("���������",nil,go("transfer_settings")) end
  if route.param=="library" then row("������ɾ���鼮������",nil,function() require('einkfrontend/maintenancesettings').open(app) end) end
  if route.param=="display" then row("ǰ��",nil,go("frontlight_settings")) end
  local nodes=app.native.catalog.roots[route.param] or {}
  m.content_key=nodes
  if route.param=="input" and app.pagepress then row("��ҳ��",nil,go("pagepress_settings")) end
  if route.param=="input" then row("�������뷨",nil,go("input_method")) end
  if route.param=="device" or route.param=="network" then
   row("ʱ��������",nil,go("clock_settings"))
  end
  if route.param=="maintenance" then
   row("ǰ�˿�����ָ�",nil,go("frontend"))
   row("ԭ����������",nil,go("catalog_category","compatibility"))
   row("�����߼�����",nil,go("catalog_category","diagnostics"))
   row("�˳����豸����",nil,go("catalog_category","power"))
   row("����",nil,go("about"))
  end
  for _,node in ipairs(nodes) do
   if node.id~="time" and node.id~="frontlight" then
   row(Native.text(node),"",function() app.native:open(nodes,m.title);app.native:select(node) end)
   local r=m.rows[#m.rows];r.enabled=Native.enabled(node);r.checked=Native.checked(node)
   r.hold_callback=function() app.native:open(nodes,m.title);app.native:select(node,true) end
   if node.checkmark_callback then r.checkmark_callback=function() app.native:open(nodes,m.title);app.native:select(node,false,true) end end
   end
  end
  if #m.rows==0 then row("��ǰû�п�����Ŀ","") end
 elseif id=="native" then
  local host=app.native.host;m.settings=true;m.title=app.native.titles[#app.native.titles] or "����";m.subtitle=""
  m.content_key=host and host.item_table
  for _,node in ipairs(host and host.item_table or {}) do
   row(Native.text(node),"",function() app.native:select(node) end)
   local r=m.rows[#m.rows];r.enabled=Native.enabled(node);r.checked=Native.checked(node)
   r.hold_callback=function() app.native:select(node,true) end
   if node.checkmark_callback then r.checkmark_callback=function() app.native:select(node,false,true) end end
  end
  if #m.rows==0 then row("��ҳ���޿�����Ŀ","") end
 elseif id=="catalog_search" then
  m.settings=true;m.title="��������";m.subtitle=route.param.query
  for _,result in ipairs(route.param.results) do
   if result.route then row(result.title,result.path,go(result.route,result.param))
   else row(Native.text(result.node),result.path,function()
    app.native:open({result.node},Native.text(result.node));app.native:select(result.node)
   end)
   m.rows[#m.rows].enabled=Native.enabled(result.node)
   end
  end
  if #m.rows==0 then row("û��ƥ�������","") end
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
 add("���������","������ļ�","transfer_settings",nil,"�ϴ� ���� �鼮 �ļ� Ŀ¼ �ļ��� ·�� ��ҳ Wi-Fi EPUB")
 add("ǰ��","��ʾ��ˢ��","frontlight_settings",nil,"�Զ�ǰ�� �Զ����� �Զ����� ��� ������ �ն� ���� ����Ӧ ���� lux ���� ɫ�� ů��")
 add("�Զ���������","��ʾ��ˢ�� ? ǰ��","auto_light",nil,"�Զ����� ���� ���� ���� �չ� ����")
 add("����������׼","ǰ�� ? �Զ���������","auto_light_threshold",nil,"�ն� ��ֵ lux �չ�")
 add("���ȼ���","ǰ�� ? �Զ���������","auto_light_memory",nil,"ѧϰ �ֶ� ƫ��")
 add("������ɾ���鼮������","������ļ�","library_cleanup",nil,"ɾ���鼮 ���� ���� ���� ʧЧ sdr ����")
 add("�Ķ��ر�","��ҳ","reading_return",nil,"�ر� ���� �豸 Ͷ�� ��� ��ֵ �۸�")
 add("ʱ��������","�豸��ϵͳ","clock_settings",nil,"����ͬ��ʱ�� Уʱ ʱ�� ����ʱ timezone ntp")
 add("�������뷨","�����밴��","input_method",nil,"ƴ�� ���� ���� ��ѡ�� ���� pinyin ��Ӣ Ӣ�� ���� �л� EN")
 if app.pagepress then add("��ҳ��","�����밴��","pagepress_settings",nil,"PagePress ѹ�� ��ѹ���� ������ �� �� ���� ��ҳ ���� Voyage") end
 add("ǰ�˿�����ָ�","ά����ָ�","frontend",nil,"ͣ�� ���� �ӹ� ԭ������")
 for _,c in ipairs(Native.extra_categories) do add(c[2],"ά����ָ�","catalog_category",c[1]) end
 for _,def in ipairs(require("einkfrontend/homelayout").registry) do add(def.name,"��ҳ ? �༭��ҳ","home_customize",def.id,"���� ����") end
 for _,item in ipairs(require("einkfrontend/registry")) do
  if match(item.title.." "..(item.help or "")) then results[#results+1]={title=item.title,path=item.section=="files" and "ά����ָ� ? ԭ����������" or "�Ķ� ? �Ű�",route="setting",param=item.id} end
 end
 local budget=2500;local seen={};local deferred={}
 local function walk(nodes,path,depth)
  if type(nodes)~="table" or depth>10 or budget<=0 then return end
  for _,node in ipairs(nodes) do if type(node)=="table" and not seen[node] and budget>0 then
   seen[node]=true;budget=budget-1;local title=Native.text(node)
   if node.id~='frontlight' and match(title) then results[#results+1]={node=node,path=path} end
   local children=node.sub_item_table
   if children then walk(children,path.." ? "..title,depth+1)
   elseif type(node.sub_item_table_func)=="function" then
    deferred[#deferred+1]={node=node,path=path.." ? "..title,depth=depth+1}
   end
  end end
 end
 for _,list in ipairs({app.native.categories,Native.extra_categories,{{"typography","�߼��Ű�"}}}) do
  for _,c in ipairs(list) do walk(app.native.catalog.roots[c[1]] or {},c[2],0) end
 end
 -- Search registered static choices before potentially huge generated font/file lists.
 local index=1
 while index<=#deferred and budget>0 do
  local entry=deferred[index];index=index+1
  if entry.depth<=10 then
   local ok,children=pcall(entry.node.sub_item_table_func)
   if ok and type(children)=="table" then walk(children,entry.path,entry.depth) end
  end
 end
 app:go("catalog_search",{query=query,results=results})
end
return Settings
