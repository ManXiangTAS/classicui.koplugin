-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Temporary, narrowly scoped LAN editor. No remote execution or file endpoints.
local socket=require('socket');local json=require('rapidjson');local UI=require('ui/uimanager')
local time=require('ui/time');local Device=require('device')
local Web={};Web.__index=Web
local function now() return time.to_s(time.now()) end
local function readfile(path,limit)
 local f=assert(io.open(path,'rb'));local s=f:read(limit+1);f:close();assert(#s<=limit,'文件过大');return s
end
local function random()
 local f=assert(io.open('/dev/urandom','rb'),'随机源不可用');local bytes=f:read(24);f:close();assert(bytes and #bytes==24,'随机源不可用')
 return (bytes:gsub('.',function(c) return string.format('%02x',c:byte()) end))
end
local function localIP()
 local probe=assert(socket.udp());local ok=probe:setpeername('192.0.2.1',9);local ip=ok and probe:getsockname();probe:close()
 assert(ip and ip~='0.0.0.0','请先连接 Wi-Fi');return ip
end
local function ipv4(ip)
 if type(ip)~='string' then return false end
 local n=0;for octet in ip:gmatch('[^.]+') do if not octet:match('^%d+$') or tonumber(octet)>255 then return false end;n=n+1 end
 return n==4 and ip:match('^%d+%.%d+%.%d+%.%d+$')~=nil
end
local topkeys={version=true,spacing=true,recent_count=true,tbr_count=true,quote_index=true,heatmap_weeks=true,daily_goal_minutes=true,quote_text=true,widgets=true}
function Web.validate(config)
 assert(type(config)=='table','配置格式不正确')
 for key in pairs(config) do assert(topkeys[key],'未知配置字段') end
 assert(type(config.widgets)=='table' and #config.widgets==13,'部件数量不正确')
 local count=0;for key in pairs(config.widgets) do assert(type(key)=='number' and key%1==0 and key>=1 and key<=13,'部件索引不正确');count=count+1 end;assert(count==13,'部件数量不正确')
 for _,w in ipairs(config.widgets) do
  assert(type(w)=='table','部件格式不正确')
  for key in pairs(w) do assert(key=='id' or key=='enabled' or key=='span','未知部件字段') end
 end
 require('einkfrontend/homelayout').validate(config)
end
function Web.new(editor,options)
 options=options or {};local self=setmetatable({editor=editor,clients={},expires=now()+900,token=random()},Web)
 self.ip=options.ip or localIP();assert(ipv4(self.ip),'网络地址不正确')
 self.listener=assert(socket.bind(self.ip,0));self.listener:settimeout(0)
 local _,port=self.listener:getsockname();self.port=tonumber(port);self.host=self.ip..':'..self.port;self.origin='http://'..self.host
 self.url=self.origin..'/#'..self.token
 self.rules={}
 local ok,why=pcall(function()
  self.html=readfile('plugins/einkfrontend.koplugin/resources/home-editor.html',150000)
  if Device:isKindle() and not options.no_firewall then
   local p=tostring(self.port)
   self.rules={ 'INPUT -p tcp -d '..self.ip..' --dport '..p..' -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT',
    'OUTPUT -p tcp -s '..self.ip..' --sport '..p..' -m conntrack --ctstate ESTABLISHED -j ACCEPT' }
   self.installed={}
   for _,rule in ipairs(self.rules) do
    local status=os.execute('iptables -A '..rule..' >/dev/null 2>&1')
    assert(status==0,'无法打开临时编辑端口');self.installed[#self.installed+1]=rule
   end
  end
  self.tick=function()
   if self.stopped then return end
   local healthy=pcall(self.poll,self)
   if not healthy then self:stop();if not editor.closed then editor.app:message('手机编辑已停止，请重新开启') end;return end
   if not self.stopped then UI:scheduleIn(.15,self.tick) end
  end
  UI:scheduleIn(.15,self.tick)
 end)
 if not ok then self:stop();error(why) end
 return self
end
function Web:stop()
 if self.stopped then return end;self.stopped=true
 if self.tick then UI:unschedule(self.tick) end
 if self.listener then self.listener:close();self.listener=nil end
 for _,client in ipairs(self.clients) do client.socket:close() end;self.clients={}
 for _,rule in ipairs(self.installed or {}) do os.execute('iptables -D '..rule..' >/dev/null 2>&1') end
 if self.qr then UI:close(self.qr) end
 if self.dialog then UI:close(self.dialog) end
 self.qr=nil;self.dialog=nil
 self.installed={};self.token=nil;self.url=nil
 if self.editor.server==self then self.editor.server=nil end
end
function Web:showAddress()
 if self.stopped then return end
 local P=require('einkfrontend/paint')
 if self.dialog then UI:close(self.dialog) end
 local box
 box=require('ui/widget/buttondialog'):new{title='手机和 Kindle 连接同一 Wi-Fi\n'..self.origin..'\n扫码进入，15分钟后自动关闭',buttons={
  {{text='显示二维码',callback=function()
   if self.stopped then return end
   UI:close(box);self.dialog=nil
   self.qr=require('ui/widget/qrmessage'):new{text=self.url,width=P.s(340),height=P.s(340)};UI:show(self.qr)
  end}},
  {{text='关闭手机编辑',callback=function() self:stop() end}},
 }}
 self.dialog=box;UI:show(box)
end
local reasons={[200]='OK',[400]='Bad Request',[401]='Unauthorized',[403]='Forbidden',[404]='Not Found',[409]='Conflict',[413]='Payload Too Large',[415]='Unsupported Media Type',[500]='Internal Server Error'}
function Web:response(status,body,mime,extra)
 body=body or '';return 'HTTP/1.1 '..status..' '..reasons[status]..'\r\nConnection: close\r\nContent-Type: '..(mime or 'application/json; charset=utf-8')..'\r\nContent-Length: '..#body..'\r\n'..(extra or '')..'Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src \'none\'; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'; img-src blob:; connect-src \'self\'; base-uri \'none\'; frame-ancestors \'none\'; form-action \'none\'\r\n\r\n'..body
end
function Web:request(method,path,headers,body)
 if headers.host~=self.host or (headers.origin and headers.origin~=self.origin) then return self:response(403,'{}') end
 if method=='GET' and path=='/' then return self:response(200,self.html,'text/html; charset=utf-8') end
 if headers.authorization~='Bearer '..self.token then return self:response(401,'{}') end
 if method=='GET' and path=='/api/layout' then
  local registry={};for _,def in ipairs(require('einkfrontend/homelayout').registry) do registry[#registry+1]={id=def.id,name=def.name} end
  return self:response(200,json.encode{config=self.editor.draft,revision=self.editor.revision,widgets=registry,fit=self.editor.preview_fit,dirty=not require('einkfrontend/adapter').equal(self.editor.base,self.editor.draft)})
 elseif method=='GET' and (path=='/api/preview' or path:match('^/api/preview%?offset=%d+$')) then
  local offset=path:match('offset=(%d+)$')
  if offset then self.editor.preview_scroll=0 end
  local file=(require('datastorage'):getDataDir()..'/cache')..'/eink-home-preview-'..self.port..'.png'
  local ok,png=pcall(function() self.editor.preview:writePNG(file);return readfile(file,8000000) end);os.remove(file)
  return ok and self:response(200,png,'image/png','X-Preview-Offset: '..math.floor(self.editor.preview_scroll)..'\r\nX-Preview-Max: '..math.floor(self.editor.preview_max or 0)..'\r\n') or self:response(500,'{}')
 elseif method=='POST' and (path=='/api/layout' or path=='/api/save') then
  if headers['content-type']~='application/json' then return self:response(415,'{}') end
  -- Bound decoder nesting independently of the body limit.
  local depth,inside,escape=0,false,false
  for i=1,#body do local c=body:sub(i,i)
   if inside then if escape then escape=false elseif c=='\\' then escape=true elseif c=='"' then inside=false end
   elseif c=='"' then inside=true elseif c=='{' or c=='[' then depth=depth+1;if depth>8 then return self:response(400,'{}') end elseif c=='}' or c==']' then depth=depth-1 end
  end
  local valid,data=pcall(function()
   local d=assert(json.decode(body));assert(type(d)=='table' and type(d.revision)=='number' and d.revision%1==0,'请求格式不正确')
   for k in pairs(d) do assert(k=='revision' or k=='config','未知请求字段') end
   Web.validate(d.config);return d
  end)
  if not valid then return self:response(400,json.encode{error='布局格式不正确'}) end
  if data.revision~=self.editor.revision then return self:response(409,json.encode{error='布局已发生变化，请重新载入'}) end
  local ok,why=self.editor:replaceDraft(data.config,data.revision)
  if not ok then return self:response(400,json.encode{error=why}) end
  if path=='/api/save' then
   ok,why=self.editor:save(true)
   if not ok then return self:response(409,json.encode{error=why,revision=self.editor.revision}) end
  end
  return self:response(200,json.encode{revision=self.editor.revision,saved=path=='/api/save',fit=self.editor.preview_fit,dirty=not require('einkfrontend/adapter').equal(self.editor.base,self.editor.draft)})
 end
 return self:response(404,'{}')
end
function Web:parse(buffer)
 local split=buffer:find('\r\n\r\n',1,true)
 if not split then if #buffer>8192 then return self:response(413,'{}') end;return nil end
 if split>8192 then return self:response(413,'{}') end
 local head=buffer:sub(1,split-1);local first,rest=head:match('^([^\r\n]+)\r\n(.*)$')
 if not first then return self:response(400,'{}') end
 local method,path=first:match('^(%u+) (/[^%s]*) HTTP/1%.[01]$')
 if not method or #path>256 then return self:response(400,'{}') end
 local headers={}
 for line in (rest..'\r\n'):gmatch('(.-)\r\n') do
  local k,v=line:match('^([%w%-]+):%s*(.-)%s*$')
  if not k then return self:response(400,'{}') end;k=k:lower();if headers[k] then return self:response(400,'{}') end;headers[k]=v
 end
 if headers['transfer-encoding'] or headers.expect then return self:response(400,'{}') end
 local length=headers['content-length'] or '0'
 if not length:match('^%d+$') or #length>6 then return self:response(400,'{}') end;length=tonumber(length)
 if length>32768 then return self:response(413,'{}') end
 local start=split+4;if #buffer-start+1<length then return nil end
 if #buffer-start+1>length then return self:response(400,'{}') end
 return self:request(method,path,headers,buffer:sub(start))
end
function Web:poll()
 if self.stopped then return end
 if self.editor.closed or now()>=self.expires then self:stop();return end
 for _=1,4 do local client=self.listener:accept();if not client then break end
  if #self.clients>=4 then client:close() else client:settimeout(0);self.clients[#self.clients+1]={socket=client,buffer='',deadline=now()+5} end
 end
 for i=#self.clients,1,-1 do local client=self.clients[i];local done=false
  if now()>client.deadline then done=true
  elseif client.response then
   local chunk=client.response:sub(client.sent or 1,(client.sent or 1)+16383)
   local sent,err,partial=client.socket:send(chunk);local n=sent or partial or 0
   client.sent=(client.sent or 1)+n
   if client.sent>#client.response or (err and err~='timeout') then done=true end
  else
   local data,err,partial=client.socket:receive(4096);client.buffer=client.buffer..(data or partial or '')
   if #client.buffer>40960 then client.response=self:response(413,'{}')
   else client.response=self:parse(client.buffer) end
   if err=='closed' and not client.response then done=true end
  end
  if done then client.socket:close();table.remove(self.clients,i) end
 end
end
return Web
