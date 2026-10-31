#!/bin/sh
# Verified TLS authenticates the origin; MD5 checks transfer consistency on K4.
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
umask 077
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
ROOT=/mnt/us/kindle-weather
XH=$ROOT/runtime/xh
CA=$ROOT/tls/cacert.pem
MODE=${1:---current}
BASE=${2:-https://wyhangzhou.github.io/kindle-weather-dashboard/}
CACHE=${3:-$ROOT/cache}
if [ "$MODE" = --current ]; then CACHE=${2:-$ROOT/cache}; fi
fail() { printf 'Weather fetch failed: %s\n' "$1" >&2; exit 1; }
case "$CACHE" in "$ROOT/cache"|"$ROOT/tests/cache-"*) ;; *) fail 'cache location' ;; esac
case "$CACHE" in *..*|*[!A-Za-z0-9/_.-]*) fail 'cache path' ;; esac

current_image() {
    [ -r "$CACHE/current" ] || return 1
    ref=''; read -r ref < "$CACHE/current" || return 1
    case "$ref" in snapshot-*) ;; *) return 1 ;; esac
    case "$ref" in *[!a-z0-9-]*) return 1 ;; esac
    "$DIR/validate.sh" --cached "$CACHE/$ref/device-manifest.txt" "$CACHE/$ref/dashboard.png" || return 1
    printf '%s\n' "$CACHE/$ref/dashboard.png"
}
[ "$MODE" != --current ] || { current_image; exit; }
[ "$MODE" = --fetch ] || exit 2
case "$BASE" in https://wyhangzhou.github.io/*) ;; *) fail 'HTTPS origin' ;; esac
case "$BASE" in *[!A-Za-z0-9:/_.-]*) fail 'URL syntax' ;; esac
BASE=${BASE%/}
[ -x "$XH" ] && [ -s "$CA" ] || fail 'TLS prerequisites'
if [ -d "$CACHE" ]; then
    [ -f "$CACHE/.kindle-weather-cache" ] || fail 'unowned cache directory'
else
    mkdir -p "$CACHE" || exit 1
    printf 'kindle-weather-v1\n' > "$CACHE/.kindle-weather-cache" || exit 1
fi
mkdir "$CACHE/.fetch-lock" 2>/dev/null || fail 'another fetch is active'
STAGE="$CACHE/.incoming-$$"
CHILD=''
cleanup() {
    rc=$?
    trap - 0 1 2 15
    if [ -n "$CHILD" ]; then kill "$CHILD" 2>/dev/null || true; wait "$CHILD" 2>/dev/null || true; fi
    if [ -n "$STAGE" ]; then
        rm -f "$STAGE/device-manifest.txt" "$STAGE/dashboard.png"
        rmdir "$STAGE" 2>/dev/null || true
    fi
    rm -f "$CACHE/current.new" "$CACHE/previous.new"
    rmdir "$CACHE/.fetch-lock" 2>/dev/null || true
    exit "$rc"
}
trap cleanup 0
trap 'exit 1' 1 2 15
mkdir "$STAGE" || exit 1
download() {
    (ulimit -f 1024; exec timeout -t 35 -s 9 "$XH" --verify "$CA" --ignore-netrc --ignore-stdin \
        --timeout 12 --check-status --quiet --download --output "$2" GET "$1") &
    CHILD=$!
    wait "$CHILD"
    download_rc=$?
    # An interrupted old-ash wait can return while the child is still alive.
    if kill -0 "$CHILD" 2>/dev/null; then return 1; fi
    CHILD=''
    return "$download_rc"
}
download "$BASE/device-manifest.txt" "$STAGE/device-manifest.txt" || fail 'metadata request'
"$DIR/validate.sh" --metadata "$STAGE/device-manifest.txt" || exit 1
generation=$(sed -n 's/^generated_epoch=//p' "$STAGE/device-manifest.txt")
weather=$(sed -n 's/^weather_epoch=//p' "$STAGE/device-manifest.txt")
digest=$(sed -n 's/^md5=//p' "$STAGE/device-manifest.txt")
old_image=$(current_image 2>/dev/null || true)
old=''
if [ -n "$old_image" ]; then
    old_dir=$(dirname "$old_image"); old=$(basename "$old_dir")
    previous_weather=$(sed -n 's/^weather_epoch=//p' "$old_dir/device-manifest.txt")
    [ "$weather" -ge "$previous_weather" ] || fail 'older than cached weather'
fi
download "$BASE/dashboard-kindle.png" "$STAGE/dashboard.png" || fail 'image request'
"$DIR/validate.sh" "$STAGE/device-manifest.txt" "$STAGE/dashboard.png" || exit 1
ref="snapshot-$generation-$digest"
if [ -d "$CACHE/$ref" ]; then
    "$DIR/validate.sh" "$CACHE/$ref/device-manifest.txt" "$CACHE/$ref/dashboard.png" || exit 1
else
    mv "$STAGE" "$CACHE/$ref" || exit 1
    STAGE=''
fi
if [ -n "$old" ] && [ "$old" != "$ref" ]; then
    printf '%s\n' "$old" > "$CACHE/previous.new" && mv "$CACHE/previous.new" "$CACHE/previous" || exit 1
fi
printf '%s\n' "$ref" > "$CACHE/current.new" && mv "$CACHE/current.new" "$CACHE/current" || exit 1
previous=''
if [ -r "$CACHE/previous" ]; then read -r previous < "$CACHE/previous" || true; fi
for folder in "$CACHE"/snapshot-*; do
    [ -d "$folder" ] || continue
    name=$(basename "$folder")
    [ "$name" != "$ref" ] && [ "$name" != "$previous" ] || continue
    rm -f "$folder/device-manifest.txt" "$folder/dashboard.png"
    rmdir "$folder" 2>/dev/null || true
done
printf '%s\n' "$CACHE/$ref/dashboard.png"
