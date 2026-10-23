-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- A small, offline candidate UI over KOReader's existing Rime-derived word map.
-- No native file replacement; every input owns its composition and wrappers.
local VK=require('ui/widget/virtualkeyboard')
local UI=require('ui/uimanager')
local util=require('util')
local Geom=require('ui/geometry')
local Input=require('ui/widget/container/inputcontainer')
local Gesture=require('ui/gesturerange')
local P=require('einkfrontend/paint');local S=P.s
local M={owners=setmetatable({},{__mode='k'}),states=setmetatable({},{__mode='k'})}
local map,codes
function M.external()
 local loader=require('pluginloader')
 for _,plugin in ipairs(loader.enabled_plugins or {}) do
  local name=plugin.name or ''
  if name:find('pinyin',1,true) or name=='moon' then return name end
 end
end
function M.enabled() return G_reader_settings:nilOrTrue('eink_pinyin') and not M.external() end
local function dictionary()
 if map then return end
 map=require('ui/data/keyboardlayouts/zh_pinyin_data');codes={}
 for code in pairs(map) do codes[#codes+1]=code end;table.sort(codes)
end
function M.lookup(code)
 dictionary();local result,seen={},{}
 local function add(value)
  if type(value)=='string' then value={value} end
  for _,text in ipairs(value or {}) do if not seen[text] and #result<64 then seen[text]=true;result[#result+1]=text end end
 end
 add(map[code]);if #code<2 or #result>=64 then return result end
 local lo,hi=1,#codes+1
 while lo<hi do local mid=math.floor((lo+hi)/2);if codes[mid] and codes[mid]<code then lo=mid+1 else hi=mid end end
 for i=lo,math.min(#codes,lo+63) do
  if codes[i]:sub(1,#code)~=code then break end
  add(map[codes[i]]);if #result>=64 then break end
 end
 return result
end
local Bar=Input:extend{}
function Bar:init()
 self.dimen=Geom:new{w=self.keyboard.width,h=S(52)}
 self.ges_events={PinyinTap={Gesture:new{ges='tap',range=self.dimen}}}
end
function Bar:paintTo(bb,x,y)
 self.dimen.x=x;self.dimen.y=y;self.hits={}
 local state=self.state;local revision=state.revision;local w,h=self.dimen.w,self.dimen.h
 bb:paintRect(x,y,w,h,P.BB.COLOR_WHITE);P.rule(bb,x,y,w)
 local mode_w=S(104);local content_w=w-mode_w
 for i,mode in ipairs({'zh_CN','en'}) do
  local px=x+content_w+(i-1)*mode_w/2;local selected=state.language==mode
  if selected then bb:paintRect(px,y+S(4),mode_w/2,h-S(8),P.BB.COLOR_BLACK) end
  P.label(bb,mode=='zh_CN' and '中' or 'EN',px,y,mode_w/2,h,16,true,'center',selected and P.BB.COLOR_WHITE or P.BB.COLOR_BLACK)
  self.hits[#self.hits+1]={x=px,y=y,w=mode_w/2,h=h,id='pinyin_language_'..mode,callback=function()
   if state:live() and state.revision==revision then state:chooseLanguage(mode) end
  end}
 end
 if #state.candidates==0 then
  local hint=state.language=='en' and '英文输入' or state.code=='' and '拼音输入 · 空格选字' or '无候选 · 回车保留字母'
  P.label(bb,hint,x+S(12),y,content_w-S(24),h,14,false)
  return
 end
 local aw=S(44);local cw=(content_w-2*aw)/4;local offset=state.page*4
 P.button(self,bb,'‹',x,y,aw,h,function() state:pageBy(-1) end,{align='center',disabled=state.page==0,id='pinyin_prev'})
 for i=1,4 do
  local value=state.candidates[offset+i]
  if value then
   P.button(self,bb,value,x+aw+(i-1)*cw,y,cw,h,function() if state:live() and state.revision==revision then state:commit(value) end end,{align='center',size=18,id='pinyin_'..i})
  end
 end
 P.button(self,bb,'›',x+content_w-aw,y,aw,h,function() state:pageBy(1) end,{align='center',disabled=offset+4>=#state.candidates,id='pinyin_next'})
end
function Bar:onPinyinTap(_,ges)
 if not self.state:live() then return true end
 P.activate(self,ges and ges.pos);return true
end
local State={};State.__index=State
function State:live() return not self.closed and self.keyboard._eink_pinyin==self and self.keyboard.visible and next(M.owners)~=nil end
function State:chooseLanguage(language)
 if not self:live() or (language~='zh_CN' and language~='en') or language==self.language then return end
 -- Explicit English switching retains unfinished Latin letters verbatim.
 -- A word already selected from candidates is never rewritten.
 self:commit(nil,true)
 self.keyboard:setKeyboardLayout(language)
 G_reader_settings:saveSetting('keyboard_layout_default',language)
 G_reader_settings:flush()
end
function State:refresh()
 self.revision=(self.revision or 0)+1
 self.page=0;self.candidates=self.code~='' and M.lookup(self.code) or {}
 if self.bar then self.bar.hits={};UI:setDirty(self.keyboard,'ui',self.bar.dimen) end
end
function State:valid()
 if self.code=='' then return true end
 local box=self.box
 return box.charpos==self.finish and table.concat(box.charlist,'',self.finish-#self.code,self.finish-1)==self.code
end
function State:commit(value,raw)
 if self.closed or self.mutating or self.code=='' then return end
 if self:valid() then
  value=raw and self.code or value or self.candidates[1] or self.code
  for _=1,#self.code do table.remove(self.box.charlist,self.box.charpos-1);self.box.charpos=self.box.charpos-1 end
  self.code='';self.finish=nil;self:refresh();self:write(value)
 else self.code='';self.finish=nil;self:refresh() end
end
function State:write(text)
 self.mutating=true;local ok,why=pcall(self.add,self.box,text);self.mutating=false
 if not ok then error(why) end
end
function State:pageBy(delta)
 if not self:live() then return end
 self.page=math.max(0,math.min(math.floor(math.max(0,#self.candidates-1)/4),self.page+delta))
 self.revision=(self.revision or 0)+1
 self.bar.hits={};UI:setDirty(self.keyboard,'ui',self.bar.dimen)
end
function M.decorate(keyboard)
 local state=keyboard._eink_pinyin;if not state or state.closed then return end
 local frame=keyboard[1][1]
 state.bar=Bar:new{state=state,keyboard=keyboard}
 local group=require('ui/widget/verticalgroup'):new{align='left',state.bar,frame}
 local frame_group=require('ui/widget/container/framecontainer'):new{padding=0,margin=0,bordersize=0,group}
 keyboard[1]=require('ui/widget/container/bottomcontainer'):new{dimen=require('device').screen:getSize(),frame_group}
 -- InputDialog uses this exact dimen to avoid covering the text and buttons.
 frame_group.dimen=frame_group:getSize();keyboard.dimen=frame_group.dimen
end
function M.attach(keyboard)
 local box=keyboard.inputbox
 if not box then return end
 if keyboard.uwrap_func then keyboard.uwrap_func();keyboard.uwrap_func=nil end
 if box.readonly or box.input_type=='number' or box.input_type=='literal' or box.is_password_type or box.text_type=='password' then return end
 local state=setmetatable({keyboard=keyboard,box=box,language=keyboard:getKeyboardLayout(),code='',candidates={},page=0,wrappers={},add=box.addChars},State)
 keyboard._eink_pinyin=state;M.states[keyboard]=state
 local function wrap(name,fn,before)
  if type(box[name])=='function' then state.wrappers[#state.wrappers+1]=util.wrapMethod(box,name,fn,before) end
 end
 wrap('addChars',function(input,text)
  if state.closed or input.readonly then return state.add(input,text) end
  if not state:valid() then state.code='';state:refresh() end
  if state.language=='zh_CN' and type(text)=='string' and text:match('^[a-z]$') and #state.code<64 and not keyboard.symbolmode then
   state:write(text);state.code=state.code..text;state.finish=input.charpos;state:refresh()
  elseif text==' ' and state.code~='' then state:commit()
  elseif text=='\n' and state.code~='' then state:commit(nil,true)
  else state:commit();state:write(text) end
 end)
 wrap('delChar',function(input)
  if state.code~='' and state:valid() then
   state.mutating=true;local ok,why=pcall(input.delChar.raw_method_call,input.delChar);state.mutating=false
   if not ok then error(why) end
   state.code=state.code:sub(1,-2);state.finish=input.charpos;state:refresh()
  else state.code='';state:refresh();input.delChar:raw_method_call() end
 end)
 for _,name in ipairs({'leftChar','rightChar','upLine','downLine','goToStartOfLine','goToEndOfLine','onTapTextBox','onHoldTextBox','onSwipeTextBox','unfocus','onCloseKeyboard','getText','delWord','delToStartOfLine','delNextChar','setText'}) do
  wrap(name,nil,function() state:commit() end)
 end
 wrap('clear',nil,function() state.code='';state:refresh() end)
 wrap('onCloseWidget',nil,function() M.release(keyboard,false) end)
 keyboard.uwrap_func=function() M.release(keyboard,true) end
 M.decorate(keyboard)
end
function M.release(keyboard,commit)
 local state=keyboard._eink_pinyin;if not state then return end
 if commit then state:commit() end
 state.closed=true;state.code='';if state.bar then state.bar.hits={} end
 for i=#state.wrappers,1,-1 do state.wrappers[i]:revert() end
 keyboard._eink_pinyin=nil;M.states[keyboard]=nil
end
function M.install(owner)
 M.owners[owner]=true;if M.init_wrapper then return end
 local init,addKeys=VK.init,VK.addKeys;M.init_original=init;M.keys_original=addKeys
 M.init_wrapper=function(keyboard,...)
  init(keyboard,...)
  local language=keyboard:getKeyboardLayout()
  if next(M.owners) and M.enabled() and (language=='zh_CN' or language=='en') then M.attach(keyboard) end
 end
 M.keys_wrapper=function(keyboard,...)
  addKeys(keyboard,...);M.decorate(keyboard)
 end
 VK.init=M.init_wrapper;VK.addKeys=M.keys_wrapper
end
function M.detach(owner)
 M.owners[owner]=nil;if next(M.owners) then return end
 local keyboards={};for keyboard in pairs(M.states) do keyboards[#keyboards+1]=keyboard end
 for _,keyboard in ipairs(keyboards) do
  M.release(keyboard,true);keyboard.uwrap_func=nil
  if keyboard.visible then M.init_original(keyboard);UI:setDirty('all','ui') end
 end
 if VK.init==M.init_wrapper then VK.init=M.init_original end
 if VK.addKeys==M.keys_wrapper then VK.addKeys=M.keys_original end
 M.init_wrapper=nil;M.keys_wrapper=nil
end
return M
