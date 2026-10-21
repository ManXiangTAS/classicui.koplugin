#!/usr/bin/env python3
"""Import the reviewed public snapshot once; preserve the existing workflow."""
from pathlib import Path
import hashlib,json,shutil,zipfile
root=Path(__file__).resolve().parents[1];folder=root/'.bootstrap';archive=folder/'source.zip'
expected=(folder/'SHA256SUMS.txt').read_text().split()[0]
assert hashlib.sha256(archive.read_bytes()).hexdigest()==expected,'Snapshot archive hash differs'
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None;manifest=json.loads(z.read('PUBLIC_MANIFEST_SHA256.json'))
 files={}
 for name,digest in manifest.items():
  destination=(root/name).resolve();assert destination.is_relative_to(root) and '.git' not in destination.relative_to(root).parts
  data=z.read(name);assert hashlib.sha256(data).hexdigest()==digest,name
  if name.startswith('.github/'):
   assert destination.read_bytes()==data,'Workflow differs; refusing to modify workflow during import'
  files[destination]=data
 for destination,data in files.items():destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(data)
shutil.rmtree(folder)
print('Imported',len(files),'verified public files; temporary archive removed')
