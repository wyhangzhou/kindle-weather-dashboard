#!/bin/sh
# K4 MC13892/MC34708: preserve only RTC alarm fields, never clock/power fields.
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
umask 077
RTC=/sys/devices/platform/mxc_rtc.0/wakeup_enable
MODE=${1:---status}
fail() { printf 'RTC alarm control failed: %s\n' "$1" >&2; exit 1; }
number() {
    case "$1" in ''|0[0-9]*|*[!0-9]*) return 1 ;; esac
    [ "${#1}" -le 10 ] && [ "$1" -le "$2" ]
}
read_state() {
    [ "$(cat /sys/class/rtc/rtc1/name)" = pmic_rtc ] || fail 'unexpected RTC device'
    R21=$(pmic sread 21) && R23=$(pmic sread 23) && R4=$(pmic sread 4) || fail 'register read'
    NOW=$(cat /sys/class/rtc/rtc1/since_epoch) || fail 'RTC counter read'
    number "$R21" 16777215 && number "$R23" 16777215 && number "$R4" 16777215 && \
        number "$NOW" 2147480000 || fail 'invalid register response'
    A21=$((R21 & 0x11ffff)); A23=$((R23 & 0x7fff)); M4=$((R4 & 2))
    TOD=$((R21 & 0x1ffff)); DISABLED=$((R21 & 0x100000))
    [ "$A23" -le 24854 ] || fail 'alarm counter range'
    DEADLINE=$((A23*86400+TOD))
}
no_future_alarm() {
    [ "$DISABLED" != 0 ] || [ "$TOD" -gt 86399 ] || [ "$DEADLINE" -le "$NOW" ]
}
token_path() {
    TOKEN=${2:-}
    case "$TOKEN" in /mnt/us/kindle-weather/state/alarm-*|/mnt/us/kindle-weather/tests/alarm-*) ;; *) fail 'state path' ;; esac
    case "$TOKEN" in *..*|*[!A-Za-z0-9/_.-]*) fail 'state path syntax' ;; esac
}
load_token() {
    [ -r "$TOKEN" ] || fail 'missing saved state'
    IFS=' ' read -r version S21 S23 S4 < "$TOKEN" || fail 'saved state read'
    [ "$version" = k4-alarm-v1 ] && number "$S21" 1179647 && number "$S23" 32767 && number "$S4" 2 || fail 'saved state format'
    [ "$((S21 & 0x11ffff))" = "$S21" ] && [ "$((S4 & 2))" = "$S4" ] || fail 'saved field masks'
}
write_field() {
    # pmic-dev.c ignores its ioctl mask: userland must preserve the whole word.
    # Restrict writes to the two RTC alarm registers; never write IRQ masks.
    case "$1:$3" in 21:0x100000|21:0x1ffff|23:0x7fff) ;; *) fail 'non-alarm register or field' ;; esac
    field_mask=$(($3))
    [ "$(($2 & field_mask))" = "$2" ] || fail 'field value exceeds its mask'
    register_before=$(pmic sread "$1") || fail 'read before alarm update'
    number "$register_before" 16777215 || fail 'read before alarm update format'
    register_next=$(((register_before & (16777215 ^ field_mask)) | $2))
    pmic write "$1" "$register_next" >/dev/null || fail 'alarm register write'
    register_after=$(pmic sread "$1") || fail 'read after alarm update'
    [ "$register_after" = "$register_next" ] || fail 'full alarm register readback'
}

case "$MODE" in
    --status)
        read_state
        printf 'counter=%s alarm=%s disabled=%s alarm21=%s day23=%s mask4=%s software=%s\n' \
            "$NOW" "$DEADLINE" "$DISABLED" "$A21" "$A23" "$M4" "$(cat "$RTC")"
        ;;
    --check)
        read_state
        no_future_alarm || fail 'another future alarm is present'
        [ "$M4" = 0 ] || fail 'native RTC alarm interrupt is masked'
        ;;
    --save)
        token_path "$@"
        [ ! -e "$TOKEN" ] || fail 'saved state already exists'
        read_state
        no_future_alarm || fail 'another future alarm is present'
        [ "$M4" = 0 ] || fail 'native RTC alarm interrupt is masked'
        printf 'k4-alarm-v1 %s %s %s\n' "$A21" "$A23" "$M4" > "$TOKEN.new" && mv "$TOKEN.new" "$TOKEN" || fail 'saving state'
        ;;
    --claim)
        # Used for the bounded awake probe after the standard RTC scheduled +30.
        token_path "$@"; load_token; read_state
        left=$((DEADLINE-NOW))
        [ "$left" -ge 1 ] && [ "$left" -le 35 ] || fail 'probe alarm is not within its bound'
        printf '%s\n' "$DEADLINE" > "$TOKEN.owned.new" && mv "$TOKEN.owned.new" "$TOKEN.owned" || fail 'saving alarm ownership'
        ;;
    --arm)
        token_path --arm "${3:-}"
        seconds=${2:-}
        number "$seconds" 3600 && [ "$seconds" -ge 10 ] || fail 'interval range'
        load_token; read_state
        no_future_alarm || fail 'another future alarm is present'
        before=$NOW
        # Complete this short transaction before processing a cancellation signal.
        trap '' 1 2 15
        printf '%s %s %s\n' "$before" "$seconds" "$DEADLINE" > "$TOKEN.arming.new" && mv "$TOKEN.arming.new" "$TOKEN.arming" || fail 'saving arm transaction'
        rm -f "$TOKEN.owned"
        printf '%s\n' "$seconds" > "$RTC" || fail 'relative wake request'
        # Same bit as the RTC driver's RTC_AIE_ON ioctl.
        write_field 21 0 0x100000
        read_state
        [ "$DEADLINE" -ge "$((before+seconds))" ] && [ "$DEADLINE" -le "$((NOW+seconds))" ] || fail 'alarm readback'
        printf '%s\n' "$DEADLINE" > "$TOKEN.owned.new" && mv "$TOKEN.owned.new" "$TOKEN.owned" || fail 'saving alarm ownership'
        rm -f "$TOKEN.arming"
        ;;
    --restore)
        token_path "$@"; load_token
        if [ ! -r "$TOKEN.owned" ] && [ ! -r "$TOKEN.arming" ]; then exit 0; fi
        read_state
        # Never overwrite an alarm installed later by another service.
        if [ -r "$TOKEN.owned" ]; then
            read -r owned < "$TOKEN.owned" || fail 'ownership read'
            number "$owned" 2147480000 || fail 'ownership value'
            [ "$DEADLINE" = "$owned" ] || fail 'alarm ownership changed'
        else
            read -r arm_before arm_seconds prior_deadline < "$TOKEN.arming" || fail 'arm transaction read'
            number "$arm_before" 2147480000 && number "$arm_seconds" 3600 && \
                number "$prior_deadline" 2147480000 || fail 'arm transaction format'
            if [ "$DEADLINE" != "$prior_deadline" ]; then
                [ "$(cat "$RTC")" = "$arm_seconds" ] && [ "$NOW" -ge "$arm_before" ] && \
                    { [ "$NOW" -le "$((arm_before+3))" ] || \
                      { [ "$DEADLINE" -ge "$((arm_before+arm_seconds))" ] && [ "$DEADLINE" -le "$((arm_before+arm_seconds+3))" ]; }; } || fail 'incomplete arm transaction ownership'
            fi
        fi
        trap '' 1 2 15
        # Match RTC_AIE_OFF, restore saved time/day while disabled, then its mask
        # and original enable bit. Preserve the native IRQ mask without writes.
        write_field 21 1048576 0x100000
        write_field 21 "$((S21 & 0x1ffff))" 0x1ffff
        write_field 23 "$S23" 0x7fff
        write_field 21 "$((S21 & 0x100000))" 0x100000
        read_state
        [ "$A21" = "$S21" ] && [ "$A23" = "$S23" ] && [ "$M4" = "$S4" ] || fail 'restore readback'
        rm -f "$TOKEN.owned" "$TOKEN.arming"
        ;;
    *) exit 2 ;;
esac
