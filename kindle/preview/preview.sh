#!/bin/sh
# One-shot display only. KUAL and the native reading framework remain active.
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

IMAGE=/mnt/us/kindle-weather/checks/project-dashboard.png
LOG=/tmp/kindle-weather-preview.log

if [ ! -s "$IMAGE" ] || [ ! -x /usr/sbin/eips ]; then
    printf '%s\n' 'Saved weather image or eips is unavailable.' >&2
    exit 1
fi

if [ "${1:-}" = '--check' ]; then
    printf '%s\n' 'Preview prerequisites are present; screen was not changed.'
    exit 0
fi

# Allow KUAL to finish handling the menu action before painting the preview.
(
    sleep 2
    exec /usr/sbin/eips -f -g "$IMAGE"
) </dev/null >"$LOG" 2>&1 &

exit 0
