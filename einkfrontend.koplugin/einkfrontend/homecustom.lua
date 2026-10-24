-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Layout=require("einkfrontend/homelayout")
local Editor={}
function Editor.render(app,route,model,row,go)
 local layout=app.home_layout;local config=layout.config
 local function save(fn)
  local ok,why=layout:change(fn);if not ok then app:message(why) end;app:render()
 end
 if route.id=="home_customize" then
  model.title="自定义主页";model.subtitle="选择部件，调整显示、顺序和宽度"
  if layout.error then row("主页配置异常","原文件保留；请恢复默认布局后再编辑") end
  row("预览主页","查看已保存的部件和布局",function() app:open("home") end)
  row("部件间距："..(config.spacing=="compact" and "紧凑" or "标准"),"轻点切换",function()
   save(function(c) c.spacing=c.spacing=="compact" and "standard" or "compact" end)
  end)
  for i,widget in ipairs(config.widgets) do
   row(i..". "..Layout.by_id[widget.id].name,(widget.enabled and "显示" or "隐藏").." · "..(widget.span==2 and "整行" or "半行"),go("home_widget",widget.id))
  end
  row("恢复默认布局","恢复最近在读、阅读数据和书库概览",function()
   app:confirm("恢复默认主页布局？将保留自定义名言内容。",function()
    local ok,why=layout:resetLayout();if not ok then app:message(why) end;app:render()
   end)
  end)
 elseif route.id=="home_widget" then
  local id=route.param;local widget,index=layout:find(id);assert(widget,"主页部件不存在")
  model.title=Layout.by_id[id].name;model.subtitle="修改立即保存，返回主页后生效"
  row("显示部件："..(widget.enabled and "开启" or "关闭"),"关闭后仍可在编辑器中重新添加",function()
   save(function(c) layout:find(id,c).enabled=not widget.enabled end)
  end)
  row("宽度："..(widget.span==2 and "整行" or "半行"),"相邻的两个半行部件并排显示",function()
   save(function(c) layout:find(id,c).span=widget.span==2 and 1 or 2 end)
  end)
  row("上移",index==1 and "已在最前" or "移到前一个部件之前",index>1 and function()
   local ok,why=layout:move(id,-1);if not ok then app:message(why) end;app:render()
  end or nil)
  row("下移",index==#config.widgets and "已在最后" or "移到后一个部件之后",index<#config.widgets and function()
   local ok,why=layout:move(id,1);if not ok then app:message(why) end;app:render()
  end or nil)
  if id=="reading_return" then
   row("购机投入",nil,function() require('einkfrontend/bookvalue').promptInvestment(app) end)
   row("查看阅读回报",nil,go("reading_return"))
  elseif id=="heatmap" then
   row("显示范围："..config.heatmap_weeks.." 周","轻点切换6、12或24周；深色表示阅读更久",function()
    save(function(c) c.heatmap_weeks=({[6]=12,[12]=24,[24]=6})[c.heatmap_weeks] end)
   end)
  elseif id=="daily_goal" then
   row("每日目标："..config.daily_goal_minutes.." 分钟","轻点修改；只保存到主页配置",function()
    app.adapter:promptText("每日阅读目标（1—1440分钟）",tostring(config.daily_goal_minutes),function(text)
     local ok,why=layout:change(function(c) c.daily_goal_minutes=tonumber(text) end)
     if ok then app:render() else app:message(why) end
     return ok
    end,{keep_on_error=true})
   end)
  elseif id=="recent" or id=="tbr" then
   local key=id=="tbr" and "tbr_count" or "recent_count"
   row("书架数量："..config[key].." 本","仅调整本书架；轻点切换3本或5本",function()
    save(function(c) c[key]=c[key]==3 and 5 or 3 end)
   end)
  elseif id=="quote" then
   row("编辑名言","每行一条；正文与出处之间用｜分隔",function()
    app.adapter:promptText("编辑名言",config.quote_text,function(text)
     save(function(c) c.quote_text=text;c.quote_index=1 end)
    end,{multiline=true})
   end)
   row("下一条名言","也可在主页轻点名言部件切换",function()
    local ok,why=layout:nextQuote();if not ok then app:message(why) end;app:render()
   end)
   row("恢复默认名言","替换自定义内容，布局保持不变",function()
    app:confirm("将自定义名言替换为默认内容？",function()
     save(function(c) c.quote_text=Layout.defaults().quote_text;c.quote_index=1 end)
    end)
   end)
  end
  if Layout.by_id[id].stats then row("数据说明","读取KOReader统计；阅读页次按每天每本书的不重复页计数") end
 else return false end
 model.settings=true;return true
end
return Editor
