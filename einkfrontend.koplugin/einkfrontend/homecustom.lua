-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Layout=require("einkfrontend/homelayout")
local Editor={}
function Editor.render(app,route,model,row,go)
 local layout=app.home_layout;local config=layout.config
 local function save(fn)
  local ok,why=layout:change(fn);if not ok then app:message(why) end;app:render()
 end
 if route.id=="home_customize" then
  model.title="自定义主页";model.subtitle=""
  if layout.error then row("主页配置异常","原文件保留；请恢复默认布局后再编辑") end
  row("预览主页",nil,function() app:open("home") end)
  row("部件间距："..(config.spacing=="compact" and "紧凑" or "标准"),nil,function()
   save(function(c) c.spacing=c.spacing=="compact" and "standard" or "compact" end)
  end)
  for i,widget in ipairs(config.widgets) do
   row(i..". "..Layout.by_id[widget.id].name,(widget.enabled and "显示" or "隐藏").." · "..(widget.span==2 and "整行" or "半行"),go("home_widget",widget.id))
  end
  row("恢复默认布局",nil,function()
   app:confirm("恢复默认主页布局？将保留自定义名言内容。",function()
    local ok,why=layout:resetLayout();if not ok then app:message(why) end;app:render()
   end)
  end)
 elseif route.id=="home_widget" then
  local id=route.param;local widget,index=layout:find(id);assert(widget,"主页部件不存在")
  model.title=Layout.by_id[id].name;model.subtitle=""
  row("显示部件："..(widget.enabled and "开启" or "关闭"),nil,function()
   save(function(c) layout:find(id,c).enabled=not widget.enabled end)
  end)
  row("宽度："..(widget.span==2 and "整行" or "半行"),nil,function()
   save(function(c) layout:find(id,c).span=widget.span==2 and 1 or 2 end)
  end)
  row("上移",nil,index>1 and function()
   local ok,why=layout:move(id,-1);if not ok then app:message(why) end;app:render()
  end or nil)
  row("下移",nil,index<#config.widgets and function()
   local ok,why=layout:move(id,1);if not ok then app:message(why) end;app:render()
  end or nil)
  if id=="reading_return" then
   row("购机投入",nil,function() require('einkfrontend/bookvalue').promptInvestment(app) end)
   row("查看阅读回报",nil,go("reading_return"))
  elseif id=="heatmap" then
   row("显示范围："..config.heatmap_weeks.." 周",nil,function()
    save(function(c) c.heatmap_weeks=({[6]=12,[12]=24,[24]=6})[c.heatmap_weeks] end)
   end)
  elseif id=="daily_goal" then
   row("每日目标："..config.daily_goal_minutes.." 分钟",nil,function()
    app.adapter:promptText("每日阅读目标（1—1440分钟）",tostring(config.daily_goal_minutes),function(text)
     local ok,why=layout:change(function(c) c.daily_goal_minutes=tonumber(text) end)
     if ok then app:render() else app:message(why) end
     return ok
    end,{keep_on_error=true})
   end)
  elseif id=="recent" or id=="tbr" then
   local key=id=="tbr" and "tbr_count" or "recent_count"
   row("书架数量："..config[key].." 本",nil,function()
    save(function(c) c[key]=c[key]==3 and 5 or 3 end)
   end)
  elseif id=="quote" then
   row("编辑名言",nil,function()
    app.adapter:promptText("编辑名言（每行一条，正文｜出处）",config.quote_text,function(text)
     save(function(c) c.quote_text=text;c.quote_index=1 end)
    end,{multiline=true})
   end)
   row("下一条名言",nil,function()
    local ok,why=layout:nextQuote();if not ok then app:message(why) end;app:render()
   end)
   row("恢复默认名言",nil,function()
    app:confirm("将自定义名言替换为默认内容？",function()
     save(function(c) c.quote_text=Layout.defaults().quote_text;c.quote_index=1 end)
    end)
   end)
  end

 else return false end
 model.help=function() app:message("主页修改会自动保存，返回主页后生效。两个相邻的半行部件并排显示。\n热力图可切换 6、12、24 周，深色表示阅读更久；书架可切换 3 本或 5 本。\n名言每行一条，正文与出处之间用｜分隔；轻点主页名言可切换下一条。\n阅读数据来自 KOReader 统计；页次按每天每本书的不重复页计数。") end
 model.settings=true;return true
end
return Editor
