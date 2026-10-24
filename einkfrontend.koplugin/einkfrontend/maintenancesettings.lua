-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
local Maintenance=require('einkfrontend/bookmaintenance')
local View={}
function View.open(app)
 if not app.book_maintenance then app.book_maintenance=Maintenance.new(app) end
 app:go('library_cleanup');app.book_maintenance:scan();app:render()
end
function View.render(app,route,m,row)
 if route.id~='library_cleanup' then return false end
 m.settings=true;m.title='������ɾ���鼮������';m.subtitle=''
 local service=app.book_maintenance
 if not service then row('ɨ����ɾ���鼮������',nil,function() View.open(app) end);return true end
 m.help=function() app:message('ֻ������ǰ���Ŀ¼�ڣ���ȷ���ļ������ڵ��鼮���ݡ�\nɨ�������Ԫ���ݻ��桢ʧЧ����������ղغ�����Ķ���¼���Լ���ɾ���鼮���Ķ����á����桢���Ϻͱ���۸���ʷ�Ķ�ͳ��������ͼ������\n����ǰ�ɲ鿴�������ִ��ʱ�ٴκ˶��ļ������·Żص��鼮���������޷���ȡ��Ŀ¼������·�����޷�ȷ�Ϲ��������ݲ���������\nͬ����ͬ��ʽ�Դ���ʱ����������������ϣ���ϣ����Ԫ���ݱ���������Ӱ�츱����') end
 if service.state=='scanning' then
  row('����ɨ�衭','ɨ���ڼ䲻��ɾ���κ��ļ�')
  row('ȡ��ɨ��',nil,function() service:cancel();app:render() end)
 elseif service.state=='cleaning' then row('����������','�뱣�����洢�豸����')
 elseif service.state=='ready' then
  local p=service.plan
  row('��ɾ�����鼮',p.count..' ��')
  row('�����������ļ�',#p.files..' �� �� '..string.format('%.1f KB',p.bytes/1024))
  if #p.empty_dirs>0 then row('�ղ���Ŀ¼',#p.empty_dirs..' ��') end
  row('��ʷ�Ķ�ͳ��','�����ۼ�ʱ����ҳ��������ͼ')
  if p.skipped>0 or p.truncated then row('����λ��������',p.truncated and 'ɨ���Ѵ����ޣ��ɷ�Ŀ¼����' or '���޷���ȡ��λ��') end
  if p.count>0 or #p.files>0 or #p.empty_dirs>0 then
   row('������������',nil,function()
    app:confirm('���� '..p.count..' ����ɾ���鼮�ļ�¼��'..#p.files..' �������ļ��� '..#p.empty_dirs..' ����Ŀ¼��\n��������Ķ����á����������ϣ���ʷ�Ķ�ͳ�Ʊ�����',function()
     app:userAction(function() service:apply(p);app:render() end)
    end)
   end)
  else row('û�з��ֿ���������','�����鼮�������ݾ��ѱ���') end
  row('����ɨ��',nil,function() service:scan();app:render() end)
  local shown=0
  for file in pairs(p.books) do
   shown=shown+1;if shown>12 then row('���и����鼮',p.count..' ���Ѽ������������');break end
   row(file:match('([^/]+)$'),file)
  end
 elseif service.state=='done' then
  local r=service.result
  row('�������',r.books..' ����¼ �� '..r.removed..' �������ļ�')
  row('�ͷſռ�',string.format('%.1f KB',r.bytes/1024))
  if r.directories>0 then row('��Ŀ¼���Ƴ�',r.directories..' ��') end
  if r.skipped>0 then row('������',r.skipped..' ����仯���޷�ȷ��') end
  if r.failed>0 then row('�����ļ�����ʧ��',r.failed..' ��ɼ��洢Ȩ�޺�����') end
  row('��ʷ�Ķ�ͳ���ѱ���')
  row('����ɨ��',nil,function() service:scan();app:render() end)
 else
  row(service.state=='error' and '����δ���' or 'ɨ����ȡ��',service.error or 'û�м�������������Ŀ')
  row('����ɨ��',nil,function() service:scan();app:render() end)
 end
 return true
end
return View
