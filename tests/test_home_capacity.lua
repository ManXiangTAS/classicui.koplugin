-- Regression checks for half-row removal; device, storage and preview drawing are simulated.
local results,scenarios,failed={}, {},0
local function copy(x) if type(x)~='table' then return x end;local o={};for k,v in pairs(x) do o[k]=copy(v) end;return o end
local function equal(a,b) if type(a)~=type(b) then return false end;if type(a)~='table' then return a==b end;for k,v in pairs(a) do if not equal(v,b[k]) then return false end end;for k in pairs(b) do if a[k]==nil then return false end end;return true end
local function json(v)
 if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"' end
 if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
 if v==nil then return 'null' end
 local out={};if #v>0 then for _,x in ipairs(v) do out[#out+1]=json(x) end;return '['..table.concat(out,',')..']' end
 for k,x in pairs(v) do out[#out+1]=json(k)..':'..json(x) end;return '{'..table.concat(out,',')..'}'
end
local function check(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil};if not ok then failed=failed+1 end end
local function fixture(width,height,scale,config)
 for name in pairs(package.loaded) do if name:match('^einkfrontend/') then package.loaded[name]=nil end end
 local disk={};local app={messages={}}
 package.loaded['einkfrontend/catalog']={copy=copy};package.loaded['einkfrontend/adapter']={equal=equal}
 package.loaded['einkfrontend/paint']={s=function(n) return math.floor(n*scale+.5) end,BB={}}
 package.loaded['datastorage']={getSettingsDir=function() return '/isolated-settings' end}
 package.loaded['luasettings']={open=function(_,path)
  local s={file=path,data=copy(disk[path] or {})}
  function s:readSetting(k) return self.data[k] end
  function s:saveSetting(k,v) self.data[k]=copy(v) end
  function s:flush() disk[path]=copy(self.data);return true end
  return s
 end}
 package.loaded.device={screen={getSize=function() return {w=width,h=height} end}}
 package.loaded['ui/uimanager']={setDirty=function() end}
 package.loaded['ui/gesturerange']={new=function(_,x) return x end}
 local Input={};function Input:extend(t) t.__index=t;function t:new(o) setmetatable(o,self);o:init();return o end;return t end
 package.loaded['ui/widget/container/inputcontainer']=Input
 local Layout=require('einkfrontend/homelayout');local Fit=require('einkfrontend/homefit')
 local model=Layout.new();if config then assert(model:commit(config)) end
 app.home_layout=model
 function app:message(msg) self.messages[#self.messages+1]=msg end
 local Editor=require('einkfrontend/homeeditor')
 -- Exercise real Editor change/replace/save and real Fit/Layout, substituting only preview drawing.
 function Editor:refreshPreview() local _,_,fit=Fit.plan(self.draft,width,Fit.viewport(height));self.preview_fit=fit end
 local editor=Editor:new{app=app}
 return editor,model,Layout,Fit
end
local function fit(Fit,config,w,h) local _,_,f=Fit.plan(config,w,Fit.viewport(h));return f end
local function set(editor,Layout,id,enabled,span)
 return editor:change(function(c) local w=Layout.find(nil,id,c);if enabled~=nil then w.enabled=enabled end;if span then w.span=span end end)
end
for _,geometry in ipairs({{600,800,1},{1072,1448,1.8},{1072,1448,1.875},{1448,1072,1.8}}) do
 for _,survivor in ipairs({'weekly','streak'}) do
  for _,full in ipairs({true,false}) do
   local label=geometry[1]..'x'..geometry[2]..' scale '..geometry[3]..' survivor '..survivor..' defaults '..tostring(full)
   check('reported interaction: '..label,function()
    local e,m,L,F=fixture(unpack(geometry));local events={}
    -- Try every widget independently as full and half; hidden state retains width by design.
    for _,def in ipairs(L.registry) do
     assert(e:change(function(c) for _,w in ipairs(c.widgets) do w.enabled=false end end))
     assert(set(e,L,def.id,true,2));assert(set(e,L,def.id,true,1));assert(set(e,L,def.id,false))
    end
    assert(e:change(function(c) for _,w in ipairs(c.widgets) do w.enabled=(w.id=='currently' or w.id=='reading_stats' or w.id=='overview');w.span=full and 2 or 1 end end))
    local function event(name,fn)
     local before=copy(e.draft);local revision=e.revision;local ok,why=fn();local state=fit(F,e.draft,geometry[1],geometry[2])
     if not ok then assert(equal(before,e.draft) and e.revision==revision) end
     assert(equal(state,e.preview_fit))
     events[#events+1]={step=name,accepted=ok==true,reason=why,needed=state.needed,available=state.available,enabled=state.requested}
     return ok
    end
    local weekly_ok=event('enable weekly half',function()return set(e,L,'weekly',true,1)end)
    local streak_ok=event('enable streak half',function()return set(e,L,'streak',true,1)end)
    assert(event('hide '..(survivor=='weekly' and 'streak' or 'weekly'),function()return set(e,L,survivor=='weekly' and 'streak' or 'weekly',false)end))
    event('try stats table half',function()return set(e,L,'stats_table',true,1)end)
    assert(event('hide currently',function()return set(e,L,'currently',false)end))
    assert(event('hide reading stats',function()return set(e,L,'reading_stats',false)end))
    assert(event('hide remaining peer',function()return set(e,L,survivor,false)end))
    assert(event('retry stats table half',function()return set(e,L,'stats_table',true,1)end))
    assert(e.preview_fit.fits)
    scenarios[#scenarios+1]={geometry=label,setup_reachable=weekly_ok==true and streak_ok==true,events=events}
   end)
  end
 end
end
local finding
check('hiding a half-row widget remains possible when re-pairing increases required height',function()
 local e,m,L,F=fixture(600,800,1)
 local c=L.defaults();local active={currently=true,reading_stats=true,quote=true,clock=true,heatmap=true,stats_table=true}
 for _,w in ipairs(c.widgets) do w.enabled=active[w.id]==true;w.span=(w.id=='currently' or w.id=='reading_stats') and 2 or 1 end
 assert(m:commit(c));e.draft=copy(c);e.base=copy(c);e:refreshPreview()
 local after=copy(c);L.find(nil,'quote',after).enabled=false
 assert(fit(F,c,600,800).needed==616 and fit(F,after,600,800).needed==652)
 local accepted,why=set(e,L,'quote',false);assert(accepted,why)
 assert(not L.find(nil,'quote',e.draft).enabled and not e.preview_fit.fits and e.revision==1)
 local saved=e:save(true);assert(not saved and equal(m.config,c),'overflow must remain a draft in the explicit editor')
 assert(m:change(function(x)L.find(nil,'quote',x).enabled=false end))
 assert(not L.find(nil,'quote',m.config).enabled,'legacy auto-save must keep the hidden choice')
 -- Reset the persisted layout; LAN draft replacement still uses the same capacity guard.
 assert(m:commit(c));e.draft=copy(c);e.base=copy(c);e.revision=0;e:refreshPreview()
 local accepted_web,web_reason=e:replaceDraft(after,e.revision);assert(accepted_web,web_reason)
 assert(not e:save(true));assert(equal(m.config,c))
 assert(set(e,L,'clock',false));assert(e.preview_fit.fits and e:save(true))
 assert(not L.find(nil,'quote',m.config).enabled and not L.find(nil,'clock',m.config).enabled)
end)
check('every single half-row stats table fits after disabling all other widgets',function()
 for _,g in ipairs({{600,800,1},{1072,1448,1.8},{1072,1448,1.875},{1448,1072,1.8}}) do
  local e,m,L,F=fixture(unpack(g))
  assert(e:change(function(c)for _,w in ipairs(c.widgets)do w.enabled=false;w.span=1 end end))
  assert(set(e,L,'stats_table',true,1));assert(e.preview_fit.fits and e.preview_fit.requested==1)
 end
end)
check('hidden widgets do not retain capacity or affect active row pairing',function()
 local e,m,L,F=fixture(600,800,1)
 local c=L.defaults();for _,w in ipairs(c.widgets) do w.enabled=(w.id=='weekly' or w.id=='streak');w.span=1 end
 local before=fit(F,c,600,800)
 for _,w in ipairs(c.widgets) do if not w.enabled then w.span=2 end end
 local after=fit(F,c,600,800)
 assert(before.needed==after.needed and before.requested==after.requested and after.requested==2)
 local frames=F.plan(c,600,F.viewport(800));assert(#frames==2 and frames[1].h==frames[2].h)
end)
check('rejected statistics-table addition is atomic and frees normally after removing defaults',function()
 local e,m,L,F=fixture(1072,1448,1.875)
 assert(set(e,L,'weekly',true,1));assert(set(e,L,'streak',true,1));assert(set(e,L,'streak',false))
 local before=copy(e.draft);local revision=e.revision
 assert(not set(e,L,'stats_table',true,1));assert(equal(e.draft,before) and e.revision==revision)
 assert(set(e,L,'currently',false));assert(set(e,L,'reading_stats',false));assert(set(e,L,'weekly',false))
 assert(set(e,L,'stats_table',true,1));assert(e.preview_fit.fits)
end)
local function crowded()
 local e,m,L,F=fixture(600,800,1);local c=L.defaults()
 local active={currently=true,reading_stats=true,quote=true,clock=true,heatmap=true,stats_table=true}
 for _,w in ipairs(c.widgets) do w.enabled=active[w.id]==true;w.span=(w.id=='currently' or w.id=='reading_stats') and 2 or 1 end
 assert(m:commit(c));e.draft=copy(c);e.base=copy(c);e:refreshPreview();return e,m,L,F
end
check('hiding cannot bypass capacity while adding another widget',function()
 local e,m,L,F=crowded();local before=copy(e.draft)
 assert(not e:change(function(c)L.find(nil,'quote',c).enabled=false;L.find(nil,'tbr',c).enabled=true end))
 assert(equal(e.draft,before) and e.revision==0)
end)
check('hiding cannot bypass capacity while expanding another widget',function()
 local e,m,L,F=crowded();local before=copy(e.draft)
 assert(not e:change(function(c)L.find(nil,'quote',c).enabled=false;L.find(nil,'heatmap',c).span=2 end))
 assert(equal(e.draft,before) and e.revision==0)
end)
check('combined preference edits are not mistaken for a hide-only change',function()
 for _,field in ipairs({'recent_count','quote_text'}) do
  local e,m,L,F=crowded();local before=copy(e.draft)
  assert(not e:change(function(c)L.find(nil,'quote',c).enabled=false;c[field]=field=='recent_count' and 5 or 'changed quote' end))
  assert(equal(e.draft,before) and e.revision==0)
 end
end)
check('hiding with a reorder remains subject to normal capacity checks',function()
 local e,m,L,F=crowded();local before=copy(e.draft)
 assert(not e:change(function(c)L.find(nil,'quote',c).enabled=false;c.widgets[1],c.widgets[2]=c.widgets[2],c.widgets[1] end))
 assert(equal(e.draft,before) and e.revision==0)
end)
check('LAN revisions still reject stale writes following a successful hide',function()
 local e,m,L,F=crowded();local after=copy(e.draft);L.find(nil,'quote',after).enabled=false
 assert(e:replaceDraft(after,0));local before=copy(e.draft)
 local ok,why=e:replaceDraft(e.base,0);assert(not ok and why=='conflict')
 assert(equal(e.draft,before) and e.revision==1)
end)
check('all valid single-widget hide operations are accepted for varied row combinations',function()
 local e,m,L,F=fixture(600,800,1);local state=73
 for _=1,160 do
  local before=L.defaults()
  for _,w in ipairs(before.widgets) do
   state=(state*48271)%2147483647;w.enabled=state%3~=0
   state=(state*48271)%2147483647;w.span=state%2+1
  end
  for _,w in ipairs(before.widgets) do if w.enabled then
   local after=copy(before);L.find(nil,w.id,after).enabled=false
   assert(F.checkChange(before,after,600,F.viewport(800)),w.id)
  end end
 end
end)
AUDIT_RESULT=json({total=#results,failed=failed,checks=results})
