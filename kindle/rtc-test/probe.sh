#!/bin/sh
# A single 30-second test; no daemon, automatic startup or framework shutdown.
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
umask 077
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
SCRIPT="$DIR/probe.sh"
LOCK=/tmp/kindle-weather-wake-test
RTC=/sys/devices/platform/mxc_rtc.0/wakeup_enable
LOGDIR=/mnt/us/kindle-weather/tests
MODE=${1:---check}

get_prop() { lipc-get-prop "$1" "$2" 2>/dev/null; }
set_prop() { lipc-set-prop "$1" "$2" "$3"; }
home() { printf 'send 102\n' > /proc/keypad; }
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }

check() {
    [ -w "$RTC" ] && [ -w /sys/power/state ] && [ -w /proc/keypad ] || return 1
    [ -x /usr/bin/waitforkey ] && [ -x /usr/sbin/eips ] || return 1
    [ -s "$DIR/prepare.png" ] && [ -s "$DIR/sleep.png" ] || return 1
    [ -n "$(pidof cvm 2>/dev/null)" ] || return 1
    [ "$(get_prop com.lab126.powerd state)" = active ] || return 1
    case " $(cat /sys/power/state) " in *' mem '*) ;; *) return 1 ;; esac
    [ "$(cat "$RTC")" = 0 ] || { printf 'An RTC wake request is already present.\n' >&2; return 1; }
    for value in "$(get_prop com.lab126.powerd preventScreenSaver)" \
                 "$(get_prop com.lab126.cmd wirelessEnable)" \
                 "$(get_prop com.lab126.wifid enable)"; do
        case "$value" in 0|1) ;; *) return 1 ;; esac
    done
    battery=$(get_prop com.lab126.powerd battLevel)
    case "$battery" in ''|*[!0-9]*) return 1 ;; esac
    [ "$battery" -ge 20 ] || { printf 'Battery must be at least 20 percent.\n' >&2; return 1; }
    printf 'Wake-test prerequisites are present; no settings changed.\n'
}

watch_keys() {
    parent=$2
    LOG=$3
    child=''
    trap 'trap - 0 1 2 15; if [ -n "$child" ]; then kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; fi; exit 0' 0 1 2 15
    log "KEY_WATCH start parent=$parent"
    while kill -0 "$parent" 2>/dev/null; do
        /usr/bin/waitforkey > "$LOCK/key-event" &
        child=$!
        printf 'ready\n' > "$LOCK/key-ready"
        wait "$child"
        waiter_rc=$?
        child=''
        code=''; value=''
        read code value < "$LOCK/key-event"
        read_rc=$?
        if [ "$waiter_rc" != 0 ] || [ "$read_rc" != 0 ]; then
            log "KEY_WATCH read waiter_rc=$waiter_rc read_rc=$read_rc"
            exit 1
        fi
        if [ "$code" = 102 ] && [ "$value" = 1 ]; then
            log 'KEY_WATCH home received'
            printf 'home\n' > "$LOCK/stop-reason"
            kill -TERM "$parent" 2>/dev/null || true
            exit 0
        fi
    done
}

if [ "$MODE" = --watch ]; then watch_keys "$@"; exit; fi
if [ "$MODE" = --check ]; then check; exit; fi
case "$MODE" in --run|--self-check) ;; *) exit 2 ;; esac
check || exit 1
mkdir "$LOCK" 2>/dev/null || { printf 'A wake test is already active.\n' >&2; exit 1; }
printf '%s\n' "$$" > "$LOCK/pid"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/wake-test.$(date -u +%Y%m%dT%H%M%S).$$.log"
printf '%s\n' "$LOG" > "$LOGDIR/last-wake-test.txt"
ORIG_PREVENT=$(get_prop com.lab126.powerd preventScreenSaver)
ORIG_WIRELESS=$(get_prop com.lab126.cmd wirelessEnable)
ORIG_WIFI=$(get_prop com.lab126.wifid enable)
ORIG_CVM=$(pidof cvm 2>/dev/null || true)
WATCH_PID=''
DEADLINE=0
ARMED=0
RESULT=not-started

cleanup() {
    rc=$?
    trap - 0 1 2 15
    if [ -n "$WATCH_PID" ]; then
        kill "$WATCH_PID" 2>/dev/null || true
        wait "$WATCH_PID" 2>/dev/null || true
    fi
    # Zero is a no-op on this old driver. A bounded test lets any early alarm expire.
    if [ "$ARMED" = 1 ]; then
        remaining=$((DEADLINE - $(date -u +%s)))
        if [ "$remaining" -gt 0 ] && [ "$remaining" -le 31 ]; then
            log "EARLY_WAKE waiting ${remaining}s for the one-shot alarm to expire"
            sleep "$((remaining+1))"
        fi
    fi
    if [ "$(get_prop com.lab126.cmd wirelessEnable)" != "$ORIG_WIRELESS" ]; then
        set_prop com.lab126.cmd wirelessEnable "$ORIG_WIRELESS" || rc=1
    fi
    set_prop com.lab126.wifid enable "$ORIG_WIFI" || rc=1
    set_prop com.lab126.powerd preventScreenSaver "$ORIG_PREVENT" || rc=1
    # This firmware rejects wakeUp while already active. Only request a transition.
    power_state=$(get_prop com.lab126.powerd state)
    if [ "$power_state" != active ]; then
        set_prop com.lab126.powerd wakeUp 1 || rc=1
        sleep 1
    fi
    home || rc=1
    restored_prevent=$(get_prop com.lab126.powerd preventScreenSaver)
    restored_wireless=$(get_prop com.lab126.cmd wirelessEnable)
    restored_wifi=$(get_prop com.lab126.wifid enable)
    after_cvm=$(pidof cvm 2>/dev/null || true)
    rtc_value=$(cat "$RTC")
    power_state=$(get_prop com.lab126.powerd state)
    log "RESTORE prevent=$restored_prevent wireless=$restored_wireless wifi=$restored_wifi rtc=$rtc_value cvm=$after_cvm state=$power_state"
    [ "$restored_prevent" = "$ORIG_PREVENT" ] && \
    [ "$restored_wireless" = "$ORIG_WIRELESS" ] && \
    [ "$restored_wifi" = "$ORIG_WIFI" ] && [ "$after_cvm" = "$ORIG_CVM" ] && \
    [ "$power_state" = active ] || rc=1
    if [ "$ARMED" = 1 ] && [ "$rtc_value" != 0 ]; then
        log 'RTC_STATUS_NOT_RESET: further native suspend/resume inspection is required'
        rc=1
    fi
    if [ -r "$LOCK/stop-reason" ]; then
        reason=$(cat "$LOCK/stop-reason")
        log "STOP reason=$reason"
        [ "$MODE" != --self-check ] || [ "$reason" = home ] || rc=1
    fi
    log "END result=$RESULT rc=$rc"
    rm -f "$LOCK/pid" "$LOCK/key-event" "$LOCK/key-ready" "$LOCK/stop-reason"
    rmdir "$LOCK" 2>/dev/null || true
    sync
    exit "$rc"
}
trap cleanup 0
trap 'RESULT=cancelled; exit 0' 1 2 15
log "START mode=$MODE prevent=$ORIG_PREVENT wireless=$ORIG_WIRELESS wifi=$ORIG_WIFI cvm=$ORIG_CVM"
set_prop com.lab126.powerd preventScreenSaver 1 || exit 1
"$SCRIPT" --watch "$$" "$LOG" </dev/null >/dev/null 2>&1 &
WATCH_PID=$!
n=0
while [ ! -r "$LOCK/key-ready" ] && [ "$n" -lt 3 ]; do
    kill -0 "$WATCH_PID" 2>/dev/null || { RESULT=home-listener-failed; exit 1; }
    sleep 1
    n=$((n+1))
done
[ -r "$LOCK/key-ready" ] || { RESULT=home-listener-not-ready; exit 1; }
sleep 1

if [ "$MODE" = --run ]; then
    sleep 2
    /usr/sbin/eips -f -g "$DIR/prepare.png" || exit 1
    n=0
    while [ "$(get_prop com.lab126.powerd isCharging)" = 1 ] && [ "$n" -lt 15 ]; do
        sleep 1
        n=$((n+1))
    done
    if [ "$(get_prop com.lab126.powerd isCharging)" != 0 ]; then
        RESULT=usb-still-connected
        exit 0
    fi
fi

set_prop com.lab126.wifid enable 0 || exit 1
sleep 2
[ "$(get_prop com.lab126.wifid enable)" = 0 ] || { RESULT=wifi-did-not-disable; exit 1; }
log 'WIFI_OFF confirmed'

if [ "$MODE" = --self-check ]; then
    home
    sleep 3
    RESULT=home-listener-did-not-stop-test
    exit 1
fi

/usr/sbin/eips -f -g "$DIR/sleep.png" || exit 1
sleep 1
before=$(date -u +%s)
DEADLINE=$((before+30))
log "SUSPEND_REQUEST before=$before deadline=$DEADLINE"
sync
ARMED=1
printf '30\n' > "$RTC" || exit 1
printf 'mem\n' > /sys/power/state
suspend_rc=$?
after=$(date -u +%s)
elapsed=$((after-before))
rtc_after=$(cat "$RTC")
log "RESUME after=$after elapsed=$elapsed suspend_rc=$suspend_rc rtc=$rtc_after"
if [ "$suspend_rc" = 0 ] && [ "$elapsed" -ge 25 ] && [ "$elapsed" -le 45 ] && [ "$rtc_after" = 0 ]; then
    RESULT=rtc-wake-pass
else
    RESULT=rtc-wake-not-proven
fi
[ "$RESULT" = rtc-wake-pass ]
