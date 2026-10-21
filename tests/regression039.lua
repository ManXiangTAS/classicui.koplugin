require("setupkoenv")
package.path="plugins/einkfrontend.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
local DS=require("datastorage");local Settings=require("luasettings")
G_reader_settings=Settings:open(DS:getDataDir().."/settings.reader.lua")
G_reader_settings:saveSetting("language","zh_CN");require("gettext").changeLang("zh_CN")
G_reader_settings:saveSetting("eink_frontend",{auto_open=false,reader_entry=true,full_takeover=true})
G_reader_settings:saveSetting("document_metadata_folder","dir")
require("logger"):setLevel(require("logger").levels.warn)
local Device=require("device");require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager");local Reader=require("apps/reader/readerui");local FM=require("apps/filemanager/filemanager")
local Doc=require("docsettings");local Equal=require("einkfrontend/adapter").equal;local Copy=require("einkfrontend/catalog").copy
local dir=assert(os.getenv("EINK_039_BOOKS"));local root=assert(os.getenv("EINK_PROJECT"));local variant=os.getenv("EINK_VARIANT")
local report={mode="regression039",variant=variant,device="NOT_RUN",tests={}}
local function check(name,fn)
 local ok,why=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and "PASS" or "FAIL",error=not ok and tostring(why) or nil}
 print((ok and "PASS " or "FAIL ")..name..(not ok and ": "..tostring(why) or ""));if not ok then error(why) end
end
local function shot(name)
 UI:forceRePaint();Device.screen:shot(root.."/test-results-039/"..name.."-"..variant..".png")
end
local function dismissMessages()
 local remove={};for _,w in ipairs(UI._window_stack) do if w.widget.text then remove[#remove+1]=w.widget end end
 for _,w in ipairs(remove) do UI:close(w) end
end

Reader:doShowReader(dir.."/A.epub");local r=assert(Reader.instance);local data=require("einkfrontend/navigationdata").new(r)
local xp=r.document:getPageXPointer(1);local xp2=r.document:getPageXPointer(math.min(2,r.document:getPageCount()))
r.annotation:addItem{page=xp,pos0=xp,pos1=xp2,drawer="lighten",text="Fixture excerpt",note="Original note",datetime="2026-10-21 08:00:00"}
data:save();local item=r.annotation.annotations[1]
local function stored() return Doc:open(r.document.file):readSetting("annotations") or {} end
local function failed(operation,flush)
 local snapshot=Copy(r.annotation.annotations);local previous=Copy(r.doc_settings.data)
 local old_flush=r.doc_settings.flush;local handle=r.handleEvent;local pdf=r.highlight.writePdfAnnotation
 local events,writes=0,0;local stats=r.statistics and Copy(r.statistics.data)
 r.handleEvent=function(owner,event,...) if event.handler=="onAnnotationsModified" then events=events+1 end;return handle(owner,event,...) end
 r.highlight.writePdfAnnotation=function() writes=writes+1 end
 r.doc_settings.flush=flush or function() error("injected storage failure") end
 local ok,why=pcall(operation)
 r.doc_settings.flush=old_flush;r.handleEvent=handle;r.highlight.writePdfAnnotation=pdf
 assert(not ok and tostring(why):find("恢复"));assert(Equal(snapshot,r.annotation.annotations));assert(r.annotation.annotations[1]==item)
 assert(events==0 and writes==0);assert(not stats or Equal(stats,r.statistics.data))
 assert(Equal(previous,r.doc_settings.data))
 r:saveSettings();assert(Equal(stored(),snapshot))
end
check("Failed note edit rolls back objects timestamps settings statistics and delayed PDF writes",function()
 failed(function() data:setNote(item,"Rejected edit") end)
 assert(item.note=="Original note")
end)
check("Failed annotation deletion cannot be committed by a later native autosave",function()
 failed(function() data:remove(item) end)
 assert(#stored()==1)
end)
check("Failed excerpt edit restores original text and edit metadata",function()
 failed(function() data:setText(item,"Rejected excerpt") end)
 assert(item.text=="Fixture excerpt" and item.text_edited==nil)
end)
check("Failed bookmark toggle restores native dogear and original list",function()
 local visible=r.view.dogear_visible;failed(function() data:toggleCurrent() end)
 assert(r.view.dogear_visible==visible)
end)
check("A silent annotation write failure is detected and cannot leak into a later save",function()
 failed(function() data:setNote(item,"Silently rejected") end,function() return false end)
end)
check("Failure after file replacement restores disk as well as memory",function()
 local flush=r.doc_settings.flush
 failed(function() data:setNote(item,"Partially saved") end,function(settings,...) flush(settings,...);error("failure after replacement") end)
 assert(stored()[1].note=="Original note")
end)
check("Committed edits notify once and PDF writeback starts only after verified sidecar persistence",function()
 local handle,pdf=r.handleEvent,r.highlight.writePdfAnnotation;local events,writes=0,0
 r.handleEvent=function(owner,event,...) if event.handler=="onAnnotationsModified" then events=events+1 end;return handle(owner,event,...) end
 r.highlight.writePdfAnnotation=function(_,action,annotation,content)
  assert(action=="content" and content=="Committed note");assert(stored()[1].note==content);writes=writes+1
 end
 assert(not data:setNote(item,"Committed note"));r.handleEvent=handle;r.highlight.writePdfAnnotation=pdf
 assert(events==1 and writes==1 and Equal(stored(),r.annotation.annotations))
end)
check("Post-commit PDF failure reports a partial result without pretending the saved note was rejected",function()
 local pdf=r.highlight.writePdfAnnotation;r.highlight.writePdfAnnotation=function() error("PDF write blocked") end
 local warning=data:setNote(item,"Sidecar remains committed");r.highlight.writePdfAnnotation=pdf
 assert(warning:find("PDF") and warning:find("已保存"));assert(stored()[1].note==item.note)
 data:setText(item,"Updated excerpt");assert(Equal(stored(),r.annotation.annotations))
end)
r:onClose()

local Browser=require("einkfrontend/browser")
check("Malformed browser state falls back field by field without overwriting unrelated settings",function()
 local fixtures={42,"invalid",true,{tabs=42,filter=42},{active="invalid",filter={statuses=42,query={}},tabs={books=42}},
 {tabs={books={layout={},sort={},stack={42,{id="books",param=42},{id="books",param={field="invalid",value="x"}}}}}},
 {tabs={books={stack={{id="books",param={},page=-2},{id="books",param={collection=42}},{id="books",param={},page=math.huge}}}}}}
 for _,value in ipairs(fixtures) do
  local settings=Settings:wrap{browser_state=value,view_state=42,books={marker=true}};local before=Copy(settings.data)
  local browser=Browser.new(settings);assert(browser.active=="books" and browser:label()=="全部")
  for _,tab in pairs(browser.tabs) do assert(tab.stack[1] and tab.stack[1].page>=1 and tab.stack[1].page<math.huge);assert(tab.layout=="grid" or tab.layout=="list") end
  assert(Equal(before,settings.data))
 end
 local nan=Browser.new(Settings:wrap{browser_state={tabs={books={stack={{id="books",param={},page=0/0}}}}}})
 assert(nan.tabs.books.stack[1].page==1)
 local valid=Browser.new(Settings:wrap{browser_state={
  active="authors",filter={query="test",statuses={["在读"]=true}},
  tabs={authors={layout="grid",sort="author",stack={
   {id="groups",param="authors"},{id="books",param={field="authors",value="Author"},page=2},
  }}},
 }})
 assert(valid.active=="authors" and #valid.tabs.authors.stack==2 and valid.tabs.authors.stack[2].page==2 and valid:label()=="在读")
end)
FM:showFiles(dir);local p=FM.instance.einkfrontend;local app=p.app
check("Empty duplicate and valid names use the same local handler in both collection entry points",function()
 local prompt=app.adapter.promptText;local entered
 app.adapter.promptText=function(_,_,_,callback,options) assert(options.keep_on_error);return callback(entered) end
 app.library:createCollection("Existing")
 for _,route in ipairs({"collections","collection_manager"}) do
  for _,name in ipairs({"   ","Existing"}) do
   entered=name;app:open(route);local ok=app.screen.model.rows[1].callback()
   assert(p.active and app.screen and FM.instance);dismissMessages()
  end
 end
 entered="  New collection  ";app:newCollection();assert(require("readcollection").coll["New collection"])
 app.adapter.promptText=prompt
end)
check("Actual collection input dialog preserves invalid input and closes only after successful creation",function()
 local dialog=app:newCollection();dialog:setInputText("Existing")
 dialog.buttons[1][2].callback();assert(UI:isWidgetShown(dialog) and dialog:getInputText()=="Existing");dismissMessages()
 dialog:setInputText("Valid dialog collection");dialog.buttons[1][2].callback();assert(not UI:isWidgetShown(dialog))
 assert(require("readcollection").coll["Valid dialog collection"] and p.active)
end)
check("Invalid series order stays in the frontend and keeps the original book metadata",function()
 local book={file=dir.."/A.epub",title="Fixture",authors="Author",series="",series_index=2}
 local prompt=app.adapter.promptText
 app.adapter.promptText=function(_,_,_,callback,options) assert(options.keep_on_error);return callback("invalid-number") end
 app:open("book",book)
 for _,row in ipairs(app.screen.model.rows) do if row.title:find("卷序：",1,true)==1 then row.callback() end end
 app.adapter.promptText=prompt;assert(p.active and app.screen and book.series_index==2);dismissMessages()
end)
check("Malformed saved return context cannot break Home or the next native host",function()
 app.library.settings:saveSetting("return_context",42);app.library.settings:saveSetting("resume_library",true);app.library.settings:flush()
 app:open("home");assert(app.screen.model.home and app:readingReturnLabel()=="书库")
 app.library.settings:saveSetting("return_context",{version=1,file="invalid",shell="home",home_route=42})
 app.library.settings:saveSetting("resume_library",true);app.library.settings:flush()
 app:open("home");assert(app.screen.model.home and app.screen.scroll_y==0)
 app:close();FM.instance:onClose();FM:showFiles(dir);p=FM.instance.einkfrontend;app=p.app
 assert(p.active)
end)
local Layout=require("einkfrontend/homelayout");local layout=app.home_layout
check("Legacy home layouts preserve their shared count when migrating to independent shelves",function()
 local old=Layout.defaults();old.tbr_count=nil;old.recent_count=5
 layout.settings:saveSetting("layout",old);layout.settings:flush();local loaded=Layout.new()
 assert(loaded.config.tbr_count==5 and loaded.config.recent_count==5 and not loaded.error)
 assert(loaded.settings:readSetting("layout").tbr_count==nil)
 assert(layout:commit(Layout.defaults()))
end)
check("Recent and TBR counts persist independently while paired half-width frames share a height",function()
 assert(layout:change(function(c) c.recent_count=5;c.tbr_count=3;for _,w in ipairs(c.widgets) do w.enabled=w.id=="recent" or w.id=="tbr";w.span=1 end end))
 local frames=require("einkfrontend/homewidgets").layout(layout.config,Device.screen:getWidth())
 local S=require("einkfrontend/paint").s;assert(frames[1].h==S(516) and frames[2].h==S(516))
 assert(Layout.new().config.tbr_count==3 and Layout.new().config.recent_count==5)
 assert(layout:change(function(c) c.tbr_count=5 end));assert(layout.config.recent_count==5)
end)
check("Restoring layout retains custom quotes while quote reset leaves the layout untouched",function()
 assert(layout:change(function(c) c.quote_text="Custom｜Me";c.quote_index=2;c.spacing="compact" end))
 assert(layout:resetLayout());assert(layout.config.quote_text=="Custom｜Me" and layout.config.quote_index==2 and layout.config.spacing=="standard")
 local before=Copy(layout.config.widgets);assert(layout:change(function(c) c.quote_text=Layout.defaults().quote_text;c.quote_index=1 end))
 assert(Equal(before,layout.config.widgets))
end)
check("Clock-only and quote-only home models perform no status or statistics database reads",function()
 app.library.books={{file=dir.."/A.epub",title="Fixture",authors="Author",series=""}}
 local status=app.library.status;local sql=require("lua-ljsqlite3/init");local open=sql.open
 local reads,opens=0,0;app.library.status=function(...) reads=reads+1;return status(...) end
 sql.open=function(...) opens=opens+1;return open(...) end
 for _,id in ipairs({"clock","quote"}) do
  assert(layout:change(function(c) for _,w in ipairs(c.widgets) do w.enabled=w.id==id end end))
  local model=require("einkfrontend/home").model(app);assert(not model.book and not model.total_seconds)
 end
 sql.open=open;app.library.status=status;assert(reads==0 and opens==0)
end)
check("Minute ticks dirty only visible clock regions and leave library data unchanged",function()
 assert(layout:change(function(c) for _,w in ipairs(c.widgets) do w.enabled=w.id=="clock" end end))
 app:open("home");shot("home-sharp-clock");local page=app.screen;local snapshot=page.model.home_data
 local dirty=UI.setDirty;local regions={}
 UI.setDirty=function(_,widget,mode,region) if widget==page then assert(region);regions[#regions+1]=region end end
 page.clock_tick();UI.setDirty=dirty;assert(#regions==2 and page.model.home_data==snapshot)
 for _,region in ipairs(regions) do assert(region.x>=0 and region.y>=0 and region.y+region.h<=page.dimen.h and region.w*region.h<page.dimen.w*page.dimen.h/2) end
 UI:unschedule(page.clock_tick);app:open("library");assert(#page:clockRegions()==1)
 app:open("settings");assert(#page:clockRegions()==0);shot("settings-sharp")
end)
check("Every bundled Sharp icon renders through the real SVG engine at 24 and 48 pixels",function()
 local Icons=require("einkfrontend/icons");local P=require("einkfrontend/paint");local BB=P.BB;local lfs=require("libs/libkoreader-lfs")
 for name in pairs(Icons.names) do
  assert(lfs.attributes(Icons.file(name),"mode")=="file")
  for _,size in ipairs({24,48}) do
   local bb=BB.new(size,size,BB.TYPE_BB8);bb:paintRect(0,0,size,size,BB.COLOR_WHITE)
   local blank=BB.tostring(bb);P.icon(bb,name,0,0,size);assert(BB.tostring(bb)~=blank,name);bb:free()
  end
 end
 app:open("library");shot("library-sharp")
end)
app:close();FM.instance:onClose()
local out=assert(io.open(root.."/test-results-039/regression039-"..variant..".json","w"));out:write(require("rapidjson").encode(report));out:close()
print("COMPLETE regression039")
