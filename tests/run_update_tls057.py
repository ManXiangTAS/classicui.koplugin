"""Real LuaSocket/LuaSec loopback HTTPS, certificates, redirects and file sinks."""
from pathlib import Path
import http.server,ssl,threading,subprocess,tempfile,os,json,sys
root=Path(__file__).resolve().parents[1];runtime=Path(sys.argv[1]).resolve();out=root/'test-results-057';out.mkdir(exist_ok=True)
state=Path(tempfile.mkdtemp(prefix='tls-',dir=out/'data'))
def openssl(*args):subprocess.run(['openssl',*args],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(state/'ca.key'),'-out',str(state/'ca.crt'),'-days','2','-subj','/CN=ClassicUI test CA')
def certificate(name,san):
 openssl('req','-newkey','rsa:2048','-nodes','-keyout',str(state/(name+'.key')),'-out',str(state/(name+'.csr')),'-subj','/CN='+name)
 (state/(name+'.ext')).write_text('subjectAltName='+san+'\n')
 openssl('x509','-req','-in',str(state/(name+'.csr')),'-CA',str(state/'ca.crt'),'-CAkey',str(state/'ca.key'),'-CAcreateserial','-out',str(state/(name+'.crt')),'-days','2','-extfile',str(state/(name+'.ext')))
certificate('good','DNS:api.github.com,DNS:github.com,DNS:release-assets.githubusercontent.com');certificate('wrong','DNS:unrelated.invalid')
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  if self.path in ['/redirect','/evil','/downgrade']:
   location={'/redirect':'https://release-assets.githubusercontent.com/good','/evil':'https://attacker.invalid/file','/downgrade':'http://github.com/file'}[self.path]
   self.send_response(302);self.send_header('Location',location);self.end_headers();return
  body=b'hello TLS' if self.path=='/good' else b'x'*65536 if self.path=='/large' else b'short'
  self.send_response(200);self.send_header('Content-Length','1000' if self.path=='/truncated' else str(len(body)));self.end_headers()
  try:self.wfile.write(body)
  except (BrokenPipeError,ssl.SSLError,ConnectionResetError):pass
servers=[]
for name in ['good','wrong']:
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.load_cert_chain(state/(name+'.crt'),state/(name+'.key'));server.socket=ctx.wrap_socket(server.socket,server_side=True)
 threading.Thread(target=server.serve_forever,daemon=True).start();servers.append(server)
env=dict(os.environ,KO_HOME=str(state/'home'),EINK_PROJECT=str(root),EINK_030_BOOKS=str(root/'tests/fixtures'),EINK_VARIANT='tls',SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',TLS_CA=str(state/'ca.crt'),TLS_GOOD=str(servers[0].server_port),TLS_WRONG=str(servers[1].server_port),TLS_OUTPUT=str(state))
try:
 with (out/'tls.log').open('w') as log:p=subprocess.run([str(runtime/'luajit'),str(root/'tests/update_tls057.lua')],cwd=runtime,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=60)
 if p.returncode:print((out/'tls.log').read_text()[-8000:]);raise SystemExit('TLS FAIL')
 report=json.loads((state/'tls.json').read_text());(out/'tls-summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(report)
finally:
 for server in servers:server.shutdown();server.server_close()
