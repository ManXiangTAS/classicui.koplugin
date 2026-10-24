-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Stable widget ids and verified settings; no dependency on another frontend.
local Copy=require("einkfrontend/catalog").copy
local Equal=require("einkfrontend/adapter").equal
local LuaSettings=require("luasettings")
local Layout={};Layout.__index=Layout
Layout.instances=setmetatable({},{__mode='k'})
Layout.registry={
 {id="currently",name="����ڶ�",height=244,enabled=true},
 {id="reading_stats",name="�����Ķ�����",height=134,enabled=true},
 {id="overview",name="������",height=214,enabled=true},
 {id="recent",name="����Ķ����",height=304,enabled=false},
 {id="quote",name="��������",height=188,enabled=false},
 {id="clock",name="ʱ��������",height=118,enabled=false},
 {id="tbr",name="�������",height=304,enabled=false},
 {id="heatmap",name="�Ķ�����ͼ",height=244,enabled=false,stats=true},
 {id="stats_table",name="�Ķ�ͳ�Ʊ�",height=284,enabled=false,stats=true},
 {id="weekly",name="�������Ķ�",height=244,enabled=false,stats=true},
 {id="streak",name="�Ķ�����",height=214,enabled=false,stats=true},
 {id="daypart",name="�Ķ�ʱ�ηֲ�",height=244,enabled=false,stats=true},
 {id="daily_goal",name="ÿ���Ķ�Ŀ��",height=188,enabled=false,stats=true},
 {id="reading_return",name="�Ķ��ر�",height=244,enabled=false},
}
Layout.by_id={};for _,def in ipairs(Layout.registry) do Layout.by_id[def.id]=def end
function Layout.defaults()
 local out={version=2,spacing="standard",recent_count=3,tbr_count=3,quote_index=1,heatmap_weeks=12,daily_goal_minutes=30,
  quote_text="ѧ��ʱϰ֮������˵�����������ѧ����\n֪֮�߲����֮�ߣ���֮�߲�����֮�ߡ��������ӺҲ��\n�����Ͳ���������ǧ��������ӡ�Ȱѧ��",widgets={}}
 for _,def in ipairs(Layout.registry) do out.widgets[#out.widgets+1]={id=def.id,enabled=def.enabled,span=2} end
 return out
end
function Layout.quotes(text)
 local out={}
 for line in text:gmatch("[^\r\n]+") do
  line=line:match("^%s*(.-)%s*$")
  if line~="" then
   assert(#line<=1200 and #out<50,"ÿ�����Բ��ܳ���1200�ֽڣ����50��")
   local q,a=line:match("^(.-)��(.*)$")
   q=(q or line):match("^%s*(.-)%s*$");assert(q~="","�������Ĳ���Ϊ��")
   out[#out+1]={text=q,author=a and a:match("^%s*(.-)%s*$") or ""}
  end
 end
 return out
end
function Layout.validate(config)
 assert(type(config)=="table" and config.version==2 and type(config.widgets)=="table","��ҳ���ָ�ʽ����ȷ")
 assert(config.heatmap_weeks==6 or config.heatmap_weeks==12 or config.heatmap_weeks==24,"����ͼ֧��6��12��24��")
 assert(type(config.daily_goal_minutes)=="number" and config.daily_goal_minutes%1==0 and config.daily_goal_minutes>=1 and config.daily_goal_minutes<=1440,"ÿ��Ŀ����Ϊ1��1440����")
 assert(config.spacing=="standard" or config.spacing=="compact","��ѡ���׼����ռ��")
 assert(config.recent_count==3 or config.recent_count==5,"����Ķ�������֧��3����5��")
 assert(config.tbr_count==3 or config.tbr_count==5,"����������֧��3����5��")
 assert(type(config.quote_text)=="string" and #config.quote_text<=16000,"�������ݹ���")
 Layout.quotes(config.quote_text)
 assert(type(config.quote_index)=="number" and config.quote_index>=1 and config.quote_index%1==0,"����λ�ò���ȷ")
 local seen={}
 for _,widget in ipairs(config.widgets) do
  assert(type(widget)=="table" and Layout.by_id[widget.id] and not seen[widget.id],"��ҳ���������ڻ��ظ�")
  assert(type(widget.enabled)=="boolean" and (widget.span==1 or widget.span==2),"��ҳ�������ֲ���ȷ")
  seen[widget.id]=true
 end
 for _,def in ipairs(Layout.registry) do assert(seen[def.id],"��ҳ��������ȱʧ") end
end
function Layout.new()
 local settings=LuaSettings:open(require("datastorage"):getSettingsDir().."/einkfrontend-home.lua")
 local config=Copy(settings:readSetting("layout") or Layout.defaults())
 -- Existing v1 layouts shared a shelf count. Preserve it on both shelves until
 -- the user deliberately changes either one; loading never overwrites the file.
 if type(config)=="table" and config.tbr_count==nil then config.tbr_count=config.recent_count end
 -- Add new modules only to a complete legacy registry. Damaged files still
 -- fail validation; loading never writes or replaces the user's saved layout.
 if type(config)=="table" and config.version==1 and type(config.widgets)=="table" then
  local seen={};for _,w in ipairs(config.widgets) do if type(w)=="table" then seen[w.id]=true end end
  local complete=true;for i=1,7 do if not seen[Layout.registry[i].id] then complete=false end end
  if complete then
   config.version=2;config.heatmap_weeks=12;config.daily_goal_minutes=30
   for i=8,#Layout.registry do config.widgets[#config.widgets+1]={id=Layout.registry[i].id,enabled=false,span=2} end
  end
 end
 -- Migrate complete v2 layouts without resetting user choices.
 if type(config)=="table" and config.version==2 and type(config.widgets)=="table" and #config.widgets==13 then
  local seen={};for _,w in ipairs(config.widgets) do if type(w)=="table" then seen[w.id]=true end end
  local complete=true;for i=1,13 do if not seen[Layout.registry[i].id] then complete=false end end
  if complete then config.widgets[#config.widgets+1]={id="reading_return",enabled=false,span=2} end
 end
 local ok,why=pcall(Layout.validate,config)
 local self=setmetatable({settings=settings,config=ok and config or Layout.defaults(),error=not ok and tostring(why) or nil},Layout)
 Layout.instances[self]=true;return self
end
function Layout:find(id,config)
 for i,widget in ipairs((config or self.config).widgets) do if widget.id==id then return widget,i end end
end
function Layout:enabled(id) local widget=self:find(id);return widget and widget.enabled end
function Layout:commit(config)
 local valid,why=pcall(Layout.validate,config);if not valid then return false,tostring(why) end
 local previous=Copy(self.settings.data)
 local ok,err=pcall(function()
  self.settings:saveSetting("layout",Copy(config));self.settings:flush()
  assert(Equal(LuaSettings:open(self.settings.file):readSetting("layout"),config),"��ҳ����δ�ܱ���")
 end)
 if not ok then self.settings.data=previous;pcall(self.settings.flush,self.settings);return false,tostring(err) end
 self.config=Copy(config);self.error=nil
 for instance in pairs(Layout.instances) do
  if instance~=self and instance.settings.file==self.settings.file then
   instance.settings.data=Copy(self.settings.data);instance.config=Copy(config);instance.error=nil
  end
 end
 return true
end
function Layout:change(fn)
 if self.error then return false,"��ҳ�����𻵣�ԭ�ļ��ѱ������ɻָ�Ĭ�ϲ���" end
 local next_config=Copy(self.config);local ok,err=pcall(fn,next_config)
 if not ok then return false,tostring(err) end
 local valid,reason=pcall(Layout.validate,next_config);if not valid then return false,tostring(reason) end
 local Fit=require('einkfrontend/homefit');local size=require('device').screen:getSize()
 local fits,why=Fit.checkChange(self.config,next_config,size.w,Fit.viewport(size.h));if not fits then return false,why end
 return self:commit(next_config)
end
function Layout:move(id,delta)
 return self:change(function(config)
  local widget,index=self:find(id,config);assert(widget,"����������")
  local target=math.max(1,math.min(#config.widgets,index+delta));table.remove(config.widgets,index);table.insert(config.widgets,target,widget)
 end)
end
function Layout:nextQuote()
 return self:change(function(config) local count=#Layout.quotes(config.quote_text);config.quote_index=config.quote_index%math.max(1,count)+1 end)
end
function Layout:resetLayout()
 local defaults=Layout.defaults()
 defaults.quote_text=self.config.quote_text;defaults.quote_index=self.config.quote_index
 return self:commit(defaults)
end
function Layout.shelfCount(config,id) return id=="tbr" and config.tbr_count or config.recent_count end
return Layout
