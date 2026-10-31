#!/bin/sh
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
LOCK=/tmp/kindle-weather-dashboard
STATE=/mnt/us/kindle-weather/state/dashboard.props
if [ -r "$LOCK/pid" ]; then
    pid=$(cat "$LOCK/pid")
    case "$pid" in ''|*[!0-9]*) exit 1 ;; esac
    if [ -r "/proc/$pid/cmdline" ]; then
        cmd=$(tr '\000' ' ' < "/proc/$pid/cmdline")
        case "$cmd" in *"$DIR/run.sh"*) ;; *) printf 'Refused an unrelated PID.\n' >&2; exit 1 ;; esac
        printf 'user\n' > "$LOCK/stop-reason"
        kill -TERM "$pid" || exit 1
        n=0
        while [ -e "$STATE" ] && [ "$n" -lt 10 ]; do sleep 1; n=$((n+1)); done
        [ ! -e "$STATE" ] || { printf 'Recovery is incomplete; inspect dashboard.log.\n' >&2; exit 1; }
        exit 0
    fi
fi
if [ -e "$STATE" ]; then "$DIR/run.sh" --recover; exit; fi
printf 'Weather mode is already stopped.\n'
