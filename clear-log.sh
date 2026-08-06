#!/system/bin/sh

case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=. ;;
esac

LOG_FILE="$MODDIR/bypass.log"
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')

: > "$LOG_FILE"
echo "[$CURRENT_TIME] Log cleared by user via WebUI." >> "$LOG_FILE"
echo "Log cleared successfully."
