from pathlib import Path
import gzip,hashlib
b=Path('.bootstrap')
data=gzip.decompress(b''.join(p.read_bytes() for p in sorted(b.glob('guide-*.part'))))
assert hashlib.sha256(data).hexdigest()=='a259b0b4eda977164e12985649e8be315116b824404f97ff589e174c27251b36'
for name in ['docs/墨页安装与使用教程.html','einkfrontend.koplugin/resources/guide.html']:
 Path(name).write_bytes(data)
Path('.github/workflows/test-release.yml').write_bytes((b/'original-workflow.yml').read_bytes())
for p in list(b.iterdir()):p.unlink()
b.rmdir()
