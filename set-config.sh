#!/system/bin/sh

case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=. ;;
esac
. "$MODDIR/power-data.sh"

CHARGE_LIMIT="$1"

if ! is_percentage "$CHARGE_LIMIT"; then
    echo "Charge limit must be an integer between 0 and 100" >&2
    exit 2
fi

TMP_FILE="$CONFIG_FILE.tmp.$$"
umask 022
if ! {
    printf 'CHARGE_LIMIT=%s\n' "$CHARGE_LIMIT"
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

echo "Configuration saved. Will apply within 1s when charger is connected."
