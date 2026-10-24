"""Verify that repository text and bytes match the reviewed source before release."""
from pathlib import Path
import hashlib, json

root = Path(__file__).resolve().parents[1]
expected = json.loads((root / "tests/release-source-sha256.json").read_text(encoding="utf-8"))
for name, digest in expected.items():
    data = (root / name).read_bytes()
    assert hashlib.sha256(data).hexdigest() == digest, "Source bytes changed: " + name
    if Path(name).suffix in {".lua", ".md", ".py", ".html", ".json", ".yml", ".cjs", ".mjs"}:
        text = data.decode("utf-8")
        assert "\ufffd" not in text, "Replacement character: " + name
meta = (root / "einkfrontend.koplugin/_meta.lua").read_text(encoding="utf-8")
assert "\u58a8\u9875" in meta
print("Verified exact source hashes and UTF-8: " + str(len(expected)) + " files")
