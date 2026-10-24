-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Maintenance=require('einkfrontend/bookmaintenance')
local View={}
function View.open(app)
 if not app.book_maintenance then app.book_maintenance=Maintenance.new(app) end
 app:go('library_cleanup');app.book_maintenance:scan();app:render()
end
function View.render(app,route,m,row)
 if route.id~='library_cleanup' then return false end
 m.settings=true;m.title='清理已删除书籍的数据';m.subtitle=''
 local service=app.book_maintenance
 if not service then row('扫描已删除书籍的数据',nil,function() View.open(app) end);return true end
 m.help=function() app:message('只处理当前书库目录内，已确认文件不存在的书籍数据。\n扫描封面与元数据缓存、失效书库索引、收藏和最近阅读记录，以及已删除书籍的阅读设置、封面、资料和本书价格。历史阅读统计与热力图保留。\n清理前可查看待处理项，执行时再次核对文件；重新放回的书籍会跳过。无法读取的目录、链接路径和无法确认归属的数据不会清理。\n同名不同格式仍存在时保留共享封面和资料；哈希共享元数据保留，避免影响副本。') end
 if service.state=='scanning' then
  row('正在扫描…','扫描期间不会删除任何文件')
  row('取消扫描',nil,function() service:cancel();app:render() end)
 elseif service.state=='cleaning' then row('正在清理…','请保持书库存储设备连接')
 elseif service.state=='ready' then
  local p=service.plan
  row('已删除的书籍',p.count..' 本')
  row('待清理数据文件',#p.files..' 个 · '..string.format('%.1f KB',p.bytes/1024))
  if #p.empty_dirs>0 then row('空残留目录',#p.empty_dirs..' 个') end
  row('历史阅读统计','保留累计时长、页数和热力图')
  if p.skipped>0 or p.truncated then row('部分位置已跳过',p.truncated and '扫描已达上限，可分目录清理' or '有无法读取的位置') end
  if p.count>0 or #p.files>0 or #p.empty_dirs>0 then
   row('清理以上数据',nil,function()
    app:confirm('清理 '..p.count..' 本已删除书籍的记录、'..#p.files..' 个残留文件和 '..#p.empty_dirs..' 个空目录？\n会清除其阅读设置、封面与资料；历史阅读统计保留。',function()
     app:userAction(function() service:apply(p);app:render() end)
    end)
   end)
  else row('没有发现可清理数据','现有书籍及其数据均已保留') end
  row('重新扫描',nil,function() service:scan();app:render() end)
  local shown=0
  for file in pairs(p.books) do
   shown=shown+1;if shown>12 then row('还有更多书籍',p.count..' 本已计入待处理数量');break end
   row(file:match('([^/]+)$'),file)
  end
 elseif service.state=='done' then
  local r=service.result
  row('清理完成',r.books..' 本记录 · '..r.removed..' 个残留文件')
  row('释放空间',string.format('%.1f KB',r.bytes/1024))
  if r.directories>0 then row('空目录已移除',r.directories..' 个') end
  if r.skipped>0 then row('已跳过',r.skipped..' 项发生变化或无法确认') end
  if r.failed>0 then row('部分文件清理失败',r.failed..' 项，可检查存储权限后重试') end
  row('历史阅读统计已保留')
  row('重新扫描',nil,function() service:scan();app:render() end)
 else
  row(service.state=='error' and '清理未完成' or '扫描已取消',service.error or '没有继续处理后续项目')
  row('重新扫描',nil,function() service:scan();app:render() end)
 end
 return true
end
return View
