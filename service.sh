#!/system/bin/sh

# ==============================
# Path and Variable Definitions
# ==============================
case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=. ;;
esac
. "$MODDIR/power-data.sh"

MAX_SIZE=1048576
LOG_FILE="$MODDIR/bypass.log"
BASE_DESC="Compatible with OnePlus Pad 2 Pro and OPlus devices. Forces bypass charging when battery level reaches limit. Configurable via WebUI or /data/adb/modules/oplusPowerController/config.txt."

LAST_STATE=""
OFFLINE_FULL_CHECK_INTERVAL=300
OFFLINE_USB_CHECK_INTERVAL=10

# ==============================
# Helper Functions
# ==============================
log() {
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$CURRENT_TIME] $1" >> "$LOG_FILE"
}

update_prop_desc() {
    local status_text="$1"
    sed -i "s|^description=.*|description=[$status_text] $BASE_DESC|g" "$MODDIR/module.prop"
}

# ==============================
# Initialization & Boot Wait
# ==============================
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done

echo "=== OPPO/OnePlus Bypass Charging Controller Started ===" >> "$LOG_FILE"
log "System boot completed. Checking power supply nodes..."

if ! required_power_nodes_available; then
    log "Error: Required power supply nodes missing! Module stopping."
    update_prop_desc "❌ Device Unsupported"
    exit 1
fi

echo 1 > "$BYPASS_NODE"
log "Safety fallback executed: Default charging enabled."
update_prop_desc "🥳 Initialized"

# ==============================
# Main Daemon Loop
# ==============================
while true; do

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "CHARGE_LIMIT=$DEFAULT_CHARGE_LIMIT" > "$CONFIG_FILE"
        log "Config file missing. Auto-generated config.txt with default charge limit 91%."
    fi

    load_power_data

    if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
        if [ "$LAST_STATE" != "DISABLED" ]; then
            echo 1 > "$BYPASS_NODE"
            log "Module disabled or marked for removal. Reverting to standard charging."
            update_prop_desc "🔴 Module Disabled"
            LAST_STATE="DISABLED"
        fi
    else
        if [ "$USB_ONLINE" != "1" ]; then
            if [ "$LAST_STATE" != "UNPLUGGED" ]; then
                echo 1 > "$BYPASS_NODE"
                log "Charger unplugged (Battery $CAPACITY%). Resetting node to charging state."
                update_prop_desc "💤 Unplugged"
                LAST_STATE="UNPLUGGED"
            fi

            # Poll USB online node every 10s while unplugged. Full battery/config check every 300s.
            OFFLINE_WAITED=0
            while [ "$OFFLINE_WAITED" -lt "$OFFLINE_FULL_CHECK_INTERVAL" ]; do
                sleep "$OFFLINE_USB_CHECK_INTERVAL"
                USB_ONLINE=$(read_node "$USB_ONLINE_NODE")
                if [ "$USB_ONLINE" = "1" ]; then
                    log "Charger plugged in. Resuming 1-second charging control loop."
                    break
                fi
                OFFLINE_WAITED=$((OFFLINE_WAITED + OFFLINE_USB_CHECK_INTERVAL))
            done
            continue
        else
            if [ "$CAPACITY" -ge "$CHARGE_LIMIT" ]; then
                if [ "$LAST_STATE" != "BYPASS_ON" ]; then
                    echo 0 > "$BYPASS_NODE"
                    log "Battery level reached $CAPACITY% (>= limit $CHARGE_LIMIT%). Activating bypass power supply."
                    update_prop_desc "⚡ Bypass Active ($CAPACITY% >= $CHARGE_LIMIT%)"
                    LAST_STATE="BYPASS_ON"
                fi
            else
                if [ "$LAST_STATE" != "CHARGING" ]; then
                    echo 1 > "$BYPASS_NODE"
                    log "Battery level is $CAPACITY% (< limit $CHARGE_LIMIT%). Standard charging allowed."
                    update_prop_desc "🟢 Normal Charging ($CAPACITY% < $CHARGE_LIMIT%)"
                    LAST_STATE="CHARGING"
                fi
            fi
        fi
    fi
    
    if [ -f "$LOG_FILE" ]; then
        FILE_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
            : > "$LOG_FILE"
            log "Log size exceeded 1MB. Auto-cleared log file." > "$LOG_FILE"
        fi
    fi
    
    sleep 1
done