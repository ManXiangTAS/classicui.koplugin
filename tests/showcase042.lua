require("setupkoenv")
package.path="plugins/einkfrontend.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open();local DS=require("datastorage")
G_reader_settings=require("luasettings"):open(DS:getDataDir().."/settings.reader.lua")
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
G_reader_settings:saveSetting("language","zh_CN");require("gettext").changeLang("zh_CN")
G_reader_settings:saveSetting("eink_frontend",{auto_open=false,reader_entry=true,full_takeover=true})
G_reader_settings:saveSetting("document_metadata_folder","dir")
require("logger"):setLevel(require("logger").levels.warn)
local Device=require("device");require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager");local Reader=require("apps/reader/readerui");local FM=require("apps/filemanager/filemanager")
local Doc=require("docsettings");local Event=require("ui/event");local P=require("einkfrontend/paint")
local root=assert(os.getenv("EINK_PROJECT"));local books=assert(os.getenv("EINK_042_BOOKS"));local output=root.."/test-results-042/"
local function ticks() for _=1,350 do UI:shiftScheduledTasksBy(-require("ui/time").s(.02));UI:_checkTasks() end end
local function shot(name)
 local remove={};for _,w in ipairs(UI._window_stack) do if w.widget.text then remove[#remove+1]=w.widget end end
 for _,w in ipairs(remove) do UI:close(w) end
 UI:forceRePaint()
 local app=Reader.instance and Reader.instance.einkfrontend.app or FM.instance and FM.instance.einkfrontend.app
 assert(not (app and app.screen and app.screen.paint_fault))
 Device.screen:shot(output..name..".png")
end
local function status(app)
 local original=app.adapter.deviceStatus
 app.adapter.deviceStatus=function(self) local value=original(self);value.battery=76;return value end
end
Reader:doShowReader(books.."/01.epub");local r=assert(Reader.instance);local app=r.einkfrontend.app
assert(app.typography:change("font_size",26));assert(app.typography:change("line_spacing",120))
r:handleEvent(Event:new("GotoPage",2));r:saveSettings();r:onClose()
for i=1,6 do
 local d=Doc:open(books..string.format("/%02d.epub",i));d:saveSetting("percent_finished",({.18,.42,0,1,.63,0})[i]);d:saveSetting("summary",{status=i==4 and "complete" or "reading"});d:flush()
 require("readhistory"):addItem(books..string.format("/%02d.epub",7-i),os.time()-i*100)
end
require("readhistory"):addItem(books.."/01.epub")
FM:showFiles(books);app=FM.instance.einkfrontend.app;status(app);app:open("library");app:scanLibrary(books);ticks();assert(#app.library.books==6)
app.library_sort="title";app:render();shot("library")
app:selectLibraryTab("series");shot("series");app:selectLibraryTab("books")
app.library:createCollection("周末慢读")
for i=1,3 do app.library:setCollection(app.library.books[i].file,"周末慢读",true) end
app:selectLibraryTab("collections");shot("collections");app:selectLibraryTab("books")
local layout=app.home_layout
assert(layout:change(function(c)
 local order={"currently","quote","recent","reading_stats","overview","clock","tbr"};local widgets={}
 for _,id in ipairs(order) do local widget=layout:find(id,c);widget.enabled=id=="currently" or id=="quote" or id=="recent";widget.span=id=="currently" and 2 or 1;widgets[#widgets+1]=widget end
 c.widgets=widgets;c.spacing="compact";c.quote_text="学而时习之，不亦说乎？｜《论语·学而》";c.quote_index=1
end))
app.library.settings:saveSetting("last_reading_detail",{file=books.."/01.epub",chapter="给自己一段安静的时间",chapter_percent=.28})
app.library.settings:flush();app:open("home");shot("home")
app:go("home_customize");shot("home-editor");app:open("settings");shot("settings")
app:showControls();shot("controls");app:close();FM.instance:onClose()
Reader:doShowReader(books.."/01.epub");r=Reader.instance;app=r.einkfrontend.app;status(app)
r:handleEvent(Event:new("GotoPage",1));shot("reading")
app:showReaderTopbar();shot("reader-toolbar")
app:showReader("font");shot("reader-font")
app:showReader("themes");shot("reader-themes")
app:close();r:onClose()
print("PASS showcase: six original demo books; real KOReader screenshots")
