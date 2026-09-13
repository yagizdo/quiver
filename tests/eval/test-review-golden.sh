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


class ReviewGoldenTest(unittest.TestCase):
    def test_grading_and_missing_report(self):
        for mode in ("report", "missing"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                claude = root / "claude"
                claude.write_text('''#!/usr/bin/env bash
set -eu
[ "$1" = "-p" ]
[ "$2" = "/quiver:review --base main --output ./review-out" ]
echo called >> "$CALL_LOG"
if [ "$REPORT_MODE" = report ]; then
  mkdir -p review-out
  cat > review-out/review-mock.md <<'REPORT'
## Findings
[M1] [MEDIUM] (logic-reviewer) app/pricing.py -- bulk_discount boundary
[H1] [HIGH] (project-context-analyst) app/backup.py -- export_snapshot shell injection
[M2] [MEDIUM] (waste-detector) app/report.py -- chunk_list duplicates helper
## Filtered Findings
average_price app/tiers.py tier_labels app/checksum.py rotate_checksum
REPORT
fi
echo '{"type":"result","result":"original evidence","total_cost_usd":0}'
''')
                claude.chmod(0o755)
                calls = root / "calls"
                env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"],
                           TMPDIR=tmp, CALL_LOG=str(calls), REPORT_MODE=mode)
                run = subprocess.run(["bash", runner], cwd=tmp, env=env,
                                     text=True, capture_output=True)
                if mode == "report":
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                    self.assertIn("Score: 12 passed, 0 failed", run.stdout)
                else:
                    self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
                    self.assertIn("HARNESS BLOCKED", run.stdout)
                    kept = Path(run.stdout.split("Workspace kept for inspection: ")[1].strip())
                    self.assertEqual(json.loads((kept / "run.json").read_text())["result"],
                                     "original evidence")
                    self.assertIn("original evidence", (kept / "run.jsonl").read_text())
                self.assertEqual(calls.read_text().splitlines(), ["called"], run.stdout)


unittest.main()
PY
