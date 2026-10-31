#!/bin/sh
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
parent=$1
LOCK=$2
LOG=$3
child=''
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }
cleanup() {
    rc=$?
    trap - 0 1 2 15
    if [ -n "$child" ]; then kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; fi
    exit "$rc"
}
trap cleanup 0
trap 'exit 0' 1 2 15
while kill -0 "$parent" 2>/dev/null; do
    waitforkey > "$LOCK/key-event" &
    child=$!
    printf 'ready\n' > "$LOCK/key-ready"
    wait "$child"
    waiter_rc=$?
    [ ! -r "$LOCK/key-stop" ] || exit 0
    if kill -0 "$child" 2>/dev/null; then
        log "KEY_WATCH interrupted with a live input waiter rc=$waiter_rc"
        exit 1
    fi
    child=''
    code=''; value=''
    read code value < "$LOCK/key-event"
    read_rc=$?
    if [ "$waiter_rc" != 0 ] || [ "$read_rc" != 0 ]; then
        log "KEY_WATCH failed waiter_rc=$waiter_rc read_rc=$read_rc"
        exit 1
    fi
    if [ "$code" = 102 ] && [ "$value" = 1 ]; then
        log 'KEY_WATCH home received'
        printf 'home\n' > "$LOCK/stop-reason"
        kill -TERM "$parent" 2>/dev/null || true
        exit 0
    fi
done
