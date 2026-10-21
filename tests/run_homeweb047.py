from pathlib import Path
import json,os,tempfile,shutil,subprocess,time,sys,socket
p=Path(__file__).resolve().parents[1];r=Path(sys.argv[1]).resolve();out=p/'test-results-047';(out/'data').mkdir(parents=True,exist_ok=True)
state=Path(tempfile.mkdtemp(dir=out/'data'));books=state/'books';books.mkdir();shutil.copyfile(p/'tests/fixtures/A.epub',books/'A.epub')
base=(p/'tests/regression046.lua').read_text().split("Reader:doShowReader(books..")[0]
base+='''
FM:showFiles(books);local app=FM.instance.einkfrontend.app;app:open('home');local editor=app:showHomeEditor()
local server=require('einkfrontend/homeweb').new(editor,{ip='127.0.0.1',no_firewall=true});editor.server=server
local json=require('rapidjson');local f=assert(io.open(os.getenv('EINK_WEB_META'),'w'));f:write(json.encode{url=server.url,origin=server.origin,token=server.token,output=root..'/test-results-047'});f:close()
local socket=require('socket');local deadline=socket.gettime()+90
while socket.gettime()<deadline do
 server:poll();UI:_checkTasks();UI:forceRePaint();local stop=io.open(os.getenv('EINK_WEB_STOP'),'r');if stop then stop:close();break end;socket.sleep(.015)
end
editor:close();app:close();FM.instance:onClose()
'''
script=state/'server.lua';script.write_text(base);meta=state/'session.json';stop=state/'stop'
env=os.environ.copy();env.update(KO_HOME=str(state),EINK_PROJECT=str(p),EINK_030_BOOKS=str(books),EINK_VARIANT='voyage',EINK_WEB_META=str(meta),EINK_WEB_STOP=str(stop),SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',EMULATE_READER_W='1072',EMULATE_READER_H='1448',EMULATE_READER_DPI='300')
with (out/'server.log').open('w') as log:
 server=subprocess.Popen([str(r/'luajit'),str(script)],cwd=r,env=env,stdout=log,stderr=subprocess.STDOUT)
 try:
  start=time.monotonic()
  while not meta.exists() and server.poll() is None and time.monotonic()-start<15:time.sleep(.05)
  assert meta.exists(),(out/'server.log').read_text()[-5000:]
  subprocess.run([os.environ.get('CODEX_PRIMARY_RUNTIME_NODE','node'),str(p/'tests/homeweb047.mjs'),str(meta)],env=env,check=True,timeout=60)
  data=json.loads(meta.read_text());host,port=data['origin'][7:].split(':')
  # A genuine fragmented request must be assembled without blocking the UI.
  conn=socket.create_connection((host,int(port)));conn.settimeout(4)
  request=f'GET /api/layout HTTP/1.1\r\nHost: {host}:{port}\r\nAuthorization: Bearer {data["token"]}\r\n\r\n'.encode()
  for start in range(0,len(request),7):conn.sendall(request[start:start+7]);time.sleep(.01)
  response=b''
  while True:
   chunk=conn.recv(4096)
   if not chunk:break
   response+=chunk
  conn.close();assert response.startswith(b'HTTP/1.1 200 ') and b'daily_goal_minutes' in response
  print('PASS fragmented HTTP request')
 finally:
  stop.touch();server.wait(timeout=10)
 assert server.returncode==0,(out/'server.log').read_text()[-5000:]
 print('PASS native server closes cleanly')
