#!/bin/sh
# Manual KUAL weather mode. Native reading stays running throughout.
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
umask 077
trap '' 1
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
LIB=$DIR/lib
ROOT=/mnt/us/kindle-weather
LOCK=/tmp/kindle-weather-dashboard
STATE=$ROOT/state/dashboard.props
TOKEN=$ROOT/state/alarm-dashboard
LOG=$ROOT/logs/dashboard.log
MODE=${1:---check}
get_prop() { lipc-get-prop "$1" "$2" 2>/dev/null; }
set_prop() { lipc-set-prop -i "$1" "$2" "$3"; }
home() { printf 'send 102\n' > /proc/keypad; }
paint_weather() { /usr/sbin/eips -f -g "$1"; }
prepare_display() {
    # Native Home repaints its status bar when the radio changes state.
    # Settle that event first, then cover it with the full image every cycle.
    set_prop com.lab126.wifid enable 0 || return 1
    sleep 2
    [ "$(get_prop com.lab126.wifid enable)" = 0 ] || return 1
    paint_weather "$1"
}
log() {
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 131072 ]; then mv -f "$LOG" "$LOG.previous"; fi
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"
}
load_state() {
    [ -r "$STATE" ] || return 1
    IFS=' ' read -r schema P W F C BOOT < "$STATE" || return 1
    [ "$schema" = k4-weather-state-v1 ] || return 1
    case "$P:$W:$F" in [01]:[01]:[01]) ;; *) return 1 ;; esac
    case "$C" in ''|*[!0-9]*) return 1 ;; esac
    case "$BOOT" in ''|*[!0-9a-f-]*) return 1 ;; esac
    [ "${#BOOT}" = 36 ]
}
restore() {
    final_rc=0
    FRAMEWORK_CHANGED=0
    if [ -r "$TOKEN" ]; then
        if "$LIB/alarm.sh" --restore "$TOKEN" >> "$LOG" 2>&1; then
            rm -f "$TOKEN"
            log 'ALARM restored'
        else
            log 'ALARM restore failed; saved ownership retained'
            final_rc=1
        fi
    fi
    now_boot=$(cat /proc/sys/kernel/random/boot_id)
    if [ "$now_boot" = "$BOOT" ]; then
        if [ "$(get_prop com.lab126.cmd wirelessEnable)" != "$W" ]; then set_prop com.lab126.cmd wirelessEnable "$W" || final_rc=1; fi
        if [ "$(get_prop com.lab126.wifid enable)" != "$F" ]; then set_prop com.lab126.wifid enable "$F" || final_rc=1; fi
        if [ "$(get_prop com.lab126.powerd preventScreenSaver)" != "$P" ]; then set_prop com.lab126.powerd preventScreenSaver "$P" || final_rc=1; fi
    else
        log 'RECOVER new boot; preserve fresh native power and wireless settings'
    fi
    if [ "$(get_prop com.lab126.powerd state)" != active ]; then
        set_prop com.lab126.powerd wakeUp 1 || final_rc=1
        sleep 1
    fi
    home || final_rc=1
    p=$(get_prop com.lab126.powerd preventScreenSaver)
    w=$(get_prop com.lab126.cmd wirelessEnable)
    f=$(get_prop com.lab126.wifid enable)
    c=$(pidof cvm 2>/dev/null || true)
    s=$(get_prop com.lab126.powerd state)
    log "RESTORE prevent=$p wireless=$w wifi=$f cvm=$c state=$s"
    if [ "$now_boot" = "$BOOT" ]; then
        [ "$p" = "$P" ] && [ "$w" = "$W" ] && [ "$f" = "$F" ] || final_rc=1
        if [ "$c" != "$C" ]; then
            FRAMEWORK_CHANGED=1
            log "FRAMEWORK_PID_CHANGED expected=$C actual=$c"
        fi
    fi
    [ "$s" = active ] && [ -n "$c" ] || final_rc=1
    "$LIB/alarm.sh" --status >> "$LOG" 2>&1 || final_rc=1
    if [ "$final_rc" = 0 ]; then rm -f "$STATE"; fi
    return "$final_rc"
}
check() {
    for lock in "$LOCK" /tmp/kindle-weather-run-test /tmp/kindle-weather-exit-test /tmp/kindle-weather-wake-test; do [ ! -d "$lock" ] || return 1; done
    [ ! -e "$STATE" ] && [ ! -e "$TOKEN" ] || { printf 'Saved weather state needs Stop / Read recovery.\n' >&2; return 1; }
    for script in alarm.sh fetch.sh validate.sh keywatch.sh; do [ -x "$LIB/$script" ] || return 1; done
    [ -s "$DIR/prepare.png" ] && [ -w /sys/power/state ] && [ -w /proc/keypad ] || return 1
    [ -x /usr/sbin/eips ] && [ -x /usr/bin/waitforkey ] || return 1
    [ -x "$ROOT/runtime/xh" ] && [ -s "$ROOT/tls/cacert.pem" ] || return 1
    [ "$(get_prop com.lab126.powerd state)" = active ] && [ -n "$(pidof cvm)" ] || return 1
    for value in "$(get_prop com.lab126.powerd preventScreenSaver)" "$(get_prop com.lab126.cmd wirelessEnable)" "$(get_prop com.lab126.wifid enable)"; do
        case "$value" in 0|1) ;; *) return 1 ;; esac
    done
    battery=$(get_prop com.lab126.powerd battLevel)
    case "$battery" in ''|*[!0-9]*) return 1 ;; esac
    [ "$battery" -ge 20 ] || return 1
    "$LIB/alarm.sh" --check || return 1
    printf 'Weather mode prerequisites passed; no settings changed.\n'
}
if [ "$MODE" = --check ]; then check; exit; fi
if [ "$MODE" = --recover ]; then
    load_state || { printf 'No readable saved weather state.\n'; exit 1; }
    mkdir -p "$ROOT/logs"
    restore
    result=$?
    log "RECOVERY_END rc=$result"
    exit "$result"
fi
case "$MODE" in --run|--trial|--self-check) ;; *) exit 2 ;; esac
check || exit 1
mkdir "$LOCK" || exit 1
printf '%s\n' "$$" > "$LOCK/pid"
mkdir -p "$ROOT/state" "$ROOT/logs" || exit 1
P=$(get_prop com.lab126.powerd preventScreenSaver)
W=$(get_prop com.lab126.cmd wirelessEnable)
F=$(get_prop com.lab126.wifid enable)
C=$(pidof cvm)
BOOT=$(cat /proc/sys/kernel/random/boot_id)
printf 'k4-weather-state-v1 %s %s %s %s %s\n' "$P" "$W" "$F" "$C" "$BOOT" > "$STATE.new" && mv "$STATE.new" "$STATE" || exit 1
WATCH=''; JOB=''; RESULT=not-started
cleanup() {
    rc=$?
    trap - 0
    trap '' 1 2 15
    printf 'stop\n' > "$LOCK/key-stop"
    if [ -n "$JOB" ]; then kill "$JOB" 2>/dev/null || true; wait "$JOB" 2>/dev/null || true; fi
    if [ -n "$WATCH" ]; then kill "$WATCH" 2>/dev/null || true; wait "$WATCH" 2>/dev/null || true; fi
    restore || rc=1
    # Keep verification failure distinct from successful power/alarm recovery.
    [ "$FRAMEWORK_CHANGED" = 0 ] || rc=1
    if [ -r "$LOCK/stop-reason" ]; then log "STOP reason=$(cat "$LOCK/stop-reason")"; fi
    log "END result=$RESULT rc=$rc"
    rm -f "$LOCK/pid" "$LOCK/key-stop" "$LOCK/key-ready" "$LOCK/key-event" "$LOCK/stop-reason" "$LOCK/fetched-path"
    rmdir "$LOCK" 2>/dev/null || true
    sync
    exit "$rc"
}
trap cleanup 0
trap 'RESULT=cancelled; exit 0' 2 15
log "START mode=$MODE interval=1800 prevent=$P wireless=$W wifi=$F cvm=$C"
"$LIB/alarm.sh" --save "$TOKEN" || exit 1
set_prop com.lab126.powerd preventScreenSaver 1 || exit 1
"$LIB/keywatch.sh" "$$" "$LOCK" "$LOG" </dev/null >/dev/null 2>&1 &
WATCH=$!
n=0
while [ ! -r "$LOCK/key-ready" ] && [ "$n" -lt 3 ]; do kill -0 "$WATCH" 2>/dev/null || exit 1; sleep 1; n=$((n+1)); done
[ -r "$LOCK/key-ready" ] || exit 1
sleep 2
if [ "$MODE" = --self-check ]; then
    set_prop com.lab126.wifid enable 0 || exit 1
    sleep 1
    [ "$(get_prop com.lab126.wifid enable)" = 0 ] || exit 1
    home
    sleep 2
    RESULT=home-listener-failed
    exit 1
fi
/usr/sbin/eips -f -g "$DIR/prepare.png" || exit 1
n=0
while [ "$(get_prop com.lab126.powerd isCharging)" = 1 ] && [ "$n" -lt 15 ]; do sleep 1; n=$((n+1)); done
[ "$(get_prop com.lab126.powerd isCharging)" = 0 ] || { RESULT=usb-still-connected; exit 0; }
cycle=0; failures=0
while :; do
    [ ! -r "$LOCK/stop-reason" ] || { RESULT=cancelled; exit 0; }
    kill -0 "$WATCH" 2>/dev/null || { RESULT=key-listener-failed; exit 1; }
    battery=$(get_prop com.lab126.powerd battLevel)
    case "$battery" in ''|*[!0-9]*) RESULT=battery-unreadable; exit 1 ;; esac
    [ "$battery" -ge 15 ] || { RESULT=low-battery; exit 0; }
    cycle=$((cycle+1)); fetched=0
    if [ "$(get_prop com.lab126.cmd wirelessEnable)" != 1 ]; then set_prop com.lab126.cmd wirelessEnable 1 || exit 1; fi
    if [ "$(get_prop com.lab126.wifid enable)" != 1 ]; then set_prop com.lab126.wifid enable 1 || exit 1; fi
    n=0
    while [ "$(get_prop com.lab126.wifid cmState)" != CONNECTED ] && [ "$n" -lt 40 ]; do sleep 1; n=$((n+1)); done
    if [ "$(get_prop com.lab126.wifid cmState)" = CONNECTED ]; then
        log "WIFI_CONNECTED cycle=$cycle waited=$n"
        log "FETCH cycle=$cycle start"
        "$LIB/fetch.sh" --fetch > "$LOCK/fetched-path" 2>> "$LOG" &
        JOB=$!
        wait "$JOB"
        fetch_rc=$?
        [ ! -r "$LOCK/stop-reason" ] || { RESULT=cancelled; exit 0; }
        if kill -0 "$JOB" 2>/dev/null; then RESULT=download-interrupted; exit 1; fi
        JOB=''
        [ "$fetch_rc" != 0 ] || fetched=1
    else
        log "WIFI_TIMEOUT cycle=$cycle waited=$n state=$(get_prop com.lab126.wifid cmState) cvm=$(pidof cvm 2>/dev/null || true)"
    fi
    if [ "$fetched" = 1 ]; then
        failures=0; interval=1800
        log "FETCH cycle=$cycle success"
    else
        failures=$((failures+1))
        case "$failures" in 1) interval=300 ;; 2) interval=600 ;; *) interval=1800 ;; esac
        log "FETCH cycle=$cycle failed; preserve cached image; retry=$interval"
    fi
    image=$("$LIB/fetch.sh" --current) || { RESULT=no-valid-cache; exit 1; }
    [ ! -r "$LOCK/stop-reason" ] || { RESULT=cancelled; exit 0; }
    kill -0 "$WATCH" 2>/dev/null || { RESULT=key-listener-failed; exit 1; }
    prepare_display "$image" || { RESULT=display-failed; exit 1; }
    log "DISPLAY cycle=$cycle cached=$((1-fetched)) redrawn=1 wifi=0"
    if [ "$MODE" = --trial ] && [ "$fetched" = 0 ]; then RESULT=trial-download-failed; exit 1; fi
    if [ "$MODE" = --trial ] && [ "$cycle" -ge 2 ]; then RESULT=trial-complete; sleep 3; exit 0; fi
    kill -0 "$WATCH" 2>/dev/null || { RESULT=key-listener-failed; exit 1; }
    [ ! -r "$LOCK/stop-reason" ] || { RESULT=cancelled; exit 0; }
    sync
    "$LIB/alarm.sh" --arm "$interval" "$TOKEN" >> "$LOG" 2>&1 || { RESULT=alarm-arm-failed; exit 1; }
    log "SUSPEND cycle=$cycle seconds=$interval wifi=0"
    before=$(date -u +%s)
    printf 'mem\n' > /sys/power/state
    suspend_rc=$?
    elapsed=$(($(date -u +%s)-before))
    log "RESUME elapsed=$elapsed suspend_rc=$suspend_rc"
    [ "$suspend_rc" = 0 ] || { RESULT=suspend-failed; exit 1; }
    if [ "$elapsed" -lt "$((interval-10))" ]; then RESULT=early-wake-exit; exit 0; fi
    [ "$elapsed" -le "$((interval+120))" ] || { RESULT=late-wake; exit 1; }
done
