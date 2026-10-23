#!/usr/bin/env python3
"""Browser + real LuaSocket server integration. Requires Playwright and Chromium."""
from pathlib import Path
import argparse,json,os,shutil,socket,subprocess,tempfile,time
p=Path(__file__).resolve().parents[1];parser=argparse.ArgumentParser();parser.add_argument('runtime',type=Path);parser.add_argument('mode',choices=['upload','home_editor']);args=parser.parse_args();r=args.runtime.resolve()
out=p/'test-results'/args.mode;out.mkdir(parents=True,exist_ok=True);state=Path(tempfile.mkdtemp(dir=out));books=state/'books';books.mkdir();shutil.copyfile(p/'tests/fixtures/A.epub',books/'A.epub');(books/'ManualBook').mkdir()
base=(p/'tests/test_core.lua').read_text().split('FM:showFiles(books);')[0]
if args.mode=='upload':setup="local T=require('einkfrontend/transfersettings');T.configure(app,books..'/ManualBook');app:open('transfer_settings');local server=require('einkfrontend/transferweb').new(app,{root=books..'/ManualBook',ip='127.0.0.1',no_firewall=true});app.transfer_server=server"
else:setup="app:open('home');local editor=app:showHomeEditor();local server=require('einkfrontend/homeweb').new(editor,{ip='127.0.0.1',no_firewall=true});editor.server=server"
base+="FM:showFiles(books);local app=FM.instance.einkfrontend.app;"+setup+'''
local f=assert(io.open(os.getenv('EINK_WEB_META'),'w'));f:write(require('rapidjson').encode{url=server.url,origin=server.origin,token=server.token,output=os.getenv('EINK_TEST_OUTPUT'),project=root,directory=books..'/ManualBook'});f:close()
local socket=require('socket');local deadline=socket.gettime()+180
while socket.gettime()<deadline do
 server:poll();UI:_checkTasks();UI:forceRePaint();local stop=io.open(os.getenv('EINK_WEB_STOP'),'r');if stop then stop:close();break end;socket.sleep(.008)
end
server:stop();if app.home_editor then app.home_editor:close() end;app:close();FM.instance:onClose()
'''
script=state/'server.lua';script.write_text(base);meta=state/'session.json';stop=state/'stop'
env=dict(os.environ,KO_HOME=str(state),EINK_PROJECT=str(p),EINK_030_BOOKS=str(books),EINK_VARIANT='voyage',EINK_TEST_OUTPUT=str(out),EINK_WEB_META=str(meta),EINK_WEB_STOP=str(stop),SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',EMULATE_READER_W='1072',EMULATE_READER_H='1448',EMULATE_READER_DPI='300')
with (out/'server.log').open('w') as log:
 server=subprocess.Popen([str(r/'luajit'),str(script)],cwd=r,env=env,stdout=log,stderr=subprocess.STDOUT)
 try:
  start=time.monotonic()
  while not meta.exists() and server.poll() is None and time.monotonic()-start<20:time.sleep(.05)
  assert meta.exists(),(out/'server.log').read_text()[-5000:]
  subprocess.run([env.get('NODE','node'),str(p/'tests'/('test_'+args.mode+'.mjs')),str(meta)],env=env,check=True,timeout=150)
  d=json.loads(meta.read_text());host,port=d['origin'][7:].split(':');conn=socket.create_connection((host,int(port)));conn.settimeout(5)
  path='/api/info' if args.mode=='upload' else '/api/layout';request=f'GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\nAuthorization: Bearer {d["token"]}\r\n\r\n'.encode()
  for i in range(0,len(request),7):conn.sendall(request[i:i+7]);time.sleep(.002)
  response=b''
  while data:=conn.recv(4096):response+=data
  conn.close();assert response.startswith(b'HTTP/1.1 200 ');print('PASS fragmented HTTP')
 finally:stop.touch();server.wait(timeout=15)
 assert server.returncode==0,(out/'server.log').read_text()[-5000:]
 assert not list((books/'ManualBook').glob('.*.part'));print('PASS session cleanup')
