#!/bin/sh
set -eu
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
"$DIR/runner.sh" --check || exit 1
"$DIR/runner.sh" --run </dev/null >/tmp/kindle-weather-run-test.stdout 2>&1 &
