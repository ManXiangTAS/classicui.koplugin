-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local T={};local UI=require('ui/uimanager');local Store=require('einkfrontend/transferstore')
function T.config() local c=G_reader_settings:readSetting('eink_transfer');return type(c)=='table' and c or {} end
function T.path(app) return T.config().path or app.library.root or Store.default end
function T.configure(app,path)
 local root=Store.directory(path,true);local old=T.config();local config={path=root,configured=true}
 G_reader_settings:saveSetting('eink_transfer',config)
 if G_reader_settings:flush()==false then G_reader_settings:saveSetting('eink_transfer',old);error('无法保存传书目录') end
 if app.transfer_server then app.transfer_server:stop() end
 app.library:cancel();app.library:clearCovers();app.library.root=root;app.library.books={};app.library:save();app:scanLibrary(root)
 return root
end
function T.wizard(app,force)
 if not force and T.config().configured then return end
 app:open('transfer_setup')
end
function T.start(app)
 if app.transfer_server and not app.transfer_server.stopped then app.transfer_server:showAddress();return end
 if not T.config().configured then T.wizard(app,true);return end
 require('ui/network/manager'):runWhenConnected(function()
  if not app.plugin.active or not app.adapter:alive() then return end
  app:userAction(function()
   app.transfer_server=require('einkfrontend/transferweb').new(app,{root=T.path(app)});app.transfer_server:showAddress();app:render()
  end)
 end)
end
function T.render(app,route,m,row,go)
 if route.id~='transfer_settings' and route.id~='transfer_setup' then return false end
 m.settings=true;m.title=route.id=='transfer_setup' and '传书向导' or '传书与书库';m.subtitle=''
 if route.id=='transfer_setup' then
  row('设置传书与书库目录',T.path(app))
  row('使用 ManualBook 默认目录',nil,function() app:userAction(function() T.configure(app,Store.default);app:open('transfer_settings') end) end)
 end
 row('选择文件夹',nil,function() app.adapter:chooseLibraryRoot(app.library.root or app.adapter:libraryRoot(),function(path)
  app:userAction(function() T.configure(app,path);app:open('transfer_settings') end)
 end) end)
 row('输入或新建目录',T.path(app),function() app.adapter:promptText('传书与书库目录',T.path(app),function(path)
  return app:userAction(function() T.configure(app,path);app:open('transfer_settings') end)
 end,{keep_on_error=true}) end)
 if route.id=='transfer_setup' then
  row('保留当前书库，稍后设置',nil,function()
   local c=T.config();c.wizard_seen=true;G_reader_settings:saveSetting('eink_transfer',c);G_reader_settings:flush();app:open('library')
  end)
 else
  row(app.transfer_server and '查看传书地址与二维码' or '开启网页传书',nil,function() T.start(app) end)
  if app.transfer_server then row('关闭网页传书',nil,function() app.transfer_server:stop();app:render() end) end
  row('重新扫描书库',nil,function() app:scanLibrary(T.path(app)) end)
  row('重新运行传书向导',nil,function() T.wizard(app,true) end)
 end
 m.help=function() app:message('手机或电脑与 Kindle 连接同一 Wi-Fi，开启网页传书后扫码。接收目录同时作为墨页书库目录，修改后保留原有书籍文件。\nEPUB 重排在发送网页上手动勾选，支持高级设置和前后预览。关闭传书、休眠或退出后地址失效；30分钟后自动结束。') end
 return true
end
return T
