-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Explicit inheritance intent is separate from KOReader's cached single-book values.
local Adapter=require("einkfrontend/adapter")
local Copy=require("einkfrontend/catalog").copy
local DocSettings=require("docsettings")
local LuaSettings=require("luasettings")
local Typography={};Typography.__index=Typography
Typography.fields={"font_face","font_size","line_spacing","page_margins","embedded_css","font_hinting","font_kerning","font_gamma","font_base_weight","word_spacing","word_expansion","cjk_width_scaling","embedded_fonts"}
local function keys(id)
 if id=="page_margins" then return {"copt_h_page_margins","copt_t_page_margin","copt_b_page_margin"} end
 return {Adapter.bindings[id].key}
end
function Typography.new(adapter)
 local self=setmetatable({adapter=adapter,ui=adapter.ui},Typography)
 if self.ui.doc_settings and self.ui.font and self.ui.typeset then
  self.meta=Copy(self.ui.doc_settings:readSetting("eink_frontend_typography") or {version=1,inherit={}})
  self.meta.inherit=self.meta.inherit or {}
  local ds=self.ui.doc_settings;self.raw_flush=rawget(ds,"flush");self.original_flush=ds.flush
  self.flush_wrapper=function(this,...)
   for id,inherit in pairs(self.meta.inherit) do
    if inherit and Adapter.bindings[id] then for _,key in ipairs(keys(id)) do this:delSetting(key) end end
   end
   this:saveSetting("eink_frontend_typography",Copy(self.meta))
   return self.original_flush(this,...)
  end
  ds.flush=self.flush_wrapper
  self.raw_handle=rawget(self.ui,"handleEvent");self.original_handle=self.ui.handleEvent
  local events={onSetFont="font_face",onSetFontSize="font_size",onSetLineSpace="line_spacing",onSetPageMargins="page_margins",onSetPageHorizMargins="page_margins",onSetPageTopMargin="page_margins",onSetPageBottomMargin="page_margins",onToggleEmbeddedStyleSheet="embedded_css",onSetFontHinting="font_hinting",onSetFontKerning="font_kerning"}
  for id,b in pairs(Adapter.bindings) do if b.event then events["on"..b.event]=id end end
  self.handle_wrapper=function(this,event,...)
   local id=event and events[event.handler]
   if id and self.ready and not self.applying then self.meta.inherit[id]=nil;self.meta.theme_id=nil end
   local result=self.original_handle(this,event,...)
   -- docsettingtweak consumes DocSettingsLoad; observe completion at the UI boundary.
   if event and event.handler=="onDocSettingsLoad" then self:onLoad(event.args[1]) end
   return result
  end
  self.ui.handleEvent=self.handle_wrapper
 end
 return self
end
function Typography:available() return self.ui.font~=nil and self.ui.typeset~=nil and self.adapter:alive() end
function Typography:detach()
 local ds=self.ui.doc_settings
 if ds and ds.flush==self.flush_wrapper then ds.flush=self.raw_flush end
 if self.ui.handleEvent==self.handle_wrapper then self.ui.handleEvent=self.raw_handle end
end
function Typography:snapshot()
 assert(self:available(),"此排版主题只用于 EPUB 等流式文档")
 local out={};for _,id in ipairs(self.fields) do out[id]=Copy(self.adapter:read(id,true)) end;return out
end
function Typography:defaults()
 assert(self:available(),"请先打开流式文档")
 local cfg=require("configurable"):new();cfg:loadDefaults(require("ui/data/creoptions"))
 local out={}
 for _,id in ipairs(self.fields) do
  local b=Adapter.bindings[id]
  if id=="font_face" then out[id]=G_reader_settings:readSetting("cre_font") or self.ui.document.default_font
  elseif id=="page_margins" then out[id]={cfg.h_page_margins[1],cfg.t_page_margin,cfg.h_page_margins[2],cfg.b_page_margin}
  else out[id]=b.boolean and cfg[b.field]==1 or (not b.boolean and Copy(cfg[b.field]) or false) end
 end
 return out
end
function Typography:validate(values)
 assert(self:available(),"请先打开 EPUB 等流式文档")
 for _,id in ipairs(self.fields) do assert(values[id]~=nil,"主题缺少字段："..id);self.adapter:validate(id,values[id]) end
end
function Typography:matches(values)
 local current=self:snapshot()
 for _,id in ipairs(self.fields) do if values[id]~=nil and not Adapter.equal(values[id],current[id]) then return false end end
 return true
end
function Typography:apply(values,inherit,theme_id,intent)
 local ok,err=pcall(function()
  assert(type(values)=="table","主题格式不正确")
  -- Legacy seven-field themes preserve new adjustments until explicitly updated.
  for i=1,7 do assert(values[self.fields[i]]~=nil,"主题缺少字段："..self.fields[i]) end
  local merged=self:snapshot()
  for _,id in ipairs(self.fields) do if values[id]~=nil then merged[id]=Copy(values[id]) end end
  self:validate(merged);values=merged
 end)
 if not ok then return false,tostring(err) end
 local before,meta=self:snapshot(),Copy(self.meta)
 local function apply(v)
  for _,id in ipairs(self.fields) do
   if not Adapter.equal(self.adapter:read(id,true),v[id]) then self.adapter:_apply(id,Copy(v[id])) end
   assert(Adapter.equal(self.adapter:read(id,true),v[id]),"排版运行值不符："..id)
  end
 end
 ok,err=pcall(function()
  self.applying=true;apply(values);self.applying=false
  for _,id in ipairs(self.fields) do self.meta.inherit[id]=inherit==true or nil end
  if intent then self.meta.inherit=Copy(intent) end
  self.meta.theme_id=theme_id
  self.ui:saveSettings()
  local disk=DocSettings:open(self.ui.document.file)
  assert(Adapter.equal(disk:readSetting("eink_frontend_typography"),self.meta),"排版记录未写入")
  for _,id in ipairs(self.fields) do
   if self.meta.inherit[id] then for _,key in ipairs(keys(id)) do assert(not disk:has(key),"继承字段未清理") end
   elseif id=="page_margins" then
    local v=values[id];assert(Adapter.equal(disk:readSetting("copt_h_page_margins"),{v[1],v[3]}) and disk:readSetting("copt_t_page_margin")==v[2] and disk:readSetting("copt_b_page_margin")==v[4],"边距未写入")
   else
    local b=Adapter.bindings[id];assert(Adapter.equal(disk:readSetting(b.key),(b.boolean and (values[id] and 1 or 0) or values[id])),"排版字段未写入："..id)
   end
  end
 end)
 self.applying=false
 if ok then return true end
 local rolled,why=pcall(function() self.meta=meta;self.applying=true;apply(before);self.applying=false;self.ui:saveSettings() end)
 self.applying=false
 return false,tostring(err)..(rolled and "；本次修改已恢复" or ("；恢复失败："..tostring(why)))
end
function Typography:change(id,value)
 local values=self:snapshot();values[id]=Copy(value)
 -- Editing one field preserves inheritance for the other managed fields.
 local intent=Copy(self.meta.inherit);intent[id]=nil
 return self:apply(values,false,nil,intent)
end
function Typography:restore() return self:apply(self:defaults(),true,nil) end
function Typography:onLoad(config)
 if not self.meta then return end
 for id,inherit in pairs(self.meta.inherit) do
  if inherit and Adapter.bindings[id] then for _,key in ipairs(keys(id)) do config:delSetting(key) end end
 end
end
function Typography:onReady()
 if not self:available() then self.ready=true;return end
 local values=self:snapshot();local defaults=self:defaults();local needed=false
 for _,id in ipairs(self.fields) do if self.meta.inherit[id] then values[id]=defaults[id];needed=true end end
 if needed then
  self.applying=true
  for _,id in ipairs(self.fields) do self.adapter:_apply(id,Copy(values[id])) end
  self.applying=false
 end
 self.ready=true
end
function Typography:saveDefaults()
 local before=Copy(G_reader_settings.data);local values=self:snapshot()
 local ok,err=pcall(function()
  for _,id in ipairs(self.fields) do
   local b=Adapter.bindings[id];local v=values[id]
   if id=="page_margins" then
    G_reader_settings:saveSetting("copt_h_page_margins",{v[1],v[3]});G_reader_settings:saveSetting("copt_t_page_margin",v[2]);G_reader_settings:saveSetting("copt_b_page_margin",v[4])
   else G_reader_settings:saveSetting(b.global_key or b.key,b.boolean and (v and 1 or 0) or v) end
  end
  G_reader_settings:flush()
  local disk=LuaSettings:open(G_reader_settings.file)
  for _,id in ipairs(self.fields) do
   local b=Adapter.bindings[id]
   if id=="page_margins" then
    local v=values[id]
    assert(Adapter.equal(disk:readSetting("copt_h_page_margins"),{v[1],v[3]}) and disk:readSetting("copt_t_page_margin")==v[2] and disk:readSetting("copt_b_page_margin")==v[4],"页边距默认值未写入")
   else assert(Adapter.equal(disk:readSetting(b.global_key or b.key),(b.boolean and (values[id] and 1 or 0) or values[id])),"默认值未写入") end
  end
 end)
 if not ok then G_reader_settings.data=before;pcall(G_reader_settings.flush,G_reader_settings) end
 return ok,err
end
return Typography
