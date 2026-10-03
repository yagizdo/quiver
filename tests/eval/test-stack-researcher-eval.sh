#!/usr/bin/env bash
# Exercise the stack-researcher eval harness with fake claude, npm and adb
# executables; never call the API or the registry.
set -euo pipefail

python3 - "$(cd "$(dirname "$0")" && pwd)/run-stack-researcher-eval.sh" <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

runner = sys.argv.pop()
repo_root = os.path.realpath(os.path.join(os.path.dirname(runner), "..", ".."))
bash = shutil.which("bash")

PEER_RANGE = ">=4.8.4 <6.1.0"

GOOD_REPORT = """### Q1 -- answered
Answer: Call execFile('adb', ['exec-out', 'screencap', '-p'], { encoding: 'buffer', maxBuffer: 64 * 1024 * 1024 }); the default maxBuffer of 1024 * 1024 bytes terminates the child once a screenshot is larger.
- documented | https://nodejs.org/docs/latest-v22.x/api/child_process.html | v22 | "maxBuffer <number> Largest amount of data in bytes allowed on stdout or stderr. Default: 1024 * 1024."

### Q2 -- narrowed
Answer: typescript-eslint does not support TypeScript 7; its latest release declares a typescript peer range of >=4.8.4 <6.1.0.
- measured | npm view typescript-eslint@latest peerDependencies | macOS, npm 11 | "{ typescript: '>=4.8.4 <6.1.0' }"
Options: oxlint
Recommended: oxlint, because typescript-eslint excludes TypeScript 7.

### Q3 -- needs-measurement
Answer: The inset line format is decided by the device build, and no device is attached.
Measure: adb shell dumpsys window displays on an API 36 emulator; the inset lines settle it.

## Gaps
- none

## Sources
- https://nodejs.org/docs/latest-v22.x/api/child_process.html -- v22
"""

# Each defect below is aimed at one check. The 1 MiB check is baited with
# products that contain "1024 * 1024" without being 1 MiB, one of them
# parenthesized, and with a "1 MiB" outside the Q1 block, which must not count
# for Q1.
FLAWED_REPORT = """### Q1 -- answered
Answer: Call execFile('adb', ['exec-out', 'screencap', '-p'], { maxBuffer: 64 * 1024 * 1024 }) and read stdout; a 1024 * 1024 * 64 limit holds about 51 MB, the same as 64 * (1024 * 1024).
- documented | https://nodejs.org/docs/latest-v22.x/api/child_process.html | v22 | "maxBuffer <number> Largest amount of data in bytes allowed on stdout or stderr."

### Q2 -- partially answered
Answer: typescript-eslint supports TypeScript up to 6.0, and its docs say 1 MiB files lint fine.
- documented | https://typescript-eslint.io/users/dependency-versions | v8 | "typescript >=4.8.4 <6.0.0"

### Q3 -- answered
Answer: Each inset line reads mInsets=[0,0][0,0].
- documented | https://source.android.com/ | API 36 | "mInsets="

## Gaps
- none

## Sources
- none
"""

FAKE_CLAUDE = r'''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["CALL_LOG"], "a") as f:
    f.write(json.dumps({"argv": sys.argv[1:], "cwd": os.getcwd(),
                        "entries": sorted(os.listdir("."))}) + "\n")
mode = os.environ["REPORT_MODE"]
if mode == "dirty":
    open("scratch.txt", "w").write("written by the run\n")
report = "" if mode == "empty" else open(os.environ["REPORT_FILE"]).read()
print(json.dumps({"type": "result", "subtype": "success", "result": report,
                  "num_turns": 7, "duration_ms": 71234, "total_cost_usd": 0.4213}))
'''

FAKE_NPM = '''#!/usr/bin/env bash
case "$*" in
  "view typescript-eslint@latest peerDependencies.typescript") echo '>=4.8.4 <6.1.0' ;;
  "view typescript dist-tags.latest") echo '7.0.2' ;;
  *) echo "unexpected npm call: $*" >&2; exit 1 ;;
esac
'''

FAKE_ADB = '''#!/usr/bin/env bash
[ "$1" = devices ] || exit 1
echo "List of devices attached"
if [ "${ADB_DEVICE:-}" = 1 ]; then
  printf 'emulator-5554\\tdevice\\n'
fi
echo
'''


def write_exe(path, text):
    path.write_text(text)
    path.chmod(0o755)


class StackResearcherEvalTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(os.path.realpath(self._tmp.name))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        write_exe(self.bin / "claude", FAKE_CLAUDE)
        write_exe(self.bin / "npm", FAKE_NPM)
        write_exe(self.bin / "adb", FAKE_ADB)
        self.calls = self.root / "calls"
        self.report = self.root / "report.md"

    def tearDown(self):
        self._tmp.cleanup()

    def run_harness(self, report=None, mode="report", path=None, extra=None):
        if report is not None:
            self.report.write_text(report)
        env = dict(os.environ,
                   PATH=path or (str(self.bin) + os.pathsep + os.environ["PATH"]),
                   TMPDIR=str(self.root), CALL_LOG=str(self.calls),
                   REPORT_MODE=mode, REPORT_FILE=str(self.report))
        env.update(extra or {})
        run = subprocess.run([bash, runner], cwd=str(self.root), env=env,
                             text=True, capture_output=True)
        # macOS mktemp -d ignores TMPDIR, so a workspace the harness keeps on
        # failure lands in the system temp dir. Remove it once the test is done.
        for kept in re.findall(r"^Workspace kept(?: for inspection)?: (\S+)$", run.stdout, re.M):
            self.addCleanup(shutil.rmtree, kept, True)
        return run

    def row(self, out, result, check):
        return re.search(r"^%s +%s" % (result, re.escape(check)), out, re.M)

    def test_clean_report_passes_every_check(self):
        run = self.run_harness(GOOD_REPORT)
        out = run.stdout + run.stderr
        self.assertEqual(run.returncode, 0, out)
        self.assertIn("Score: 10 passed, 0 failed", out)
        self.assertIn("Cost: 7 turns, 71.2s, $0.4213", out)
        self.assertNotRegex(out, re.compile(r"^FAIL ", re.M))
        calls = [json.loads(l) for l in self.calls.read_text().splitlines()]
        self.assertEqual(len(calls), 1, out)
        call = calls[0]
        argv = call["argv"]
        self.assertEqual(argv[0], "-p")
        prompt = argv[1]
        self.assertIn('subagent_type="quiver:stack-researcher"', prompt)
        self.assertIn("Project root: %s (empty)" % call["cwd"], prompt)
        # Backticks reach the model as text, not as command substitution.
        self.assertIn("1. How should the CLI read the PNG that `adb exec-out screencap -p` writes", prompt)
        self.assertIn("3. What is the exact format of the inset lines `adb shell dumpsys window displays` prints on Android API 36?", prompt)
        self.assertIn("- no runtime dependencies beyond the Node standard library", prompt)
        self.assertEqual(argv[argv.index("--plugin-dir") + 1], repo_root)
        self.assertEqual(argv[argv.index("--max-budget-usd") + 1], "5")
        # The agent reads open-web pages, so nothing outside this list may run
        # unprompted: no curl or gh, which can send a local file or call a
        # write API, and never bypassPermissions. User settings stay unloaded,
        # since dontAsk also runs whatever their allow rules permit.
        self.assertEqual(argv[argv.index("--setting-sources") + 1], "project,local")
        self.assertEqual(argv[argv.index("--permission-mode") + 1], "dontAsk")
        self.assertNotIn("bypassPermissions", argv)
        self.assertEqual(argv[argv.index("--allowedTools") + 1:argv.index("--output-format")],
                         ["Agent", "WebSearch", "WebFetch", "mcp__plugin_quiver_context7",
                          "Bash(npm view *)"])
        self.assertEqual(argv[argv.index("--output-format") + 1], "json")
        self.assertEqual(call["entries"], [], "project root was not empty when the run started")
        self.assertEqual(os.path.basename(call["cwd"]), "project", call["cwd"])
        self.assertFalse(os.path.exists(os.path.dirname(call["cwd"])),
                         "a passing run left its workspace behind")

    def test_flawed_report_fails_the_checks_it_breaks(self):
        run = self.run_harness(FLAWED_REPORT, mode="dirty")
        out = run.stdout + run.stderr
        self.assertEqual(run.returncode, 1, out)
        for check in ("Q2 heading uses a listed status",
                      "Q1 states the 1 MiB default",
                      "Q1 sets encoding to buffer",
                      "Q2 quotes the live peer range",
                      "Q3 status is needs-measurement",
                      "Project root is still empty"):
            self.assertTrue(self.row(out, "FAIL", check), check + "\n" + out)
        for check in ("Q1 heading uses a listed status",
                      "Q3 heading uses a listed status",
                      "Q1 names maxBuffer",
                      "Q1 uses exec-out"):
            self.assertTrue(self.row(out, "PASS", check), check + "\n" + out)
        self.assertIn("Score: 4 passed, 6 failed", out)
        self.assertIn("Cost: 7 turns, 71.2s, $0.4213", out)
        self.assertIn("Workspace kept for inspection: ", out)

    def test_empty_result_is_reported_as_blocked(self):
        run = self.run_harness(mode="empty")
        out = run.stdout + run.stderr
        self.assertEqual(run.returncode, 1, out)
        self.assertIn("HARNESS BLOCKED", out)
        self.assertIn("Cost: 7 turns, 71.2s, $0.4213", out)
        kept = Path(out.split("Workspace kept for inspection: ")[1].split()[0])
        self.assertEqual(json.loads((kept / "run.json").read_text())["num_turns"], 7)

    def test_attached_device_refuses_before_the_run(self):
        run = self.run_harness(GOOD_REPORT, extra={"ADB_DEVICE": "1"})
        out = run.stdout + run.stderr
        self.assertEqual(run.returncode, 1, out)
        self.assertIn("ABORT", out)
        self.assertIn("emulator-5554", out)
        self.assertFalse(self.calls.exists(), "claude ran with a device attached")

    def test_missing_npm_refuses_before_the_run(self):
        (self.bin / "npm").unlink()
        dirs = [d for d in os.environ["PATH"].split(os.pathsep)
                if d and not os.access(os.path.join(d, "npm"), os.X_OK)]
        path = os.pathsep.join([str(self.bin)] + dirs)
        for tool in ("awk", "dirname"):
            if shutil.which(tool, path=path) is None:
                self.skipTest("%s shares a directory with npm on this machine" % tool)
        run = self.run_harness(GOOD_REPORT, path=path)
        out = run.stdout + run.stderr
        self.assertEqual(run.returncode, 1, out)
        self.assertIn("ABORT: npm is not on PATH", out)
        self.assertFalse(self.calls.exists(), "claude ran without npm")


unittest.main()
PY
