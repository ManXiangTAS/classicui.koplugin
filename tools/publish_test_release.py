#!/usr/bin/env python3
"""Create a draft, upload verified assets, then publish a prerelease in CI."""
from pathlib import Path
import hashlib,json,os,sys,urllib.request,urllib.error
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tests'))
from build_public_release import VERSION
repo=os.environ['GITHUB_REPOSITORY'];commit=os.environ['GITHUB_SHA'];token=os.environ['GH_TOKEN']
assert repo=='ManXiangTAS/classicui.koplugin' and len(commit)==40
base='https://api.github.com/repos/'+repo;tag='v'+VERSION
headers={'Accept':'application/vnd.github+json','Authorization':'Bearer '+token,'X-GitHub-Api-Version':'2022-11-28','User-Agent':'ClassicUI-test-release'}
def request(url,method='GET',data=None,mime='application/json'):
 h=dict(headers);h['Content-Type']=mime
 if data is not None and not isinstance(data,bytes):data=json.dumps(data).encode()
 with urllib.request.urlopen(urllib.request.Request(url,data=data,method=method,headers=h),timeout=60) as r:return json.load(r)
try:release=request(base+'/releases/tags/'+tag)
except urllib.error.HTTPError as e:
 if e.code!=404:raise
 release=request(base+'/releases','POST',{'tag_name':tag,'target_commitish':commit,'name':'ClassicUI · 墨页 '+VERSION,'body':(root/'docs/0.5.0-test.4_菜单与边界复查.md').read_text(),'draft':True,'prerelease':True})
assets=Path(sys.argv[1]);files=[assets/f'ClassicUI_{VERSION}_install.zip',assets/f'ClassicUI_{VERSION}_source.zip',assets/'SHA256SUMS.txt']
existing={a['name']:a for a in release['assets']}
for path in files:
 digest='sha256:'+hashlib.sha256(path.read_bytes()).hexdigest()
 if path.name in existing:
  assert existing[path.name].get('digest')==digest,'Existing asset differs; refusing replacement'
 else:
  assert release['draft'],'Refusing to modify an already published release'
  url=release['upload_url'].split('{')[0]+'?name='+path.name
  uploaded=request(url,'POST',path.read_bytes(),'application/zip' if path.suffix=='.zip' else 'text/plain')
  assert uploaded['size']==path.stat().st_size
  if uploaded.get('digest'):assert uploaded['digest']==digest
release=request(base+'/releases/'+str(release['id']),'PATCH',{'draft':False,'prerelease':True})
assert not release['draft'] and release['prerelease'];print(release['html_url'])
