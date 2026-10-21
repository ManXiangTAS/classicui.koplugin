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
local output=root..'/test-results-046/';local report={tests={},frames={},variant=variant,device='NOT_RUN'}
local function check(name,fn) local ok,err=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(err) or nil};print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)));assert(ok,err) end
local function clear() local list={};for _,entry in ipairs(UI._window_stack) do if entry.widget.text then list[#list+1]=entry.widget end end;for _,w in ipairs(list) do UI:close(w) end end
local function shot(name,meta) clear();UI:forceRePaint();local file=name..'-'..variant..'.png';Device.screen:shot(output..file);meta=meta or {};meta.file=file;report.frames[#report.frames+1]=meta end
local function hit(widget,id) UI:forceRePaint();for _,h in ipairs(widget.hits) do if h.id==id then assert(h.callback,id);return h end end;error('missing hit '..id) end
local function activate(widget,id) return hit(widget,id).callback() end

Reader:doShowReader(books..'/navigation.epub');local r=assert(Reader.instance);local app=r.einkfrontend.app
check('Themes offer one default tile and retain Save and Manage actions',function()
 local panel=app:showReader('themes');UI:forceRePaint();assert(#panel.theme_tiles==1)
 hit(panel,'theme_save');hit(panel,'theme_manage')
 activate(panel,'theme_builtin:default');UI:forceRePaint()
 assert(app.typography.meta.theme_id=='builtin:default' and app.typography:matches(app.typography:defaults()))
 assert(panel.theme_tiles[1].selected);shot('themes-reference')
 activate(panel,'theme_manage');UI:forceRePaint();assert(panel.tab=='theme_list');activate(panel,'aa_back');assert(panel.tab=='themes')
end)
check('Every Aa close button removes panel and toolbar',function()
 for _,tab in ipairs({'themes','font','layout','fonts','font_options','layout_options','theme_list'}) do
  local panel=app:showReader(tab);activate(panel,'aa_close');assert(app.reader_panel==nil)
  for _,entry in ipairs(UI._window_stack) do assert(entry.widget~=panel) end
 end
end)
check('Dropdown in a book has neither library home nor sync shortcuts',function()
 local c=app:showControls();UI:forceRePaint();shot('reading-dropdown')
 for _,hit in ipairs(c.hits) do assert(hit.id~='controls_sync' and hit.id~='reading_return') end;c:close()
end)
app:close();r:onClose();FM:showFiles(books);app=FM.instance.einkfrontend.app;app:open('home')
check('Native catalog retains every static action and separates compatibility maintenance and power',function()
 app.native:refresh();assert(#app.native.catalog:audit().missing==0)
 assert(app.native.catalog.entries.filemanager_display_mode.category=='compatibility')
 app:go('catalog_category','maintenance');assert(#app.screen.model.rows<10);shot('maintenance')
 app:go('catalog_category','compatibility');assert(app.screen.model.title=='原生界面设置' and #app.screen.model.rows>0)
end)
check('Clock settings are single line rows and use the shared centered typography',function()
 app:go('clock_settings');UI:forceRePaint()
 for _,row in ipairs(app.screen.model.rows) do assert(not row.note or row.note=='');assert(not row.title:find('时区范围',1,true)) end
 for _,row in ipairs(app.screen.row_layout) do if row.value then assert(math.abs((row.label.y+row.label.h/2)-(row.value.y+row.value.h/2))<=1) end end
 shot('clock-settings')
end)
check('Global settings search covers native lazy options and home widgets',function()
 require('einkfrontend/settings').search(app,'热力图');local rows=app.screen.model.rows;assert(#rows>=1 and rows[1].title=='阅读热力图');rows[1].callback();assert(app.home_editor.selected=='heatmap');app.home_editor:close()
 require('einkfrontend/settings').search(app,'原生界面');assert(#app.screen.model.rows>=1)
end)
check('Collection hidden state persists but collections remain manageable and can be restored',function()
 app.library:createCollection('To Be Read');assert(app.library:setCollectionVisible('To Be Read',false))
 assert(not app.library:collectionVisible('To Be Read'));assert(not require('einkfrontend/library').new(app.plugin.ui):collectionVisible('To Be Read'))
 for _,c in ipairs(app.library:collections(nil,nil,true)) do assert(c.name~='To Be Read') end
 app:open('library');app:selectLibraryTab('collections');for _,row in ipairs(app.screen.model.rows) do assert(row.title~='新建收藏') end
 app:go('collection_manager');local found=false;for _,row in ipairs(app.screen.model.rows) do if row.title=='待读' then found=true end end;assert(found)
 app.library:editCollection('To Be Read','稍后再读');assert(not app.library:collectionVisible('稍后再读'));assert(app.library:collectionVisible('To Be Read'))
 assert(app.library:setCollectionVisible('稍后再读',true));app.library:editCollection('稍后再读',nil)
end)
check('Collection visibility and rename failures restore frontend native memory and disk',function()
 app.library:createCollection('隐藏事务');assert(app.library:setCollectionVisible('隐藏事务',false))
 local flush=app.library.settings.flush;app.library.settings.flush=function() error('injected visibility write failure') end
 assert(not app.library:setCollectionVisible('隐藏事务',true));assert(not app.library:collectionVisible('隐藏事务'))
 local ok=pcall(app.library.editCollection,app.library,'隐藏事务','失败的新名');assert(not ok)
 assert(require('readcollection').coll['隐藏事务'] and not require('readcollection').coll['失败的新名'])
 assert(not app.library:collectionVisible('隐藏事务'))
 app.library.settings.flush=flush;assert(Settings:open(app.library.settings.file):readSetting('hidden_collections')['隐藏事务'])
 app.library:editCollection('隐藏事务',nil)
end)
check('Settings global search indexes lazy branches without invoking their action callbacks',function()
 local refresh=app.native.refresh;app.native.refresh=function() end;local roots=app.native.catalog.roots
 app.native.catalog.roots={device={{text='外层',sub_item_table_func=function() return {{text='测试深层选项046',callback=function() error('search must not invoke actions') end}} end}}}
 require('einkfrontend/settings').search(app,'测试深层');assert(#app.screen.model.rows==1 and app.screen.model.rows[1].title=='测试深层选项046')
 app.native.catalog.roots=roots;app.native.refresh=refresh
end)
check('Collection page search stays local and clearing restores all rows',function()
 app:go('collection_manager');local count=#app.screen.model.rows;local prompt=app.adapter.promptText
 app.adapter.promptText=function(_,title,_,fn) assert(title=='搜索当前页面');fn('不存在的收藏') end
 app:searchCurrent();assert(app.stack[#app.stack].id=='collection_manager' and app.screen.model.rows[1].title=='没有匹配的项目')
 app.adapter.promptText=function(_,_,_,fn) fn('') end;app:searchCurrent();assert(#app.screen.model.rows==count);app.adapter.promptText=prompt
end)
check('Library search from its options shows real book results and category search stays scoped',function()
 app.library.books={{file=books..'/A.epub',title='独特甲书',authors='作者甲',series='甲系列'},{file=books..'/B.epub',title='独特乙书',authors='作者乙',series='乙系列'}}
 app:go('library_options');local prompt=app.adapter.promptText
 app.adapter.promptText=function(_,title,_,fn) assert(title=='搜索书库');fn('独特乙') end
 app:searchCurrent();assert(app.screen.model.library and #app.screen.model.rows==1 and app.screen.model.rows[1].book.title=='独特乙书')
 app.browser.filter.query='';app:go('books',{field='authors',value='作者甲'})
 app.adapter.promptText=function(_,title,_,fn) assert(title=='搜索当前分类的书籍');fn('独特乙') end
 app:searchLibrary();assert(app.screen.model.rows[1].title=='没有匹配的书籍' and not app.screen.model.rows[1].book)
 app.adapter.promptText=prompt;app.browser.filter.query='';app:open('home')
end)
local editor=app:showHomeEditor()
check('Home editor previews changes immediately and does not save until requested',function()
 UI:forceRePaint();local base=Copy(app.home_layout.config);local before=require('ffi').string(editor.preview.data,editor.preview.stride*editor.preview.h)
 activate(editor,'editor_toggle_currently');assert(editor.draft.widgets[1].enabled~=base.widgets[1].enabled and Equal(app.home_layout.config,base))
 assert(require('ffi').string(editor.preview.data,editor.preview.stride*editor.preview.h)~=before);shot('home-editor')
 local prompt=app.adapter.promptText;app.adapter.promptText=function(_,title,_,fn) assert(title=='搜索主页部件');fn('七天') end
 activate(editor,'editor_search');UI:forceRePaint();assert(#editor.filtered==1 and editor.filtered[1].id=='weekly')
 editor.query='热力值';UI:setDirty(editor,'ui');UI:forceRePaint();assert(#editor.filtered==1 and editor.filtered[1].id=='heatmap');shot('home-editor-search')
 editor.query='';UI:setDirty(editor,'ui');UI:forceRePaint();app.adapter.promptText=prompt
 local ok,why=editor:save(true);assert(ok,why);assert(Equal(app.home_layout.config,editor.draft));assert(Equal(Settings:open(app.home_layout.settings.file):readSetting('layout'),editor.draft))
end)
local web=require('einkfrontend/homeweb').new(editor,{ip='127.0.0.1',no_firewall=true});editor.server=web
local json=require('rapidjson')
local function request(method,path,body,extra)
 local headers={host=web.host,authorization='Bearer '..web.token,['content-type']='application/json',origin=web.origin}
 for k,v in pairs(extra or {}) do headers[k]=v end
 return web:request(method,path,headers,body or '')
end
check('Web editor rejects unauthorized requests foreign origins DNS rebinding and stale revisions',function()
 assert(request('GET','/api/layout',nil,{authorization='wrong'}):find(' 401 ',1,true))
 assert(request('GET','/api/layout',nil,{origin='http://evil.example'}):find(' 403 ',1,true))
 assert(request('GET','/api/layout',nil,{host='evil.example'}):find(' 403 ',1,true))
 assert(request('GET','/api/layout'):find(' 200 ',1,true))
 local body=json.encode{revision=editor.revision-1,config=editor.draft};assert(request('POST','/api/layout',body):find(' 409 ',1,true))
end)
check('Web editor strictly validates payloads nesting headers and body limits',function()
 local c=Copy(editor.draft);c.unknown='no';assert(request('POST','/api/layout',json.encode{revision=editor.revision,config=c}):find(' 400 ',1,true))
 assert(request('POST','/api/layout',string.rep('[',12)..string.rep(']',12)):find(' 400 ',1,true))
 assert(web:parse('POST /api/layout HTTP/1.1\r\nHost: '..web.host..'\r\nContent-Length: 40000\r\n\r\n'):find(' 413 ',1,true))
 assert(web:parse('POST /api/layout HTTP/1.1\r\nHost: '..web.host..'\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n'):find(' 400 ',1,true))
 assert(web:parse('GET / HTTP/1.1\r\nHost: '..web.host..'\r\nTransfer-Encoding: chunked\r\n\r\n'):find(' 400 ',1,true))
 assert(request('GET','/../../settings.reader.lua'):find(' 404 ',1,true))
end)
check('Authorized web draft updates actual native preview and Save verifies disk',function()
 local c=Copy(editor.draft);c.spacing=c.spacing=='compact' and 'standard' or 'compact';local rev=editor.revision
 assert(request('POST','/api/layout',json.encode{revision=rev,config=c}):find(' 200 ',1,true));assert(editor.revision==rev+1 and Equal(editor.draft,c))
 assert(request('GET','/api/preview?offset=99999'):find('X-Preview-Offset:',1,true))
 assert(request('GET','/api/preview'):find('Content-Type: image/png',1,true))
 assert(request('POST','/api/save',json.encode{revision=editor.revision,config=c}):find(' 200 ',1,true));assert(Equal(app.home_layout.config,c));shot('home-editor-web-saved')
end)
check('Native editor and web revisions protect against conflicting writers',function()
 local revision=editor.revision;editor:change(function(c) c.spacing='standard' end)
 assert(not editor:replaceDraft(editor.draft,revision))
 local old=Copy(app.home_layout.config);assert(app.home_layout:change(function(c) c.daily_goal_minutes=31 end));assert(not editor:save(true));assert(app.home_layout:commit(old))
end)
check('Closing editor revokes token closes sockets removes poll and frees preview',function()
 web:showAddress();assert(web.dialog);editor:close();assert(not web.dialog);assert(web.stopped and web.token==nil and web.listener==nil and editor.preview==nil and app.home_editor==nil)
end)
local expired=app:showHomeEditor();local server=require('einkfrontend/homeweb').new(expired,{ip='127.0.0.1',no_firewall=true});expired.server=server;server.expires=0;server:poll()
check('Temporary web session expires and also stops on suspend',function()
 assert(server.stopped);expired.server=require('einkfrontend/homeweb').new(expired,{ip='127.0.0.1',no_firewall=true});local other=expired.server;expired:onSuspend();assert(other.stopped);expired:close()
end)
app:close();FM.instance:onClose()
local file=assert(io.open(output..'regression-'..variant..'.json','w'));file:write(json.encode(report));file:close();print('COMPLETE '..variant)
