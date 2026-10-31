#!/bin/sh
# Parse a fixed data format without eval, and check a native framebuffer image.
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
metadata_only=0
allow_stale=0
case "${1:-}" in
    --metadata) metadata_only=1; shift ;;
    --cached) allow_stale=1; shift ;;
esac
meta=${1:-}
image=${2:-}
fail() { printf 'Weather validation failed: %s\n' "$1" >&2; exit 1; }
[ -f "$meta" ] || fail 'missing metadata'
[ "$(wc -c < "$meta")" -le 4096 ] || fail 'metadata too large'
schema=''; generated_epoch=''; weather_epoch=''; expires_epoch=''; file=''
bytes=''; md5=''; sha256=''; width=''; height=''; mode=''; rotation=''
seen='|'; count=0
while IFS='=' read -r key value || [ -n "$key" ]; do
    case "$seen" in *"|$key|"*) fail 'duplicate field' ;; esac
    seen="$seen$key|"; count=$((count+1))
    case "$key" in
        schema) schema=$value ;; generated_epoch) generated_epoch=$value ;;
        weather_epoch) weather_epoch=$value ;; expires_epoch) expires_epoch=$value ;;
        file) file=$value ;; bytes) bytes=$value ;; md5) md5=$value ;;
        sha256) sha256=$value ;; width) width=$value ;; height) height=$value ;;
        mode) mode=$value ;; rotation) rotation=$value ;;
        *) fail 'unknown field' ;;
    esac
done < "$meta"
[ "$count" = 12 ] && [ "$schema" = kindle-weather-v1 ] || fail 'schema or missing field'
[ "$file" = dashboard-kindle.png ] || fail 'unexpected image name'
[ "$width" = 600 ] && [ "$height" = 800 ] && [ "$mode" = L ] || fail 'image format'
case "$rotation" in counterclockwise|clockwise) ;; *) fail 'rotation' ;; esac
for value in "$generated_epoch" "$weather_epoch" "$expires_epoch" "$bytes"; do
    case "$value" in ''|0*|*[!0-9]*) fail 'invalid integer' ;; esac
    [ "${#value}" -le 10 ] && [ "$value" -le 2147480000 ] || fail 'integer range'
done
[ "$bytes" -ge 100 ] && [ "$bytes" -le 262144 ] || fail 'image size range'
case "$md5$sha256" in *[!0-9a-f]*) fail 'digest format' ;; esac
[ "${#md5}" = 32 ] && [ "${#sha256}" = 64 ] || fail 'digest length'
now=$(date -u +%s)
[ "$weather_epoch" -ge 1600000000 ] && [ "$generated_epoch" -ge "$((weather_epoch-600))" ] || fail 'timestamp order'
[ "$generated_epoch" -le "$((now+600))" ] && [ "$weather_epoch" -le "$((now+600))" ] || fail 'future data'
ttl=$((expires_epoch-weather_epoch))
[ "$ttl" -ge 900 ] && [ "$ttl" -le 10800 ] || fail 'expiry range'
if [ "$allow_stale" = 0 ]; then [ "$expires_epoch" -ge "$now" ] || fail 'stale data'; fi
[ "$metadata_only" = 0 ] || exit 0
[ -f "$image" ] && [ "$(wc -c < "$image")" -eq "$bytes" ] || fail 'image length'
actual=$(md5sum "$image") || fail 'digest unavailable'
[ "${actual%% *}" = "$md5" ] || fail 'image checksum'
header=$(hexdump -n 33 -v -e '1/1 "%02x"' "$image") || fail 'PNG header read'
[ "$header" = 89504e470d0a1a0a0000000d4948445200000258000003200800000000da0b4318 ] || fail 'PNG header'
footer=$(dd if="$image" bs=1 skip="$((bytes-12))" count=12 2>/dev/null | hexdump -v -e '1/1 "%02x"')
[ "$footer" = 0000000049454e44ae426082 ] || fail 'PNG end marker'
