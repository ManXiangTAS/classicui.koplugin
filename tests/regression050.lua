require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open()
local DS=require('datastorage');local Settings=require('luasettings')
G_reader_settings=Settings:open(DS:getDataDir()..'/settings.reader.lua')
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
local output=root..'/test-results-050/';local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn) local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil};print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err) end
local function clear() local list={};for _,entry in ipairs(UI._window_stack) do if entry.widget.text then list[#list+1]=entry.widget end end;for _,w in ipairs(list) do UI:close(w) end end
local function shot(name,meta) clear();UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(output..file);meta=meta or {};meta.file=file;report.frames[#report.frames+1]=meta end
local function hit(widget,id) UI:setDirty(widget,"ui");UI:forceRePaint();for _,h in ipairs(widget.hits) do if h.id==id then assert(h.callback,id);return h end end;error('missing hit '..id) end
local function activate(widget,id) return hit(widget,id).callback() end

Reader:doShowReader(books..'/navigation.epub');local r=assert(Reader.instance);local app=r.einkfrontend.app
check('Only default is bundled and its tile applies the configured native defaults',function()
 local panel=app:showReader('themes');UI:forceRePaint();local choices=panel:themeChoices()
 assert(#choices==1 and choices[1].name=='默认' and choices[1].id=='builtin:default')
 activate(panel,'theme_builtin:default');UI:forceRePaint()
 assert(app.typography:matches(app.typography:defaults()) and panel.theme_tiles[1].selected)
 shot('themes-default')
end)
check('Saved themes including Kindle-like names remain user data and apply their own values',function()
 local panel=app.reader_panel;local t=app.typography;local original=t:snapshot()
 for i,name in ipairs({'舒适','自定义','我的主题'}) do
  local values=Copy(original);values.font_size=20+i*2
  local ok,id=app.themes:create(name,values);assert(ok,id)
  local choices=panel:themeChoices();assert(#choices==i+1 and choices[i+1].name==name)
  UI:forceRePaint();activate(panel,'theme_'..id);UI:forceRePaint()
  assert(t.meta.theme_id==id and t:matches(values) and panel.theme_tiles[i+1].selected)
 end
 shot('themes-saved')
end)
check('Manual adjustments and legacy synthetic IDs do not falsely select a theme or change book values',function()
 local panel=app.reader_panel;local t=app.typography;assert(t:change('font_size',35));t.meta.theme_id='builtin:3'
 local before=t:snapshot();local choices,selected=panel:themeChoices()
 assert(#choices==4 and selected==nil and Equal(before,t:snapshot()))
 UI:forceRePaint();for _,tile in ipairs(panel.theme_tiles) do assert(not tile.selected) end;shot('themes-adjusted')
end)
check('Default follows configured defaults while saved themes remain independent and editable',function()
 local panel=app.reader_panel;local saved=app.themes.records[1];local id=saved.id
 activate(panel,'theme_builtin:default');assert(app.typography:matches(app.typography:defaults()))
 assert(app.typography.meta.theme_id=='builtin:default')
 for _,v in pairs(app.typography.meta.inherit) do assert(v==true) end
 local values=Copy(saved.values);values.font_size=30;assert(app.themes:update(id,values));assert(app.themes:rename(id,'改名'))
 UI:forceRePaint();activate(panel,'theme_'..id);assert(app.typography:matches(values))
 assert(app.themes:delete(id));local choices=panel:themeChoices();assert(#choices==3)
 shot('themes-after-manage')
end)
app:close();r:onClose()
local file=assert(io.open(output..'regression-'..variant..'.json','w'));file:write(require('json').encode(report));file:close();print('COMPLETE '..variant)
