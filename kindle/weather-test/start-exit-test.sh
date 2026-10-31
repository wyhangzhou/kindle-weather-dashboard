#!/bin/sh
set -eu
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
"$DIR/exit-test.sh" --check || exit 1
"$DIR/exit-test.sh" --run </dev/null >/tmp/kindle-weather-exit-test.stdout 2>&1 &
