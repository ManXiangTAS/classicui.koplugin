#!/usr/bin/env python3
"""Emergency withdrawal authorized by the repository owner: no package publication."""
import json,os,time,urllib.request
repo=os.environ['GITHUB_REPOSITORY']
assert repo=='ManXiangTAS/classicui.koplugin'
base='https://api.github.com/repos/'+repo
headers={'Accept':'application/vnd.github+json','Authorization':'Bearer '+os.environ['GH_TOKEN'],'X-GitHub-Api-Version':'2022-11-28','User-Agent':'ClassicUI-release-withdrawal'}
def request(url,method='GET',data=None):
 h=dict(headers);h['Content-Type']='application/json'
 payload=json.dumps(data).encode() if data is not None else None
 with urllib.request.urlopen(urllib.request.Request(url,data=payload,method=method,headers=h),timeout=60) as response:return json.load(response)
releases=[]
for page in range(1,101):
 batch=request(base+'/releases?per_page=100&page='+str(page))
 releases.extend(batch)
 if len(batch)<100:break
else:raise RuntimeError('Release pagination limit exceeded')
count=0
for release in releases:
 if release['draft']:continue
 result=request(base+'/releases/'+str(release['id']),'PATCH',{'draft':True})
 assert result['draft'],'Withdrawal failed'
 print('WITHDRAWN',release['tag_name'],flush=True);count+=1
 time.sleep(1)
print('WITHDRAWAL COMPLETE',count,'previous releases are drafts; no package published',flush=True)
