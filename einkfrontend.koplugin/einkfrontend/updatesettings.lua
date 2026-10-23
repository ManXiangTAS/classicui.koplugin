-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local U=require('einkfrontend/updater');local B=require('einkfrontend/updateboot');local V={}
function V.render(app,route,m,row,go)
 if route.id~='plugin_update' and route.id~='plugin_update_channel' and route.id~='plugin_update_source' then return false end
 m.settings=true;m.title=route.id=='plugin_update' and '墨页更新' or route.id=='plugin_update_source' and '更新源' or '更新通道';m.subtitle=''
 local config=U.config()
 if route.id=='plugin_update_source' then
  for _,option in ipairs({{'墨页中转（默认）','relay'},{'GitHub 直连','github'}}) do
   local value=option[2];row(option[1],nil,function() U.set('source',value);app:back() end);m.rows[#m.rows].checked=config.source==value
  end
  row('自定义中转地址',nil,function()
   app.adapter:promptText('中转基础地址',config.custom_base,function(value)
    local ok,why=pcall(U.set,'relay_base',value)
    if not ok then app:message(tostring(why));return false end
    app:back()
   end,{keep_on_error=true,input_type='literal'})
  end);m.rows[#m.rows].checked=config.source=='custom'
  row('查看当前地址',nil,function() app:message(config.source=='github' and 'https://api.github.com' or config.relay_base) end)
  return true
 end
 if route.id=='plugin_update_channel' then
  for _,option in ipairs({{'正式版','stable'},{'测试版与正式版','testing'}}) do
   local value=option[2];row(option[1],nil,function() U.set('channel',value);app:back() end)
   m.rows[#m.rows].checked=config.channel==value
  end;return true
 end
 local state=U.state();local pending=B.pending(B.root());local result=B.load(B.work(B.root()),'result.json')
 row('当前版本',nil);m.rows[#m.rows].value=U.current;m.rows[#m.rows].value_width=190
 row('检查更新',nil,function() U.check(app,false) end);m.rows[#m.rows].enabled=not U.job
 if U.job then
  row(U.job.kind=='check' and '正在检查更新' or '正在下载并校验',nil)
  row('取消当前任务',nil,U.cancel)
 end
 local release=state.release
 if release then
  row('可用版本',nil);m.rows[#m.rows].value=release.version;m.rows[#m.rows].value_width=190
  row('更新说明',nil,function() app:message(release.notes~='' and release.notes or '此版本没有附带更新说明') end)
  if not pending or pending.version~=release.version then
   row('下载并准备更新',nil,function()
    app:confirm('下载墨页 '..release.version..'？\n校验后将在下次启动 KOReader 时安装，保留现有配置。',function() U.prepare(app,release,false) end)
   end);m.rows[#m.rows].enabled=not U.job
  end
 end
 if pending then
  row('待安装版本',nil);m.rows[#m.rows].value=pending.version;m.rows[#m.rows].value_width=190
  row('重启并安装',nil,function() app:confirm('保存设置，重启 KOReader 并安装 '..pending.version..'？',function() if U.job then app:message('请先结束当前更新任务');return end;require('ui/uimanager'):flushSettings();require('ui/uimanager'):restartKOReader() end) end);m.rows[#m.rows].enabled=not U.job
  row('取消待安装更新',nil,function() app:confirm('删除已准备的更新？当前版本与配置不变。',function() if U.job then app:message('请先结束当前更新任务');return end;B.clearPending(B.root());app:render() end) end);m.rows[#m.rows].enabled=not U.job
 end
 row('更新源',nil,go('plugin_update_source'));m.rows[#m.rows].value=config.source=='github' and 'GitHub 直连' or config.source=='custom' and '自定义中转' or '墨页中转';m.rows[#m.rows].value_width=190
 if state.info and state.info.stale then row('中转信息尚未刷新',nil,function() app:message('中转正在提供上次成功同步的缓存。可以下载已校验的包，但最新发布信息可能尚未同步。') end) end
 row('自动检查更新',nil,function() U.set('auto_check',not config.auto_check) end);m.rows[#m.rows].checked=config.auto_check
 row('自动更新',nil,function() U.set('auto_install',not config.auto_install) end);m.rows[#m.rows].checked=config.auto_install
 row('更新通道',nil,go('plugin_update_channel'));m.rows[#m.rows].value=config.channel=='stable' and '正式版' or '测试版与正式版';m.rows[#m.rows].value_width=190
 row('自动更新方式',nil,function() app:message('默认关闭自动检查和自动更新。\n开启后，仅在已有网络连接时后台检查，每天最多一次；失败后至少间隔一小时再试，不自动开启 Wi-Fi。\n自动更新会下载并校验官方安装包，下次启动 KOReader 时安装，不在阅读中覆盖代码，也不会自动重启。\n关闭自动检查会同时关闭自动更新。已准备的更新可单独取消。') end)
 if state.checked then row('上次检查',nil);m.rows[#m.rows].value=os.date('%m-%d %H:%M',state.checked);m.rows[#m.rows].value_width=180 end
 if state.error then row('检查或下载失败',nil,function() app:message(state.error) end) end
 if result then row(result.ok and '上次安装完成' or '上次安装已恢复',nil,function() app:message(result.message or '') end) end
 return true
end
return V
