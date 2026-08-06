#!/system/bin/sh

case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=. ;;
esac

LOG_FILE="$MODDIR/bypass.log"

if [ -f "$LOG_FILE" ]; then
    tail -n 100 "$LOG_FILE"
else
    echo "No log history available."
fi
