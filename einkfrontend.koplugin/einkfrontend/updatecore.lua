-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local B=require('einkfrontend/updateboot');local C={}
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
function C.allowed(url)
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
function C.get(url,path,limit)
 local socketutil=require('socketutil');local http=require('socket.http');local https=require('ssl.https');local socket=require('socket')
 local block,total=socketutil.block_timeout,socketutil.total_timeout;local started=socket.gettime()
 socketutil:set_timeout(12,path and 150 or 35)
 local ok,result=pcall(function()
  for _=1,6 do
   assert(C.allowed(url),'禁止跳转到非 GitHub 下载地址')
   local file=path and assert(io.open(path,'wb'));local chunks={};local size=0
   local request_ok,code,headers
   local called,why=pcall(function()
    request_ok,code,headers=http.request{url=url,method='GET',redirect=false,proxy=false,
     headers={['User-Agent']='ClassicUI-Updater',Accept='application/vnd.github+json'},
     create=function()
      local conn=https.tcp{verify='peer',cafile=C.ca_file or 'data/ca-bundle.crt',protocol='tlsv1_2'}()
      local connect=conn.connect
      function conn:connect(host,port)
       local result=connect(self,host,port)
       assert(hostname(self.sock:getpeercertificate(),host),'TLS 主机名校验失败')
       return result
      end
      return conn
     end,
     sink=function(chunk,err)
      if err then return nil,err end
      if chunk then
       size=size+#chunk;if size>limit then return nil,'下载内容超过限制' end
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
   else error(code==403 and 'GitHub 请求受限，请稍后重试' or 'HTTP '..tostring(code)) end
  end
  error('下载跳转次数过多')
 end)
 socketutil:set_timeout(block,total)
 if not ok then if path then os.remove(path) end;error(result) end
 return result
end
function C.fetch(current,channel)
 local body=C.get(C.api,nil,2*1024*1024)
 return C.select(require('json').decode(body),current,channel)
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
 local size=C.get(release.url,zip,C.max_zip);if size~=release.size then os.remove(zip);error('安装包下载不完整') end
 local ok,why=pcall(C.stage,root,zip,release);os.remove(zip);assert(ok,why)
 return {version=release.version}
end
return C
