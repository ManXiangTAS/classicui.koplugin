-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Native document, ToC and annotation data; no parallel bookmark store.
local Event=require("ui/event")
local Equal=require("einkfrontend/adapter").equal
local Copy=require("einkfrontend/catalog").copy
local Data={};Data.__index=Data
function Data.new(ui) return setmetatable({ui=ui},Data) end
local function matches(text,query) return not query or query=="" or tostring(text or ""):lower():find(query:lower(),1,true)~=nil end
function Data:tocRows(collapsed,query)
 local module=self.ui.toc;module:fillToc();local toc=module.toc or {};local rows={}
 local current=self.ui.rolling and module:getAccurateTocIndexByXPointer(self.ui.document:getXPointer()) or module:getTocIndexByPage(self.ui:getCurrentPage())
 local hidden_depth
 for i,item in ipairs(toc) do
  local depth=item.depth or 1
  if hidden_depth and depth<=hidden_depth then hidden_depth=nil end
  local title=module:cleanUpTocTitle(item.title,true)
  local children=toc[i+1] and (toc[i+1].depth or 1)>depth or false
  if (query and query~="" or not hidden_depth) and matches(title,query) then
   local page=self.ui.pagemap and self.ui.pagemap:wantsPageLabels() and item.xpointer and self.ui.pagemap:getXPointerPageLabel(item.xpointer) or tostring(item.page)
   rows[#rows+1]={title=title,page=page,depth=depth,index=i,item=item,children=children,current=i==current}
  end
  if collapsed[i] and (not query or query=="") and not hidden_depth then hidden_depth=depth end
 end
 return rows,current,toc
end
function Data:annotationRows(filter,query,reverse)
 local bm=self.ui.bookmark;local rows={}
 for i,item in ipairs(self.ui.annotation.annotations) do
  local kind=bm.getBookmarkType(item)
  if (filter=="bookmarks" and kind=="bookmark" or filter=="annotations" and kind~="bookmark") and matches((item.text or "").."\n"..(item.note or "").."\n"..(item.chapter or ""),query) then
   rows[#rows+1]={title=item.text or item.chapter or "页面书签",note=item.note,chapter=item.chapter,
    page=bm:getBookmarkPageString(item.page),pageno=bm:getBookmarkPageNumber(item),item=item,index=i,kind=kind,datetime=item.datetime or ""}
  end
 end
 table.sort(rows,function(a,b)
  if a.pageno~=b.pageno then return reverse and a.pageno>b.pageno or not reverse and a.pageno<b.pageno end
  return reverse and a.index>b.index or not reverse and a.index<b.index
 end)
 return rows
end
function Data:resolve(item)
 local all=self.ui.annotation.annotations
 if type(item)=="number" then return assert(all[item],"标注已不存在"),item end
 for i,v in ipairs(all) do if v==item then return v,i end end
 for i,v in ipairs(all) do
  if Equal(v.page,item.page) and v.datetime==item.datetime and Equal(v.pos0,item.pos0) and Equal(v.pos1,item.pos1) then return v,i end
 end
 error("标注已不存在，请刷新列表")
end
function Data:jump(row,is_toc)
 self.ui.link:addCurrentLocationToStack()
 if is_toc then
  local item=row.item
  self.ui:handleEvent(item.xpointer and Event:new("GotoXPointer",item.xpointer,item.xpointer) or Event:new("GotoPage",item.page))
 else local item=self:resolve(row.item);self.ui.bookmark:gotoBookmark(item.page,item.pos0) end
end
function Data:save()
 self.ui:saveSettings()
 local stored=require("docsettings"):open(self.ui.document.file):readSetting("annotations") or {}
 assert(Equal(stored,self.ui.annotation.annotations),"书签/标注未能写入，请检查存储空间与权限")
end
-- Native callbacks are synchronous. Hold notifications and PDF writes until the
-- sidecar is durable; restore the original objects (including their identities)
-- on failure so later native autosaves cannot commit a rejected operation.
function Data:transaction(change)
 local ui=self.ui;local annotation=ui.annotation;local highlight=ui.highlight
 local list=annotation.annotations;local originals,values={},{}
 for i,item in ipairs(list) do originals[i]=item;values[i]=Copy(item) end
 local settings=Copy(ui.doc_settings.data)
 local handler,pdf=ui.handleEvent,highlight.writePdfAnnotation
 local own_handler,own_pdf=rawget(ui,"handleEvent"),rawget(highlight,"writePdfAnnotation")
 local events,writes={},{}
 ui.handleEvent=function(owner,event,...)
  if event.handler=="onAnnotationsModified" then
   annotation:onAnnotationsModified(event.args[1]);events[#events+1]=event;return true
  end
  return handler(owner,event,...)
 end
 highlight.writePdfAnnotation=function(_,action,item,content)
  writes[#writes+1]={action=action,item=Copy(item),content=content}
 end
 local ok,why=pcall(function() change();self:save() end)
 ui.handleEvent=own_handler;highlight.writePdfAnnotation=own_pdf
 if not ok then
  for k in pairs(list) do list[k]=nil end
  for i,item in ipairs(originals) do
   for k in pairs(item) do item[k]=nil end
   for k,v in pairs(values[i]) do item[k]=v end
   list[i]=item
  end
  annotation.annotations=list;ui.doc_settings.data=settings
  -- A writer may have failed after replacing a file: attempt to persist the
  -- restored state too. A still-failing disk must never be reported as success.
  local restored=pcall(self.save,self)
  pcall(ui.bookmark.setDogearVisibility,ui.bookmark,ui.bookmark:getCurrentPageNumber())
  pcall(ui.view.footer.maybeUpdateFooter,ui.view.footer)
  error(tostring(why)..(restored and "；已恢复原标注" or "；内存已恢复，请检查存储后重新保存"),0)
 end
 -- Timestamps were staged before persistence. Do not stamp a second time while
 -- notifying native view/statistics consumers of the now-committed operation.
 local own_modified=rawget(annotation,"onAnnotationsModified")
 annotation.onAnnotationsModified=function() end
 local notified,notice=pcall(function() for _,event in ipairs(events) do handler(ui,event) end end)
 annotation.onAnnotationsModified=own_modified
 local written,write_error=pcall(function()
  for _,write in ipairs(writes) do pdf(highlight,write.action,write.item,write.content) end
 end)
 if not written then return "标注已保存，但 PDF 写回失败："..tostring(write_error) end
 if not notified then return "标注已保存，但显示更新失败："..tostring(notice) end
end
function Data:toggleCurrent()
 return self:transaction(function() self.ui.bookmark:onToggleBookmark() end)
end
function Data:remove(item)
 return self:transaction(function()
  local canonical,index=self:resolve(item);self.ui.bookmark:removeItem(canonical,index)
 end)
end
function Data:setNote(item,text)
 assert(type(text)=="string","笔记需要文本")
 return self:transaction(function()
 local canonical=self:resolve(item);local bm=self.ui.bookmark;local before=bm.getBookmarkType(canonical)
 self.ui.highlight:writePdfAnnotation("content",canonical,text)
 canonical.note=text~="" and text or nil
 local after=bm.getBookmarkType(canonical)
 local change={canonical}
 if before~=after then change.nb_highlights_added=before=="highlight" and -1 or 1;change.nb_notes_added=before=="highlight" and 1 or -1 end
 self.ui:handleEvent(Event:new("AnnotationsModified",change))
 end)
end
function Data:setText(item,text)
 return self:transaction(function()
 local canonical,index=self:resolve(item);assert(canonical.drawer,"页面书签没有摘录文本")
 assert(not self.ui.bookmark.bookmark_menu,"请先关闭原生书签管理")
 self.ui.bookmark:setHighlightedText(index,text,function() end)
 self.ui:handleEvent(Event:new("AnnotationsModified",{canonical}))
 end)
end
return Data
