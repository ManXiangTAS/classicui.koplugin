-- Original project code. SPDX-License-Identifier: AGPL-3.0-or-later
-- Backend evidence at KOReader 9192014d8bd82a91dc1012473be0f238dedfdb54:
-- filemanagerbookinfo.lua:getDocProps; documentregistry.lua:openDocument;
-- docsettings.lua:open; readcollection.lua:addCollection/addItem/removeItem/write.
local UIManager=require("ui/uimanager")
local DataStorage=require("datastorage")
local LuaSettings=require("luasettings")
local DocSettings=require("docsettings")
local Registry=require("document/documentregistry")
local BookInfo=require("apps/filemanager/filemanagerbookinfo")
local lfs=require("libs/libkoreader-lfs")
local ffiUtil=require("ffi/util")
local Library={}
Library.__index=Library
Library.instances=setmetatable({},{__mode='k'})

function Library.new(ui)
    local file=DataStorage:getSettingsDir().."/einkfrontend-library.lua"
    -- Reader and file-manager instances must not flush competing snapshots.
    local settings
    for instance in pairs(Library.instances) do
        if instance.settings.file==file then settings=instance.settings;break end
    end
    settings=settings or LuaSettings:open(file)
    local self=setmetatable({ui=ui,settings=settings,books=settings:readSetting("books") or {},
        root=settings:readSetting("root"),covers={},cover_order={}},Library)
    Library.instances[self]=true;return self
end

function Library:save()
    self.settings:saveSetting("root",self.root)
    self.settings:saveSetting("books",self.books)
    assert(self.settings:flush()~=false,"��Ᵽ��ʧ��")
    for instance in pairs(Library.instances) do
        if instance~=self and instance.settings.file==self.settings.file then
            instance:cancel();instance:clearCovers()
            instance.settings=self.settings;instance.books=self.books;instance.root=self.root
        end
    end
end

function Library:cancel()
    if self.tick then UIManager:unschedule(self.tick) end
    self.tick=nil;self.job=nil
end

function Library:clearCovers()
    for _,bb in pairs(self.covers) do if bb then bb:free() end end
    self.covers={};self.cover_order={}
end

function Library:close() self:cancel();self:clearCovers() end

function Library:status(book)
    local data=DocSettings:open(book.file)
    local summary=data:readSetting("summary")
    local percent=data:readSetting("percent_finished")
    if type(percent)~="number" or percent~=percent then percent=nil end
    if percent then percent=math.max(0,math.min(1,percent)) end
    if summary and summary.status=="new" then return "δ��",nil end
    if summary and summary.status=="complete" then return "�����",1 end
    if summary and summary.status=="abandoned" then return "����",percent end
    if summary and summary.status=="reading" then return "�ڶ�",percent end
    if percent and percent>0 then return "�ڶ�",percent end
    return "δ��",nil
end

function Library:scan(path,callback)
    self:cancel()
    path=assert(ffiUtil.realpath(path),"���Ŀ¼������")
    assert(lfs.attributes(path,"mode")=="directory","��ѡ������ļ���")
    local old={}
    for _,book in ipairs(self.books) do old[book.file]=book end
    local found,errors,truncated={},0,false
    local count=0
    local info=BookInfo:new{ui=self.ui}
    local co=coroutine.create(function()
        local function visit(dir,depth)
            if depth>32 or truncated then return end
            local ok,iter,state=pcall(lfs.dir,dir)
            if not ok then errors=errors+1;return end
            for entry in iter,state do
                if entry:sub(1,1)~="." and not entry:match("%.sdr$") and entry~="koreader" and entry~="system" then
                    local file=dir.."/"..entry
                    local attr=lfs.symlinkattributes(file)
                    if attr and attr.mode=="directory" then visit(file,depth+1)
                    elseif attr and attr.mode=="file" and Registry:hasProvider(file) and not Registry:isImageFile(file) then
                        if #found>=10000 then truncated=true;break end
                        local cached=old[file]
                        local book
                        if cached and cached.mtime==attr.modification and cached.size==attr.size then book=cached
                        else
                            local success,props=pcall(info.getDocProps,info,file,nil,false)
                            if not success then props={};errors=errors+1 end
                            props=props or {}
                            book={file=file,title=props.display_title or props.title or entry,
                                authors=props.authors or "����δ֪",series=props.series or "",
                                series_index=props.series_index,mtime=attr.modification,size=attr.size}
                        end
                        found[#found+1]=book
                        coroutine.yield(#found)
                    end
                end
                count=count+1
                if count%24==0 then coroutine.yield(#found) end
            end
        end
        visit(path,0)
        table.sort(found,function(a,b) return a.title<b.title end)
    end)
    self.job=co
    local function step()
        if self.job~=co then return end
        local ok,value=coroutine.resume(co)
        if not ok then
            self:cancel();callback(false,tostring(value));return
        end
        if coroutine.status(co)=="dead" then
            self.job=nil;self.tick=nil
            self.root=path;self.books=found;self:clearCovers();self:save()
            callback(true,string.format("%d �� �� %d ���ȡ�쳣%s",#found,errors,truncated and " �� �ѵ�10000������" or ""))
        else
            callback(nil,string.format("����������%d ��",value or #found))
            if self.job==co then UIManager:scheduleIn(0.01,self.tick) end
        end
    end
    self.tick=function()
        local ok,err=pcall(step)
        if not ok then self:cancel();pcall(callback,false,tostring(err)) end
    end
    UIManager:nextTick(self.tick)
end

function Library:groups(field,filter,sort)
    local counts={}
    local representatives={}
    local order={}
    for index,book in ipairs(self:list(filter,sort)) do
        local value=book[field]
        if value and value~="" then
            counts[value]=(counts[value] or 0)+1;representatives[value]=representatives[value] or book
            order[value]=order[value] or index
        end
    end
    local groups={}
    for name,count in pairs(counts) do groups[#groups+1]={name=name,count=count,book=representatives[name]} end
    table.sort(groups,function(a,b)
        if sort and sort~="title" and order[a.name]~=order[b.name] then return order[a.name]<order[b.name] end
        return a.name<b.name
    end)
    return groups
end

function Library:list(filter,sort,query)
    local books={}
    query=query or (filter and filter.query)
    local last_opened={}
    if sort=="last_opened" then
        for _,entry in ipairs(require("readhistory").hist) do
            if not entry.dim then last_opened[entry.file]=tonumber(entry.time) or 0 end
        end
    end
    local collection=filter and filter.collection and require("readcollection").coll[filter.collection]
    for _,book in ipairs(self.books) do
        local include=lfs.attributes(book.file,"mode")=="file"
        if filter and filter.field then include=include and book[filter.field]==filter.value end
        if filter and filter.collection then include=include and collection and collection[book.file]~=nil end
        local status=self:status(book)
        if filter and filter.status then include=include and status==filter.status end
        if filter and filter.statuses and next(filter.statuses) then
            include=include and filter.statuses[status]==true
        end
        if query and query~="" then
            local hay=(book.title.." "..book.authors.." "..book.series):lower()
            include=include and hay:find(query:lower(),1,true)~=nil
        end
        if include then books[#books+1]=book end
    end
    table.sort(books,function(a,b)
        if sort=="last_opened" then
            local at,bt=last_opened[a.file] or 0,last_opened[b.file] or 0
            if at~=bt then return at>bt end
        end
        if sort=="author" and a.authors~=b.authors then return a.authors<b.authors end
        if sort=="recent" and a.mtime~=b.mtime then return a.mtime>b.mtime end
        if filter and filter.field=="series" then
            local ai,bi=tonumber(a.series_index) or math.huge,tonumber(b.series_index) or math.huge
            if ai~=bi then return ai<bi end
        end
        if a.title==b.title then return a.file<b.file end
        return a.title<b.title
    end)
    return books
end

function Library:cover(file)
    if self.covers[file]~=nil then return self.covers[file] or nil end
    local doc,bb
    local ok=pcall(function()
        local cover=DocSettings:findCustomCoverFile(file)
        doc=Registry:openDocument(cover or file)
        if doc then
            if doc.loadDocument and not doc:loadDocument(false) then return end
            bb=doc:getCoverPageImage()
        end
    end)
    if doc then pcall(doc.close,doc) end
    if not ok and bb then bb:free();bb=nil end
    if bb then
        local ratio=math.min(240/bb:getWidth(),360/bb:getHeight(),1)
        if ratio<1 then
            local scaled=bb:scale(math.max(1,math.floor(bb:getWidth()*ratio)),math.max(1,math.floor(bb:getHeight()*ratio)))
            bb:free();bb=scaled
        end
    end
    if #self.cover_order>=12 then
        local expired=table.remove(self.cover_order,1)
        if self.covers[expired] then self.covers[expired]:free() end
        self.covers[expired]=nil
    end
    self.covers[file]=bb or false;self.cover_order[#self.cover_order+1]=file
    return bb
end

function Library:collectionLabel(name)
    if name==require("readcollection").default_collection_name then return "�ղؼ�" end
    if name:lower()=="to be read" then return "����" end
    return name
end

function Library:collectionVisible(name)
 local hidden=self.settings:readSetting("hidden_collections")
 return type(hidden)~="table" or hidden[name]~=true
end
function Library:setCollectionVisible(name,visible)
 local Copy=require("einkfrontend/catalog").copy
 if not require("readcollection").coll[name] then return false,"�ղ��Ѿ�������" end
 local before=Copy(self.settings.data);local hidden=self.settings:readSetting("hidden_collections")
 hidden=type(hidden)=="table" and Copy(hidden) or {};hidden[name]=not visible or nil
 local ok,why=pcall(function()
  self.settings:saveSetting("hidden_collections",hidden);self.settings:flush()
  assert(require("einkfrontend/adapter").equal(LuaSettings:open(self.settings.file):readSetting("hidden_collections"),hidden),"��ʾ����δ�ܱ���")
 end)
 if not ok then self.settings.data=before;pcall(self.settings.flush,self.settings);return false,tostring(why) end
 return true
end
function Library:collections(filter,sort,visible_only)
    local rc=require("readcollection")
    local list={}
    local rank,book_by_file={},{}
    for index,book in ipairs(self:list(filter,sort)) do rank[book.file]=index;book_by_file[book.file]=book end
    for name,coll in pairs(rc.coll) do if not visible_only or self:collectionVisible(name) then
        local n=0;for _ in pairs(coll) do n=n+1 end
        local available,best,representative=0,math.huge,nil
        for file in pairs(coll) do
            if rank[file] then
                available=available+1
                if rank[file]<best then best=rank[file];representative=book_by_file[file] end
            end
        end
        list[#list+1]={name=name,count=n,label=self:collectionLabel(name),
            available=available,rank=best,book=representative}
    end end
    table.sort(list,function(a,b)
        if sort and sort~="title" and a.rank~=b.rank then return a.rank<b.rank end
        return a.label<b.label
    end)
    return list
end

function Library:createCollection(name)
    name=(name or ""):match("^%s*(.-)%s*$")
    assert(name~="" and #name<=200,"�ղ����Ʋ���Ϊ���Ҳ��ܳ���200�ֽ�")
    local rc=require("readcollection")
    assert(not rc.coll[name],"ͬ���ղ��Ѿ�����")
    rc:addCollection(name)
    local ok,err=pcall(function()
        rc:write({[name]=true})
        local disk=LuaSettings:open(DataStorage:getSettingsDir().."/collection.lua")
        assert(disk:has(name),"�ղ�δ�ܱ���")
    end)
    if not ok then
        rc:removeCollection(name)
        local restored=pcall(rc.write,rc)
        error(tostring(err)..(restored and "���ѳ����½�" or "�����ر���ʧ��"))
    end
end

-- Keep native collection settings (including folder rules/defaults) and roll back on write failure.
function Library:editCollection(name,new_name)
    local rc=require("readcollection")
    assert(rc.coll[name],"�ղ��Ѿ�������")
    assert(name~=rc.default_collection_name,"Ĭ���ղؼв�����������ɾ��")
    if new_name then
        new_name=new_name:match("^%s*(.-)%s*$")
        assert(new_name~="" and #new_name<=200,"�ղ����Ʋ���Ϊ���Ҳ��ܳ���200�ֽ�")
        if new_name==name then return name end
        assert(not rc.coll[new_name],"ͬ���ղ��Ѿ�����")
    end
    local Copy=require("einkfrontend/catalog").copy
    local previous={coll=Copy(rc.coll),settings=Copy(rc.coll_settings),default=rc.coll_default}
    local previous_front=Copy(self.settings.data)
    local ok,err=pcall(function()
        if new_name then rc:renameCollection(name,new_name) else rc:removeCollection(name) end
        rc:write()
        local disk=LuaSettings:open(DataStorage:getSettingsDir().."/collection.lua")
        assert(not disk:has(name),"�ղ��޸�δ�ܱ���")
        if new_name then
            local saved=assert(disk:readSetting(new_name),"���ղ�����δ�ܱ���")
            assert(require("einkfrontend/adapter").equal(saved.settings,rc.coll_settings[new_name]),"�ղ����ñ��治һ��")
            local members={};for _,item in ipairs(saved) do members[item.file]=true end
            for file in pairs(rc.coll[new_name]) do assert(members[file],"�ղس�Աδ�ܱ���");members[file]=nil end
            assert(not next(members),"�ղس�Ա���治һ��")
        end
        local hidden=self.settings:readSetting("hidden_collections")
        if type(hidden)=="table" and hidden[name]~=nil then
            hidden=Copy(hidden);local value=hidden[name];hidden[name]=nil;if new_name then hidden[new_name]=value end
            self.settings:saveSetting("hidden_collections",hidden);self.settings:flush()
            assert(require("einkfrontend/adapter").equal(LuaSettings:open(self.settings.file):readSetting("hidden_collections"),hidden),"�ղ���ʾ����δ�ܸ���")
        end
    end)
    if not ok then
        self.settings.data=previous_front;pcall(self.settings.flush,self.settings)
        rc.coll,rc.coll_settings,rc.coll_default=previous.coll,previous.settings,previous.default
        local restored=pcall(rc.write,rc)
        error(tostring(err)..(restored and "���ѻָ�ԭ�ղ�" or "���ָ�����ʧ��"))
    end
    return new_name
end

function Library:collectionBooks(name)
    local rc=require("readcollection");local members=assert(rc.coll[name],"�ղ��Ѿ�������")
    local books,seen={},{}
    for _,book in ipairs(self:list()) do books[#books+1]=book;seen[book.file]=true end
    -- Members outside the indexed root remain visible and removable.
    for file in pairs(members) do
        if not seen[file] then
            local props=DocSettings:open(file):readSetting("doc_props") or {}
            books[#books+1]={file=file,title=props.display_title or props.title or file:match("([^/]+)$"),authors=props.authors or "����δ֪"}
        end
    end
    table.sort(books,function(a,b) if a.title==b.title then return a.file<b.file end;return a.title<b.title end)
    return books
end

function Library:inCollection(file,name) return require("readcollection"):isFileInCollection(file,name) end
function Library:setCollection(file,name,enabled)
    local rc=require("readcollection")
    assert(rc.coll[name],"�ղ��Ѿ�������")
    assert(lfs.attributes(file,"mode")=="file","�鼮�ļ�������")
    local old=rc:isFileInCollection(file,name)
    local ok,err=pcall(function()
        if enabled then
            if not old then rc:addItem(file,name);rc:write({[name]=true}) end
        else rc:removeItem(file,name) end
        local saved=LuaSettings:open(DataStorage:getSettingsDir().."/collection.lua"):readSetting(name) or {}
        local present=false
        for _,item in ipairs(saved) do if item.file==file then present=true end end
        assert(present==enabled,"�ղس�Աδ�ܱ���")
    end)
    if not ok then
        local restored=pcall(function()
            if old and not rc:isFileInCollection(file,name) then rc:addItem(file,name)
            elseif not old then rc:removeItem(file,name,true) end
            rc:write({[name]=true})
        end)
        error(tostring(err)..(restored and "���ѻָ�ԭ����" or "���ָ�����ʧ��"))
    end
end

function Library:setMetadata(book,key,value)
    assert(key=="series" or key=="series_index","��֧�ֵ�Ԫ������Ŀ")
    if key=="series" and value~=nil then assert(type(value)=="string" and #value<=1000,"ϵ�����ƹ���") end
    if key=="series_index" and value~=nil then
        assert(type(value)=="number" and value==value and value>=0 and value<100000,"����ӦΪ0��100000֮�����ֵ")
    end
    local info=BookInfo:new{ui=self.ui}
    local existing=DocSettings:findCustomMetadataFile(book.file)
    local settings=DocSettings.openSettingsFile(existing)
    if not settings:has("doc_props") then
        local props=info:getDocProps(book.file,nil,false)
        local original={}
        for k,v in pairs(props) do if k~="display_title" then original[k]=v end end
        settings:saveSetting("doc_props",original)
    end
    local custom=settings:readSetting("custom_props") or {}
    local previous=custom[key]
    custom[key]=value
    settings:saveSetting("custom_props",custom)
    local ok,err=pcall(function()
        assert(settings:flushCustomMetadata(book.file),"Ԫ���ݱ���ʧ��")
        local path=assert(DocSettings:findCustomMetadataFile(book.file),"δ�ҵ������Ԫ����")
        local saved=DocSettings.openSettingsFile(path):readSetting("custom_props") or {}
        assert(saved[key]==value,"Ԫ���ݱ���ֵ��һ��")
    end)
    if not ok then
        custom[key]=previous;settings:saveSetting("custom_props",custom)
        local restored=settings:flushCustomMetadata(book.file)
        error(tostring(err)..(restored and "���ѻָ�ԭֵ" or "��ԭֵ�ָ�Ҳʧ��"))
    end
    local props=settings:readSetting("doc_props") or {}
    book[key]=value~=nil and value or props[key]
    if key=="series" and not book.series then book.series="" end
    require("ui/widget/booklist").resetBookInfoCache(book.file)
    self.ui:handleEvent(require("ui/event"):new("InvalidateMetadataCache",book.file))
    if self.ui.document and self.ui.document.file==book.file then
        self.ui.doc_props[key]=book[key]
        self.ui.doc_settings:getCustomMetadataFile(true)
    end
    self:save()
end

-- One verified native metadata transaction, shared by uploads and on-device edits.
function Library:editDetails(book,changes)
    local Copy=require("einkfrontend/catalog").copy
    for key,value in pairs(changes) do
        assert(key=="title" or key=="authors","δ֪�鼮��Ϣ")
        assert(type(value)=="string" and #value<=600 and not value:find("[%c]"),"�鼮��Ϣ��������������ַ�")
        if key=="title" then assert(value:match("%S"),"��������Ϊ��") end
    end
    local info=BookInfo:new{ui=self.ui};local path=DocSettings:findCustomMetadataFile(book.file)
    local settings=DocSettings.openSettingsFile(path);local before=Copy(settings.data);local oldbook=Copy(book)
    local oldlibrary=Copy(self.settings.data)
    local ok,why=pcall(function()
        if not settings:has("doc_props") then
            local props=Copy(info:getDocProps(book.file,nil,false) or {});props.display_title=nil;settings:saveSetting("doc_props",props)
        end
        local custom=Copy(settings:readSetting("custom_props") or {})
        for key,value in pairs(changes) do custom[key]=value end
        settings:saveSetting("custom_props",custom);assert(settings:flushCustomMetadata(book.file),"�鼮��Ϣ����ʧ��")
        local saved=DocSettings.openSettingsFile(assert(DocSettings:findCustomMetadataFile(book.file))):readSetting("custom_props")
        for key,value in pairs(changes) do assert(saved[key]==value,"�鼮��Ϣδ�ܱ���");book[key]=value end
        self:save()
    end)
    if not ok then
        settings.data=before;pcall(settings.flushCustomMetadata,settings,book.file)
        for key in pairs(book) do book[key]=nil end;for key,v in pairs(oldbook) do book[key]=v end
        self.settings.data=oldlibrary;pcall(self.settings.flush,self.settings);error(why,0)
    end
    require("ui/widget/booklist").resetBookInfoCache(book.file)
    self.ui:handleEvent(require("ui/event"):new("InvalidateMetadataCache",book.file))
    if self.ui.document and self.ui.document.file==book.file then
        for key,value in pairs(changes) do self.ui.doc_props[key]=value end
        if changes.title then self.ui.doc_props.display_title=changes.title end
        self.ui.doc_settings:getCustomMetadataFile(true)
    end
end

function Library:setReadStatus(book,status)
    assert(({new=true,reading=true,complete=true,abandoned=true})[status],"�Ķ�״̬��Ч")
    local doc=self.ui.document and self.ui.document.file==book.file and self.ui.doc_settings or DocSettings:open(book.file)
    local Copy=require('einkfrontend/catalog').copy;local old=Copy(doc:readSetting('summary'))
    local summary=Copy(old or {});summary.status=status
    local ok,why=pcall(function()
        doc:saveSetting('summary',summary);assert(doc:flush()~=false,'�Ķ�״̬����ʧ��')
        assert(DocSettings:open(book.file):readSetting('summary').status==status,'�Ķ�״̬δ�ܱ���')
    end)
    if not ok then doc:saveSetting('summary',old);pcall(doc.flush,doc);error(why,0) end
    require('ui/widget/booklist').resetBookInfoCache(book.file)
end

return Library
