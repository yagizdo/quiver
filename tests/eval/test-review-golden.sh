#!/usr/bin/env bash
# Exercise the real harness with a fake Claude executable; never call the API.
set -euo pipefail

python3 - "$(cd "$(dirname "$0")" && pwd)/run-review-golden.sh" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

runner = sys.argv.pop()

FINDINGS = """## Findings
[M1] [MEDIUM] (logic-reviewer) app/pricing.py -- bulk_discount boundary
[H1] [HIGH] (project-context-analyst) app/backup.py -- export_snapshot shell injection
[M2] [MEDIUM] (waste-detector) app/report.py -- chunk_list duplicates helper
"""
FILTERED = """## Filtered Findings
average_price app/tiers.py tier_labels app/checksum.py rotate_checksum
"""
REFUTED = """- [L1] refuted-by-verification -- README.md:5 -- sentence is unnecessary -- DECISIONS.md:4: "the kiosk build greps for this line"
- [M3] refuted-by-verification -- app/ledger.py:9 -- pack_records size comment is wrong -- `python3 tools/measure_ledger.py` -> exit 0: 600000 bytes
"""

REPORTS = {
    # Both new baits caught by verification and moved to Filtered.
    "refuted": FINDINGS + FILTERED + REFUTED,
    # Both new baits never raised at all.
    "absent": FINDINGS + FILTERED,
    # The README bait survives into Findings: the absent-form expectation fails.
    "reported": FINDINGS + "[L1] [LOW] (waste-detector) README.md -- sentence is unnecessary\n" + FILTERED,
    "missing": "",
}


class ReviewGoldenTest(unittest.TestCase):
    def test_grading_and_missing_report(self):
        for mode, body in REPORTS.items():
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                claude = root / "claude"
                claude.write_text('''#!/usr/bin/env bash
set -eu
[ "$1" = "-p" ]
[ "$2" = "/quiver:review --base main --run-checks --output ./review-out" ]
echo called >> "$CALL_LOG"
if [ -n "$REPORT_BODY" ]; then
  mkdir -p review-out
  printf '%s' "$REPORT_BODY" > review-out/review-mock.md
fi
echo '{"type":"result","result":"original evidence","total_cost_usd":0}'
''')
                claude.chmod(0o755)
                calls = root / "calls"
                env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"],
                           TMPDIR=tmp, CALL_LOG=str(calls), REPORT_BODY=body)
                run = subprocess.run(["bash", runner], cwd=tmp, env=env,
                                     text=True, capture_output=True)
                out = run.stdout + run.stderr
                if mode == "refuted":
                    self.assertEqual(run.returncode, 0, out)
                    self.assertIn("Score: 15 passed, 0 failed", run.stdout)
                    self.assertEqual(run.stdout.count("not reported; refuted by verification"), 3, out)
                elif mode == "absent":
                    self.assertEqual(run.returncode, 0, out)
                    self.assertIn("Score: 15 passed, 0 failed", run.stdout)
                    self.assertEqual(run.stdout.count("not reported; no refuted-by-verification line"), 3, out)
                elif mode == "reported":
                    self.assertEqual(run.returncode, 1, out)
                    self.assertIn("Score: 14 passed, 1 failed", run.stdout)
                    self.assertRegex(run.stdout, r"FAIL\s+~ README\s+false positive: ")
                else:
                    self.assertEqual(run.returncode, 1, out)
                    self.assertIn("HARNESS BLOCKED", run.stdout)
                    kept = Path(run.stdout.split("Workspace kept for inspection: ")[1].strip())
                    self.assertEqual(json.loads((kept / "run.json").read_text())["result"],
                                     "original evidence")
                    self.assertIn("original evidence", (kept / "run.jsonl").read_text())
                self.assertEqual(calls.read_text().splitlines(), ["called"], run.stdout)


unittest.main()
PY
