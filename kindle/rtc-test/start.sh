#!/bin/sh
set -eu
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
"$DIR/probe.sh" --check || exit 1
"$DIR/probe.sh" --run </dev/null >/tmp/kindle-weather-wake-test.stdout 2>&1 &
exit 0
