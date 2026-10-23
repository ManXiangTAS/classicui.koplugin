-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Prices are optional user records, stored as integer fen (CNY), never savings claims.
local Copy=require('einkfrontend/catalog').copy
local Settings=require('luasettings')
local Value={};Value.__index=Value;Value.maximum=99999999
function Value.parse(text,required)
 assert(type(text)=='string','请输入金额');text=text:match('^%s*(.-)%s*$')
 if text=='' then assert(not required,'请填写购机投入');return nil end
 assert(#text<=12 and (text:match('^%d+$') or text:match('^%d+%.%d%d?$')),'金额最多保留两位小数')
 local whole,fraction=text:match('^(%d+)%.?(%d*)$');local cents=tonumber(whole)*100+tonumber((fraction..'00'):sub(1,2))
 assert(cents>=0 and cents<=Value.maximum,'金额应在0至999999.99元之间')
 if required then assert(cents>0,'购机投入需大于0元') end
 return cents
end
function Value.money(cents) return cents~=nil and string.format('%.2f',cents/100) or '' end
function Value.valid(cents) return type(cents)=='number' and cents==cents and cents%1==0 and cents>=0 and cents<=Value.maximum end
function Value.new(library) return setmetatable({library=library},Value) end
function Value:config()
 local d=self.library.settings:readSetting('reading_return')
 if d==nil then return {version=1,revision=0,books={}} end
 assert(type(d)=='table' and d.version==1 and type(d.books)=='table' and type(d.revision)=='number' and d.revision>=0 and d.revision<1e12,'阅读回报记录异常，原数据已保留')
 assert(d.investment==nil or (Value.valid(d.investment) and d.investment>0),'购机投入记录异常')
 for file,v in pairs(d.books) do
  assert(type(file)=='string' and type(v)=='table' and (v.cents==nil or Value.valid(v.cents)) and type(v.revision)=='number' and v.revision>=0,'本书价格记录异常')
  assert(v.identity==nil or (type(v.identity)=='string' and #v.identity==64 and v.identity:match('^[a-f0-9]+$')),'书籍标识异常')
 end
 return d
end
function Value:change(fn)
 local store=self.library.settings;local old=Copy(store.data);local d=Copy(self:config());d.revision=d.revision+1;fn(d)
 local ok,why=pcall(function()
  store:saveSetting('reading_return',d);assert(store:flush()~=false,'无法保存阅读回报')
  assert(require('einkfrontend/adapter').equal(Settings:open(store.file):readSetting('reading_return'),d),'阅读回报保存失败')
 end)
 if not ok then store.data=old;pcall(store.flush,store);error(why,0) end
end
function Value:investment(text) local cents=Value.parse(text,true);self:change(function(d) d.investment=cents end) end
function Value:price(file) local ok,d=pcall(self.config,self);if not ok then return nil end;local r=d.books[file];return r and r.cents end
function Value:setPrice(file,text,identity)
 local cents=Value.parse(text);self:change(function(d)
  local old=d.books[file] or {};d.books[file]={cents=cents,identity=identity or old.identity,revision=d.revision}
 end)
end
-- A duplicate upload with an untouched optional price keeps the last value;
-- clearing a price in book details remains an explicit operation.
function Value:recordUpload(file,text,identity)
 local cents=Value.parse(text or '')
 if cents==nil then
  local latest
  for _,rec in pairs(self:config().books) do
   if rec.identity==identity and (not latest or rec.revision>latest.revision) then latest=rec end
  end
  if latest then cents=latest.cents end
 end
 self:setPrice(file,Value.money(cents),identity)
end
function Value:summary()
 local data=self:config();local groups={};local total,priced,missing,completed=0,0,0,0
 for _,book in ipairs(self.library.books) do
  if require('libs/libkoreader-lfs').attributes(book.file,'mode')=='file' then
   local rec=data.books[book.file];local key=rec and rec.identity or book.file
   local group=groups[key] or {revision=-1,complete=false};groups[key]=group
   if rec and rec.revision>=group.revision then group.cents=rec.cents;group.revision=rec.revision end
   if self.library:status(book)=='已完成' then group.complete=true end
  end
 end
 for _,g in pairs(groups) do if g.complete then
  completed=completed+1
  if g.cents~=nil then total=total+g.cents;priced=priced+1 else missing=missing+1 end
 end end
 local percent=data.investment and math.floor(total/data.investment*100) or nil
 local comment=not percent and '设置购机投入' or percent<25 and '故事刚开始' or percent<50 and '渐入佳境' or percent<75 and '稳步接近' or percent<100 and '就快回本' or percent<150 and '已经回本' or percent<250 and '越读越值' or '超值书旅'
 return {total=total,investment=data.investment,percent=percent,comment=comment,priced=priced,missing=missing,completed=completed}
end
function Value.promptInvestment(app,on_saved)
 local value=app.book_value;local ok,data=pcall(value.config,value)
 if not ok then return app:message(data) end
 app.adapter:promptText('购机投入（元）',Value.money(data.investment),function(text)
  return app:userAction(function() value:investment(text);app:render();if on_saved then on_saved() end end)
 end,{keep_on_error=true})
end
function Value.render(app,route,m,row,go)
 if route.id~='reading_return' then return false end
 m.settings=true;m.title='阅读回报';m.subtitle=''
 local ok,d=pcall(app.book_value.summary,app.book_value)
 if not ok then row('记录暂不可用','原数据已保留');m.help=function() app:message(d) end;return true end
 row('购机投入',d.investment and '¥'..Value.money(d.investment) or '填写设备购入金额',function() Value.promptInvestment(app) end)
 row('已读书籍价值','¥'..Value.money(d.total))
 row('阅读回报进度',d.percent and tostring(d.percent)..'% · '..d.comment or '设置投入后显示百分比')
 row('已完成阅读',d.completed..' 本 · '..d.priced..' 本已填写价格')
 row('待补价格',d.missing..' 本',go('books',{status='已完成'}))
 row('选择书籍，填写价格',nil,go('books',{}))
 row('主页显示与布局',nil,go('home_widget','reading_return'))
 m.help=function() app:message('已读书籍价值 ÷ 购机投入。只计入标记为“已完成”的书；未填价格不计金额；免费书可填0。相同上传文件只计一次，重复阅读不重复累计。金额为你的阅读记录，不代表实际节省或投资收益。') end
 return true
end
return Value
