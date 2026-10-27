#!/system/bin/sh
# Flips FAST_CHARGE between MAX and SMART. Called by FastChargeToggle.apk
# through the /data/local/tmp/toggle_fast_charge.sh wrapper that service.sh
# writes at boot. The first stdout line is shown as the app's toast.

case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=. ;;
esac
. "$MODDIR/power-data.sh"

load_config

if [ "$FAST_CHARGE" = "MAX" ]; then
    sh "$MODDIR/set-config.sh" FAST_CHARGE=SMART >/dev/null 2>&1
    echo "Smart thermal control restored - Max fast charge OFF"
else
    sh "$MODDIR/set-config.sh" FAST_CHARGE=MAX >/dev/null 2>&1
    echo "Max fast charge ON - screen-on throttling removed"
fi
