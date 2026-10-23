"""Fresh-process plugin activation and interruption recovery with complete plugin trees."""
from pathlib import Path
import os,shutil,json,zipfile,hashlib,subprocess,tempfile,sys
root=Path(__file__).resolve().parents[1];base=Path(sys.argv[1]).resolve();out=root/'test-results-057';(out/'data').mkdir(exist_ok=True)
state=Path(tempfile.mkdtemp(prefix='boot-',dir=out/'data'))
original={p.relative_to(root/'einkfrontend.koplugin').as_posix():p.read_bytes() for p in (root/'einkfrontend.koplugin').rglob('*') if p.is_file()}
future=dict(original);future['einkfrontend/version.lua']=b"return '0.5.0-test.8'\n"
def manifest(files,version):return {'schema':1,'version':version,'koreader':['v2026.07.1','v2026.07.2'],'files':{k:hashlib.sha256(v).hexdigest() for k,v in files.items()}}
future['UPDATE_MANIFEST.json']=json.dumps(manifest(future,'0.5.0-test.8')).encode()
archive=state/'future.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for name,data in future.items():z.writestr('einkfrontend.koplugin/'+name,data)
release={'version':'0.5.0-test.8','sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
(state/'release.json').write_text(json.dumps(release))
results=[]
for mode,expected in [('activate','0.5.0-test.8'),('interrupt','0.5.0-test.7'),('tamper','0.5.0-test.7')]:
 runtime=state/(mode+'-runtime');shutil.copytree(base,runtime,symlinks=True,copy_function=os.link)
 link=runtime/'plugins/einkfrontend.koplugin';link.unlink()
 target=state/mode;shutil.copytree(root/'einkfrontend.koplugin',target)
 (target/'UPDATE_MANIFEST.json').write_text(json.dumps(manifest(original,'0.5.0-test.7')))
 (target/'user-note.txt').write_text('preserved user file')
 if link.is_symlink():link.unlink()
 link.symlink_to(target)
 home=state/(mode+'-home');books=home/'books';books.mkdir(parents=True);shutil.copyfile(root/'tests/navigation/chapters.epub',books/'book.epub')
 env=dict(os.environ,KO_HOME=str(home),EINK_PROJECT=str(root),EINK_030_BOOKS=str(books),EINK_VARIANT='boot',EINK_BOOT_TARGET=str(target),EINK_BOOT_ARCHIVE=str(archive),EINK_BOOT_RELEASE=str(state/'release.json'),EINK_BOOT_MODE=mode,EINK_BOOT_EXPECTED=expected,SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1')
 with (out/f'boot-{mode}.log').open('w') as log:
  for script in ['update_boot_stage057.lua','update_boot_start057.lua']:
   p=subprocess.run([str(runtime/'luajit'),str(root/'tests'/script)],cwd=runtime,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=90)
   if p.returncode:print((out/f'boot-{mode}.log').read_text()[-7000:]);raise SystemExit('BOOT FAIL '+mode)
 assert (target/'user-note.txt').read_text()=='preserved user file'
 results.append({'name':mode,'status':'PASS','loaded_version':expected});print('PASS boot',mode,expected,flush=True)
summary={'checks':len(results),'failures':0,'device':'NOT_RUN','scope':'Fresh-process whole-plugin staged activation, interrupted swap recovery and tampered stage rejection','results':results}
(out/'boot-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
