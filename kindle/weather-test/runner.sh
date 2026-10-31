#!/bin/sh
# Exactly two downloads/displays separated by one 30-second suspend.
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
umask 077
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
ROOT=/mnt/us/kindle-weather
LOCK=/tmp/kindle-weather-run-test
RTC=/sys/devices/platform/mxc_rtc.0/wakeup_enable
get_prop() { lipc-get-prop "$1" "$2" 2>/dev/null; }
set_prop() { lipc-set-prop "$1" "$2" "$3"; }
home() { printf 'send 102\n' > /proc/keypad; }
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }
check() {
    [ ! -d "$LOCK" ] && [ ! -d /tmp/kindle-weather-wake-test ] || return 1
    [ -w "$RTC" ] && [ "$(cat "$RTC")" = 0 ] && [ -w /sys/power/state ] || return 1
    [ -w /proc/keypad ] && [ -x /usr/bin/waitforkey ] && [ -x /usr/sbin/eips ] || return 1
    for script in keywatch.sh validate.sh fetch.sh; do [ -x "$DIR/$script" ] || return 1; done
    [ -s "$DIR/prepare.png" ] && [ -x "$ROOT/runtime/xh" ] && [ -s "$ROOT/tls/cacert.pem" ] || return 1
    [ -n "$(pidof cvm 2>/dev/null)" ] && [ "$(get_prop com.lab126.powerd state)" = active ] || return 1
    [ "$(get_prop com.lab126.cmd wirelessEnable)" = 1 ] && [ "$(get_prop com.lab126.wifid enable)" = 1 ] || return 1
    case "$(get_prop com.lab126.powerd preventScreenSaver)" in 0|1) ;; *) return 1 ;; esac
    battery=$(get_prop com.lab126.powerd battLevel)
    case "$battery" in ''|*[!0-9]*) return 1 ;; esac
    [ "$battery" -ge 20 ] || return 1
    printf 'Two-refresh test prerequisites passed; no settings changed.\n'
}
MODE=${1:---check}
[ "$MODE" != --check ] || { check; exit; }
case "$MODE" in --run|--self-check) ;; *) exit 2 ;; esac
check || exit 1
mkdir "$LOCK" || exit 1
printf '%s\n' "$$" > "$LOCK/pid"
mkdir -p "$ROOT/tests" || exit 1
LOG="$ROOT/tests/weather-test.$(date -u +%Y%m%dT%H%M%S).$$.log"
printf '%s\n' "$LOG" > "$ROOT/tests/last-weather-test.txt"
ORIG_PREVENT=$(get_prop com.lab126.powerd preventScreenSaver)
ORIG_WIRELESS=$(get_prop com.lab126.cmd wirelessEnable)
ORIG_WIFI=$(get_prop com.lab126.wifid enable)
ORIG_CVM=$(pidof cvm)
WATCH_PID=''; NET_PID=''; DEADLINE=0; ARMED=0; RESULT=not-started
cleanup() {
    rc=$?
    trap - 0 1 2 15
    printf 'stop\n' > "$LOCK/key-stop"
    if [ -n "$NET_PID" ]; then kill "$NET_PID" 2>/dev/null || true; wait "$NET_PID" 2>/dev/null || true; fi
    if [ -n "$WATCH_PID" ]; then kill "$WATCH_PID" 2>/dev/null || true; wait "$WATCH_PID" 2>/dev/null || true; fi
    if [ "$ARMED" = 1 ]; then
        remaining=$((DEADLINE-$(date -u +%s)))
        if [ "$remaining" -gt 0 ] && [ "$remaining" -le 31 ]; then
            log "EARLY_WAKE waiting ${remaining}s for this alarm to expire"
            sleep "$((remaining+1))"
        fi
    fi
    if [ "$(get_prop com.lab126.cmd wirelessEnable)" != "$ORIG_WIRELESS" ]; then
        set_prop com.lab126.cmd wirelessEnable "$ORIG_WIRELESS" || rc=1
    fi
    set_prop com.lab126.wifid enable "$ORIG_WIFI" || rc=1
    set_prop com.lab126.powerd preventScreenSaver "$ORIG_PREVENT" || rc=1
    if [ "$(get_prop com.lab126.powerd state)" != active ]; then
        set_prop com.lab126.powerd wakeUp 1 || rc=1
        sleep 1
    fi
    home || rc=1
    p=$(get_prop com.lab126.powerd preventScreenSaver)
    w=$(get_prop com.lab126.cmd wirelessEnable)
    f=$(get_prop com.lab126.wifid enable)
    c=$(pidof cvm 2>/dev/null || true)
    a=$(cat "$RTC"); s=$(get_prop com.lab126.powerd state)
    log "RESTORE prevent=$p wireless=$w wifi=$f cvm=$c rtc=$a state=$s"
    [ "$p" = "$ORIG_PREVENT" ] && [ "$w" = "$ORIG_WIRELESS" ] && [ "$f" = "$ORIG_WIFI" ] && \
        [ "$c" = "$ORIG_CVM" ] && [ "$a" = 0 ] && [ "$s" = active ] || rc=1
    if [ -r "$LOCK/stop-reason" ]; then log "STOP reason=$(cat "$LOCK/stop-reason")"; fi
    log "END result=$RESULT rc=$rc"
    rm -f "$LOCK/pid" "$LOCK/key-stop" "$LOCK/key-ready" "$LOCK/key-event" "$LOCK/stop-reason" "$LOCK/fetched-path"
    rmdir "$LOCK" 2>/dev/null || true
    sync
    exit "$rc"
}
trap cleanup 0
trap 'RESULT=cancelled; exit 0' 1 2 15
log "START mode=$MODE cycles=2 sleep=30 prevent=$ORIG_PREVENT wireless=$ORIG_WIRELESS wifi=$ORIG_WIFI cvm=$ORIG_CVM"
set_prop com.lab126.powerd preventScreenSaver 1 || exit 1
"$DIR/keywatch.sh" "$$" "$LOCK" "$LOG" </dev/null >/dev/null 2>&1 &
WATCH_PID=$!
n=0
while [ ! -r "$LOCK/key-ready" ] && [ "$n" -lt 3 ]; do
    kill -0 "$WATCH_PID" 2>/dev/null || { RESULT=key-listener-failed; exit 1; }
    sleep 1; n=$((n+1))
done
[ -r "$LOCK/key-ready" ] || { RESULT=key-listener-not-ready; exit 1; }
sleep 2
if [ "$MODE" = --self-check ]; then
    set_prop com.lab126.wifid enable 0 || exit 1
    sleep 2
    [ "$(get_prop com.lab126.wifid enable)" = 0 ] || exit 1
    log 'SELF_CHECK wifi=0; sending Home without display or suspend'
    home
    sleep 3
    RESULT=home-listener-did-not-stop-test
    exit 1
fi
/usr/sbin/eips -f -g "$DIR/prepare.png" || exit 1
n=0
while [ "$(get_prop com.lab126.powerd isCharging)" = 1 ] && [ "$n" -lt 15 ]; do sleep 1; n=$((n+1)); done
[ "$(get_prop com.lab126.powerd isCharging)" = 0 ] || { RESULT=usb-still-connected; exit 0; }
cycle=1
while [ "$cycle" -le 2 ]; do
    [ ! -r "$LOCK/stop-reason" ] || { RESULT=cancelled; exit 0; }
    kill -0 "$WATCH_PID" 2>/dev/null || { RESULT=key-listener-failed; exit 1; }
    set_prop com.lab126.wifid enable 1 || exit 1
    n=0
    while [ "$(get_prop com.lab126.wifid cmState)" != CONNECTED ] && [ "$n" -lt 20 ]; do sleep 1; n=$((n+1)); done
    [ "$(get_prop com.lab126.wifid cmState)" = CONNECTED ] || { RESULT=wifi-unavailable; exit 1; }
    log "FETCH cycle=$cycle start"
    "$DIR/fetch.sh" --fetch > "$LOCK/fetched-path" 2>> "$LOG" &
    NET_PID=$!
    wait "$NET_PID"
    fetch_rc=$?
    [ ! -r "$LOCK/stop-reason" ] || { RESULT=cancelled; exit 0; }
    if kill -0 "$NET_PID" 2>/dev/null; then RESULT=download-interrupted; exit 1; fi
    NET_PID=''
    [ "$fetch_rc" = 0 ] || { RESULT=fetch-failed-old-cache-preserved; exit 1; }
    image=''; read -r image < "$LOCK/fetched-path" || exit 1
    expected=$("$DIR/fetch.sh" --current) || exit 1
    [ "$image" = "$expected" ] || exit 1
    [ ! -r "$LOCK/stop-reason" ] || { RESULT=cancelled; exit 0; }
    kill -0 "$WATCH_PID" 2>/dev/null || { RESULT=key-listener-failed; exit 1; }
    /usr/sbin/eips -f -g "$image" || { RESULT=display-failed; exit 1; }
    log "DISPLAY cycle=$cycle validated=1"
    [ "$cycle" != 2 ] || break
    set_prop com.lab126.wifid enable 0 || exit 1
    sleep 2
    [ "$(get_prop com.lab126.wifid enable)" = 0 ] || exit 1
    kill -0 "$WATCH_PID" 2>/dev/null || { RESULT=key-listener-failed; exit 1; }
    [ ! -r "$LOCK/stop-reason" ] || { RESULT=cancelled; exit 0; }
    sync
    before=$(date -u +%s); DEADLINE=$((before+30)); ARMED=1
    log "SUSPEND cycle=$cycle before=$before deadline=$DEADLINE wifi=0"
    printf '30\n' > "$RTC" || exit 1
    printf 'mem\n' > /sys/power/state
    suspend_rc=$?
    elapsed=$(($(date -u +%s)-before)); rtc_after=$(cat "$RTC")
    log "RESUME elapsed=$elapsed suspend_rc=$suspend_rc rtc=$rtc_after"
    [ "$suspend_rc" = 0 ] && [ "$elapsed" -ge 25 ] && [ "$elapsed" -le 45 ] && [ "$rtc_after" = 0 ] || { RESULT=rtc-wake-unproven; exit 1; }
    ARMED=0
    cycle=$((cycle+1))
done
sleep 3
kill -0 "$WATCH_PID" 2>/dev/null || { RESULT=key-listener-failed; exit 1; }
RESULT=two-refresh-test-pass
