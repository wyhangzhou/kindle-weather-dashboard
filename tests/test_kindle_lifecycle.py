"""Regressions from the first real 30-minute Kindle trial; no device required."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

BASE = Path(__file__).resolve().parents[1]


class KindleLifecycleTests(unittest.TestCase):
    def test_paint_waits_for_clear_and_image_to_finish_on_the_panel(self):
        source = (BASE / "kindle/dashboard/run.sh").read_text()
        definitions = source.split('if [ "$MODE" = --check ]', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "panel-probe.sh"
            script.write_text(definitions + r'''
PENDING=old-frame
display_sync() { printf 'wait\n'; PENDING=''; }
run_eips() {
    [ -z "$PENDING" ] || exit 9
    printf 'draw %s\n' "$*"
    PENDING=$*
}
paint_weather /weather.png || exit 1
[ -z "$PENDING" ] || exit 2
''')
            result = subprocess.run(["/bin/sh", str(script)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(),
                             ["wait", "draw -f -c", "wait", "draw -f -g /weather.png", "wait"])

    def test_failed_panel_wait_stops_the_next_display_command(self):
        source = (BASE / "kindle/dashboard/run.sh").read_text()
        definitions = source.split('if [ "$MODE" = --check ]', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "panel-failure.sh"
            script.write_text(definitions + r'''
N=0
display_sync() { N=$((N+1)); printf 'wait=%s\n' "$N"; [ "$N" != 2 ]; }
run_eips() { printf 'draw %s\n' "$*"; }
if paint_weather /weather.png; then exit 1; fi
''')
            result = subprocess.run(["/bin/sh", str(script)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ["wait=1", "draw -f -c", "wait=2"])

    def test_same_image_covers_native_status_bar_after_each_radio_change(self):
        source = (BASE / "kindle/dashboard/run.sh").read_text()
        definitions = source.split('if [ "$MODE" = --check ]', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "display-probe.sh"
            script.write_text(definitions + r'''
WIFI=1
FRAME=status-bar
set_prop() { WIFI=$3; FRAME=status-bar; printf 'wifi=%s\n' "$WIFI"; }
get_prop() { printf '%s\n' "$WIFI"; }
sleep() { printf 'settle=%s\n' "$1"; }
paint_weather() {
    [ "$WIFI" = 0 ] || return 1
    FRAME=weather
    printf 'paint=%s\n' "$1"
}
prepare_display /same-cached-weather.png || exit 1
[ "$FRAME" = weather ] || exit 1
# A new wake/network cycle redraws native chrome even if the image is unchanged.
WIFI=1; FRAME=status-bar
prepare_display /same-cached-weather.png || exit 1
[ "$FRAME" = weather ] || exit 1
''')
            result = subprocess.run(["/bin/sh", str(script)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(),
                             ["wifi=0", "settle=2", "paint=/same-cached-weather.png"] * 2)

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
