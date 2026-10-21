-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local socket=require('socket');local json=require('rapidjson');local UI=require('ui/uimanager')
local Device=require('device');local time=require('ui/time');local Store=require('einkfrontend/transferstore')
local Base=require('einkfrontend/homeweb');local Web={};Web.__index=Web
local function now() return time.to_s(time.now()) end
local function random()
 local f=assert(io.open('/dev/urandom','rb'));local b=f:read(24);f:close();assert(b and #b==24,'随机源不可用')
 return (b:gsub('.',function(c)return string.format('%02x',c:byte())end))
end
local function read(path) local f=assert(io.open('plugins/einkfrontend.koplugin/resources/'..path,'rb'));local s=f:read('*a');f:close();return s end
function Web.new(app,options)
 options=options or {};local self=setmetatable({app=app,editor={},clients={},token=random(),expires=now()+1800,store=Store.new(options.root)},Web)
 local probe=assert(socket.udp());local ok=probe:setpeername('192.0.2.1',9);self.ip=options.ip or (ok and probe:getsockname());probe:close()
 assert(type(self.ip)=='string' and self.ip:match('^%d+%.%d+%.%d+%.%d+$') and self.ip~='0.0.0.0','请先连接 Wi-Fi')
 self.listener=assert(socket.bind(self.ip,0));self.listener:settimeout(0);local _,port=self.listener:getsockname();self.port=tonumber(port)
 self.host=self.ip..':'..self.port;self.origin='http://'..self.host;self.url=self.origin..'/#'..self.token
 local good,why=pcall(function()
  self.assets={['/']=read('send-to-device.html'),['/polish']=read('epub-polish.html'),['/jszip.min.js']=read('jszip.min.js')}
  self.installed={}
  if Device:isKindle() and not options.no_firewall then
   local rules={'INPUT -p tcp -d '..self.ip..' --dport '..self.port..' -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT',
    'OUTPUT -p tcp -s '..self.ip..' --sport '..self.port..' -m conntrack --ctstate ESTABLISHED -j ACCEPT'}
   for _,rule in ipairs(rules) do assert(os.execute('iptables -I '..rule..' >/dev/null 2>&1')==0,'无法开启传书端口');self.installed[#self.installed+1]=rule end
  end
  self.tick=function()
   if self.stopped then return end
   local healthy=pcall(self.poll,self)
   if not healthy then self:stop();app:message('网页传书已停止，请重新开启');return end
   if not self.stopped then UI:scheduleIn(.03,self.tick) end
  end
  UI:scheduleIn(.03,self.tick)
 end)
 if not good then self:stop();error(why) end
 return self
end
function Web:response(status,body,mime)
 return Base.response(self,status,body,mime):gsub("frame%-ancestors 'none'","frame-ancestors 'self'"):gsub("script%-src 'unsafe%-inline';","script-src 'self' 'unsafe-inline';"):gsub("img%-src blob:;","img-src blob: data:; font-src data:; frame-src 'self';")
end
function Web:stop()
 if self.stopped then return end
 if self.scan_job then UI:unschedule(self.scan_job);self.scan_job=nil end
 local cleaned=self.store:abort();if not cleaned then cleaned=self.store:abort() end
 Base.stop(self)
 if not cleaned then require('logger').warn('Transfer temporary file cleanup pending');self.app:message('传书已关闭，但有未完成的临时文件暂时无法清理。请退出 KOReader 后检查接收目录中的隐藏 .moye-upload-*.part 文件。') end
 if self.app.transfer_server==self then self.app.transfer_server=nil end
end
function Web:showAddress()
 if self.stopped then return end
 if self.dialog then UI:close(self.dialog) end
 local box;box=require('ui/widget/buttondialog'):new{title='网页传书 · 同一 Wi-Fi\n'..self.origin..'\n30分钟后关闭，文件保存在\n'..self.store.root,buttons={
  {{text='显示二维码',callback=function() if self.stopped then return end;UI:close(box);self.dialog=nil;self.qr=require('ui/widget/qrmessage'):new{text=self.url,width=require('einkfrontend/paint').s(340),height=require('einkfrontend/paint').s(340)};UI:show(self.qr) end}},
  {{text='显示完整连接地址',callback=function() if not self.stopped then self.app:message(self.url..'\n地址包含临时访问密钥，请勿转发') end end}},
  {{text='关闭传书',callback=function() self:stop();self.app:render() end}},
 }};self.dialog=box;UI:show(box)
end
function Web:request(method,path,headers,body)
 if self.stopped or now()>=self.expires then return self:response(401,'{}') end
 if headers.host~=self.host or (headers.origin and headers.origin~=self.origin) then return self:response(403,'{}') end
 if method=='GET' and path=='/help' then return self:response(200,read('guide.html'),'text/html; charset=utf-8') end
 if method=='GET' and self.assets[path] then return self:response(200,self.assets[path],path=='/jszip.min.js' and 'text/javascript; charset=utf-8' or 'text/html; charset=utf-8') end
 if headers.authorization~='Bearer '..self.token then return self:response(401,'{}') end
 if method=='GET' and path=='/api/info' then return self:response(200,json.encode{directory=self.store.root,limit=Store.limit,chunk=Store.chunk,expires_in=math.max(0,math.floor(self.expires-now()))}) end
 local valid,why=pcall(function()
  if method=='POST' and path=='/api/begin' then
   assert(headers['content-type']=='application/json','请求类型无效');assert(#body<=2048,'请求过大')
   local d=assert(json.decode(body));assert(type(d)=='table','请求格式无效');for k in pairs(d) do assert(k=='name' or k=='size','未知请求字段') end
   local u=self.store:begin(d.name,d.size,random());self.last_activity=now();return {id=u.id,offset=0}
  elseif method=='POST' and path:match('^/api/chunk/[a-f0-9]+/%d+$') then
   assert(headers['content-type']=='application/octet-stream','请求类型无效')
   local id,offset=path:match('^/api/chunk/([a-f0-9]+)/(%d+)$');local n=self.store:append(id,tonumber(offset),body);self.last_activity=now();return {offset=n}
  elseif method=='POST' and path:match('^/api/finish/[a-f0-9]+$') then
   assert(#body==0,'请求格式无效');local id=path:match('/([a-f0-9]+)$');local name=self.store:finish(id);self.last_activity=nil
   if self.scan_job then UI:unschedule(self.scan_job) end
   self.scan_job=function() self.scan_job=nil;if self.app.plugin.active and self.app.adapter:alive() then self.app:scanLibrary(self.store.root) end end
   UI:scheduleIn(.5,self.scan_job);return {name=name,saved=true}
  elseif method=='POST' and path:match('^/api/cancel/[a-f0-9]+$') then
   local id=path:match('/([a-f0-9]+)$');if self.store.upload then assert(self.store.upload.id==id,'上传标识无效');self.store:abort() end;return {cancelled=true}
  end
 end)
 if valid and why then return self:response(200,json.encode(why)) end
 if not valid then
  -- Expected input failures remain local. Paths, internal stack and file content never leave the device.
  return self:response(400,json.encode{error=tostring(why):gsub('[%w_./%-]+%.lua:%d+:%s*','')})
 end
 return self:response(404,'{}')
end
function Web:parse(buffer)
 local split=buffer:find('\r\n\r\n',1,true)
 if not split then return #buffer>8192 and self:response(413,'{}') or nil end
 if split>8192 then return self:response(413,'{}') end
 local head=buffer:sub(1,split-1);local first,rest=head:match('^([^\r\n]+)\r\n(.*)$');if not first then return self:response(400,'{}') end
 local method,path=first:match('^(%u+) (/[^%s]*) HTTP/1%.[01]$');if not method or #path>256 then return self:response(400,'{}') end
 local headers={}
 for line in (rest..'\r\n'):gmatch('(.-)\r\n') do
  local k,v=line:match('^([%w%-]+):%s*(.-)%s*$');if not k then return self:response(400,'{}') end;k=k:lower();if headers[k] then return self:response(400,'{}') end;headers[k]=v
 end
 if headers['transfer-encoding'] or headers.expect then return self:response(400,'{}') end
 if headers.host~=self.host or (headers.origin and headers.origin~=self.origin) then return self:response(403,'{}') end
 if path:sub(1,5)=='/api/' and headers.authorization~='Bearer '..self.token then return self:response(401,'{}') end
 local length=headers['content-length'] or '0';if not length:match('^%d+$') or #length>6 then return self:response(400,'{}') end;length=tonumber(length)
 if length>Store.chunk then return self:response(413,'{}') end
 local start=split+4;if #buffer-start+1<length then return nil end
 if #buffer-start+1>length then return self:response(400,'{}') end
 return self:request(method,path,headers,buffer:sub(start))
end
function Web:poll()
 if self.stopped then return end
 if not self.app.plugin.active or now()>=self.expires then self:stop();return end
 if self.store.temp and not self.store.upload and (not self.cleanup_at or now()>self.cleanup_at) then self.store:abort();self.cleanup_at=now()+1 end
 if self.last_activity and now()-self.last_activity>120 then self.store:abort();self.last_activity=nil end
 for _=1,4 do local client=self.listener:accept();if not client then break end
  if #self.clients>=4 then client:close() else client:settimeout(0);self.clients[#self.clients+1]={socket=client,buffer='',deadline=now()+15} end
 end
 for i=#self.clients,1,-1 do local c=self.clients[i];local done=false
  if now()>c.deadline then done=true
  elseif c.response then
   local sent,err,part=c.socket:send(c.response:sub(c.sent or 1,(c.sent or 1)+65535));c.sent=(c.sent or 1)+(sent or part or 0)
   if c.sent>#c.response or (err and err~='timeout') then done=true end
  else
   for _=1,4 do
    local data,err,part=c.socket:receive(16384);local bytes=data or part or '';c.buffer=c.buffer..bytes
    if #c.buffer>Store.chunk+8192 then c.response=self:response(413,'{}') else c.response=self:parse(c.buffer) end
    if c.response then break end
    if err=='closed' then done=true;break end
    if #bytes==0 then break end
   end
  end
  if done then c.socket:close();table.remove(self.clients,i) end
 end
end
return Web
