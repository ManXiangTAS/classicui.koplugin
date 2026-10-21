require('setupkoenv')
package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
G_defaults=require('luadefaults'):open();local DS=require('datastorage');local Settings=require('luasettings')
G_reader_settings=Settings:open(DS:getDataDir()..'/settings.reader.lua')
G_reader_settings:saveSetting('eink_transfer',{wizard_seen=true})
G_reader_settings:saveSetting('language','zh_CN');require('gettext').changeLang('zh_CN')
G_reader_settings:saveSetting('eink_frontend',{auto_open=false,reader_entry=true,full_takeover=true})
G_reader_settings:saveSetting('document_metadata_folder','dir')
require('logger'):setLevel(require('logger').levels.warn)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local FM=require('apps/filemanager/filemanager');local Reader=require('apps/reader/readerui')
local Clock=require('einkfrontend/clock');local Copy=require('einkfrontend/catalog').copy;local Equal=require('einkfrontend/adapter').equal
local root=assert(os.getenv('EINK_PROJECT'));local dir=assert(os.getenv('EINK_030_BOOKS'));local variant=os.getenv('EINK_VARIANT');local mode=arg[1]
local report={version='0.3.14-dev',variant=variant,mode=mode,device='NOT_RUN',network='native timesync callback mocked; no host/system clock writes',tests={}}
local function check(name,fn) local ok,why=pcall(fn);report.tests[#report.tests+1]={name=name,status=ok and 'PASS' or 'FAIL',error=not ok and tostring(why) or nil};print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(why)));assert(ok,why) end
local function shot(name)
 local remove={};for _,v in ipairs(UI._window_stack) do if v.widget.text then remove[#remove+1]=v.widget end end;for _,v in ipairs(remove) do UI:close(v) end
 UI:forceRePaint();assert(not (FM.instance and FM.instance.einkfrontend.app.screen and FM.instance.einkfrontend.app.screen.paint_fault));Device.screen:shot(root..'/test-results-045/'..name..'-'..variant..'.png')
end
FM:showFiles(dir);local app=FM.instance.einkfrontend.app;local clock=app.clock
local function row(title) for _,r in ipairs(app.screen.model.rows) do if r.title==title then return r end end;error('missing row '..title) end
local function UTC(y,m,d,h,min) Clock.apply('Etc/UTC');return os.time{year=y,month=m,day=d,hour=h or 0,min=min or 0,sec=0} end
if mode=='restart' then
 check('Fresh KOReader process restores saved IANA timezone before frontend rendering',function()
  assert(clock.config.zone=='Asia/Shanghai' and not clock.error);assert(os.date('%z',1767225600)=='+0800')
  app:open('clock_settings');assert(app.screen.model.title=='时间与日期');shot('clock-restart')
 end)
else
 check('Bundled timezone inventory is complete and excludes arbitrary paths',function()
  assert(Clock.version=='2026e' and #Clock.zones==419)
  for _,zone in ipairs(Clock.zones) do assert(Clock.by_id[zone.id]);Clock.apply(zone.id);assert(os.date('%z',1767225600):match('^[+-]%d%d%d%d$')) end
  Clock.apply('system');assert(os.getenv('TZ')=='UTC')
 end)
 check('IANA zones apply UTC offsets fractional offsets and opposite-hemisphere DST',function()
  local winter=UTC(2026,1,15,12);local summer=UTC(2026,7,15,12)
  for _,entry in ipairs({{'Asia/Shanghai','+0800','+0800'},{'Asia/Tokyo','+0900','+0900'},{'Asia/Kolkata','+0530','+0530'},{'Asia/Kathmandu','+0545','+0545'},{'America/New_York','-0500','-0400'},{'Europe/London','+0000','+0100'},{'Australia/Sydney','+1100','+1000'}}) do
   Clock.apply(entry[1]);assert(os.date('%z',winter)==entry[2],entry[1]);assert(os.date('%z',summer)==entry[3],entry[1])
  end
  Clock.apply('system');assert(os.getenv('TZ')=='UTC')
 end)
 check('SQLite local day and Lua clock change together across date boundaries',function()
  local ts=UTC(2026,1,1,20,30);local conn=require('lua-ljsqlite3/init').open(':memory:')
  assert(conn:rowexec("SELECT date("..ts..",'unixepoch','localtime')")=='2026-01-01')
  assert(clock:select('Asia/Shanghai'));assert(os.date('%Y-%m-%d %H:%M',ts)=='2026-01-02 04:30')
  assert(conn:rowexec("SELECT date("..ts..",'unixepoch','localtime')")=='2026-01-02');conn:close()
  assert(require('einkfrontend/homestats').day(-1,ts)=='2026-01-01')
 end)
 check('Settings expose one time destination under device and network, and search finds timezone',function()
  for _,category in ipairs({'device','network'}) do
   app:open('catalog_category',category);row('时间与日期').callback();assert(app.screen.model.title=='时间与日期')
   row('时区');row('立即同步时间与日期');row('手动时间与显示格式')
  end
  require('einkfrontend/settings').search(app,'时区');row('时间与日期').callback();assert(app.screen.model.title=='时间与日期')
  shot('clock-settings-unavailable')
 end)
 check('Timezone picker selects real zones and supports searchable complete inventory',function()
  app:open('settings');app:go('catalog_category','device');row('时间与日期').callback();row('时区').callback()
  row('东京').callback();assert(clock.config.zone=='Asia/Tokyo' and os.date('%z')=='+0900');assert(#app.stack==3 and app.stack[2].param=='device')
  app:back();assert(app.stack[#app.stack].param=='device')
  app:open('clock_zone_list','Kathmandu');assert(#app.screen.model.rows==2);row('尼泊尔').callback();assert(clock.config.zone=='Asia/Kathmandu' and os.date('%z')=='+0545')
  app:open('clock_zone_list','no_such_zone_045');assert(#app.screen.model.rows==2);row('没有匹配的地区')
  app:open('clock_zones');local page=app.screen;UI:forceRePaint();page:scrollBy(page.scroll_max);shot('clock-zones-bottom')
  assert(clock:select('Asia/Shanghai'));app:open('clock_zones');shot('clock-zones')
 end)
 check('Invalid selections and failed writes restore both timezone and persisted settings',function()
  local before=Copy(clock.config);local tz=os.getenv('TZ')
  for _,value in ipairs({'../etc/passwd','Asia/Shanghai;date','unknown','',true}) do assert(not clock:select(value));assert(Equal(clock.config,before) and os.getenv('TZ')==tz) end
  local flush=clock.settings.flush;clock.settings.flush=function() error('injected clock flush failure') end
  local ok=clock:select('Europe/London');clock.settings.flush=flush;assert(not ok)
  assert(Equal(clock.config,before) and os.getenv('TZ')==tz);assert(Equal(Settings:open(clock.settings.file):readSetting('clock'),before))
  clock.settings.flush=function() end;ok=clock:select('Europe/London');clock.settings.flush=flush;assert(not ok and os.getenv('TZ')==tz)
  assert(Equal(Settings:open(clock.settings.file):readSetting('clock'),before))
 end)
 check('Damaged timezone settings remain on disk until explicit valid selection',function()
  local before=Copy(clock.config);clock.settings:saveSetting('clock',{version=1,zone='../../invalid'});clock.settings:flush()
  local broken=Clock.new();assert(broken.error);assert(Settings:open(clock.settings.file):readSetting('clock').zone=='../../invalid')
  assert(broken:select('Asia/Shanghai'));assert(not broken.error);assert(clock.config.zone==before.zone)
 end)
 check('Unsupported or disabled native timesync never pretends a successful sync',function()
  local refresh=app.native.refresh;app.native.refresh=function() end;local entries=app.native.catalog.entries;local previous=entries.synchronize_time
  entries.synchronize_time=nil;local ok,why=Clock.sync(app);assert(not ok and why:find('不可用'))
  entries.synchronize_time={node={enabled=false,callback=function() error('must not run') end}};assert(not Clock.sync(app))
  entries.synchronize_time=previous;app.native.refresh=refresh
 end)
 check('Native sync uses network gating once, refreshes afterward and preserves native messages',function()
  local Network=require('ui/network/manager');local run=Network.runWhenOnline;local refresh=app.native.refresh
  local saved=app.native.catalog.entries.synchronize_time;local called,gated,queued=0,0
  app.native.refresh=function() end
  app.native.catalog.entries.synchronize_time={node={callback=function() called=called+1 end}}
  Network.runWhenOnline=function(_,callback) gated=gated+1;queued=callback end
  app:open('clock_settings');assert(Clock.sync(app));assert(called==0 and gated==1);queued();assert(called==1)
  shot('clock-settings');Network.runWhenOnline=run;app.native.refresh=refresh;app.native.catalog.entries.synchronize_time=saved
 end)
 check('Thrown sync failure stays local and a closed owner cancels queued callback',function()
  local Network=require('ui/network/manager');local run=Network.runWhenOnline;local refresh=app.native.refresh;local saved=app.native.catalog.entries.synchronize_time
  app.native.refresh=function() end;Network.runWhenOnline=function(_,fn) fn() end
  app.native.catalog.entries.synchronize_time={node={callback=function() error('injected NTP failure') end}}
  local message=app.message;local text;app.message=function(_,v) text=v end;assert(Clock.sync(app));assert(text:find('未完成') and text:find('injected NTP failure'));app.message=message
  local queued;Network.runWhenOnline=function(_,fn) queued=fn end
  app.native.catalog.entries.synchronize_time={node={callback=function() error('closed owner invoked') end}}
  assert(Clock.sync(app));local alive=app.adapter.alive;app.adapter.alive=function() return false end;queued();app.adapter.alive=alive
  app.plugin.active=false;queued();app.plugin.active=true
  Network.runWhenOnline=run;app.native.refresh=refresh;app.native.catalog.entries.synchronize_time=saved
 end)
 check('Home clock opens the same settings and manual native controls remain reachable',function()
  assert(app.home_layout:change(function(c) for _,w in ipairs(c.widgets) do w.enabled=w.id=='clock' end end));app:open('home');UI:forceRePaint()
  local hit;for _,h in ipairs(app.screen.hits) do if h.id=='home_clock_settings' then hit=h end end;assert(hit);hit.callback();assert(app.screen.model.title=='时间与日期')
  row('手动时间与显示格式').callback();assert(app.stack[#app.stack].id=='native')
  assert(app.native.host and #app.native.host.item_table>1);app:back()
 end)
 check('Reader and file-manager owners share selected timezone without changing UTC epoch',function()
  local start=os.time();Reader:doShowReader(dir..'/A.epub');local r=assert(Reader.instance);local other=r.einkfrontend.app
  assert(other.clock.config.zone=='Asia/Shanghai');assert(other.clock:select('Asia/Tokyo'));assert(clock.config.zone=='Asia/Tokyo')
  local flush=clock.settings.flush;clock.settings.flush=function() error('cross-owner failure') end
  assert(not clock:select('Europe/London'));clock.settings.flush=flush
  assert(clock.config.zone=='Asia/Tokyo' and Settings:open(clock.settings.file):readSetting('clock').zone=='Asia/Tokyo')
  assert(os.time()-start>=0 and os.time()-start<30);other:open('clock_settings');shot('clock-reader');other:close();r:onClose()
  assert(clock:select('system'));assert(os.getenv('TZ')=='UTC');assert(clock:select('Asia/Shanghai'))
 end)
end
app:close();if FM.instance then FM.instance:onClose() end
local f=assert(io.open(root..'/test-results-045/'..mode..'-'..variant..'.json','w'));f:write(require('json').encode(report));f:close();print('PASS clock045 '..mode)
