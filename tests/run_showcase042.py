from pathlib import Path
import subprocess,tempfile,os,sys,hashlib,json
p=Path(__file__).resolve().parents[1];r=Path(sys.argv[1]).resolve();out=p/'test-results-042';(out/'data').mkdir(parents=True,exist_ok=True)
state=Path(tempfile.mkdtemp(prefix='showcase-',dir=out/'data'));books=state/'books'
subprocess.run([sys.executable,str(p/'tests/build_showcase_books.py'),str(books),str(r)],check=True)
before={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in books.glob('*.epub')}
env=os.environ.copy();env.update(KO_HOME=str(state),EINK_PROJECT=str(p),EINK_042_BOOKS=str(books),SDL_VIDEODRIVER='dummy',SDL_RENDER_DRIVER='software',EMULATE_BW_SCREEN='1',EMULATE_READER_W='1072',EMULATE_READER_H='1448',EMULATE_READER_DPI='300')
with (out/'showcase.log').open('w') as f:run=subprocess.run([str(r/'luajit'),str(p/'tests/showcase042.lua')],cwd=r,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=90)
if run.returncode:print((out/'showcase.log').read_text()[-6500:]);raise SystemExit(1)
assert before=={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in books.glob('*.epub')}
(out/'showcase.json').write_text(json.dumps({'version':'0.3.12-dev','status':'PASS','device':'NOT_RUN','screenshots':'real KOReader offscreen','content':'original demo books/covers; seeded demo progress, not user data','fixture_hashes':before},indent=2)+'\n')
print('PASS showcase screenshots; demo EPUB bytes unchanged')
