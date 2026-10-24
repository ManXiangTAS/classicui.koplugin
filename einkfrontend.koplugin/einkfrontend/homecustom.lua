-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Layout=require("einkfrontend/homelayout")
local Editor={}
function Editor.render(app,route,model,row,go)
 local layout=app.home_layout;local config=layout.config
 local function save(fn)
  local ok,why=layout:change(fn);if not ok then app:message(why) end;app:render()
 end
 if route.id=="home_customize" then
  model.title="�Զ�����ҳ";model.subtitle=""
  if layout.error then row("��ҳ�����쳣","ԭ�ļ���������ָ�Ĭ�ϲ��ֺ��ٱ༭") end
  row("Ԥ����ҳ",nil,function() app:open("home") end)
  row("������ࣺ"..(config.spacing=="compact" and "����" or "��׼"),nil,function()
   save(function(c) c.spacing=c.spacing=="compact" and "standard" or "compact" end)
  end)
  for i,widget in ipairs(config.widgets) do
   row(i..". "..Layout.by_id[widget.id].name,(widget.enabled and "��ʾ" or "����").." �� "..(widget.span==2 and "����" or "����"),go("home_widget",widget.id))
  end
  row("�ָ�Ĭ�ϲ���",nil,function()
   app:confirm("�ָ�Ĭ����ҳ���֣��������Զ����������ݡ�",function()
    local ok,why=layout:resetLayout();if not ok then app:message(why) end;app:render()
   end)
  end)
 elseif route.id=="home_widget" then
  local id=route.param;local widget,index=layout:find(id);assert(widget,"��ҳ����������")
  model.title=Layout.by_id[id].name;model.subtitle=""
  row("��ʾ������"..(widget.enabled and "����" or "�ر�"),nil,function()
   save(function(c) layout:find(id,c).enabled=not widget.enabled end)
  end)
  row("���ȣ�"..(widget.span==2 and "����" or "����"),nil,function()
   save(function(c) layout:find(id,c).span=widget.span==2 and 1 or 2 end)
  end)
  row("����",nil,index>1 and function()
   local ok,why=layout:move(id,-1);if not ok then app:message(why) end;app:render()
  end or nil)
  row("����",nil,index<#config.widgets and function()
   local ok,why=layout:move(id,1);if not ok then app:message(why) end;app:render()
  end or nil)
  if id=="reading_return" then
   row("����Ͷ��",nil,function() require('einkfrontend/bookvalue').promptInvestment(app) end)
   row("�鿴�Ķ��ر�",nil,go("reading_return"))
  elseif id=="heatmap" then
   row("��ʾ��Χ��"..config.heatmap_weeks.." ��",nil,function()
    save(function(c) c.heatmap_weeks=({[6]=12,[12]=24,[24]=6})[c.heatmap_weeks] end)
   end)
  elseif id=="daily_goal" then
   row("ÿ��Ŀ�꣺"..config.daily_goal_minutes.." ����",nil,function()
    app.adapter:promptText("ÿ���Ķ�Ŀ�꣨1��1440���ӣ�",tostring(config.daily_goal_minutes),function(text)
     local ok,why=layout:change(function(c) c.daily_goal_minutes=tonumber(text) end)
     if ok then app:render() else app:message(why) end
     return ok
    end,{keep_on_error=true})
   end)
  elseif id=="recent" or id=="tbr" then
   local key=id=="tbr" and "tbr_count" or "recent_count"
   row("���������"..config[key].." ��",nil,function()
    save(function(c) c[key]=c[key]==3 and 5 or 3 end)
   end)
  elseif id=="quote" then
   row("�༭����",nil,function()
    app.adapter:promptText("�༭���ԣ�ÿ��һ�������ģ�������",config.quote_text,function(text)
     save(function(c) c.quote_text=text;c.quote_index=1 end)
    end,{multiline=true})
   end)
   row("��һ������",nil,function()
    local ok,why=layout:nextQuote();if not ok then app:message(why) end;app:render()
   end)
   row("�ָ�Ĭ������",nil,function()
    app:confirm("���Զ��������滻ΪĬ�����ݣ�",function()
     save(function(c) c.quote_text=Layout.defaults().quote_text;c.quote_index=1 end)
    end)
   end)
  end

 else return false end
 model.help=function() app:message("��ҳ�޸Ļ��Զ����棬������ҳ����Ч���������ڵİ��в���������ʾ��\n����ͼ���л� 6��12��24 �ܣ���ɫ��ʾ�Ķ����ã���ܿ��л� 3 ���� 5 ����\n����ÿ��һ�������������֮���ã��ָ��������ҳ���Կ��л���һ����\n�Ķ��������� KOReader ͳ�ƣ�ҳ�ΰ�ÿ��ÿ����Ĳ��ظ�ҳ������") end
 model.settings=true;return true
end
return Editor
