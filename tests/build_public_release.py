#!/usr/bin/env python3
"""Build deterministic manual-install and source archives for ClassicUI."""
from pathlib import Path
import hashlib,json,re,sys,zipfile
PROJECT=Path(__file__).resolve().parents[1];VERSION='0.6.2'
def sha(data):return hashlib.sha256(data).hexdigest()
def public_paths():
 files=[]
 for name in ['einkfrontend.koplugin','docs','media','tools','tests']:
  for p in (PROJECT/name).rglob('*'):
   if p.is_file() and not any(s in p.parts for s in ['__pycache__','node_modules','.release-work']) and not p.name.endswith(('.pyc','.mp4','.wav','.log')):files.append(p)
 for name in ['README.md','CHANGELOG.md','NOTICE.md','COPYING','.gitignore']:files.append(PROJECT/name)
 files.extend((PROJECT/'.github/workflows').glob('*.yml'));return sorted(set(files))
def inputs():
 plugin=PROJECT/'einkfrontend.koplugin';assert (plugin/'einkfrontend/version.lua').read_text().strip()==f"return '{VERSION}'"
 assert f'version = "{VERSION}"' in (plugin/'_meta.lua').read_text()
 assert 'removed=true' in (plugin/'einkfrontend/updater.lua').read_text()
 assert not any((plugin/'resources'/name).exists() for name in ['epub-polish.html','jszip.min.js'])
 from xml.etree import ElementTree as ET
 for p in (plugin/'resources/transfer-assets').glob('*.svg'):
  for e in ET.parse(p).iter():
   assert e.tag.split('}')[-1].lower() not in ['script','foreignobject']
   for k,v in e.attrib.items():assert not k.lower().startswith('on') and (not k.endswith('href') or v.startswith('#'))
 files={str(p.relative_to(PROJECT)):p.read_bytes() for p in public_paths()}
 for name,data in files.items():
  assert not name.startswith('test-results') and '/data/' not in name
  if name.endswith(('.lua','.py','.md','.html','.json','.mjs','.yml')):
   text=data.decode();assert not re.search(r'github_pat_[A-Za-z0-9_]{30,}|gh[pousr]_[A-Za-z0-9]{30,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----',text),name
 return files

def writezip(path,files):
 staged=path.with_suffix('.zip.building')
 with zipfile.ZipFile(staged,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for rel,data in sorted(files.items()):
   info=zipfile.ZipInfo(rel,(2026,10,23,0,0,0));info.external_attr=0o100644<<16;info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,data)
 with zipfile.ZipFile(staged) as z:
  assert z.testzip() is None
  for rel,data in files.items():assert sha(z.read(rel))==sha(data)
 staged.replace(path)
def build(output):
 out=Path(output);out.mkdir(parents=True,exist_ok=True);files=inputs()
 encode=lambda v:(json.dumps(v,ensure_ascii=False,indent=2)+'\n').encode()
 info={'name':'ClassicUI · 墨页','version':VERSION,'plugin_directory':'einkfrontend.koplugin','koreader':['v2026.07.1','v2026.07.2'],'installation':'manual'}
 install={k:v for k,v in files.items() if k.startswith('einkfrontend.koplugin/')};install['einkfrontend.koplugin/COPYING']=files['COPYING'];install['README_安装.md']=files['docs/guide.md'];install['BUILD_INFO.json']=encode(info)
 install['SHA256.json']=encode({k:sha(v) for k,v in sorted(install.items())})
 source=dict(files);source['BUILD_INFO.json']=encode(info);source['SHA256.json']=encode({k:sha(v) for k,v in sorted(source.items())})
 installer=out/f'ClassicUI_{VERSION}_install.zip';archive=out/f'ClassicUI_{VERSION}_source.zip';writezip(installer,install);writezip(archive,source)
 hashes={p.name:sha(p.read_bytes()) for p in [installer,archive]};(out/'SHA256SUMS.txt').write_text(''.join(v+'  '+k+'\n' for k,v in hashes.items()))
 print(json.dumps({'version':VERSION,'public_files':len(files),'assets':hashes},ensure_ascii=False,indent=2));return installer,archive
if __name__=='__main__':build(sys.argv[1] if len(sys.argv)>1 else PROJECT/'dist')
