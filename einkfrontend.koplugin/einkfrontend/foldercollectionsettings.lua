-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Import=require('einkfrontend/foldercollections')
local View={}
function View.render(app,route,m,row)
 if route.id~='folder_collections' then return false end
 m.settings=true;m.title='文件夹转为收藏';m.subtitle=''
 if not app.folder_import then app.folder_import=Import.new(app) end
 local service=app.folder_import
 local view={state=service.state,source=service.plan and service.plan.root or service.source or app.library.root,
  notices={},secondary={}}
 m.folder_import=view
 local function scan(path)
  app:userAction(function() service:scan(path) end);app:render()
 end
 local function choose()
  app.adapter:chooseLibraryRoot(view.source or app.adapter:libraryRoot(),scan,
   {title='选择分类文件夹的上级目录：长按确认'})
 end
 local function collections() app:open('collections');app:selectLibraryTab('collections') end
 m.help=function() app:message('选择包含分类文件夹的上级目录。例如目录中有“文学/鲁迅”，就会生成“文学”和“文学/鲁迅”收藏。父目录收藏包含其子目录中的书。\n“新增”表示新建收藏；“补入”表示只添加现有收藏中缺少的书；“已导入”表示无需重复操作。\n根目录散放的书籍保留原样；空目录、图片、隐藏目录、阅读数据目录和链接不导入。\n原文件、现有收藏和书库目录保留。导入前自动备份收藏；新增书籍后可再次扫描导入。') end
 if service.state=='scanning' then
  view.headline='正在扫描…';view.description='扫描期间不会修改书籍或收藏'
  view.primary={text='取消扫描',callback=function() service:cancel();app:render() end}
 elseif service.state=='ready' then
  local plan=service.plan;local summary=service:summary(plan)
  local pending=summary.created+summary.merged
  view.source=plan.root
  if #plan.groups==0 then
   view.headline='没有找到分类文件夹'
   view.description='请选择包含分类文件夹的上级目录'
   view.primary={text='更换文件夹',callback=choose}
  elseif pending==0 then
   view.headline='全部已导入'
   view.description=#plan.groups..' 个收藏已包含对应书籍，无需重复导入'
   view.primary={text='查看收藏',callback=collections}
  else
   view.headline='可导入 '..pending..' 个收藏'
   local parts={}
   if summary.created>0 then parts[#parts+1]='新增 '..summary.created..' 个' end
   if summary.merged>0 then parts[#parts+1]='补入 '..summary.merged..' 个' end
   if summary.unchanged>0 then parts[#parts+1]='已导入 '..summary.unchanged..' 个' end
   view.description=table.concat(parts,' · ')
   view.primary={text='导入 '..pending..' 个收藏',callback=function()
    app:confirm('新建 '..summary.created..' 个收藏，向 '..summary.merged..' 个现有收藏补入书籍？\n不会移动书籍或移除原有收藏成员。',function()
     app:userAction(function() service:apply(plan) end);app:render()
    end)
   end}
  end
  for _,group in ipairs(summary.groups) do
   row(group.name,nil);local r=m.rows[#m.rows]
   r.count=group.count;r.import_status=group.status
  end
  if plan.loose>0 then view.notices[#view.notices+1]=plan.loose..' 本散放书籍保留原样' end
  if plan.skipped>0 then view.notices[#view.notices+1]='已跳过 '..plan.skipped..' 个链接或无法读取的位置' end
  view.secondary={{text='重新扫描',callback=function() scan(plan.root) end},
   {text='更换文件夹',callback=choose}}
 elseif service.state=='done' then
  local result=service.result
  view.headline='导入完成'
  view.description='新增 '..result.created..' 个收藏 · 补入 '..result.merged..' 个收藏'
  view.notices={'书籍仍保存在原文件夹中'}
  view.primary={text='查看收藏',callback=collections}
  view.secondary={{text='继续导入',callback=choose}}
 else
  view.headline=service.state=='error' and '扫描未完成' or service.state=='cancelled' and '扫描已取消' or '保留原来的文件夹分类'
  view.description=service.state=='error' and tostring(service.error) or '选择旧书库，预览后转为收藏'
  view.notices={'原书籍位置与已有收藏保持不变'}
  view.primary={text='选择文件夹',callback=choose}
  if app.library.root then view.secondary={{text='使用当前书库',callback=function() scan(app.library.root) end}} end
 end
 return true
end
return View
