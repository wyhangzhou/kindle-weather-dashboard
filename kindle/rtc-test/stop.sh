#!/bin/sh
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
LOCK=/tmp/kindle-weather-wake-test
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
if [ -r "$LOCK/pid" ]; then
    pid=$(cat "$LOCK/pid")
    case "$pid" in ''|*[!0-9]*) exit 1 ;; esac
    if [ -r "/proc/$pid/cmdline" ]; then
        command=$(tr '\000' ' ' < "/proc/$pid/cmdline")
        case "$command" in
            *"$DIR/probe.sh"*)
                printf 'user\n' > "$LOCK/stop-reason"
                kill -TERM "$pid"
                exit 0
                ;;
            *) printf 'PID does not belong to the wake test.\n' >&2; exit 1 ;;
        esac
    fi
fi
printf 'No active wake test.\n'
