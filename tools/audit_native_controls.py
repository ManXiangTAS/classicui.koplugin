"""Inventory standard control constructors and rounded-frame candidates.

Usage: python tools/audit_native_controls.py /path/to/fixed/koreader/source
This is a static source inventory, not a runtime coverage percentage.
"""
from pathlib import Path
import csv, hashlib, json, re, subprocess, sys

project = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve()
out = project / 'docs/native-controls'
out.mkdir(parents=True, exist_ok=True)
commit = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
assert commit == '9192014d8bd82a91dc1012473be0f238dedfdb54', 'Audit the supported pinned KOReader revision'
controls = {
    'infomessage', 'notification', 'confirmbox', 'multiconfirmbox', 'inputdialog', 'multiinputdialog',
    'buttondialog', 'spinwidget', 'doublespinwidget', 'datetimewidget', 'radiobuttonwidget',
    'textviewer', 'dictquicklookup', 'openwithdialog', 'keyboardlayoutdialog', 'fontchooser',
    'frontlightwidget', 'naturallightwidget', 'skimtowidget', 'imageviewer', 'menu', 'touchmenu',
    'progressbardialog', 'button', 'buttontable', 'buttonprogresswidget', 'toggleswitch',
    'filechooser', 'bookstatuswidget', 'configdialog', 'sortwidget', 'inputtext', 'virtualkeyboard',
}
constructors, radii, primitives = [], [], []
digests = {}
for path in sorted([*(source / 'frontend').rglob('*.lua'), *(source / 'plugins').rglob('*.lua')]):
    rel = path.relative_to(source).as_posix()
    data = path.read_bytes()
    text = data.decode('utf-8')
    # Remove block comments but retain line numbers. This intentionally does not
    # execute Lua, callbacks, lazy menu providers or hardware actions.
    text = re.sub(r'--\[\[(.*?)\]\]', lambda m: '\n' * m[0].count('\n'), text, flags=re.S)
    aliases = {m[1]: m[2] for m in re.finditer(r'local\s+(\w+)\s*=\s*require\(["\']ui/widget/([^"\']+)["\']\)', text)}
    touched = False
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split('--', 1)[0]
        for match in re.finditer(r'\b(\w+):new\s*[{(]', code):
            control = aliases.get(match[1])
            if control in controls:
                constructors.append({'source': rel, 'line': number, 'control': control,
                                     'coverage': 'common_renderer', 'evidence': 'static_call_site'})
                touched = True
        match = re.search(r'\bradius\s*=(?!=)\s*(.+)', code)
        if match:
            expression = match[1].strip().rstrip(',')
            if expression not in ['0', 'nil', '{'] and not re.match(r'\s*local\s+radius\s*=', code):
                radii.append({'source': rel, 'line': number, 'expression': expression,
                              'renderer': 'progresswidget' if rel.endswith('/progresswidget.lua') else 'framecontainer',
                              'evidence': 'static_candidate; circular frames intentionally retained'})
                touched = True
        if re.search(r':paintRoundedRect(?:RGB32)?\s*\(|\bpaintRoundedRect\(bb,', code):
            primitives.append({'source': rel, 'line': number, 'code': code.strip()})
            touched = True
    if touched:
        digests[rel] = hashlib.sha256(data).hexdigest()

for name, rows in [('constructors.csv', constructors), ('rounded-frames.csv', radii)]:
    with (out / name).open('w', newline='', encoding='utf-8-sig') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader(); writer.writerows(rows)
report = {'koreader_commit': commit, 'scope': 'pinned frontend and bundled plugin Lua sources',
          'constructor_sites': len(constructors), 'constructor_files': len({r['source'] for r in constructors}),
          'rounded_candidates': len(radii), 'direct_rounded_primitives': primitives,
          'source_sha256': digests,
          'limitations': ['Static call sites are not executed tests or independent features.',
                         'Uninstalled third-party plugins and firmware windows are outside this inventory.',
                         'Common rendering does not mean the full interaction was rewritten.']}
(out / 'inventory.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print({k: v for k, v in report.items() if k not in ['source_sha256', 'limitations']})
