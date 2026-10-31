#!/bin/sh
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
LOCK=/tmp/kindle-weather-run-test
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
[ -r "$LOCK/pid" ] || { printf 'No weather test is active.\n'; exit 0; }
pid=$(cat "$LOCK/pid")
case "$pid" in ''|*[!0-9]*) exit 1 ;; esac
[ -r "/proc/$pid/cmdline" ] || exit 0
cmd=$(tr '\000' ' ' < "/proc/$pid/cmdline")
case "$cmd" in *"$DIR/runner.sh"*) ;; *) printf 'Refused an unrelated PID.\n' >&2; exit 1 ;; esac
printf 'user\n' > "$LOCK/stop-reason"
kill -TERM "$pid"
