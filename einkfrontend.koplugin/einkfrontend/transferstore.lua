-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- No remote paths: the device user selects one root, clients supply basenames only.
local bit=require('bit');require('ffi/posix_h')
local lfs=require('libs/libkoreader-lfs');local util=require('ffi/util')
local Store={};Store.__index=Store
Store.default='/mnt/us/documents/ManualBook';Store.limit=200*1024*1024;Store.chunk=64*1024
local extensions={epub=true,pdf=true,txt=true,fb2=true,cbz=true,cbr=true,djvu=true,mobi=true,azw=true,azw3=true,html=true,htm=true,rtf=true,doc=true,docx=true}
function Store.directory(path,create)
 assert(type(path)=='string' and #path<=1024 and path:sub(1,1)=='/' and not path:find('[%c\\]'),'����������ļ���·��')
 path=path:gsub('/+$','');assert(path~='' and path~='/mnt' and path~='/mnt/us','��ѡ���鼮ר���ļ���')
 local current=''
 for part in path:gmatch('[^/]+') do
  assert(part~='.' and part~='..','Ŀ¼���ܰ��� . �� ..');current=current..'/'..part
  local attr=lfs.symlinkattributes(current)
  if not attr and create then assert(lfs.mkdir(current),'�޷������鼮�ļ���');attr=lfs.symlinkattributes(current) end
  assert(attr and attr.mode=='directory','�ļ��в����ڻ������������')
 end
 assert(util.realpath(path)==path,'�ļ���·����Ч');return path
end
function Store.filename(name)
 assert(type(name)=='string' and #name>0 and #name<=180 and name:sub(1,1)~='.' and not name:find('[%c/\\:*?"<>|]') and not name:match('[ .]$'),'�ļ�����Ч����ʹ�ò�����180�ֽڵ�����')
 assert(extensions[(name:match('%.([%w]+)$') or ''):lower()],'��֧�ִ��ļ�����');return name
end
function Store.new(root)
 return setmetatable({root=Store.directory(root,false)},Store)
end
function Store:checkRoot() assert(Store.directory(self.root,false)==self.root,'�鼮�ļ����ѱ仯') end
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
 assert(type(size)=='number' and size%1==0 and size>0 and size<=Store.limit,'ÿ������200 MB')
 local _,free=util.df(self.root);assert(free and free>=size+16*1024*1024,'�ռ䲻�㣬�����ٱ����鼮��С��16 MB�Ŀ��ÿռ�')
 assert(not self.upload,'������ɻ�ȡ����ǰ�ļ�')
 if self.temp then assert(self:abort(),'�ϴ��ϴ�����ʱ�ļ���ʱ�޷���������رմ��������') end
 assert(type(id)=='string' and id:match('^[a-f0-9]+$') and #id==48,'�Ự��ʶ��Ч')
 -- Exclusive open prevents overwriting preexisting paths, including symlinks.
 local ffi=require('ffi');local C=ffi.C
 local path=self.root..'/.moye-upload-'..id..'.part'
 local fd=C.open(path,bit.bor(1,64,128),ffi.cast("unsigned int",384));assert(fd>=0,'�޷�������ʱ�ļ�������ռ���Ŀ¼Ȩ��');C.close(fd)
 self.temp=path;self.file=assert(io.open(path,'wb'));self.upload={name=name,size=size,received=0,id=id};self.digest=require("ffi/sha2").sha256();return self.upload
end
function Store:append(id,offset,body)
 local u=assert(self.upload,'û�����ڽ��յ��鼮');assert(id==u.id,'�ϴ���ʶ�ѹ���')
 assert(type(offset)=='number' and offset==u.received,'�ϴ�λ�ò�һ�£�������')
 assert(#body>0 and #body<=Store.chunk and u.received+#body<=u.size,'�ֿ��С��Ч')
 self:checkRoot();assert(self.file:write(body),'д��ʧ�ܣ�����ʣ��ռ�');assert(self.file:flush(),'д��ʧ��');self.digest(body);u.received=u.received+#body;return u.received
end
function Store:finish(id)
 self:checkRoot();local u=assert(self.upload,'û�����ڽ��յ��鼮');assert(id==u.id and u.received==u.size,'�鼮��δ�������')
 if not u.sealed then
  assert(self.file,'�ϴ��ļ��Ѿ��رգ������·���')
  assert(util.fsyncOpenedFile(self.file),'���浽�洢ʧ�ܣ�����ռ����豸״̬')
  local file=self.file;self.file=nil
  local called,closed=pcall(file.close,file)
  if not called or not closed then self:abort();error('����ʧ�ܣ������·����鼮') end
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
  assert(ffi.errno()==17,'�޷������鼮������ʣ��ռ��Ȩ��')
 end
 assert(fd and fd>=0,'ͬ���ļ�����');C.close(fd)
 local target=self.root..'/'..name
 -- The reserved final basename is ours; never replace an existing user file.
 local ok,why=os.rename(self.temp,target)
 if not ok then os.remove(target);error('�޷�����鼮���棺'..tostring(why)) end
 self.temp=nil;self.upload=nil
 if not util.fsyncDirectory(self.root) then require('logger').warn('Transfer directory sync unavailable') end
 self.digest=nil;return name,u.identity
end
return Store
