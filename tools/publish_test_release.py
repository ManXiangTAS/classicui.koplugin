#!/usr/bin/env python3
"""Prepare a draft; publication requires an explicit maintainer confirmation."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,time,urllib.request,urllib.error
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tests'))
from build_public_release import VERSION
repo=os.environ['GITHUB_REPOSITORY'];commit=os.environ['GITHUB_SHA'];token=os.environ['GH_TOKEN']
publish_confirmed=os.environ.get('RELEASE_PUBLISH_CONFIRMED')=='1'
assert repo=='ManXiangTAS/classicui.koplugin' and len(commit)==40
assert 'removed=true' in (root/'einkfrontend.koplugin/einkfrontend/updater.lua').read_text()
assets=Path(sys.argv[1])
files=[assets/f'ClassicUI_{VERSION}_install.zip',assets/f'ClassicUI_{VERSION}_source.zip']
(assets/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in files));files.append(assets/'SHA256SUMS.txt')
base='https://api.github.com/repos/'+repo;tag='v'+VERSION
headers={'Accept':'application/vnd.github+json','Authorization':'Bearer '+token,'X-GitHub-Api-Version':'2022-11-28','User-Agent':'ClassicUI-release'}
def request(url,method='GET',data=None,mime='application/json'):
 h=dict(headers);h['Content-Type']=mime
 if data is not None and not isinstance(data,bytes):data=json.dumps(data).encode()
 with urllib.request.urlopen(urllib.request.Request(url,data=data,method=method,headers=h),timeout=120) as r:
  if r.status==204:return None
  return json.load(r)
try:release=request(base+'/releases/tags/'+tag)
except urllib.error.HTTPError as e:
 if e.code!=404:raise
 release=request(base+'/releases','POST',{'tag_name':tag,'target_commitish':commit,'name':'墨页 · ClassicUI '+VERSION,'body':(root/f'docs/release-{VERSION}.md').read_text(),'draft':True,'prerelease':False})
if not release['draft']:
 print('Release already published; retaining its original assets.');sys.exit(0)
# A candidate may be rebuilt before approval. Its draft metadata follows the
# exact source used to build the assets; published versions are never replaced.
release=request(base+'/releases/'+str(release['id']),'PATCH',{'target_commitish':commit,'body':(root/f'docs/release-{VERSION}.md').read_text()})
existing={a['name']:a for a in release['assets']}
for path in files:
 digest='sha256:'+hashlib.sha256(path.read_bytes()).hexdigest()
 if path.name in existing and existing[path.name].get('digest')!=digest:
  assert release['draft'],'Refusing to replace published assets'
  request(base+'/releases/assets/'+str(existing[path.name]['id']),'DELETE');del existing[path.name]
 if path.name not in existing:
  assert release['draft'],'Refusing to replace published assets'
  mime='video/mp4' if path.suffix=='.mp4' else 'application/zip' if path.suffix=='.zip' else 'text/plain'
  uploaded=request(release['upload_url'].split('{')[0]+'?name='+path.name,'POST',path.read_bytes(),mime)
  assert uploaded['size']==path.stat().st_size
  if uploaded.get('digest'):assert uploaded['digest']==digest
# Earlier releases stay reversible as drafts; tags and source history are retained.
for page in range(1,101):
 batch=request(base+'/releases?per_page=100&page='+str(page))
 for old in batch:
  if old['tag_name']!=tag and not old['draft']:
   assert request(base+'/releases/'+str(old['id']),'PATCH',{'draft':True})['draft'];time.sleep(.3)
 if len(batch)<100:break
else:raise RuntimeError('Release pagination limit exceeded')
if publish_confirmed:
 release=request(base+'/releases/'+str(release['id']),'PATCH',{'draft':False,'prerelease':False,'make_latest':'true'})
 assert not release['draft'] and not release['prerelease']
else:assert release['draft'],'Candidate must remain a draft until stability is confirmed'
print(json.dumps({'url':release['html_url'],'draft':release['draft'],'version':VERSION}))
