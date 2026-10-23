-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local B=require('einkfrontend/updateboot');local S=require('einkfrontend/updatesource');local C={}
C.repo='ManXiangTAS/classicui.koplugin'
C.api='https://api.github.com/repos/'..C.repo..'/releases?per_page=100'
C.max_zip=64*1024*1024
function C.short(text,count)
 local chars=require('util').splitToChars(tostring(text));return table.concat(chars,'',1,math.min(count,#chars))
end
function C.version(text)
 if type(text)~='string' or #text>64 then return end
 local a,b,c,tail=text:match('^v?(%d+)%.(%d+)%.(%d+)(.*)$');if not a then return end
 for _,n in ipairs({a,b,c}) do if #n>8 or (#n>1 and n:sub(1,1)=='0') then return end end
 local v={tonumber(a),tonumber(b),tonumber(c),pre={}}
 if tail~='' then
  local pre=tail:match('^%-([%w.%-]+)$');if not pre then return end
  for id in (pre..'.'):gmatch('(.-)%.') do
   if id=='' or (id:match('^%d+$') and #id>1 and id:sub(1,1)=='0') then return end
   v.pre[#v.pre+1]=id
  end
 end
 return v
end
function C.newer(a,b)
 a=C.version(a);b=C.version(b);if not a or not b then return false end
 for i=1,3 do if a[i]~=b[i] then return a[i]>b[i] end end
 if #a.pre==0 or #b.pre==0 then return #a.pre==0 and #b.pre>0 end
 for i=1,math.max(#a.pre,#b.pre) do
  local x,y=a.pre[i],b.pre[i];if not x or not y then return x~=nil end
  if x~=y then
   local nx,ny=x:match('^%d+$') and tonumber(x),y:match('^%d+$') and tonumber(y)
   if nx and ny then return nx>ny elseif nx or ny then return ny~=nil else return x>y end
  end
 end
 return false
end
function C.asset(release)
 local tag=release.tag_name;assert(C.version(tag),'发布版本号无效')
 local version=tag:gsub('^v','');local name='ClassicUI_'..version..'_install.zip'
 for _,asset in ipairs(release.assets or {}) do if asset.name==name then
  local url='https://github.com/'..C.repo..'/releases/download/'..tag..'/'..name
  assert(asset.browser_download_url==url,'安装包来源不是官方仓库')
  assert(type(asset.size)=='number' and asset.size>0 and asset.size<=C.max_zip,'安装包大小无效')
  local hash=type(asset.digest)=='string' and asset.digest:match('^sha256:([a-f0-9]+)$')
  assert(hash and #hash==64,'发布包缺少 SHA-256 校验值')
  return {tag=tag,version=version,url=url,size=asset.size,sha256=hash,notes=type(release.body)=='string' and C.short(release.body,180) or '',page='https://github.com/'..C.repo..'/releases/tag/'..tag}
 end end
 error('发布中没有完整的墨页安装包')
end
function C.select(releases,current,channel)
 assert(type(releases)=='table' and C.version(current) and (releases[1]~=nil or next(releases)==nil),'发布列表或当前版本无效')
 local best
 for _,release in ipairs(releases) do
  if type(release)=='table' and not release.draft and C.version(release.tag_name) then
   local pre=#C.version(release.tag_name).pre>0 or release.prerelease==true
   if (channel=='testing' or not pre) and C.newer(release.tag_name,current) and (not best or C.newer(release.tag_name,best.tag_name)) then best=release end
  end
 end
 -- A broken newest release must be reported, never silently replaced by an older one.
 return best and C.asset(best) or nil
end
local hosts={['github.com']=true,['api.github.com']=true,['release-assets.githubusercontent.com']=true,['objects.githubusercontent.com']=true,['github-releases.githubusercontent.com']=true}
function C.allowed(url,source)
 if source and source.source~='github' then return S.allowed(url,source.relay_base or S.default_base) end
 if type(url)~='string' or #url>4096 or url:find('[%c\\]') then return false end
 local host=url:match('^https://([^/?:#]+)[/?]') or url:match('^https://([^/?:#]+)$')
 return hosts[host]==true
end
local function hostname(cert,host)
 if cert.checkhost then return cert:checkhost(host)==true end
 local extensions=cert:extensions();local san=extensions and extensions['2.5.29.17']
 for _,name in ipairs(san and san.dNSName or {}) do
  name=name:lower()
  if name==host or (name:sub(1,2)=='*.' and host:match('^[^.]+%.(.+)$')==name:sub(3)) then return true end
 end
 return false
end
local error_mt={__tostring=function(e) return e.message end}
function C.httpError(status,headers,body)
 local message='HTTP '..tostring(status);local code
 if type(body)=='string' and #body<=8192 then
  local ok,data=pcall(require('json').decode,body)
  if ok and type(data)=='table' and data.schema==1 and type(data.error)=='table' then
   if type(data.error.message)=='string' then message=C.short(data.error.message,120) end
   if type(data.error.code)=='string' and data.error.code:match('^[A-Z_]+$') then code=data.error.code end
  end
 end
 if status==503 and not code then message='更新源暂不可用，请稍后重试'
 elseif status==403 and not code then message='更新源拒绝访问，请检查地址或稍后重试'
 elseif status==404 and not code then message='更新接口不存在，请检查中转基础地址'
 elseif status==429 and not code then message='更新请求受限，请稍后重试' end
 local wait=headers and headers['retry-after'];local retry_at
 if type(wait)=='string' and wait:match('^%d+$') then retry_at=os.time()+math.min(31536000,tonumber(wait))
 elseif type(wait)=='string' then
  local day,mon,year,hour,min,sec=wait:match('^%a+, (%d%d) (%a+) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT$')
  local months={Jan=0,Feb=1,Mar=2,Apr=3,May=4,Jun=5,Jul=6,Aug=7,Sep=8,Oct=9,Nov=10,Dec=11}
  if day and months[mon] then
   local ffi=require('ffi');require('ffi/posix_h');local tm=ffi.new('struct tm');tm.tm_mday=tonumber(day);tm.tm_mon=months[mon];tm.tm_year=tonumber(year)-1900
   tm.tm_hour=tonumber(hour);tm.tm_min=tonumber(min);tm.tm_sec=tonumber(sec);retry_at=tonumber(ffi.C.timegm(tm))
   if retry_at<os.time() then retry_at=nil end
  end
 end
 return setmetatable({status=status,code=code,message=message..(code and '（'..code..'）' or ''),retry_at=retry_at},error_mt)
end
function C.get(url,path,limit,source)
 local socketutil=require('socketutil');local http=require('socket.http');local https=require('ssl.https');local socket=require('socket')
 local block,total=socketutil.block_timeout,socketutil.total_timeout;local started=socket.gettime()
 socketutil:set_timeout(12,path and 150 or 35)
 local ok,result=pcall(function()
  for _=1,6 do
   assert(C.allowed(url,source),'更新地址或跳转不属于所选更新源')
   local file=path and assert(io.open(path,'wb'));local chunks={};local size=0;local prefix=''
   local request_ok,code,headers
   local called,why=pcall(function()
    request_ok,code,headers=http.request{url=url,method='GET',redirect=false,proxy=false,
     headers={['User-Agent']='ClassicUI-Updater',Accept='application/json',['Accept-Encoding']='identity'},
     create=function()
      local conn=https.tcp{verify='peer',cafile=C.ca_file or 'data/ca-bundle.crt',protocol='tlsv1_2'}()
      local connect=conn.connect
      function conn:connect(host,port)
       local result=connect(self,host,port)
       assert(result,'无法连接更新源：'..host)
       assert(hostname(self.sock:getpeercertificate(),host),'TLS 主机名校验失败')
       return result
      end
      return conn
     end,
     sink=function(chunk,err)
      if err then return nil,err end
      if chunk then
       size=size+#chunk;if size>limit then return nil,'下载内容超过限制' end
       if #prefix<8192 then prefix=prefix..chunk:sub(1,8192-#prefix) end
       if socket.gettime()-started>(path and 150 or 35) then return nil,'下载超时' end
       if file then local wrote,e=file:write(chunk);if not wrote then return nil,e end else chunks[#chunks+1]=chunk end
      end
      return 1
     end}
   end)
   if file then file:close() end
   assert(called,why);assert(request_ok,'网络请求失败：'..tostring(code))
   if code==200 then return path and size or table.concat(chunks) end
   if (code==301 or code==302 or code==303 or code==307 or code==308) and headers and headers.location then url=require('socket.url').absolute(url,headers.location)
   else error(C.httpError(code,headers,prefix)) end
  end
  error('下载跳转次数过多')
 end)
 socketutil:set_timeout(block,total)
 if not ok then if path then os.remove(path) end;error(result) end
 return result
end
function C.relay(data,current,channel,base)
 assert(type(data)=='table' and data.schema==1 and data.repo==C.repo and data.channel==channel,'中转清单协议、仓库或通道不匹配')
 assert(type(data.stale)=='boolean','中转缓存状态无效')
 local info={status=data.status,stale=data.stale}
 if type(data.source_checked_at)=='string' then
  assert(#data.source_checked_at<=64 and not data.source_checked_at:find('%c'),'中转检查时间无效');info.source_checked_at=data.source_checked_at
 end
 if data.status=='no_release' then assert(data.release==nil or data.release==require('json.util').null,'无发布清单包含了版本');return nil,info end
 assert(data.status=='ready' and type(data.release)=='table','中转清单尚未就绪或状态无效')
 local r=data.release;local v=C.version(r.version)
 assert(v and r.version:sub(1,1)~='v' and type(r.tag)=='string' and r.tag:gsub('^v','')==r.version,'中转版本或标签无效')
 assert(type(r.prerelease)=='boolean' and (channel=='testing' or (#v.pre==0 and not r.prerelease)),'中转返回了错误的版本通道')
 local a=r.asset;assert(type(a)=='table' and a.name=='ClassicUI_'..r.version..'_install.zip','不是完整的墨页安装包')
 assert(type(a.size)=='number' and a.size==math.floor(a.size) and a.size>0 and a.size<=C.max_zip,'安装包大小无效')
 assert(type(a.sha256)=='string' and #a.sha256==64 and a.sha256:match('^[a-f0-9]+$'),'安装包摘要无效')
 local origin='https://github.com/'..C.repo..'/releases/download/'..r.tag..'/'..a.name
 assert(a.origin_url==origin and r.page=='https://github.com/'..C.repo..'/releases/tag/'..r.tag,'安装包官方来源不匹配')
 assert(a.download_path=='/v1/classicui/packages/'..r.version..'/'..a.sha256..'.zip','中转安装包路径无效')
 assert(type(r.notes)=='string' and type(r.koreader)=='table' and #r.koreader>0 and #r.koreader<=100,'中转说明或兼容信息无效')
 local compatible=false
 for _,revision in ipairs(r.koreader) do assert(type(revision)=='string' and #revision<=100,'中转兼容版本无效');if revision==require('version'):getCurrentRevision() then compatible=true end end
 if not C.newer(r.version,current) then return nil,info end
 assert(compatible,'此更新不支持当前 KOReader 版本')
 return {tag=r.tag,version=r.version,url=origin,size=a.size,sha256=a.sha256,notes=C.short(r.notes,180),page=r.page,relay_base=S.base(base),download_path=a.download_path,channel=channel},info
end
function C.fetch(current,channel,source)
 if source and source.source~='github' then
  local base=S.base(source.relay_base or S.default_base)
  local body=C.get(S.url(base,'/v1/classicui/manifest',channel),nil,2*1024*1024,source)
  local ok,data=pcall(require('json').decode,body);assert(ok,'中转未返回有效 JSON，请检查完整基础地址及站点防护')
  return C.relay(data,current,channel,base)
 end
 local body=C.get(C.api,nil,2*1024*1024)
 local releases=require('json').decode(body)
 return C.select(releases,current,channel),{status=next(releases)==nil and 'no_release' or 'ready',stale=false}
end
function C.stage(root,zip,release)
 assert(B.regular(zip) and B.hash(zip)==release.sha256,'安装包 SHA-256 校验失败')
 local work=B.work(root);assert(not B.load(work,'journal.json'),'安装恢复尚未完成')
 local reader=require('ffi/archiver').Reader:new();assert(reader:open(zip),'无法打开安装包')
 local ok,why=pcall(function()
  local entries,seen={},{};local total=0;local manifest
  for entry in reader:iterate() do
   assert(entry.mode=='file','安装包包含链接或非普通文件')
   assert(B.safe(entry.path),'安装包路径无效')
   local folded=entry.path:lower();assert(not seen[folded],'安装包包含重名文件');seen[folded]=true
   assert(#entries<4096 and entry.size>=0 and entry.size<=8*1024*1024,'安装包文件过大或过多')
   total=total+tonumber(entry.size);assert(total<=128*1024*1024,'安装包展开后过大')
   local rel=entry.path:match('^einkfrontend%.koplugin/(.+)$')
   local extra=({['BUILD_INFO.json']=true,['SOURCE_FILES_SHA256.json']=true,['README_安装与范围.md']=true,['Voyage_0.4.0_实测指南.md']=true})[entry.path]
   assert(rel or extra,'不是墨页安装包，或包含插件外的文件')
   entries[#entries+1]={path=entry.path,rel=rel,size=tonumber(entry.size)}
   if rel=='UPDATE_MANIFEST.json' then
    assert(entry.size<=512*1024,'更新清单过大')
    manifest=B.manifest(require('json').decode(assert(reader:extractToMemory(entry.path))))
   end
  end
  assert(not reader.err,reader.err);assert(manifest and manifest.version==release.version,'安装包缺少更新清单或版本不符')
  local _,free=require('ffi/util').df(root);assert(free>=total*2+8*1024*1024,'可用空间不足')
  -- A valid old prepared update is retained until the replacement is fully checked.
  B.removeTree(work..'/incoming');B.mkdir(work..'/incoming')
  local actual={}
  for _,entry in ipairs(entries) do if entry.rel then
   local data=assert(reader:extractToMemory(entry.path),'安装包内容损坏')
   assert(#data==entry.size,'安装包文件长度不符')
   if entry.rel~='UPDATE_MANIFEST.json' then assert(manifest.files[entry.rel]==require('ffi/sha2').sha256(data),'文件校验失败：'..entry.rel);actual[entry.rel]=true end
   B.atomic(work..'/incoming',entry.rel,data)
  end end
  for path in pairs(manifest.files) do assert(actual[path],'清单文件缺失：'..path) end
  assert(B.read(work..'/incoming/main.lua',128*1024):find('einkfrontend/updateboot',1,true),'安装包不支持安全重启安装')
  B.checkStage(root,release.version,work..'/incoming')
  -- Mark no pending operation before rotating stages; interruption leaves old code intact.
  os.remove(work..'/pending.json');B.removeTree(work..'/next');assert(os.rename(work..'/incoming',work..'/next'))
  B.checkStage(root,release.version)
  B.save(work,'pending.json',{schema=1,version=release.version,created=os.time()})
 end)
 reader:close();if not ok then B.removeTree(work..'/incoming');error(why) end
 return true
end
function C.download(root,release)
 assert(C.allowed(release.url) and C.version(release.version) and release.url=='https://github.com/'..C.repo..'/releases/download/'..(release.tag or 'v'..release.version)..'/ClassicUI_'..release.version..'_install.zip','下载信息无效')
 assert(type(release.size)=='number' and release.size>0 and release.size<=C.max_zip and type(release.sha256)=='string' and #release.sha256==64 and release.sha256:match('^[a-f0-9]+$'),'下载校验信息无效')
 local work=B.work(root);B.mkdir(work)
 local _,free=require('ffi/util').df(root);assert(free>=release.size*3+8*1024*1024,'可用空间不足')
 local zip=work..'/download.zip';assert(not require('libs/libkoreader-lfs').symlinkattributes(zip) or B.regular(zip),'下载目标不是普通文件')
 local source=release.relay_base and {source='relay',relay_base=S.base(release.relay_base)} or nil
 local url=release.url
 if source then
  assert(release.download_path=='/v1/classicui/packages/'..release.version..'/'..release.sha256..'.zip','中转下载路径无效')
  url=S.url(source.relay_base,release.download_path)
 end
 local size=C.get(url,zip,C.max_zip,source);if size~=release.size then os.remove(zip);error('安装包下载不完整') end
 local ok,why=pcall(C.stage,root,zip,release);os.remove(zip);assert(ok,why)
 return {version=release.version}
end
function C.prepare(root,release,current,config)
 local ok,result=pcall(C.download,root,release)
 if ok then return result end
 if not (release.relay_base and type(result)=='table' and result.status==410 and result.code=='PACKAGE_RETIRED') then error(result) end
 local fresh,info=C.fetch(current,config.channel,config)
 if not fresh then return {no_update=true,info=info} end
 local pending=B.pending(root)
 if pending and not C.newer(fresh.version,pending.version) then return {version=pending.version,release=fresh,info=info} end
 local value=C.download(root,fresh);value.release=fresh;value.info=info;return value
end
return C
