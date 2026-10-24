-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Short classified book actions, with independent subpages for longer edits.
local View={}
local titles={book_reading='�Ķ�',book_info='�鼮��Ϣ',book_organize='�����鼮',book_files='�ļ�����'}
function View.render(app,route,m,row,go)
 if route.id~='book' and not titles[route.id] then return false end
 local book=route.param
 book.authors=book.authors or '����δ֪';book.series=book.series or '';book.title=book.title or book.file:match('([^/]+)$')
 m.settings=true;m.title=route.id=='book' and book.title or titles[route.id];m.subtitle=''
 if route.id=='book' then
  row('�Ķ�',nil,go('book_reading',book))
  row('�鼮��Ϣ',nil,go('book_info',book))
  row('�����鼮',nil,go('book_organize',book))
  row('�ļ�����',nil,go('book_files',book))
 elseif route.id=='book_reading' then
  row('��ʼ�Ķ�',nil,function() app:openLibraryBook(book) end)
  local status,percent=app.library:status(book)
  row('�Ķ�״̬',nil,function() app:chooseReadStatus(book) end)
  m.rows[#m.rows].value=status..(percent and (' '..math.floor(percent*100)..'%') or '')
 elseif route.id=='book_info' then
  row('����������',book.title..' �� '..book.authors,function()
   app.adapter:promptText('����',book.title,function(title)
    app.adapter:promptText('����',book.authors=='����δ֪' and '' or book.authors,function(author)
     return app:userAction(function() app.library:editDetails(book,{title=title,authors=author});app:render() end)
    end,{keep_on_error=true})
   end)
  end)
  local value=require('einkfrontend/bookvalue');local price=app.book_value:price(book.file)
  row('����۸�',price~=nil and '��'..value.money(price) or 'δ��д',function()
   app.adapter:promptText('����۸�Ԫ�����������',value.money(app.book_value:price(book.file)),function(text)
    return app:userAction(function() app.book_value:setPrice(book.file,text);app:render() end)
   end,{keep_on_error=true})
  end)
  row('�鼮�ļ�',book.file)
 elseif route.id=='book_organize' then
  row('�ղع���',nil,go('book_collections',book))
  row('ϵ��',book.series~='' and book.series or 'δ����',function()
   app.adapter:promptText('ϵ������',book.series,function(text)
    return app:userAction(function() app.library:setMetadata(book,'series',text);app:render() end)
   end,{keep_on_error=true})
  end)
  row('����',tostring(book.series_index or 'δ����'),function()
   app.adapter:promptText('ϵ�о���',tostring(book.series_index or ''),function(text)
    return app:userAction(function()
     local value
     if text~='' then value=assert(tonumber(text),'��������Ч����');assert(value==value and math.abs(value)<math.huge,'��������Ч����') end
     app.library:setMetadata(book,'series_index',value);app:render()
    end)
   end,{keep_on_error=true})
  end)
  row('�ָ��鼮ԭϵ��',nil,function()
   app:userAction(function() app.library:setMetadata(book,'series',nil);app.library:setMetadata(book,'series_index',nil);app:render() end)
  end)
 else
  row('�鼮�ļ�',book.file)
  row('ɾ���鼮',nil,function() require('einkfrontend/bookmaintenance').requestDelete(app,book) end)
 end
 return true
end
return View
