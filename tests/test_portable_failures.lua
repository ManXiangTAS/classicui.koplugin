
local checks,failed={},0
local function test(name,fn)
 local ok,why=pcall(fn);checks[#checks+1]={name=name,passed=ok,error=not ok and tostring(why) or nil}
 if not ok then failed=failed+1 end
end
local function encode(v)
 if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"' end
 if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
 if v==nil then return 'null' end
 local t={};if #v>0 then for _,x in ipairs(v) do t[#t+1]=encode(x) end;return '['..table.concat(t,',')..']' end
 for k,x in pairs(v) do t[#t+1]=encode(k)..':'..encode(x) end;return '{'..table.concat(t,',')..'}'
end
local function copy(x) if type(x)~='table' then return x end;local o={};for k,v in pairs(x) do o[k]=copy(v) end;return o end
local ui,files,removed,rename_fail,close_fail,fsync_fail,clock,power,device,sensor
local settings,app,last_errno,doc_fault,seq,hash_final
local id=string.rep('a',48)
local function init()
 for name in pairs(package.loaded) do if name:match('^einkfrontend/') then package.loaded[name]=nil end end
 files={};removed={};rename_fail=false;close_fail=false;fsync_fail=false;clock=100;last_errno=0;doc_fault=false;seq=10;hash_final=0
 local function entry(mode,body) seq=seq+1;return {mode=mode,body=body or '',size=#(body or ''),dev=1,ino=seq,modification=1} end
 for _,p in ipairs({'/','/books','/settings','/docsettings','/history'}) do files[p]=entry('directory') end
 local function attr(p,k) local a=files[p];if not a then return nil,'missing',2 end;return k and a[k] or copy(a) end
 local function handle(p)
  local f={path=p,closed=false}
  function f:write(s) assert(not self.closed);local a=files[p];a.body=a.body..s;a.size=#a.body;return true end
  function f:flush() assert(not self.closed);return true end
  function f:close() assert(not self.closed,'already closed');self.closed=true;if close_fail then close_fail=false;return nil,'close failed' end;return true end
  local pos=1
  function f:read(n) assert(not self.closed);local s=files[p].body;if pos>#s then return nil end;if n=='*a' then n=#s end;local r=s:sub(pos,pos+n-1);pos=pos+#r;return r end
  return f
 end
 io={open=function(p,mode)
  if p=='/dev/urandom' then return {read=function() return string.rep('x',24) end,close=function() end} end
  if mode=='wb' then files[p]=entry('file');return handle(p) end
  if not files[p] then return nil end;return handle(p)
 end}
 os={remove=function(p) if files[p] then files[p]=nil;removed[#removed+1]=p;return true end;return nil end,
  rename=function(a,b) if rename_fail then return nil,'rename injected failure' end;assert(files[a]);files[b]=files[a];files[a]=nil;return true end}
 ui={tasks={}}
 function ui:unschedule(fn) for i=#self.tasks,1,-1 do if self.tasks[i]==fn then table.remove(self.tasks,i) end end end
 function ui:scheduleIn(_,fn) self.tasks[#self.tasks+1]=fn end
 function ui:nextTick(fn) self.tasks[#self.tasks+1]=fn end
 function ui:setDirty() end
 function ui:drain() local n=0;while #self.tasks>0 do n=n+1;assert(n<100);local f=table.remove(self.tasks,1);f() end end
 settings={data={}}
 function settings:readSetting(k) return self.data[k] end
 function settings:saveSetting(k,v) self.data[k]=v end
 function settings:flush() return true end
 power={fl_min=0,fl_max=25,fl_intensity=18,value=18,writes=0}
 function power:frontlightIntensity() return self.value end
 function power:frontlightIntensityHW() return self.value end
 function power:setIntensity(v) self.value=v;self.writes=self.writes+1 end
 function power:updateResumeFrontlightState() end
 device={model='KindleVoyage',screen={night_mode=false}}
 function device:getPowerDevice() return power end
 function device:isKindle() return true end
 function device:hasFrontlight() return true end
 function device:hasLightSensor() return true end
 sensor={value=10}
 function sensor:probe() return true,nil,self.value end
 function sensor:read() return self.value end
 local storedata={file='/settings/library.lua',data={books={}}}
 function storedata:flush() return true end
 function storedata:readSetting(k) return self.data[k] end
 app={plugin={active=true,ui={}},adapter={alive=function() return true end},library={settings=storedata,books={},root='/books'},book_value={recordUpload=function() end},stack={{id='library_cleanup'}},messages={}}
 function app:message(why) self.messages[#self.messages+1]=why end
 function app:userAction(fn) local ok,why=pcall(fn);if not ok then self:message(why) end;return ok,why end
 function app:render() end
 package.loaded['ui/uimanager']=ui
 package.loaded['ui/time']={now=function() return clock end,to_s=function(x) return x end}
 package.loaded['device']=device
 package.loaded['libs/libkoreader-lfs']={symlinkattributes=attr,attributes=attr,mkdir=function(p) files[p]=entry('directory');return true end,dir=function(p)
  assert(files[p],'unreadable directory')
  local prefix=p=='/' and '/' or p..'/';local names={};for q in pairs(files) do if q:sub(1,#prefix)==prefix then local n=q:sub(#prefix+1);if n~='' and not n:find('/',1,true) then names[#names+1]=n end end end
  local i=0;return function() i=i+1;return names[i] end
 end}
 package.loaded['ffi/util']={realpath=function(p) return files[p] and p or nil end,df=function() return 0,1000000000 end,
  fsyncOpenedFile=function(f) assert(f and not f.closed,'fsync on closed or missing file');return not fsync_fail end,fsyncDirectory=function() return true end}
 package.loaded['bit']={bor=function(...) local n=0;for _,v in ipairs({...}) do n=n+v end;return n end}
 package.loaded['ffi/posix_h']={}
 package.loaded['ffi']={cast=function(_,v) return v end,errno=function() return last_errno end,C={open=function(p)
  if files[p] then last_errno=17;return -1 end;files[p]=entry('file');return 42
 end,close=function() return 0 end}}
 package.loaded['ffi/sha2']={sha256=function() return function(chunk) if not chunk then hash_final=hash_final+1;return string.rep('d',64) end end end}
 package.loaded['logger']={warn=function() end}
 package.loaded['rapidjson']={encode=encode}
 package.loaded['socket']={}
 package.loaded['datastorage']={getSettingsDir=function() return '/settings' end,getDocSettingsDir=function() return '/docsettings' end}
 package.loaded['luasettings']={open=function(_,p) return {data={}} end}
 package.loaded['docsettings']={getHistoryPath=function(_,file) return '/history/'..file:match('([^/]+)$') end,getSidecarDir=function(_,file,loc)
  if doc_fault then error('injected metadata failure') end
  return (loc=='doc' and '/docsettings' or '')..file:gsub('%.[^/.]+$','')..'.sdr'
 end}
 package.loaded['apps/reader/readerui']={}
 package.loaded['document/documentregistry']={hasProvider=function() return true end}
 package.loaded['einkfrontend/library']={instances={}}
 package.loaded['readhistory']={hist={},removeItemByPath=function() end}
 package.loaded['readcollection']={coll={}}
 package.loaded['ui/widget/booklist']={resetBookInfoCache=function() end}
 return entry
end
local function light()
 local L=require('einkfrontend/autolight').new(settings,device,ui,sensor,function() return clock end)
 L.config.enabled=true;L.config.anchor=18;L.expected=18;L.running=true;L.owners[app]=true;return L
end
local function upload()
 local S=require('einkfrontend/transferstore');local s=S.new('/books');s:begin('book.epub',3,id);s:append(id,0,'abc');return s
end
test('native idle dimming is not persisted as manual off',function()
 init();local l=light();app.plugin.ui.autodim={autodim_save_fl=18};power.value=0
 assert(not l:guard());assert(not l.config.off_locked,'idle dimming was stored as manual off');assert(l.pause_until==nil)
end)
test('native dim event does not start manual priority',function()
 init();local l=light();app.plugin.ui.autodim={autodim_save_fl=18};power.value=6;l:externalChanged()
 assert(l.pause_until==nil,'native dim event started 15-minute manual priority');assert(l.expected==18)
end)
test('restored native brightness resumes automatic sampling',function()
 init();local l=light();app.plugin.ui.autodim={autodim_save_fl=18};power.value=0;l:externalChanged()
 power.value=18;l:externalChanged();app.plugin.ui.autodim.autodim_save_fl=nil
 assert(l:guard(),'automatic controller remained paused after native restore')
end)
test('genuine manual off remains locked',function()
 init();local l=light();power.value=0;l:externalChanged();assert(l.config.off_locked and l.manual_hold==nil)
end)
test('manual learning commits after stable delay',function()
 init();local l=light();power.value=20;l:manual(20,true);clock=103;l:commitLearning()
 assert(#l:profile().memories==1 and l:profile().memories[1].level==20)
end)
test('cancelled calibration restores original brightness',function()
 init();local l=light();local t=assert(l:beginCalibration());assert(l:preview(t,23));l:finishCalibration(t,false);assert(power.value==18)
end)
test('calibration cancellation on suspend leaves no tasks',function()
 init();local l=light();local t=l:beginCalibration();l:preview(t,22);l:suspend()
 assert(power.value==18 and l.calibration==nil and #ui.tasks==0)
end)
test('curve accepts full Voyage synthetic range',function()
 init();local c=require('einkfrontend/lightcurve');assert(c.target(0,25,0,25,{})==25);assert(c.target(10000,25,0,25,{})==0);assert(c.target(0/0,18,0,25,{})==nil)
end)
test('upload retries final rename without reopening sealed file',function()
 init();local s=upload();rename_fail=true;assert(not pcall(s.finish,s,id));rename_fail=false
 local ok,name=pcall(s.finish,s,id);assert(ok,tostring(name));assert(name=='book.epub' and files['/books/book.epub'].body=='abc');assert(hash_final==1)
end)
test('upload destination collision preserves original contents',function()
 local entry=init();files['/books/book.epub']=entry('file','original');local s=upload();local name=s:finish(id)
 assert(name=='book (1).epub');assert(files['/books/book.epub'].body=='original');assert(files['/books/'..name].body=='abc')
end)
test('upload fsync failure can be retried',function()
 init();local s=upload();fsync_fail=true;assert(not pcall(s.finish,s,id));fsync_fail=false;assert(s:finish(id)=='book.epub')
end)
test('upload close failure releases invalid handle and session',function()
 init();local s=upload();close_fail=true;assert(not pcall(s.finish,s,id));assert(s.file==nil and s.upload==nil,'closed handle retained in upload')
end)
test('upload rejects traversal and unsupported extensions',function()
 init();local S=require('einkfrontend/transferstore');for _,n in ipairs({'../x.epub','.hidden.epub','x.lua','x/evil.epub'}) do assert(not pcall(S.filename,n)) end
end)
test('cancel upload removes only its temporary file',function()
 local entry=init();files['/books/keep.epub']=entry('file','safe');local s=upload();assert(s:abort());assert(files['/books/keep.epub'].body=='safe');assert(s.temp==nil and s.upload==nil)
end)
test('late library scan failure is contained after successful upload',function()
 init();local W=require('einkfrontend/transferweb');local s=upload()
 local w=setmetatable({store=s,host='127.0.0.1:123',origin='http://127.0.0.1:123',token='secret',expires=1000,app=app,receipts={},receipt_order={}},W)
 function w:response(status,body) return {status=status,body=body} end
 function app:scanLibrary() error('injected unavailable storage') end
 assert(w:request('POST','/api/finish/'..id,{host=w.host,authorization='Bearer secret'},'').status==200)
 local ok,why=pcall(ui.drain,ui);assert(ok,tostring(why));assert(#app.messages==1);assert(files['/books/book.epub'].body=='abc')
end)
test('upload receipt retry does not save a second copy',function()
 init();local W=require('einkfrontend/transferweb');local s=upload()
 local w=setmetatable({store=s,host='127.0.0.1:123',origin='http://127.0.0.1:123',token='secret',expires=1000,app=app,receipts={},receipt_order={}},W)
 function w:response(status,body) return {status=status,body=body} end
 local h={host=w.host,authorization='Bearer secret'}
 assert(w:request('POST','/api/finish/'..id,h,'').status==200);assert(w:request('POST','/api/finish/'..id,h,'').status==200)
 assert(files['/books/book.epub'] and not files['/books/book (1).epub'])
end)
test('unauthenticated upload requests are rejected',function()
 init();local W=require('einkfrontend/transferweb');local w=setmetatable({host='127.0.0.1:123',origin='http://127.0.0.1:123',token='secret',expires=1000,app=app},W)
 function w:response(status) return status end
 assert(w:request('POST','/api/finish/'..id,{host=w.host},'')==401)
 assert(w:request('POST','/api/finish/'..id,{host=w.host,origin='http://foreign',authorization='Bearer secret'},'')==403)
end)
test('cleanup completion errors do not escape scheduled callback',function()
 init();local M=require('einkfrontend/bookmaintenance');local service=M.new(app)
 service:run('scanning',function() return {} end,function() error('injected completion failure') end)
 local ok,why=pcall(ui.drain,ui);assert(ok,tostring(why));assert(service.state=='error')
end)
test('cleanup rendering errors are contained',function()
 init();local M=require('einkfrontend/bookmaintenance');local service=M.new(app);app.screen=true
 function app:render() error('injected render failure') end
 service:run('scanning',function() coroutine.yield();return {} end,function() end)
 local ok,why=pcall(ui.drain,ui);assert(ok,tostring(why));assert(service.state=='error' and service.co==nil)
end)
test('deletion reports cleanup failure after document was deleted',function()
 local entry=init();files['/books/book.epub']=entry('file','abc');doc_fault=true
 local M=require('einkfrontend/bookmaintenance');local ok,result=pcall(M.deleteBook,app,{file='/books/book.epub'})
 assert(ok,tostring(result));assert(result>0);assert(not files['/books/book.epub'])
end)
test('deletion refuses currently open book',function()
 local entry=init();files['/books/book.epub']=entry('file','abc')
 package.loaded['apps/reader/readerui'].instance={document={file='/books/book.epub'}}
 local M=require('einkfrontend/bookmaintenance');assert(not pcall(M.deleteBook,app,{file='/books/book.epub'}));assert(files['/books/book.epub'])
end)
test('cleanup never removes metadata if book reappeared',function()
 local entry=init();local M=require('einkfrontend/bookmaintenance');local service=M.new(app)
 files['/books/book.epub']=entry('file','restored');files['/books/book.sdr']=entry('directory');files['/books/book.sdr/metadata.epub.lua']=entry('file','data')
 local a=copy(files['/books/book.sdr/metadata.epub.lua'])
 local plan={root='/books',root_attr=copy(files['/books']),skipped=0,books={['/books/book.epub']=true},files={{path='/books/book.sdr/metadata.epub.lua',book='/books/book.epub',attr=a,hash=string.rep('d',64)}},empty_dirs={}}
 service.plan=plan;service.state='ready';service:apply(plan);ui:drain()
 assert(files['/books/book.epub'] and files['/books/book.sdr/metadata.epub.lua']);assert(service.result.skipped==1)
end)

test('other automatic controller is not mistaken for manual input',function()
 init();local l=light();app.plugin.ui.autofrontlight={enabled=true};power.value=4;l:externalChanged()
 assert(l.pause_until==nil and l.expected==18);assert(not l:guard());assert(not l.config.off_locked)
end)
test('manual priority follows environment targets instead of a fixed timeout',function()
 init();local l=light();power.value=20;l:manual(20,false);clock=10000;l:sample();assert(l.manual_hold and power.value==20);sensor.value=10000;l:sample();assert(not l.manual_hold and power.value==19)
end)
test('night mode keeps independent remembered preferences',function()
 init();local l=light();device.screen.night_mode=true;l:syncMode();power.value=12;l:manual(12,true);clock=103;l:commitLearning()
 assert(#l.config.dark.memories==1 and #l.config.memories==0)
end)
test('preference save failure preserves previous configuration',function()
 init();local l=light();local before=l.config.anchor;function settings:flush() return false end
 assert(not l:changeProfile('anchor',24));assert(l.config.anchor==before and l.fault and #ui.tasks==0)
end)
test('failed hardware write disables automatic jobs',function()
 init();local l=light();function power:setIntensity() error('hardware unavailable') end
 assert(not l:write(24));assert(l.fault and not l.writing and #ui.tasks==0)
end)
test('malformed remembered preferences are bounded and discarded',function()
 init();local c=require('einkfrontend/lightcurve');local m={};for i=1,30 do m[i]={lux=i*10,level=18} end
 assert(#c.clean(m,0,25)<=12);assert(#c.clean({{lux=-1,level=4},{lux=0/0,level=9},{lux=10,level=100}},0,25)==0)
end)
test('cleanup refuses a replaced root before any deletion',function()
 local entry=init();local M=require('einkfrontend/bookmaintenance');local service=M.new(app)
 local plan={root='/books',root_attr=copy(files['/books']),skipped=0,books={},files={},empty_dirs={}}
 service.plan=plan;service.state='ready';files['/books']=entry('directory')
 service:apply(plan);ui:drain();assert(service.state=='error');assert(#removed==0)
end)
test('cleanup protects modified sidecar content',function()
 local entry=init();local M=require('einkfrontend/bookmaintenance');local service=M.new(app)
 files['/books/book.sdr']=entry('directory');files['/books/book.sdr/metadata.epub.lua']=entry('file','data')
 local p='/books/book.sdr/metadata.epub.lua'
 local plan={root='/books',root_attr=copy(files['/books']),skipped=0,books={},files={{path=p,book='/books/book.epub',attr=copy(files[p]),hash=string.rep('e',64)}},empty_dirs={}}
 service.plan=plan;service.state='ready';service:apply(plan);ui:drain();assert(files[p]);assert(service.result.skipped==1)
end)
test('cleanup protects metadata for a currently open book',function()
 local entry=init();local M=require('einkfrontend/bookmaintenance');local service=M.new(app)
 files['/books/book.sdr']=entry('directory');local p='/books/book.sdr/metadata.epub.lua';files[p]=entry('file','data')
 package.loaded['apps/reader/readerui'].instance={document={file='/books/book.epub'}}
 local plan={root='/books',root_attr=copy(files['/books']),skipped=0,books={},files={{path=p,book='/books/book.epub',attr=copy(files[p]),hash=string.rep('d',64)}},empty_dirs={}}
 service.plan=plan;service.state='ready';service:apply(plan);ui:drain();assert(files[p] and service.result.skipped==1)
end)
test('deletion rejects file identity changed after confirmation',function()
 local entry=init();files['/books/book.epub']=entry('file','old');local expected=copy(files['/books/book.epub']);files['/books/book.epub']=entry('file','new')
 assert(not pcall(require('einkfrontend/bookmaintenance').deleteBook,app,{file='/books/book.epub'},expected))
 assert(files['/books/book.epub'].body=='new')
end)
test('deletion rejects symbolic links',function()
 local entry=init();files['/books/book.epub']=entry('link');assert(not pcall(require('einkfrontend/bookmaintenance').deleteBook,app,{file='/books/book.epub'}));assert(#removed==0)
end)
test('deleting one format preserves sibling book and shared cover',function()
 local entry=init();files['/books/book.epub']=entry('file','epub');files['/books/book.pdf']=entry('file','pdf')
 files['/books/book.sdr']=entry('directory')
 for _,n in ipairs({'metadata.epub.lua','metadata.pdf.lua','cover.png','custom_metadata.lua'}) do files['/books/book.sdr/'..n]=entry('file',n) end
 package.loaded['readcollection'].removeItem=function() end
 local count=require('einkfrontend/bookmaintenance').deleteBook(app,{file='/books/book.epub'});assert(count==0,tostring(count))
 assert(not files['/books/book.sdr/metadata.epub.lua']);assert(files['/books/book.pdf'] and files['/books/book.sdr/metadata.pdf.lua'])
 assert(files['/books/book.sdr/cover.png'] and files['/books/book.sdr/custom_metadata.lua'])
end)
test('HTTP parser rejects duplicate and ambiguous length headers',function()
 init();local W=require('einkfrontend/transferweb');local w=setmetatable({host='127.0.0.1:123',origin='http://127.0.0.1:123',token='secret',expires=1000,app=app},W)
 function w:response(status) return status end
 local head='POST /api/begin HTTP/1.1\r\nHost: '..w.host..'\r\nAuthorization: Bearer secret\r\n'
 assert(w:parse(head..'Content-Length: 0\r\nContent-Length: 0\r\n\r\n')==400)
 assert(w:parse(head..'Transfer-Encoding: chunked\r\n\r\n')==400)
 assert(w:parse(head..'Content-Length: 65537\r\n\r\n')==413)
end)
test('HTTP parser bounds headers and waits for incomplete chunks',function()
 init();local W=require('einkfrontend/transferweb');local w=setmetatable({host='127.0.0.1:123',origin='http://127.0.0.1:123',token='secret',expires=1000,app=app},W)
 function w:response(status) return status end
 assert(w:parse(string.rep('x',8193))==413)
 assert(w:parse('POST /api/chunk/'..id..'/0 HTTP/1.1\r\nHost: '..w.host..'\r\nAuthorization: Bearer secret\r\nContent-Length: 3\r\n\r\na')==nil)
end)
test('expired transfer token cannot finish a pending upload',function()
 init();local W=require('einkfrontend/transferweb');local w=setmetatable({expires=99,app=app},W);function w:response(status) return status end
 assert(w:request('POST','/api/finish/'..id,{},'')==401)
end)
test('excess JSON nesting is rejected before decoder',function()
 init();local W=require('einkfrontend/transferweb');local w=setmetatable({host='127.0.0.1:123',origin='http://127.0.0.1:123',token='secret',expires=1000,app=app},W)
 function w:response(status) return status end
 local decoded=false;package.loaded.rapidjson.decode=function() decoded=true;return {} end
 assert(w:request('POST','/api/begin',{host=w.host,authorization='Bearer secret',['content-type']='application/json'},string.rep('[',9)..'0'..string.rep(']',9))==400)
 assert(not decoded)
end)


test('exception during upload close does not retain a dead session',function()
 init();local s=upload();function s.file:close() self.closed=true;error('injected close exception') end
 assert(not pcall(s.finish,s,id));assert(s.file==nil and s.upload==nil)
end)


test('local reading-status filter survives a return route',function()
 init();local B=require('einkfrontend/browser')
 local r=B.route{id='books',param={status='已完成',statuses={['在读']=true,['bad']=true}}}
 assert(r.param.status=='已完成','local read-status filter was discarded')
 assert(r.param.statuses['在读']==true and not r.param.statuses.bad)
end)
test('saved browser tab retains a local status filter',function()
 init();settings.data.browser_state={tabs={books={stack={{id='books',param={status='已完成'}}}}}}
 local b=require('einkfrontend/browser').new(settings)
 assert(b.tabs.books.stack[1].param.status=='已完成')
end)
local function themeFixture(data,bad_counter)
 init();local store={data=copy(data),file='/themes'}
 function store:readSetting(k) return self.data[k] end
 function store:saveSetting(k,v) self.data[k]=copy(v) end
 function store:flush() return true end
 package.loaded.luasettings={open=function() return {file=store.file,data=copy(store.data),readSetting=function(self,k)
  if bad_counter and k=='counter' then return -1 end;return self.data[k] end,
  saveSetting=store.saveSetting,flush=function(self) store.data=copy(self.data);return true end} end}
 local function equal(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end;return true
 end
 package.loaded['einkfrontend/adapter']={equal=equal}
 return require('einkfrontend/themes').new(),store
end
test('theme creation recovers a missing counter without duplicate ids',function()
 local t=themeFixture({themes={{id='t1',name='old',values={}}}})
 local ok,id=t:create('new',{});assert(ok and id=='t2','theme id collided after missing counter')
end)
test('theme creation recovers a malformed counter from existing ids',function()
 local t=themeFixture({themes={{id='t9',name='old',values={}}},counter='damaged'})
 local called,ok,id=pcall(t.create,t,'new',{});assert(called and ok and id=='t10')
end)
test('duplicate persisted theme ids are preserved and block edits',function()
 local data={themes={{id='t1',name='a',values={}},{id='t1',name='b',values={}}},counter=1}
 local t,store=themeFixture(data);assert(t.error);assert(not t:create('new',{}));assert(#store.data.themes==2)
end)
test('non-array persisted theme records are never silently discarded',function()
 local t,store=themeFixture({themes={legacy={id='t1',name='old',values={}}},counter=1})
 assert(t.error);assert(not t:create('new',{}));assert(store.data.themes.legacy)
end)
test('theme transaction verifies the saved counter as well as records',function()
 local t=themeFixture({themes={},counter=0},true)
 assert(not t:create('new',{}),'counter readback mismatch was ignored');assert(#t.records==0 and t.counter==0)
end)


test('live theme managers keep each other current before the next edit',function()
 local a,store=themeFixture({themes={},counter=0})
 local b=require('einkfrontend/themes').new()
 assert(a:create('a',{}));assert(b:create('b',{}))
 assert(#store.data.themes==2 and store.data.counter==2,'stale theme manager overwrote another edit')
 assert(#a.records==2 and #b.records==2)
end)
local function libraryFixture()
 init();local disk={books={}};local Settings={}
 function Settings:open(file)
  local s={file=file,data=copy(disk)}
  function s:readSetting(k) return self.data[k] end
  function s:saveSetting(k,v) self.data[k]=v end
  function s:flush() disk=copy(self.data);return true end
  return s
 end
 package.loaded.luasettings=Settings
 package.loaded['apps/filemanager/filemanagerbookinfo']={}
 package.loaded['einkfrontend/library']=nil
 package.loaded['readcollection'].removeItem=function() end
 local L=require('einkfrontend/library')
 return L.new({}),L.new({}),function() return disk end
end
test('reader edits survive later library view-state saves',function()
 local a,b,disk=libraryFixture()
 b.settings:saveSetting('reading_return',{version=1,books={['/books/book.epub']={cents=100}}});b.settings:flush()
 a.settings:saveSetting('browser_state',{active='books'});a.settings:flush()
 assert(disk().reading_return,'stale library settings overwrote reader price')
end)
test('library rescans update other live indexes before later saves',function()
 local a,b,disk=libraryFixture();a.books={{file='/books/new.epub',title='new'}};a.root='/books';a:save()
 assert(#b.books==1 and b.books[1].file=='/books/new.epub')
 b:save();assert(#disk().books==1)
end)
test('cleanup does not detach browser settings from the live library store',function()
 local a,b=libraryFixture();local browser=require('einkfrontend/browser').new(a.settings)
 local service=require('einkfrontend/bookmaintenance').new({library=b})
 service:forget({['/books/missing.epub']=true})
 assert(a.settings==browser.settings and a.settings==b.settings,'cleanup left an obsolete settings writer')
end)
test('homepage layout commits synchronize every live layout model',function()
 local _,store=themeFixture({})
 local L=require('einkfrontend/homelayout');local a,b=L.new(),L.new()
 local c=L.defaults();c.spacing='compact';assert(a:commit(c))
 assert(b.config.spacing=='compact','reader layout did not observe library layout edit')
 local d=copy(b.config);d.quote_text='new quote';assert(b:commit(d))
 assert(store.data.layout.spacing=='compact' and a.config.quote_text=='new quote')
end)

AUDIT_RESULT=encode({checks=checks,total=#checks,failed=failed})
