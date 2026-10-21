from pathlib import Path
import tarfile,subprocess,hashlib,json,shutil,sys,tempfile
project=Path(__file__).resolve().parents[1]
base=Path(tempfile.mkdtemp(prefix='classicui-tz-build-'));source=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else project/'docs/vendor/tzdata2026e.tar.gz';extract=base/'source';extract.mkdir(exist_ok=True)
with tarfile.open(source) as t:
 for f in t.getmembers():
  if f.isfile() and '/' not in f.name:t.extract(f,extract,filter='data')
assert (extract/'version').read_text().strip()=='2026e'
compiled=base/'compiled';compiled.mkdir(exist_ok=True)
subprocess.run(['zic','-b','fat','-d',str(compiled),*[str(extract/f) for f in ['africa','antarctica','asia','australasia','europe','northamerica','southamerica','etcetera','backward']]],check=True)
out=project/'einkfrontend.koplugin/resources/timezones';out.mkdir(parents=True,exist_ok=True)
zones=[]
for line in (extract/'zone.tab').read_text().splitlines():
 if line and not line.startswith('#'):
  cols=line.split('\t');zones.append({'id':cols[2],'country':cols[0]})
zones.append({'id':'Etc/UTC','country':'--'});zones.sort(key=lambda v:v['id'])
for entry in zones:
 src=compiled/entry['id'];dst=out/entry['id'];dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst);assert dst.read_bytes().startswith(b'TZif');entry['sha256']=hashlib.sha256(dst.read_bytes()).hexdigest()
(out/'zones.json').write_text(json.dumps({'version':'2026e','zones':zones},ensure_ascii=False,indent=2)+'\n')
shutil.copyfile(extract/'LICENSE',out/'LICENSE')
(out/'SOURCES.json').write_text(json.dumps({'project':'IANA Time Zone Database','version':'2026e','source_url':'https://data.iana.org/time-zones/releases/tzdata2026e.tar.gz','archive_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'compile_command':'zic -b fat -d OUTPUT africa antarctica asia australasia europe northamerica southamerica etcetera backward','compiler':subprocess.check_output(['zic','--version'],text=True).strip(),'selector':'zone.tab plus Etc/UTC','license':'Public domain; see LICENSE'},indent=2)+'\n')
print(len(zones),'bundled zones',sum((out/z['id']).stat().st_size for z in zones),'bytes')
