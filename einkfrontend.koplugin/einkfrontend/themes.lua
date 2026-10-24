-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local LuaSettings=require("luasettings")
local Copy=require("einkfrontend/catalog").copy
local Equal=require("einkfrontend/adapter").equal
local Themes={};Themes.__index=Themes
Themes.instances=setmetatable({},{__mode='k'})
local MAX_COUNTER=9007199254740990
local function counter(value) return type(value)=='number' and value==value and value%1==0 and value>=0 and value<=MAX_COUNTER end
function Themes.new()
 local settings=LuaSettings:open(require("datastorage"):getSettingsDir().."/einkfrontend-themes.lua")
 local self=setmetatable({settings=settings,records=Copy(settings:readSetting("themes") or {}),counter=settings:readSetting("counter") or 0},Themes)
 local damaged=type(self.records)~="table"
 local highest,ids=0,{}
 if not damaged then
  for key in pairs(self.records) do
   if type(key)~="number" or key%1~=0 or key<1 or key>#self.records then damaged=true;break end
  end
  for _,t in ipairs(self.records) do
   if type(t)~="table" or type(t.id)~="string" or t.id=="" or ids[t.id] or type(t.name)~="string" or type(t.values)~="table" then damaged=true;break end
   ids[t.id]=true
   local n=tonumber(t.id:match("^t(%d+)$"))
   if n then if not counter(n) then damaged=true;break end;highest=math.max(highest,n) end
  end
 end
 if damaged then self.error="主题库格式不正确，保留原文件";self.records={} end
 -- Repair only the in-memory sequence. Loading never replaces the saved data.
 self.counter=math.max(counter(self.counter) and self.counter or 0,highest)
 Themes.instances[self]=true
 return self
end
function Themes:find(id) for _,t in ipairs(self.records) do if t.id==id then return t end end end
function Themes:name(name,id)
 assert(type(name)=="string","请输入主题名称")
 name=name:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
 local count=0;for _ in name:gmatch("[^\128-\191]") do count=count+1 end
 assert(count>=1 and count<=24 and not name:find("%c"),"主题名称需要1—24个字符")
 for _,t in ipairs(self.records) do assert(t.id==id or t.name:lower()~=name:lower(),"已有同名主题，请换一个名称") end
 return name
end
function Themes:commit(next_records,next_counter)
 assert(not self.error,self.error)
 local previous=Copy(self.settings.data)
 local ok,err=pcall(function()
  self.settings:saveSetting("version",2);self.settings:saveSetting("themes",Copy(next_records));self.settings:saveSetting("counter",next_counter or self.counter);assert(self.settings:flush()~=false,"主题未能写入，请检查存储空间与权限")
  local disk=LuaSettings:open(self.settings.file)
  assert(Equal(disk:readSetting("themes"),next_records),"主题未能写入，请检查存储空间与权限")
  assert(disk:readSetting("version")==2 and disk:readSetting("counter")==(next_counter or self.counter),"主题编号未能保存")
 end)
 if not ok then
  self.settings.data=previous;pcall(self.settings.flush,self.settings)
  return false,tostring(err)
 end
 self.records=Copy(next_records);self.counter=next_counter or self.counter
 for instance in pairs(Themes.instances) do
  if instance~=self and instance.settings.file==self.settings.file then
   instance.settings.data=Copy(self.settings.data);instance.records=Copy(self.records);instance.counter=self.counter;instance.error=nil
  end
 end
 return true
end
function Themes:create(name,values)
 if self.error then return false,self.error end
 if self.counter>=MAX_COUNTER then return false,"主题编号已达上限，原数据已保留" end
 local ok,result=pcall(self.name,self,name);if not ok then return false,result end
 local records=Copy(self.records);local id="t"..string.format("%.0f",self.counter+1)
 records[#records+1]={id=id,name=result,kind="cre",schema=2,values=Copy(values)}
 local saved,why=self:commit(records,self.counter+1);return saved,saved and id or why
end
function Themes:rename(id,name)
 local t=self:find(id);if not t then return false,"主题已不存在" end
 local ok,result=pcall(self.name,self,name,id);if not ok then return false,result end
 local records=Copy(self.records);for _,r in ipairs(records) do if r.id==id then r.name=result end end
 return self:commit(records)
end
function Themes:update(id,values)
 local records=Copy(self.records);assert(self:find(id),"主题已不存在")
 for _,r in ipairs(records) do if r.id==id then r.values=Copy(values);r.schema=2 end end
 return self:commit(records)
end
function Themes:delete(id)
 local records={};for _,r in ipairs(self.records) do if r.id~=id then records[#records+1]=Copy(r) end end
 return self:commit(records)
end
return Themes
