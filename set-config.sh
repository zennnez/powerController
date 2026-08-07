#!/system/bin/sh

case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=. ;;
esac
. "$MODDIR/power-data.sh"

load_config

for arg in "$@"; do
    case "$arg" in
        MODE=*) MODE="${arg#*=}" ;;
        CHARGE_LIMIT=*) CHARGE_LIMIT="${arg#*=}" ;;
        UPPER_LIMIT=*) UPPER_LIMIT="${arg#*=}" ;;
        LOWER_LIMIT=*) LOWER_LIMIT="${arg#*=}" ;;
        THERMAL_GUARD=*) THERMAL_GUARD="${arg#*=}" ;;
        MAX_TEMP=*) MAX_TEMP="${arg#*=}" ;;
        OVERRIDE_MODE=*) OVERRIDE_MODE="${arg#*=}" ;;
        [0-9]*)
            CHARGE_LIMIT="$arg"
            ;;
    esac
done

[ "$MODE" != "DUAL" ] && MODE="SINGLE"
! is_percentage "$CHARGE_LIMIT" && CHARGE_LIMIT=$DEFAULT_CHARGE_LIMIT
! is_percentage "$UPPER_LIMIT" && UPPER_LIMIT=$DEFAULT_UPPER_LIMIT
! is_percentage "$LOWER_LIMIT" && LOWER_LIMIT=$DEFAULT_LOWER_LIMIT

# Shared with load_config() in power-data.sh so the same minimum-band-gap
# rule applies whether the config comes from the WebUI, a CLI arg, or a
# manually edited config.txt.
normalize_dual_limits

[ "$THERMAL_GUARD" != "0" ] && THERMAL_GUARD="1"
(! is_number "$MAX_TEMP" || [ "$MAX_TEMP" -lt 25 ] || [ "$MAX_TEMP" -gt 60 ]) && MAX_TEMP=$DEFAULT_MAX_TEMP

case "$OVERRIDE_MODE" in
    FORCE_BYPASS|FORCE_CHARGE) ;;
    *) OVERRIDE_MODE="AUTO" ;;
esac

TMP_FILE="$CONFIG_FILE.tmp.$$"
umask 022
if ! {
    printf 'MODE=%s\n' "$MODE"
    printf 'CHARGE_LIMIT=%s\n' "$CHARGE_LIMIT"
    printf 'UPPER_LIMIT=%s\n' "$UPPER_LIMIT"
    printf 'LOWER_LIMIT=%s\n' "$LOWER_LIMIT"
    printf 'THERMAL_GUARD=%s\n' "$THERMAL_GUARD"
    printf 'MAX_TEMP=%s\n' "$MAX_TEMP"
    printf 'OVERRIDE_MODE=%s\n' "$OVERRIDE_MODE"
} > "$TMP_FILE"; then
    echo "Failed to write temporary configuration file" >&2
    rm -f "$TMP_FILE"
    exit 1
fi

if ! mv -f "$TMP_FILE" "$CONFIG_FILE"; then
    echo "Failed to update configuration file" >&2
    rm -f "$TMP_FILE"
    exit 1
fi

echo "Configuration updated successfully."
