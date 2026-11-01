"""Regressions from the first real 30-minute Kindle trial; no device required."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

BASE = Path(__file__).resolve().parents[1]


class KindleLifecycleTests(unittest.TestCase):
    def test_long_running_actions_close_the_kindlet(self):
        menu = json.loads((BASE / "kindle/dashboard/menu.json").read_text())

        def actions(node):
            for item in node.get("items", []):
                yield item
                yield from actions(item)

        starts = [item for item in actions(menu) if item.get("action") == "./start.sh"]
        self.assertEqual(len(starts), 2)
        self.assertTrue(all(item.get("exitmenu", True) is True for item in starts),
                        "An active Kindlet times out after a long kernel suspend")

    def test_restarted_framework_fails_trial_but_releases_restored_state(self):
        source = (BASE / "kindle/dashboard/run.sh").read_text()
        # Exercise the real restoration/cleanup functions with only native I/O
        # boundaries replaced. Never execute the startup or suspend code.
        definitions = source.split('if [ "$MODE" = --check ]', 1)[0]
        cleanup = source.split("cleanup() {", 1)[1].split("\ntrap cleanup 0", 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "lib").mkdir()
            alarm = root / "lib/alarm.sh"
            alarm.write_text("#!/bin/sh\nexit 0\n")
            alarm.chmod(0o755)
            script = root / "probe.sh"
            script.write_text(definitions + r'''
ROOT=$(dirname "$0")
LIB=$ROOT/lib
LOCK=$ROOT/lock
STATE=$ROOT/props
TOKEN=$ROOT/no-alarm-token
LOG=$ROOT/events
mkdir "$LOCK"
printf 'saved state\n' > "$STATE"
P=0; W=1; F=1; C=10
BOOT=00000000-0000-0000-0000-000000000000
WATCH=''; JOB=''; RESULT=trial-complete
get_prop() {
    case "$2" in state) printf 'active\n' ;; preventScreenSaver) printf '0\n' ;; *) printf '1\n' ;; esac
}
set_prop() { return 0; }
pidof() { printf '20\n'; }
cat() {
    case "$1" in /proc/sys/kernel/random/boot_id) printf '%s\n' "$BOOT" ;; *) /bin/cat "$@" ;; esac
}
home() { printf 'home\n' >> "$LOG"; }
sync() { :; }
''' + "\ncleanup() {" + cleanup + "\ntrue\ncleanup\n")
            result = subprocess.run(["/bin/sh", str(script)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertFalse((root / "props").exists(), "Successful restoration must release its journal")
            log = (root / "events").read_text()
            self.assertIn("FRAMEWORK_PID_CHANGED expected=10 actual=20", log)
            self.assertIn("END result=trial-complete rc=1", log)


if __name__ == "__main__":
    unittest.main()
