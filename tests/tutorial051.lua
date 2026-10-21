require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');local Settings=require('luasettings')
G_reader_settings=Settings:open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,reader_entry=true,full_takeover=true})
G_reader_settings:saveSetting('document_metadata_folder','dir')
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local Reader=require('apps/reader/readerui');local FM=require('apps/filemanager/filemanager')
local P=require('einkfrontend/paint');local S=P.s;local B=P.BB
local Layout=require('einkfrontend/homelayout');local Copy=require('einkfrontend/catalog').copy
local Equal=require('einkfrontend/adapter').equal;local Stats=require('einkfrontend/homestats')
local root=assert(os.getenv('EINK_PROJECT'));local books=assert(os.getenv('EINK_030_BOOKS'));local variant=os.getenv('EINK_VARIANT')
local output=root..'/test-results-051/';local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn) local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil};print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err) end
local function clear() local list={};for _,entry in ipairs(UI._window_stack) do if entry.widget.text then list[#list+1]=entry.widget end end;for _,w in ipairs(list) do UI:close(w) end end
local function shot(name,meta) clear();UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(output..file);meta=meta or {};meta.file=file;report.frames[#report.frames+1]=meta end
local function hit(widget,id) UI:setDirty(widget,"ui");UI:forceRePaint();for _,h in ipairs(widget.hits) do if h.id==id then assert(h.callback,id);return h end end;error('missing hit '..id) end
local function activate(widget,id) return hit(widget,id).callback() end

FM:showFiles(books);local app=FM.instance.einkfrontend.app
app:open('settings');app:showSettingsMore();shot('tutorial-more-menu')
local function drain() for i=1,500 do UI:_checkTasks();if not app.library.job then return end;require('socket').sleep(.003) end end
app:scanLibrary(books);drain();app:open('library');shot('tutorial-library')
app:open('home');shot('tutorial-home');local editor=app:showHomeEditor();UI:forceRePaint();Device.screen:shot(output..'tutorial-editor-'..variant..'.png');editor:close()
app:open('catalog_category','maintenance');shot('tutorial-maintenance');app:open('catalog_category','library');shot('tutorial-library-settings')
app:close();FM.instance:onClose()
local file=assert(io.open(output..'tutorial-'..variant..'.json','w'));file:write(require('json').encode(report));file:close()
