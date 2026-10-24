"""Check distributable contents and deterministic builds on the current platform."""
from pathlib import Path
import contextlib, hashlib, importlib.util, io, json, tempfile, unittest, zipfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("classicui_build_under_test",ROOT/"tests/build_public_release.py")
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
class BuildIntegrity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory();cls.out=Path(cls.tmp.name)
        with contextlib.redirect_stdout(io.StringIO()): cls.paths=builder.build(cls.out)
    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()
    def test_installer_contains_startup_and_all_plugin_source(self):
        with zipfile.ZipFile(self.paths[0]) as z:
            names=set(z.namelist())
            self.assertIn("einkfrontend.koplugin/main.lua",names)
            self.assertIn("einkfrontend.koplugin/einkfrontend/transferweb.lua",names)
            expected={p.relative_to(ROOT).as_posix() for p in (ROOT/"einkfrontend.koplugin").rglob("*") if p.is_file()}
            self.assertTrue(expected<=names,sorted(expected-names))
    def test_all_archive_names_are_portable_and_relative(self):
        for archive in self.paths:
            with zipfile.ZipFile(archive) as z:
                for info in z.infolist(): self.assertEqual(info.create_system,3)
                for name in z.namelist():
                    self.assertNotIn("\\",name)
                    self.assertFalse(name.startswith("/"))
                    self.assertNotIn("..",name.split("/"))
    def test_internal_manifests_cover_every_payload_exactly(self):
        for archive in self.paths:
            with zipfile.ZipFile(archive) as z:
                self.assertIsNone(z.testzip())
                manifest=json.loads(z.read("SHA256.json"))
                self.assertEqual(set(manifest),set(z.namelist())-{"SHA256.json"})
                for name,sha in manifest.items(): self.assertEqual(hashlib.sha256(z.read(name)).hexdigest(),sha)
    def test_source_omits_private_build_outputs_and_media_binaries(self):
        with zipfile.ZipFile(self.paths[1]) as z:
            for name in z.namelist():
                self.assertFalse(any(p in name.split("/") for p in [".git","node_modules","__pycache__","test-results"]))
                self.assertFalse(name.endswith((".log",".mp4",".wav",".pyc")))
            self.assertIn("tests/test_light_policy.lua",z.namelist())
    def test_build_is_reproducible_and_version_consistent(self):
        self.assertNotIn(b'\r\n',(self.out/'SHA256SUMS.txt').read_bytes())
        before=[p.read_bytes() for p in self.paths]
        with contextlib.redirect_stdout(io.StringIO()): builder.build(self.out)
        self.assertEqual(before,[p.read_bytes() for p in self.paths])
        with zipfile.ZipFile(self.paths[0]) as z:
            self.assertEqual(json.loads(z.read("BUILD_INFO.json"))["version"],builder.VERSION)
            self.assertIn(builder.VERSION,z.read("einkfrontend.koplugin/_meta.lua").decode("utf-8"))
if __name__=="__main__": unittest.main()
