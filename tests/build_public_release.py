#!/usr/bin/env python3
"""Build reproducible public artifacts from an explicit source allowlist."""
from pathlib import Path
import hashlib,json,re,sys,zipfile
PROJECT=Path(__file__).resolve().parents[1]
VERSION='0.5.0-test.8'
def sha(data):return hashlib.sha256(data).hexdigest()
def public_paths():
 paths=[]
 for folder in ['einkfrontend.koplugin','tests']:
  for p in (PROJECT/folder).rglob('*'):
   if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.pyc':paths.append(p)
 for rel in ['README.md','docs/PagePress.md','docs/0.5.0_网页传书与重排.md','docs/0.5.0_安全检查.md','docs/墨页安装与使用教程.html','docs/主页固定一屏.md','COPYING','PROJECT_STATUS.json','Voyage_0.4.0_实测指南.md','docs/0.4.0_主题与主页编辑.md','docs/vendor/tzdata2026e.tar.gz','tools/make_tutorial051.py','tools/encode_tutorial051.py','tools/record_transfer051.mjs','tools/build_timezones.py','tools/publish_test_release.py','tools/import_public_snapshot.py','test-results-051/combined-summary.json','test-results-051/syntax.json','test-results-051/summary.json','test-results-051/browser-summary.json','test-results-051/tutorial-video.json','test-results-047/browser-summary.json','test-results-040/summary.json','test-results-041/summary.json']:
  paths.append(PROJECT/rel)
 paths+=list((PROJECT/'docs/previews').glob('*.png'))
 paths+=list((PROJECT/'docs/native-controls').glob('*'))
 paths+=[PROJECT/rel for rel in ['docs/0.5.0-test.5_输入法与原生屏保.md','test-results-055/summary.json','test-results-055/combined-summary.json','test-results-055/syntax.json']]
 paths+=[PROJECT/rel for rel in ['docs/0.5.0-test.6_中英一键切换.md','test-results-056/summary.json','test-results-056/combined-summary.json','test-results-056/syntax.json']]
 paths+=[PROJECT/rel for rel in ['docs/0.5.0-test.7_插件内更新.md','test-results-057/summary.json','test-results-057/combined-summary.json','test-results-057/syntax.json','test-results-057/tls-summary.json','test-results-057/boot-summary.json','test-results-057/live-network.json']]
 paths+=[PROJECT/rel for rel in ['docs/0.5.0-test.8_屏保壁纸整合.md','test-results-058/summary.json','test-results-058/combined-summary.json','test-results-058/syntax.json']]
 paths.append(PROJECT/'.gitignore')
 paths+=[PROJECT/rel for rel in ['docs/0.5.0-test.3_设置更多菜单.md','test-results-053/summary.json','test-results-053/combined-summary.json','test-results-053/syntax.json']]
 paths+=[PROJECT/rel for rel in ['docs/0.5.0-test.4_菜单与边界复查.md','test-results-054/summary.json','test-results-054/combined-summary.json','test-results-054/syntax.json','test-results-054/network-summary.json','test-results-046/summary.json']]
 paths+=[PROJECT/rel for rel in ['docs/0.5.0-test.2_基础控件统一.md','tools/audit_native_controls.py','test-results-052/summary.json','test-results-052/combined-summary.json','test-results-052/syntax.json','test-results-030/summary.json','test-results/summary.json']]
 paths+=list((PROJECT/'.github/workflows').glob('*.yml'))
 return sorted(set(paths))
def inputs():
 status=json.loads((PROJECT/'PROJECT_STATUS.json').read_text());assert status['software_version']==VERSION
 checks=json.loads((PROJECT/'test-results-058/combined-summary.json').read_text());assert checks['failures']==0
 syntax=json.loads((PROJECT/'test-results-058/syntax.json').read_text());assert syntax['status']=='PASS'
 for rel,digest in {**syntax['sha256'],**syntax.get('web_sha256',{})}.items():assert sha((PROJECT/rel).read_bytes())==digest,rel
 zones=PROJECT/'einkfrontend.koplugin/resources/timezones';inventory=json.loads((zones/'zones.json').read_text());assert inventory['version']=='2026e' and len(inventory['zones'])==419
 for z in inventory['zones']:assert sha((zones/z['id']).read_bytes())==z['sha256'],z['id']
 icons=PROJECT/'einkfrontend.koplugin/resources/icons/sharp';assert len(list(icons.glob('*.svg')))==33
 for f in [PROJECT/'einkfrontend.koplugin/resources/JSZIP-LICENSE.txt',PROJECT/'einkfrontend.koplugin/resources/PAKO-LICENSE.txt',zones/'LICENSE',icons/'LICENSE',PROJECT/'COPYING']:assert f.is_file()
 files={p.relative_to(PROJECT).as_posix():p.read_bytes() for p in public_paths()}
 for rel,data in files.items():
  assert not any(part in rel.split('/') for part in ['data','.env','.git']) and not rel.endswith('.log'),rel
  if rel.endswith(('.py','.lua','.md','.mjs','.html','.json','.yml')):
   text=data.decode('utf-8');assert not re.search(r'github_pat_[A-Za-z0-9_]{30,}|gh[pousr]_[A-Za-z0-9]{30,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----',text),rel
 manifest={k:sha(v) for k,v in sorted(files.items())}
 return files,manifest,checks,syntax

def writezip(path,files):
 staged=path.with_suffix('.zip.building')
 with zipfile.ZipFile(staged,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for rel,data in sorted(files.items()):
   info=zipfile.ZipInfo(rel,(2026,10,21,0,0,0));info.external_attr=0o100644<<16;info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,data)
 with zipfile.ZipFile(staged) as z:
  assert z.testzip() is None
  for rel,data in files.items():assert sha(z.read(rel))==sha(data),rel
 staged.replace(path)

def build(output):
 output=Path(output);output.mkdir(parents=True,exist_ok=True)
 files,manifest,checks,syntax=inputs()
 info={'version':VERSION,'date':'2026-10-23','source_tree_sha256':sha(json.dumps(manifest,sort_keys=True).encode()),'koreader_commit':'9192014d8bd82a91dc1012473be0f238dedfdb54','checks':checks['checks'],'distinct_cases':checks['distinct_cases'],'runs':checks['runs'],'lua_files':syntax['files'],'device':'NOT_RUN_AFTER_CHANGES','settings_more':'Settings root only; two anchored rows for global settings search and restart; no page replacement; outside dismissal and lifecycle cleanup verified','native_controls':'Inherited reversible common renderer policy; no renderer changes this iteration','inherited_features':'LAN transfer, EPUB reflow and home editor retained; older browser evidence is historical and is not counted as rerun','pagepress':'Voyage physical pressure and haptic settings still pending','home':'Fixed viewport with bounded responsive widgets','network_clock':'No NTP or RTC changed on host','tutorial':'Existing 0.5.0 tutorial retained; this update is documented separately'}
 info['plugin_updater']='Default-off automatic check/install; manual check; TLS and SHA256; verified stage; journaled pre-load activation and recovery; no forced Wi-Fi or restart; real GitHub DNS unavailable in test environment'
 info['input_method']='Persistent one-tap Chinese/English bar; preserves raw preedit on English switch; native English keys; offline host word map; external pinyin plugins take precedence; password/number/literal excluded'
 info['stock_screensaver']='Integrated into Sleep screen > Wallpaper; random_image + auto-detected local path only; exclusive wallpaper selection; display preferences preserved; legacy backups supported; physical suspend NOT_RUN'
 info['context_audit']='Shared page eligibility, stale-hit invalidation, nested Back behavior and owned dialog lifecycle checked across three layouts'
 info['inherited_features']='Only wallpaper, existing input/screensaver and settings popup suites rerun this iteration; older update, transfer, browser and core reports are historical and excluded from current count'
 encoded=lambda value:(json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()
 install={k:v for k,v in files.items() if k.startswith('einkfrontend.koplugin/')};install['einkfrontend.koplugin/COPYING']=files['COPYING']
 install['README_安装与范围.md']=files['README.md'];install['Voyage_0.4.0_实测指南.md']=files['Voyage_0.4.0_实测指南.md'];install['BUILD_INFO.json']=encoded(info)
 plugin_prefix='einkfrontend.koplugin/'
 update_manifest={'schema':1,'version':VERSION,'koreader':['v2026.07.1','v2026.07.2'],'files':{k[len(plugin_prefix):]:sha(v) for k,v in install.items() if k.startswith(plugin_prefix)}}
 install[plugin_prefix+'UPDATE_MANIFEST.json']=encoded(update_manifest)
 install['SOURCE_FILES_SHA256.json']=encoded({k:sha(v) for k,v in sorted(install.items())})
 installer=output/f'ClassicUI_{VERSION}_install.zip';writezip(installer,install)
 source=dict(files);source['PUBLIC_MANIFEST_SHA256.json']=encoded(manifest);source['BUILD_INFO.json']=encoded(info)
 archive=output/f'ClassicUI_{VERSION}_source.zip';writezip(archive,source)
 hashes={p.name:sha(p.read_bytes()) for p in [installer,archive]};(output/'SHA256SUMS.txt').write_text(''.join(v+'  '+k+'\n' for k,v in hashes.items()))
 print(json.dumps({'version':VERSION,'files':len(files),'source_tree_sha256':info['source_tree_sha256'],'assets':hashes},indent=2));return installer,archive
if __name__=='__main__':build(sys.argv[1] if len(sys.argv)>1 else PROJECT/'release-build')
