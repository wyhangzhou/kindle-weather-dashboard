#!/bin/sh
# A bounded early-wake/exit test. One 120-second alarm, no automatic repeats.
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
umask 077
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
ROOT=/mnt/us/kindle-weather
LOCK=/tmp/kindle-weather-exit-test
TOKEN=$ROOT/state/alarm-exit-test
get_prop() { lipc-get-prop "$1" "$2" 2>/dev/null; }
set_prop() { lipc-set-prop -i "$1" "$2" "$3"; }
home() { printf 'send 102\n' > /proc/keypad; }
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }
check() {
    for lock in "$LOCK" /tmp/kindle-weather-run-test /tmp/kindle-weather-wake-test; do [ ! -d "$lock" ] || return 1; done
    [ ! -e "$TOKEN" ] && [ -x "$DIR/alarm.sh" ] && [ -s "$DIR/exit-prepare.png" ] || return 1
    [ -x /usr/sbin/eips ] && [ -x /usr/bin/waitforkey ] && [ -w /proc/keypad ] && [ -w /sys/power/state ] || return 1
    [ "$(get_prop com.lab126.powerd state)" = active ] && [ -n "$(pidof cvm)" ] || return 1
    for v in "$(get_prop com.lab126.powerd preventScreenSaver)" "$(get_prop com.lab126.cmd wirelessEnable)" "$(get_prop com.lab126.wifid enable)"; do
        case "$v" in 0|1) ;; *) return 1 ;; esac
    done
    battery=$(get_prop com.lab126.powerd battLevel)
    case "$battery" in ''|*[!0-9]*) return 1 ;; esac
    [ "$battery" -ge 20 ] || return 1
    "$DIR/alarm.sh" --check || return 1
    "$DIR/fetch.sh" --current >/dev/null || return 1
    printf 'Early-exit test prerequisites passed; no settings changed.\n'
}
MODE=${1:---check}
[ "$MODE" != --check ] || { check; exit; }
case "$MODE" in --run|--self-check) ;; *) exit 2 ;; esac
check || exit 1
mkdir "$LOCK" || exit 1
printf '%s\n' "$$" > "$LOCK/pid"
mkdir -p "$ROOT/tests" "$ROOT/state" || exit 1
LOG="$ROOT/tests/exit-test.$(date -u +%Y%m%dT%H%M%S).$$.log"
printf '%s\n' "$LOG" > "$ROOT/tests/last-exit-test.txt"
P=$(get_prop com.lab126.powerd preventScreenSaver)
W=$(get_prop com.lab126.cmd wirelessEnable)
F=$(get_prop com.lab126.wifid enable)
C=$(pidof cvm)
IRQ_MASK=$(pmic sread 4)
WATCH=''; SAVED=0; RESULT=not-started
cleanup() {
    rc=$?
    trap - 0
    trap '' 1 2 15
    printf 'stop\n' > "$LOCK/key-stop"
    if [ -n "$WATCH" ]; then kill "$WATCH" 2>/dev/null || true; wait "$WATCH" 2>/dev/null || true; fi
    started=$(date -u +%s)
    if [ "$SAVED" = 1 ]; then
        if "$DIR/alarm.sh" --restore "$TOKEN" >> "$LOG" 2>&1; then
            log "ALARM_RESTORED elapsed=$(($(date -u +%s)-started))"
            rm -f "$TOKEN"
        else
            log 'ALARM_RESTORE_FAILED saved ownership retained for inspection'
            rc=1
        fi
    fi
    if [ "$(get_prop com.lab126.cmd wirelessEnable)" != "$W" ]; then set_prop com.lab126.cmd wirelessEnable "$W" || rc=1; fi
    set_prop com.lab126.wifid enable "$F" || rc=1
    set_prop com.lab126.powerd preventScreenSaver "$P" || rc=1
    if [ "$(get_prop com.lab126.powerd state)" != active ]; then
        set_prop com.lab126.powerd wakeUp 1 || rc=1
        sleep 1
    fi
    home || rc=1
    p=$(get_prop com.lab126.powerd preventScreenSaver)
    w=$(get_prop com.lab126.cmd wirelessEnable)
    f=$(get_prop com.lab126.wifid enable)
    c=$(pidof cvm)
    s=$(get_prop com.lab126.powerd state)
    log "RESTORE prevent=$p wireless=$w wifi=$f cvm=$c state=$s"
    log "IRQ_MASK before=$IRQ_MASK after=$(pmic sread 4)"
    [ "$p" = "$P" ] && [ "$w" = "$W" ] && [ "$f" = "$F" ] && [ "$c" = "$C" ] && [ "$s" = active ] || rc=1
    "$DIR/alarm.sh" --status >> "$LOG" 2>&1 || rc=1
    if [ -r "$LOCK/stop-reason" ]; then log "STOP reason=$(cat "$LOCK/stop-reason")"; fi
    log "END result=$RESULT rc=$rc"
    rm -f "$LOCK/pid" "$LOCK/key-stop" "$LOCK/key-ready" "$LOCK/key-event" "$LOCK/stop-reason"
    rmdir "$LOCK" 2>/dev/null || true
    sync
    exit "$rc"
}
trap cleanup 0
trap 'RESULT=cancelled; exit 0' 1 2 15
log "START mode=$MODE alarm=120 prevent=$P wireless=$W wifi=$F cvm=$C"
"$DIR/alarm.sh" --save "$TOKEN" || exit 1
SAVED=1
set_prop com.lab126.powerd preventScreenSaver 1 || exit 1
"$DIR/keywatch.sh" "$$" "$LOCK" "$LOG" </dev/null >/dev/null 2>&1 &
WATCH=$!
n=0
while [ ! -r "$LOCK/key-ready" ] && [ "$n" -lt 3 ]; do
    kill -0 "$WATCH" 2>/dev/null || exit 1
    sleep 1; n=$((n+1))
done
[ -r "$LOCK/key-ready" ] || exit 1
sleep 2
if [ "$MODE" = --self-check ]; then
    home
    sleep 3
    RESULT=home-listener-failed
    exit 1
fi
/usr/sbin/eips -f -g "$DIR/exit-prepare.png" || exit 1
n=0
while [ "$(get_prop com.lab126.powerd isCharging)" = 1 ] && [ "$n" -lt 15 ]; do sleep 1; n=$((n+1)); done
[ "$(get_prop com.lab126.powerd isCharging)" = 0 ] || { RESULT=usb-still-connected; exit 0; }
image=$("$DIR/fetch.sh" --current) || exit 1
/usr/sbin/eips -f -g "$image" || exit 1
set_prop com.lab126.wifid enable 0 || exit 1
sleep 2
[ "$(get_prop com.lab126.wifid enable)" = 0 ] || exit 1
kill -0 "$WATCH" 2>/dev/null || exit 1
[ ! -r "$LOCK/stop-reason" ] || { RESULT=cancelled; exit 0; }
"$DIR/alarm.sh" --arm 120 "$TOKEN" || exit 1
log "SUSPEND alarm_counter=$(cat "$TOKEN.owned") wifi=0"
before=$(date -u +%s)
printf 'mem\n' > /sys/power/state
suspend_rc=$?
elapsed=$(($(date -u +%s)-before))
log "RESUME elapsed=$elapsed suspend_rc=$suspend_rc"
[ "$suspend_rc" = 0 ] || exit 1
if [ "$elapsed" -lt 110 ]; then RESULT=early-wake; else RESULT=alarm-expired; fi
# Give the user a short opportunity to press Home after the power-button wake.
sleep 5
