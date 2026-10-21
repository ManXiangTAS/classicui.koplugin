#!/usr/bin/env python3
"""Package a clean committed handoff, public installer and complete local history."""
from pathlib import Path
import hashlib,json,subprocess,sys,zipfile
from build_public_release import VERSION,build
project=Path(__file__).resolve().parents[1];delivery=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else project.parent/'deliverables';delivery.mkdir(parents=True,exist_ok=True)
def git(*args):return subprocess.check_output(['git','-C',str(project),*args],text=True).strip()
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
assert not git('status','--porcelain'),'Commit source and evidence before packaging'
commit=git('rev-parse','HEAD');installer,source=build(delivery)
bundle=delivery/f'source-history-{VERSION}-{commit[:12]}.bundle';staged=bundle.with_suffix('.bundle.building')
subprocess.run(['git','-C',str(project),'bundle','create',str(staged),'--all'],check=True)
assert f'{commit} HEAD' in subprocess.check_output(['git','bundle','list-heads',str(staged)],text=True)
subprocess.run(['git','-C',str(project),'bundle','verify',str(staged)],check=True,capture_output=True);staged.replace(bundle)
full=delivery/f'ClassicUI_{VERSION}_full_handoff.zip';staged=full.with_suffix('.zip.building');prefix=f'ClassicUI_{VERSION}/';manifest={}
with zipfile.ZipFile(staged,'w',zipfile.ZIP_DEFLATED) as z:
 for rel in filter(None,subprocess.check_output(['git','-C',str(project),'ls-files','-z']).decode().split('\0')):
  assert not (rel.startswith('test-results') and '/data/' in rel)
  if rel=='source-history.bundle':continue
  z.write(project/rel,prefix+rel);manifest[rel]=digest(project/rel)
 for path,rel in [(bundle,'source-history.bundle'),(installer,'安装包/'+installer.name)]:z.write(path,prefix+rel);manifest[rel]=digest(path)
 info=json.loads((project/'test-results-049/combined-summary.json').read_text());info.update(source_commit=commit,version=VERSION,history='Complete local Git history; public repository is a sanitized snapshot')
 z.writestr(prefix+'BUILD_INFO.json',json.dumps(info,ensure_ascii=False,indent=2));z.writestr(prefix+'MANIFEST_SHA256.json',json.dumps(manifest,ensure_ascii=False,indent=2))
with zipfile.ZipFile(staged) as z:
 assert z.testzip() is None
 for rel,sha in manifest.items():assert hashlib.sha256(z.read(prefix+rel)).hexdigest()==sha
staged.replace(full)
print(json.dumps({'install':str(installer),'source':str(source),'full':str(full),'bytes':full.stat().st_size,'source_commit':commit,'files':len(manifest),'integrity':'PASS'},ensure_ascii=False))
