#!/bin/sh
set -eu
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
MODE=${1:---run}
case "$MODE" in --run|--trial) ;; *) exit 2 ;; esac
"$DIR/run.sh" --check || exit 1
# Let KUAL finish its normal close before the independent mode starts.
(trap '' 1; sleep 2; exec "$DIR/run.sh" "$MODE") </dev/null >/tmp/kindle-weather-dashboard.stdout 2>&1 &
