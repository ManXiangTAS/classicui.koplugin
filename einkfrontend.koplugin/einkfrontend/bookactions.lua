-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Short classified book actions, with independent subpages for longer edits.
local View={}
local titles={book_reading='阅读',book_info='书籍信息',book_organize='整理书籍',book_files='文件操作'}
function View.render(app,route,m,row,go)
 if route.id~='book' and not titles[route.id] then return false end
 local book=route.param
 book.authors=book.authors or '作者未知';book.series=book.series or '';book.title=book.title or book.file:match('([^/]+)$')
 m.settings=true;m.title=route.id=='book' and book.title or titles[route.id];m.subtitle=''
 if route.id=='book' then
  row('阅读','开始阅读 · 阅读状态',go('book_reading',book))
  row('书籍信息','书名与作者 · 本书价格 · 文件位置',go('book_info',book))
  row('整理书籍','收藏归属 · 系列 · 卷序',go('book_organize',book))
  row('文件操作','删除本机书籍',go('book_files',book))
 elseif route.id=='book_reading' then
  row('开始阅读',nil,function() app:openLibraryBook(book) end)
  local status,percent=app.library:status(book)
  row('阅读状态',nil,function() app:chooseReadStatus(book) end)
  m.rows[#m.rows].value=status..(percent and (' '..math.floor(percent*100)..'%') or '')
 elseif route.id=='book_info' then
  row('书名与作者',book.title..' · '..book.authors,function()
   app.adapter:promptText('书名',book.title,function(title)
    app.adapter:promptText('作者',book.authors=='作者未知' and '' or book.authors,function(author)
     return app:userAction(function() app.library:editDetails(book,{title=title,authors=author});app:render() end)
    end,{keep_on_error=true})
   end)
  end)
  local value=require('einkfrontend/bookvalue');local price=app.book_value:price(book.file)
  row('本书价格',price~=nil and '¥'..value.money(price) or '未填写',function()
   app.adapter:promptText('本书价格（元，留空清除）',value.money(app.book_value:price(book.file)),function(text)
    return app:userAction(function() app.book_value:setPrice(book.file,text);app:render() end)
   end,{keep_on_error=true})
  end)
  row('书籍文件',book.file)
 elseif route.id=='book_organize' then
  row('收藏归属',nil,go('book_collections',book))
  row('系列',book.series~='' and book.series or '未设置',function()
   app.adapter:promptText('系列名称',book.series,function(text)
    return app:userAction(function() app.library:setMetadata(book,'series',text);app:render() end)
   end,{keep_on_error=true})
  end)
  row('卷序',tostring(book.series_index or '未设置'),function()
   app.adapter:promptText('系列卷序',tostring(book.series_index or ''),function(text)
    return app:userAction(function()
     local value
     if text~='' then value=assert(tonumber(text),'请输入有效数字');assert(value==value and math.abs(value)<math.huge,'请输入有效数字') end
     app.library:setMetadata(book,'series_index',value);app:render()
    end)
   end,{keep_on_error=true})
  end)
  row('恢复书籍原系列','清除本机系列和卷序覆盖',function()
   app:userAction(function() app.library:setMetadata(book,'series',nil);app.library:setMetadata(book,'series_index',nil);app:render() end)
  end)
 else
  row('书籍文件',book.file)
  row('删除书籍','永久删除本机文件；历史阅读统计保留',function() require('einkfrontend/bookmaintenance').requestDelete(app,book) end)
 end
 return true
end
return View
