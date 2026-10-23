"""Real LuaSocket/LuaSec loopback HTTPS, certificates, redirects and file sinks."""
from pathlib import Path
import http.server,ssl,threading,subprocess,tempfile,os,json,sys,urllib.parse,hashlib
root=Path(__file__).resolve().parents[1];runtime=Path(sys.argv[1]).resolve();out=root/'test-results-059';out.mkdir(exist_ok=True)
(out/'data').mkdir(exist_ok=True)
state=Path(tempfile.mkdtemp(prefix='relay-tls-',dir=out/'data'))
def openssl(*args):subprocess.run(['openssl',*args],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(state/'ca.key'),'-out',str(state/'ca.crt'),'-days','2','-subj','/CN=ClassicUI test CA')
def certificate(name,san):
 openssl('req','-newkey','rsa:2048','-nodes','-keyout',str(state/(name+'.key')),'-out',str(state/(name+'.csr')),'-subj','/CN='+name)
 (state/(name+'.ext')).write_text('subjectAltName='+san+'\n')
 openssl('x509','-req','-in',str(state/(name+'.csr')),'-CA',str(state/'ca.crt'),'-CAkey',str(state/'ca.key'),'-CAcreateserial','-out',str(state/(name+'.crt')),'-days','2','-extfile',str(state/(name+'.ext')))
certificate('good','DNS:api.github.com,DNS:github.com,DNS:release-assets.githubusercontent.com,DNS:relay.example');certificate('wrong','DNS:unrelated.invalid')
package=(root/'tests/update-fixtures/valid.zip').read_bytes()
manifest=json.loads((root/'tests/relay-fixtures/manifest-ready.example.json').read_text())
manifest['release']['asset']['size']=len(package)
manifest['release']['asset']['sha256']=hashlib.sha256(package).hexdigest()
manifest['release']['asset']['download_path']='/v1/classicui/packages/'+manifest['release']['version']+'/'+hashlib.sha256(package).hexdigest()+'.zip'
counts={}
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def send(self,status,body=b'',headers=None):
  self.send_response(status)
  for k,v in (headers or {}).items():self.send_header(k,v)
  if 'Content-Length' not in (headers or {}):self.send_header('Content-Length',str(len(body)))
  self.end_headers()
  try:self.wfile.write(body)
  except (BrokenPipeError,ssl.SSLError,ConnectionResetError):pass
 def do_GET(self):
  url=urllib.parse.urlsplit(self.path);query=urllib.parse.parse_qs(url.query)
  mode=url.path.split('/')[1];route=query.get('classicui_relay',[''])[0]
  if self.headers.get('Accept-Encoding')!='identity':return self.send(400,b'identity required')
  if route=='/v1/classicui/manifest':
   if query.get('channel')!=['testing']:return self.send(400,b'channel')
   if mode=='html':return self.send(200,b'<html>Login required</html>')
   data=json.loads(json.dumps(manifest));data['release']['notes']='package_calls='+str(counts.get(mode,0))
   return self.send(200,json.dumps(data).encode(),{'Content-Type':'application/json'})
  if route!=manifest['release']['asset']['download_path']:return self.send(404,b'route')
  counts[mode]=counts.get(mode,0)+1
  if mode=='expired' or (mode=='retry' and counts[mode]==1):
   return self.send(410,json.dumps({'schema':1,'error':{'code':'PACKAGE_RETIRED','message':'package retired','retryable':True}}).encode(),{'Content-Type':'application/json'})
  if mode=='busy':return self.send(503,json.dumps({'schema':1,'error':{'code':'CACHE_NOT_READY','message':'cache not ready','retryable':True}}).encode(),{'Retry-After':'60'})
  if mode=='cross':return self.send(302,headers={'Location':'https://github.com/good'})
  if mode=='downgrade':return self.send(302,headers={'Location':'http://relay.example'+self.path})
  if mode=='same' and counts[mode]==1:return self.send(302,headers={'Location':'https://relay.example'+self.path})
  if mode=='truncated':return self.send(200,b'short',{'Content-Length':str(len(package))})
  body=package[:-1]+b'X' if mode=='wrongsha' else package
  return self.send(200,body,{'Content-Type':'application/zip'})
servers=[]
for name in ['good','wrong']:
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.load_cert_chain(state/(name+'.crt'),state/(name+'.key'));server.socket=ctx.wrap_socket(server.socket,server_side=True)
 threading.Thread(target=server.serve_forever,daemon=True).start();servers.append(server)
env=dict(os.environ,KO_HOME=str(state/'home'),EINK_PROJECT=str(root),EINK_030_BOOKS=str(root/'tests/fixtures'),EINK_VARIANT='tls',SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',TLS_CA=str(state/'ca.crt'),TLS_GOOD=str(servers[0].server_port),TLS_WRONG=str(servers[1].server_port),TLS_OUTPUT=str(state))
try:
 with (out/'tls.log').open('w') as log:p=subprocess.run([str(runtime/'luajit'),str(root/'tests/relay_tls059.lua')],cwd=runtime,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=60)
 if p.returncode:print((out/'tls.log').read_text()[-8000:]);raise SystemExit('TLS FAIL')
 report=json.loads((state/'tls.json').read_text());(out/'relay-tls-summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(report)
finally:
 for server in servers:server.shutdown();server.server_close()
