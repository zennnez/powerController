#!/system/bin/sh

case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=. ;;
esac
. "$MODDIR/power-data.sh"

load_config

if [ "$OVERRIDE_MODE" = "FORCE_CHARGE" ]; then
    NEW_MODE="AUTO"
    MESSAGE="Switched to Auto Control Mode"
else
    NEW_MODE="FORCE_CHARGE"
    MESSAGE="Switched to Forced Charge Mode"
fi

"$MODDIR/set-config.sh" OVERRIDE_MODE="$NEW_MODE"

echo "========================================="
echo "$MESSAGE"
echo "========================================="
