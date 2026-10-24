-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- No remote paths: the device user selects one root, clients supply basenames only.
local bit=require('bit');require('ffi/posix_h')
local lfs=require('libs/libkoreader-lfs');local util=require('ffi/util')
local Store={};Store.__index=Store
Store.default='/mnt/us/documents/ManualBook';Store.limit=200*1024*1024;Store.chunk=64*1024
local extensions={epub=true,pdf=true,txt=true,fb2=true,cbz=true,cbr=true,djvu=true,mobi=true,azw=true,azw3=true,html=true,htm=true,rtf=true,doc=true,docx=true}
function Store.directory(path,create)
 assert(type(path)=='string' and #path<=1024 and path:sub(1,1)=='/' and not path:find('[%c\\]'),'请输入绝对文件夹路径')
 path=path:gsub('/+$','');assert(path~='' and path~='/mnt' and path~='/mnt/us','请选择书籍专用文件夹')
 local current=''
 for part in path:gmatch('[^/]+') do
  assert(part~='.' and part~='..','目录不能包含 . 或 ..');current=current..'/'..part
  local attr=lfs.symlinkattributes(current)
  if not attr and create then assert(lfs.mkdir(current),'无法创建书籍文件夹');attr=lfs.symlinkattributes(current) end
  assert(attr and attr.mode=='directory','文件夹不存在或包含符号链接')
 end
 assert(util.realpath(path)==path,'文件夹路径无效');return path
end
function Store.filename(name)
 assert(type(name)=='string' and #name>0 and #name<=180 and name:sub(1,1)~='.' and not name:find('[%c/\\:*?"<>|]') and not name:match('[ .]$'),'文件名无效；请使用不超过180字节的书名')
 assert(extensions[(name:match('%.([%w]+)$') or ''):lower()],'不支持此文件类型');return name
end
function Store.new(root)
 return setmetatable({root=Store.directory(root,false)},Store)
end
function Store:checkRoot() assert(Store.directory(self.root,false)==self.root,'书籍文件夹已变化') end
function Store:abort()
 if self.file then pcall(self.file.close,self.file);self.file=nil end
 self.upload=nil;self.digest=nil
 if self.temp and lfs.symlinkattributes(self.temp) then
  if not os.remove(self.temp) then return false end
 end
 self.temp=nil;return true
end
function Store:begin(name,size,id)
 self:checkRoot();Store.filename(name)
 assert(type(size)=='number' and size%1==0 and size>0 and size<=Store.limit,'每本书限200 MB')
 local _,free=util.df(self.root);assert(free and free>=size+16*1024*1024,'空间不足，请至少保留书籍大小加16 MB的可用空间')
 assert(not self.upload,'请先完成或取消当前文件')
 if self.temp then assert(self:abort(),'上次上传的临时文件暂时无法清理，请关闭传书后重试') end
 assert(type(id)=='string' and id:match('^[a-f0-9]+$') and #id==48,'会话标识无效')
 -- Exclusive open prevents overwriting preexisting paths, including symlinks.
 local ffi=require('ffi');local C=ffi.C
 local path=self.root..'/.moye-upload-'..id..'.part'
 local fd=C.open(path,bit.bor(1,64,128),ffi.cast("unsigned int",384));assert(fd>=0,'无法创建临时文件，请检查空间与目录权限');C.close(fd)
 self.temp=path;self.file=assert(io.open(path,'wb'));self.upload={name=name,size=size,received=0,id=id};self.digest=require("ffi/sha2").sha256();return self.upload
end
function Store:append(id,offset,body)
 local u=assert(self.upload,'没有正在接收的书籍');assert(id==u.id,'上传标识已过期')
 assert(type(offset)=='number' and offset==u.received,'上传位置不一致，请重试')
 assert(#body>0 and #body<=Store.chunk and u.received+#body<=u.size,'分块大小无效')
 self:checkRoot();assert(self.file:write(body),'写入失败，请检查剩余空间');assert(self.file:flush(),'写入失败');self.digest(body);u.received=u.received+#body;return u.received
end
function Store:finish(id)
 self:checkRoot();local u=assert(self.upload,'没有正在接收的书籍');assert(id==u.id and u.received==u.size,'书籍尚未传输完成')
 if not u.sealed then
  assert(self.file,'上传文件已经关闭，请重新发送')
  assert(util.fsyncOpenedFile(self.file),'保存到存储失败，请检查空间与设备状态')
  local file=self.file;self.file=nil
  local called,closed=pcall(file.close,file)
  if not called or not closed then self:abort();error('保存失败，请重新发送书籍') end
  u.sealed=true
 end
 -- A failed final rename is retryable without fsync on a closed handle or
 -- finalizing the incremental digest twice.
 if not u.identity then u.identity=self.digest() end
 local stem,ext=u.name:match('^(.*)(%.[^.]+)$');local name=u.name
 local fd;local ffi=require('ffi');local C=ffi.C
 for i=0,999 do
  name=i==0 and u.name or stem..' ('..i..')'..ext
  fd=C.open(self.root..'/'..name,bit.bor(1,64,128),ffi.cast("unsigned int",384))
  if fd>=0 then break end
  assert(ffi.errno()==17,'无法保存书籍，请检查剩余空间和权限')
 end
 assert(fd and fd>=0,'同名文件过多');C.close(fd)
 local target=self.root..'/'..name
 -- The reserved final basename is ours; never replace an existing user file.
 local ok,why=os.rename(self.temp,target)
 if not ok then os.remove(target);error('无法完成书籍保存：'..tostring(why)) end
 self.temp=nil;self.upload=nil
 if not util.fsyncDirectory(self.root) then require('logger').warn('Transfer directory sync unavailable') end
 self.digest=nil;return name,u.identity
end
return Store
