"""Run local checks without network, user settings, or real book libraries."""
from pathlib import Path
import hashlib, importlib.util, json, os, py_compile, subprocess, sys, tempfile, unittest

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"test-results"/"local"
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    scratch=(OUT/"_tmp").resolve()
    assert scratch.is_relative_to(ROOT.resolve())
    scratch.mkdir(exist_ok=True)
    tempfile.tempdir=str(scratch)
    loader=unittest.TestLoader()
    suites=unittest.TestSuite([loader.discover(str(ROOT/"tests"),pattern=name) for name in ("test_release_policy.py","test_build_integrity.py")])
    result=unittest.TextTestRunner(verbosity=2).run(suites)
    python={"suite":"python-release-build","total":result.testsRun,"failed":len(result.errors)+len(result.failures),"skipped":len(result.skipped)}
    (OUT/"python-summary.json").write_text(json.dumps(python,indent=2)+"\n",encoding="utf-8")
    if not result.wasSuccessful(): return 1
    compiled=[]
    for folder in (ROOT/"tests",ROOT/"tools"):
        for file in folder.glob("*.py"):
            py_compile.compile(str(file),doraise=True);compiled.append(file.relative_to(ROOT).as_posix())
    for args in (["node",str(ROOT/"tests/run_portable_audit.cjs"),str(ROOT),"audit"],
                 ["node",str(ROOT/"tests/run_portable_audit.cjs"),str(ROOT),"policy"],
                 ["node",str(ROOT/"tests/run_portable_audit.cjs"),str(ROOT),"response"],
                 ["node",str(ROOT/"tests/run_portable_audit.cjs"),str(ROOT),"upgrade"],
                 ["node",str(ROOT/"tests/test_web_logic.cjs"),str(ROOT)]):
        proc=subprocess.run(args,cwd=ROOT,timeout=90)
        if proc.returncode: return proc.returncode
    reports=[python]
    for file in (ROOT/"test-results/portable/audit-summary.json",ROOT/"test-results/portable/policy-summary.json",ROOT/"test-results/web-logic/summary.json",ROOT/"test-results/portable/response-summary.json",ROOT/"test-results/portable/upgrade-summary.json"):
        reports.append(json.loads(file.read_text(encoding="utf-8")))
    summary={"version":(ROOT/"einkfrontend.koplugin/einkfrontend/version.lua").read_text(encoding="utf-8").split("'")[1],
             "total":sum(x["total"] for x in reports),"failed":sum(x["failed"] for x in reports),"suites":reports,
             "lua_syntax_files":reports[1]["syntax_files"],"python_syntax_files":len(compiled),
             "physical_device":"NOT_RUN","koreader_linux_emulator":"NOT_RUN","actual_browser":"NOT_RUN",
             "lua_runtime":"Fengari Lua 5.3; not LuaJIT","network":"NONE (mocked APIs only)"}
    summary['tested_inputs_sha256']={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for folder in ('einkfrontend.koplugin','tests','tools') for p in (ROOT/folder).rglob('*') if p.is_file() and not any(x in p.parts for x in ('node_modules','__pycache__')) and p.suffix in ('.lua','.py','.cjs','.mjs','.json','.html')}
    (OUT/"combined-summary.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in summary.items() if k not in ("suites","tested_inputs_sha256")},ensure_ascii=False,indent=2))
    return 0
if __name__=="__main__": raise SystemExit(main())
