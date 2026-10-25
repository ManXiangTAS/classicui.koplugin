-- Real application modules with simulated rendering/storage, not native font QA.
local checks,failed,previews={},0,{}
local function test(name,fn)
 local ok,why=pcall(fn);checks[#checks+1]={name=name,passed=ok,error=not ok and tostring(why) or nil}
 if not ok then failed=failed+1;print('FAIL '..name..': '..tostring(why)) end
end
local function copy(x) if type(x)~='table' then return x end;local out={};for k,v in pairs(x) do out[k]=copy(v) end;return out end
local function encode(v)
 if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"' end
 if type(v)=='boolean' or type(v)=='number' then return tostring(v) end
 if v==nil then return 'null' end
 local out={};if #v>0 then for _,item in ipairs(v) do out[#out+1]=encode(item) end;return '['..table.concat(out,',')..']' end
 for key,item in pairs(v) do out[#out+1]=encode(key)..':'..encode(item) end;return '{'..table.concat(out,',')..'}'
end
local function clear() for name in pairs(package.loaded) do if name:match('^einkfrontend/') then package.loaded[name]=nil end end end
local function typography()
 clear();local disk={};local app={};local values={font_face='测试字体',font_size=29.5,line_spacing=120,page_margins={12,12,12,12},
  embedded_css=true,embedded_fonts=false,font_hinting=2,font_kerning=3,font_gamma=36,font_base_weight=0,
  word_spacing={100,100},word_expansion=0,cjk_width_scaling=100}
 local ds={readSetting=function(_,key) return disk[key] end,has=function(_,key) return disk[key]~=nil end}
 package.loaded['ui/event']={};package.loaded.docsettings={open=function() return ds end}
 package.loaded.luasettings={};package.loaded['ui/widget/filechooser']={};package.loaded.version={}
 local Adapter=require('einkfrontend/adapter');local Typography=require('einkfrontend/typography')
 local ui={font={},typeset={},document={file='/book.epub'}}
 local adapter=setmetatable({ui=ui,alive=function() return true end,read=function(_,id) return copy(values[id]) end,
  choices=function(_,id) return id=='font_face' and {{'测试字体','测试字体'},{'另一字体','另一字体'}} or require('einkfrontend/registry').by_id[id].choices end,
  _apply=function(_,id,value) values[id]=copy(value) end},Adapter)
 local model=setmetatable({adapter=adapter,ui=ui,meta={version=1,inherit={}}},Typography)
 function ui:saveSettings()
  disk.eink_frontend_typography=copy(model.meta)
  for _,id in ipairs(Typography.fields) do
   local b=Adapter.bindings[id]
   if id=='page_margins' then disk.copt_h_page_margins={values[id][1],values[id][3]};disk.copt_t_page_margin=values[id][2];disk.copt_b_page_margin=values[id][4]
   else disk[b.key]=b.boolean and (values[id] and 1 or 0) or copy(values[id]) end
  end
 end
 return adapter,model,values,disk
end
test('native half-point sizes pass validation while invalid values remain rejected',function()
 local adapter=typography()
 for _,value in ipairs({12,12.5,29.5,72,254.5,255}) do adapter:validate('font_size',value) end
 for _,value in ipairs({11.5,255.5,29.25,0/0,math.huge,-math.huge,'29.5'}) do assert(not pcall(adapter.validate,adapter,'font_size',value)) end
end)
test('changing font weight at the photographed 29.5 size persists both fields',function()
 local adapter,model,values,disk=typography();local ok,err=model:change('font_base_weight',.25)
 assert(ok,err);assert(values.font_size==29.5 and disk.copt_font_size==29.5 and disk.copt_font_base_weight==.25)
end)
test('switching font and contrast no longer fails because of unchanged fractional size',function()
 local adapter,model,values,disk=typography()
 local ok,err=model:change('font_face','另一字体');assert(ok,err)
 ok,err=model:change('font_gamma',37);assert(ok,err)
 assert(values.font_size==29.5 and disk.font_face=='另一字体' and disk.copt_font_gamma==37)
end)
test('half-point sizes persist when changed and when loading a saved theme',function()
 local adapter,model,values,disk=typography()
 local ok,err=model:change('font_size',30);assert(ok,err)
 local theme=model:snapshot();theme.font_size=29.5
 ok,err=model:apply(theme,false,'user:half');assert(ok,err)
 assert(disk.copt_font_size==29.5 and disk.eink_frontend_typography.theme_id=='user:half')
end)
local function renderer(width,height,scale)
 clear();local operations={};local function S(n) return math.floor(n*scale+.5) end
 local function buffer(ox,oy,clip)
  local bb={ox=ox or 0,oy=oy or 0,clip=clip}
  function bb:paintRect(x,y,w,h,color) operations[#operations+1]={kind='rect',x=self.ox+x,y=self.oy+y,w=w,h=h,color=color,clip=self.clip} end
  function bb:viewport(x,y,w,h) return buffer(self.ox+x,self.oy+y,{x=self.ox+x,y=self.oy+y,w=w,h=h}) end
  function bb:free() end
  return bb
 end
 local P={s=S,BB={COLOR_WHITE=255,COLOR_BLACK=0,COLOR_DARK_GRAY=90,COLOR_LIGHT_GRAY=210},style={title=20,label=18,row=20,secondary=14}}
 local function textWidth(text,size)
  local n=0;for c in tostring(text):gmatch('[%z\1-\127\194-\244][\128-\191]*') do n=n+(#c>1 and size or size*.55) end;return n
 end
 function P.inkLabel(bb,text,x,y,w,h,size,bold,color,align)
  text=tostring(text);local tw=math.min(w,textWidth(text,S(size)));local th=math.min(h,S(size))
  if bb then operations[#operations+1]={kind='text',text=text,x=bb.ox+x,y=bb.oy+y,w=w,h=h,size=S(size),bold=bold or false,color=color or 0,align=align or 'center',clip=bb.clip} end
  return {x=align=='left' and x or x+(w-tw)/2,y=y+(h-th)/2,w=tw,h=th}
 end
 function P.label(bb,text,x,y,w,h,size,bold,align,color) return P.inkLabel(bb,text,x,y,w,h,size,bold,color,align or 'left') end
 function P.inkIcon(bb,name,x,y,w,h,size)
  if bb then operations[#operations+1]={kind='icon',name=name,x=bb.ox+x,y=bb.oy+y,w=w,h=h,size=size} end
  return {x=x+(w-size)/2,y=y+(h-size)/2,w=size,h=size}
 end
 P.centerIcon=P.inkIcon
 function P.rule(bb,x,y,w,n) bb:paintRect(x,y,w,math.max(1,S(n or 1)),0) end
 function P.line(bb,x,y,w) bb:paintRect(x,y,w,1,210) end
 function P.button(page,bb,text,x,y,w,h,callback,opts)
  opts=opts or {};P.label(bb,text,x+S(8),y,w-S(16),h,opts.size or 18,opts.bold,opts.align)
  page.hits[#page.hits+1]={x=x,y=y,w=w,h=h,callback=callback,id=opts.id}
 end
 package.loaded['einkfrontend/paint']=P
 local Input={};function Input:extend(t) t.__index=t;function t:new(o) setmetatable(o,self);o:init();return o end;return t end
 package.loaded['ui/widget/container/inputcontainer']=Input
 local ui={setDirty=function() end};package.loaded['ui/uimanager']=ui
 package.loaded.device={screen={getSize=function() return {w=width,h=height} end,scaleBySize=function(_,n) return S(n) end}}
 package.loaded['ui/geometry']={};package.loaded['ui/gesturerange']={new=function(_,v) return v end}
 package.loaded['ui/font']={};package.loaded['ui/widget/textwidget']={};package.loaded['ui/widget/imagewidget']={}
 package.loaded['ffi/blitbuffer']=P.BB;package.loaded['libs/libkoreader-lfs']={};package.loaded['ffi/util']={}
 package.loaded['document/documentregistry']={};package.loaded.luasettings={};package.loaded.datastorage={}
 local app={plugin={active=true},adapter={alive=function() return true end},library={root='/mnt/us/documents/ManualBook'},stack={}}
 function app:render() end
 function app:message() end
 function app:userAction(fn) return pcall(fn) end
 function app:confirm(_,callback) self.confirmed=callback end
 local service=setmetatable({state='ready'},require('einkfrontend/foldercollections'));app.folder_import=service
 local rc={coll={}};package.loaded.readcollection=rc
 local Page=require('einkfrontend/screen')
 local function render(groups,existing,loose,skipped,state)
  operations={};rc.coll=existing or {};service.state=state or 'ready'
  service.plan={root=app.library.root,groups=groups,loose=loose or 0,skipped=skipped or 0}
  service.result={created=1,merged=0};service.error='无法读取目录'
  local route={id='folder_collections'};app.stack={route}
  local m={rows={},route=route}
  local function row(title,note,fn) m.rows[#m.rows+1]={title=title,note=note,callback=fn} end
  assert(require('einkfrontend/foldercollectionsettings').render(app,route,m,row))
  local page=Page:new{app=app};app.screen=page;page:setModel(m);page:_paintSettings(buffer(),0,0)
  return page,m,copy(operations)
 end
 return render,S,app
end
test('the photographed already-imported folder has one concise row and a view-collections action',function()
 local render=renderer(600,800,1);local files,coll={},{}
 for i=1,8 do files[i]='/old/'..i..'.epub';coll[files[i]]={} end
 local page,m,ops=render({{name='人形电脑天使心',files=files}},{['人形电脑天使心']=coll},12)
 assert(m.folder_import.headline=='全部已导入' and m.folder_import.primary.text=='查看收藏')
 assert(#m.rows==1 and m.rows[1].count==8 and m.rows[1].import_status=='已导入')
 assert(m.folder_import.notices[1]=='12 本散放书籍保留原样' and page.scroll_max==0)
 previews[#previews+1]={name='already-imported',width=600,height=800,operations=ops}
end)
test('new, partially imported and complete folders have distinct accurate states',function()
 local render=renderer(600,800,1)
 local page,m,ops=render({{name='文学/鲁迅',files={'/a','/b'}},{name='小说',files={'/c','/d'}},{name='已读',files={'/e'}}},
  {['小说']={['/c']={}},['已读']={['/e']={}}},12)
 assert(m.folder_import.headline=='可导入 2 个收藏' and m.folder_import.primary.text=='导入 2 个收藏')
 assert(m.rows[1].import_status=='新增' and m.rows[2].import_status=='补入1本' and m.rows[3].import_status=='已导入')
 previews[#previews+1]={name='import-preview',width=600,height=800,operations=ops}
end)
test('import footer remains below its scrolling list at desktop, Voyage and landscape sizes',function()
 for _,geometry in ipairs({{600,800,1},{1072,1448,1.8},{1448,1072,1.8}}) do
  local render,S=renderer(unpack(geometry));local groups={}
  for i=1,30 do groups[i]={name='目录 '..i,files={'/book'..i}} end
  local page,m,ops=render(groups,{},3,1)
  assert(page.scroll_max>0 and page.row_h==S(54))
  local bottom=page.header_h+page.info_h+page.viewport_h
  assert(bottom<=geometry[2]-page.footer_h)
  for _,hit in ipairs(page.hits) do
   assert(hit.x>=0 and hit.x+hit.w<=geometry[1] and hit.y>=0 and hit.y+hit.h<=geometry[2])
   if hit.id=='folder_import_primary' then assert(hit.y>bottom) end
  end
  previews[#previews+1]={name='long-list-'..geometry[1],width=geometry[1],height=geometry[2],operations=ops}
 end
end)
test('idle, scanning, cancelled, error and completion each have an appropriate primary action',function()
 local render=renderer(600,800,1)
 for _,entry in ipairs({{'idle','选择文件夹'},{'scanning','取消扫描'},{'cancelled','选择文件夹'},{'error','选择文件夹'},{'done','查看收藏'}}) do
  local page,m=render({},nil,0,0,entry[1])
  assert(m.folder_import.primary.text==entry[2] and #m.rows==0 and page.scroll_max==0)
 end
end)
test('a source containing only loose books offers changing folders without an import action',function()
 local render=renderer(600,800,1);local page,m=render({},nil,12)
 assert(m.folder_import.headline=='没有找到分类文件夹' and m.folder_import.primary.text=='更换文件夹')
 assert(m.folder_import.notices[1]=='12 本散放书籍保留原样')
end)
AUDIT_RESULT=encode({checks=checks,total=#checks,failed=failed,previews=previews,rendering='Simulated paint backend; not KOReader native font rasterization'})
