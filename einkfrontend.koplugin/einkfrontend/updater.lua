-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- One non-modal worker, shared by FileManager and Reader instances.
local UI=require('ui/uimanager');local fs=require('ffi/util');local json=require('json')
local B=require('einkfrontend/updateboot');local C=require('einkfrontend/updatecore');local S=require('einkfrontend/updatesource')
local U={owners=setmetatable({},{__mode='k'}),current=require('einkfrontend/version')}
function U.config()
 local value=G_reader_settings:readSetting('eink_updater');value=type(value)=='table' and value or {}
 local source=value.source=='github' and 'github' or value.source=='custom' and 'custom' or 'relay'
 local valid,base=pcall(S.base,value.custom_base or value.relay_base or S.default_base)
 if not valid then base=S.default_base end
 return {auto_check=value.auto_check==true,auto_install=value.auto_check==true and value.auto_install==true,
  source=source,custom_base=base,relay_base=source=='custom' and base or S.default_base,
  channel=value.channel=='stable' and 'stable' or value.channel=='testing' and 'testing' or U.current:find('-',1,true) and 'testing' or 'stable'}
end
function U.state()
 local v=G_reader_settings:readSetting('eink_updater_state');v=type(v)=='table' and v or {}
 if v.context~=S.key(U.config()) then return {} end
 if type(v.release)~='table' or not C.newer(v.release.version,U.current) then v.release=nil end
 return v
end
function U.save(value)
 value.context=S.key(U.config());G_reader_settings:saveSetting('eink_updater_state',value);G_reader_settings:flush()
end
function U.render()
 for owner in pairs(U.owners) do local app=owner.app
  if owner.active and app.adapter:alive() and app.screen and app.screen.model.route.id=='plugin_update' then app:render() end
 end
end
function U.valid(app) return app and app.plugin.active and app.adapter:alive() and app.screen and app.screen.model.route.id=='plugin_update' end
function U.cancel()
 local job=U.job;if not job or job.cancelled then return end
 job.cancelled=true;UI:unschedule(job.poll);fs.terminateSubProcess(job.pid)
 local function reap()
  if fs.isSubProcessDone(job.pid) then
   fs.readAllFromFD(job.fd);if U.job==job then U.job=nil end;UI:allowStandby()
   if job.kind=='download' then
    local root=B.root();local pending=B.pending(root)
    if pending and pending.version~=job.pending_before then pcall(B.clearPending,root) end
    pcall(B.removeTree,B.work(root)..'/incoming');os.remove(B.work(root)..'/download.zip')
   end
   U.render()
  else UI:scheduleIn(.2,reap) end
 end
 reap()
end
function U.run(kind,task,done)
 if U.job then return false end
 UI:preventStandby()
 local ffi=require('ffi');local parent=tonumber(ffi.C.getpid())
 local pid,fd=fs.runInSubProcess(function(_,write_fd)
  if ffi.os=='Linux' then
   ffi.cdef('int prctl(int option, ...); int getppid(void);')
   assert(ffi.C.prctl(1,ffi.cast('unsigned long',9),ffi.cast('unsigned long',0),ffi.cast('unsigned long',0),ffi.cast('unsigned long',0))==0,'无法设置更新子进程生命周期')
   if tonumber(ffi.C.getppid())~=parent then return end
  end
  local ok,value=pcall(task);local result={ok=ok,result=ok and value or nil,error=not ok and C.short(tostring(value),160) or nil,retry_at=not ok and type(value)=='table' and value.retry_at or nil}
  local output=json.encode(result);if #output>3500 then output=json.encode({ok=false,error='更新任务返回的数据过大'}) end
  fs.writeToFD(write_fd,output,true)
 end,true)
 if not pid then UI:allowStandby();done({ok=false,error='无法启动更新任务'});return false end
 local job={pid=pid,fd=fd,kind=kind,started=os.time()};U.job=job
 job.poll=function()
  if U.job~=job then return end
  if fs.isSubProcessDone(pid) then
   U.job=nil;UI:allowStandby()
   local text=fs.readAllFromFD(fd);local ok,value=pcall(json.decode,text)
   done(ok and type(value)=='table' and value or {ok=false,error='更新任务未返回有效结果'});U.render()
  elseif os.time()-job.started>(kind=='download' and 360 or 180) then
   U.cancel();done({ok=false,error='更新请求超时，请检查网络或稍后重试'})
  else UI:scheduleIn(.2,job.poll) end
 end
 UI:scheduleIn(.2,job.poll);U.render();return true
end
function U.error(app,why,retry_at)
 local state=U.state();state.error=C.short(tostring(why),160);state.retry_at=retry_at;U.save(state)
 if U.valid(app) then app:message(state.error) end;U.render()
end
function U.waiting(app)
 local retry=tonumber(U.state().retry_at)
 if retry and retry>os.time() then
  if U.valid(app) then app:message('更新源要求稍后重试，请在 '..os.date('%m-%d %H:%M',retry)..' 后再试') end
  return true
 end
end
function U.prepare(app,release,automatic)
 if U.job then if U.valid(app) then app:message('已有更新任务正在运行') end;return end
 if U.waiting(automatic and nil or app) then return end
 local config=U.config();local context=S.key(config)
 if (config.source=='github' and release.relay_base) or (config.source~='github' and release.relay_base~=config.relay_base) then
  U.error(automatic and nil or app,'更新源已改变，请重新检查更新');return
 end
 local root=B.root();local previous=B.pending(root)
 local attempted=U.state();attempted.download_attempt=os.time();U.save(attempted)
 U.run('download',function() return C.prepare(root,release,U.current,config) end,function(result)
  if S.key(U.config())~=context then return end
  if not result.ok then U.error(automatic and nil or app,result.error,result.retry_at);return end
  local state=U.state();state.error=nil;state.retry_at=nil
  local outcome=result.result or {}
  if outcome.release then state.release=outcome.release end
  if outcome.info then state.info=outcome.info end
  if outcome.no_update then state.release=nil end
  U.save(state)
  if U.valid(app) then app:message(outcome.no_update and '更新源已刷新，当前没有可下载的新版本' or '更新已下载并校验，将在下次启动 KOReader 时安装。当前阅读不会中断。') end
 end)
 if U.job and U.job.kind=='download' then U.job.version=release.version;U.job.pending_before=previous and previous.version or false end
end
function U.check(app,automatic)
 if U.job then if U.valid(app) then app:message('已有更新任务正在运行') end;return end
 if U.waiting(automatic and nil or app) then return end
 local function begin()
  if not automatic and not U.valid(app) then return end
  local config=U.config();local context=S.key(config);if automatic and not config.auto_check then return end
  local state=U.state();state.attempt=os.time();U.save(state)
  U.run('check',function()
   local release,info=C.fetch(U.current,config.channel,config);return {release=release,info=info}
  end,function(result)
   if S.key(U.config())~=context then return end
   if not result.ok then U.error(automatic and nil or app,result.error,result.retry_at);return end
   local state=U.state();state.checked=os.time();state.error=nil;state.retry_at=nil;state.release=result.result and result.result.release;state.info=result.result and result.result.info;U.save(state)
   local release=state.release;local config_now=U.config()
   if automatic and config_now.auto_install and release then
    local pending=B.pending(B.root())
    if not pending or C.newer(release.version,pending.version) then U.prepare(nil,release,true) end
   elseif not automatic and U.valid(app) and not release then
    local text=state.info and state.info.status=='no_release' and '此通道暂无发布' or '当前通道没有比 '..U.current..' 更新的版本'
    if state.info and state.info.stale then text=text..'；中转信息尚未刷新' end
    app:message(text)
   end
  end)
 end
 local network=require('ui/network/manager')
 if automatic then if network:isConnected() then begin() end
 else network:runWhenOnline(begin) end
end
function U.schedule()
 if U.timer then UI:unschedule(U.timer) end
 if not U.config().auto_check or not next(U.owners) then return end
 U.timer=function()
  U.timer=nil;if not next(U.owners) or not U.config().auto_check then return end
  local state=U.state();local now=os.time();local last=tonumber(state.checked) or 0;local attempt=tonumber(state.attempt) or 0
  local pending=B.pending(B.root());local download_attempt=tonumber(state.download_attempt) or 0
  if (tonumber(state.retry_at) or 0)>now then return end
  if U.config().auto_install and state.release and (not pending or C.newer(state.release.version,pending.version)) and (now<download_attempt or now-download_attempt>=3600) and require('ui/network/manager'):isConnected() then U.prepare(nil,state.release,true);return end
  if now>=last and now-last<86400 or now>=attempt and now-attempt<3600 then return end
  U.check(nil,true)
 end
 UI:scheduleIn(5,U.timer)
end
function U.set(key,value)
 assert(key=='auto_check' or key=='auto_install' or key=='channel' or key=='source' or key=='relay_base')
 if key=='source' then assert(value=='relay' or value=='github' or value=='custom','更新源无效') end
 if key=='channel' then assert(value=='stable' or value=='testing','更新通道无效') end
 if key=='relay_base' then value=S.base(value) end
 local config=U.config();config[key]=value
 if key=='relay_base' then config.source='custom';config.custom_base=value end
 if key=='auto_install' and value then config.auto_check=true end
 if key=='auto_check' and not value then config.auto_install=false end
 U.cancel();G_reader_settings:saveSetting('eink_updater',config)
 if key=='source' or key=='relay_base' or key=='channel' then G_reader_settings:delSetting('eink_updater_state') end
 G_reader_settings:flush();U.schedule();U.render()
end
function U.attach(owner) U.owners[owner]=true;U.schedule() end
function U.detach(owner)
 U.owners[owner]=nil;if next(U.owners) then return end
 if U.timer then UI:unschedule(U.timer);U.timer=nil end;U.cancel()
end
function U.suspend()
 if U.timer then UI:unschedule(U.timer);U.timer=nil end;U.cancel()
end
function U.resume() U.schedule() end
return U
