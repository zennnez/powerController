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
! is_percentage "$CHARGE_LIMIT" && CHARGE_LIMIT=91
! is_percentage "$UPPER_LIMIT" && UPPER_LIMIT=91
! is_percentage "$LOWER_LIMIT" && LOWER_LIMIT=78

if [ "$MODE" = "DUAL" ]; then
    if [ "$UPPER_LIMIT" -le "$LOWER_LIMIT" ]; then
        if [ "$UPPER_LIMIT" -gt 5 ]; then
            LOWER_LIMIT=$((UPPER_LIMIT - 5))
        else
            UPPER_LIMIT=91
            LOWER_LIMIT=78
        fi
    fi
fi

[ "$THERMAL_GUARD" != "0" ] && THERMAL_GUARD="1"
(! is_number "$MAX_TEMP" || [ "$MAX_TEMP" -lt 25 ] || [ "$MAX_TEMP" -gt 60 ]) && MAX_TEMP=43

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
