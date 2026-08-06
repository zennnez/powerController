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
BASE_DESC="Bypass charging controller with WebUI & thermal protection."

LAST_STATE=""
OFFLINE_FULL_CHECK_INTERVAL=300
OFFLINE_USB_CHECK_INTERVAL=10

VERSION_STR=$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2 | tr -d '\r\n ')
[ -z "$VERSION_STR" ] && VERSION_STR="v94.0"

VERSION_CODE_STR=$(grep '^versionCode=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2 | tr -d '\r\n ')
[ -z "$VERSION_CODE_STR" ] && VERSION_CODE_STR="80"

# ==============================
# Helper Functions
# ==============================
log() {
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$CURRENT_TIME] $1" >> "$LOG_FILE"
}

update_prop_desc() {
    local status_text="$1"

    local mode_desc=""
    if [ "$MODE" = "DUAL" ]; then
        mode_desc="Mode: Dual Hysteresis ($UPPER_LIMIT% / $LOWER_LIMIT%)"
    else
        mode_desc="Mode: Single Limit ($CHARGE_LIMIT%)"
    fi

    local thermal_desc=""
    if [ "$THERMAL_GUARD" = "1" ]; then
        thermal_desc="Thermal Guard: Enabled (${MAX_TEMP}°C)"
    else
        thermal_desc="Thermal Guard: Disabled"
    fi

    local override_desc="Override: $OVERRIDE_MODE"
    local settings_summary="$mode_desc | $thermal_desc | $override_desc"

    local tmp_prop="$MODDIR/module.prop.tmp.$$"
    {
        printf 'id=oplusPowerController\n'
        printf 'name=OnePlus / OPPO Bypass Charging Controller\n'
        printf 'version=%s\n' "$VERSION_STR"
        printf 'versionCode=%s\n' "$VERSION_CODE_STR"
        printf 'author=wind1, zen\n'
        printf 'description=[Status: %s] \\n%s \\n%s\n' "$status_text" "$settings_summary" "$BASE_DESC"
    } > "$tmp_prop" && mv -f "$tmp_prop" "$MODDIR/module.prop"
}

get_temp_celsius() {
    local raw="$1"
    case "$raw" in
        ''|N/A|*[!0-9]*) echo 0; return ;;
    esac
    if [ "$raw" -ge 200 ]; then
        echo $((raw / 10))
    else
        echo "$raw"
    fi
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

if [ ! -f "$CONFIG_FILE" ]; then
    {
        echo "MODE=SINGLE"
        echo "CHARGE_LIMIT=$DEFAULT_CHARGE_LIMIT"
        echo "UPPER_LIMIT=$DEFAULT_UPPER_LIMIT"
        echo "LOWER_LIMIT=$DEFAULT_LOWER_LIMIT"
        echo "THERMAL_GUARD=1"
        echo "MAX_TEMP=$DEFAULT_MAX_TEMP"
        echo "OVERRIDE_MODE=AUTO"
    } > "$CONFIG_FILE"
    log "Config file missing. Auto-generated config.txt with default values."
fi

load_power_data
update_prop_desc "🥳 Initialized"

# ==============================
# Main Daemon Loop
# ==============================
while true; do

    if [ ! -f "$CONFIG_FILE" ]; then
        {
            echo "MODE=SINGLE"
            echo "CHARGE_LIMIT=$DEFAULT_CHARGE_LIMIT"
            echo "UPPER_LIMIT=$DEFAULT_UPPER_LIMIT"
            echo "LOWER_LIMIT=$DEFAULT_LOWER_LIMIT"
            echo "THERMAL_GUARD=1"
            echo "MAX_TEMP=$DEFAULT_MAX_TEMP"
            echo "OVERRIDE_MODE=AUTO"
        } > "$CONFIG_FILE"
        log "Config file missing. Auto-generated config.txt with default values."
    fi

    load_power_data

    if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
        if [ "$LAST_STATE" != "DISABLED" ]; then
            echo 1 > "$BYPASS_NODE"
            log "Module disabled or marked for removal. Reverting to standard charging."
            update_prop_desc "🔴 Module Disabled"
            LAST_STATE="DISABLED"
        fi
    elif [ "$USB_ONLINE" != "1" ]; then
        if [ "$LAST_STATE" != "UNPLUGGED" ]; then
            echo 1 > "$BYPASS_NODE"
            log "Charger unplugged (Battery $CAPACITY%). Resetting node to charging state."
            update_prop_desc "💤 Unplugged"
            LAST_STATE="UNPLUGGED"
        fi

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
        # 1. Manual Override Evaluation
        if [ "$OVERRIDE_MODE" = "FORCE_BYPASS" ]; then
            if [ "$LAST_STATE" != "FORCE_BYPASS" ]; then
                echo 0 > "$BYPASS_NODE"
                log "Manual override active: Forced Bypass Power Supply ON."
                update_prop_desc "⚡ Forced Bypass ON"
                LAST_STATE="FORCE_BYPASS"
            fi
        elif [ "$OVERRIDE_MODE" = "FORCE_CHARGE" ]; then
            if [ "$LAST_STATE" != "FORCE_CHARGE" ]; then
                echo 1 > "$BYPASS_NODE"
                log "Manual override active: Forced Charging ON."
                update_prop_desc "🟢 Forced Charge ON"
                LAST_STATE="FORCE_CHARGE"
            fi
        else
            # 2. Thermal Guard Safety Evaluation
            TEMP_C=$(get_temp_celsius "$TEMPERATURE")
            if [ "$THERMAL_GUARD" = "1" ] && [ "$TEMP_C" -ge "$MAX_TEMP" ]; then
                if [ "$LAST_STATE" != "THERMAL_GUARD_ACTIVE" ]; then
                    echo 0 > "$BYPASS_NODE"
                    log "Thermal Guard triggered: Battery Temp ${TEMP_C}°C >= ${MAX_TEMP}°C limit! Forcing bypass mode."
                    update_prop_desc "🛡️ Thermal Guard Active (${TEMP_C}°C)"
                    LAST_STATE="THERMAL_GUARD_ACTIVE"
                fi
            else
                # 3. Normal Automated Control Logic
                if [ "$MODE" = "DUAL" ]; then
                    # Dual Threshold Hysteresis Mode
                    if [ "$CAPACITY" -ge "$UPPER_LIMIT" ]; then
                        if [ "$LAST_STATE" != "BYPASS_ON" ]; then
                            echo 0 > "$BYPASS_NODE"
                            log "[Dual Mode] Battery reached $CAPACITY% (>= upper limit $UPPER_LIMIT%). Activating bypass."
                            update_prop_desc "⚡ Bypass Active ($CAPACITY% >= $UPPER_LIMIT%)"
                            LAST_STATE="BYPASS_ON"
                        fi
                    elif [ "$CAPACITY" -le "$LOWER_LIMIT" ]; then
                        if [ "$LAST_STATE" != "CHARGING" ]; then
                            echo 1 > "$BYPASS_NODE"
                            log "[Dual Mode] Battery dropped to $CAPACITY% (<= lower limit $LOWER_LIMIT%). Resuming charging."
                            update_prop_desc "🟢 Normal Charging ($CAPACITY% <= $LOWER_LIMIT%)"
                            LAST_STATE="CHARGING"
                        fi
                    else
                        # Capacity is between LOWER_LIMIT and UPPER_LIMIT (e.g. 78% < 90% < 91%)
                        if [ "$LAST_STATE" = "CHARGING" ] || [ "$LAST_STATE" = "WAITING_UP" ]; then
                            if [ "$LAST_STATE" != "WAITING_UP" ]; then
                                log "[Dual Mode] Battery is $CAPACITY%. Continuing charging until upper limit $UPPER_LIMIT%."
                                update_prop_desc "🟢 Charging Active (Waiting for $UPPER_LIMIT%)"
                                LAST_STATE="WAITING_UP"
                            fi
                        else
                            # Default to Bypass ON if plugged in above lower limit or coming down
                            if [ "$LAST_STATE" != "WAITING_DOWN" ] && [ "$LAST_STATE" != "BYPASS_ON" ]; then
                                echo 0 > "$BYPASS_NODE"
                                log "[Dual Mode] Battery is $CAPACITY% (> lower limit $LOWER_LIMIT%). Activating bypass until capacity drops to $LOWER_LIMIT%."
                                update_prop_desc "⚡ Bypass Active (Waiting for $LOWER_LIMIT%)"
                                LAST_STATE="WAITING_DOWN"
                            elif [ "$LAST_STATE" != "WAITING_DOWN" ]; then
                                log "[Dual Mode] Battery is $CAPACITY%. Holding bypass until capacity drops to $LOWER_LIMIT%."
                                update_prop_desc "⚡ Bypass Active (Waiting for $LOWER_LIMIT%)"
                                LAST_STATE="WAITING_DOWN"
                            fi
                        fi
                    fi
                else
                    # Single Charge Limit Mode
                    if [ "$CAPACITY" -ge "$CHARGE_LIMIT" ]; then
                        if [ "$LAST_STATE" != "BYPASS_ON" ]; then
                            echo 0 > "$BYPASS_NODE"
                            log "[Single Mode] Battery reached $CAPACITY% (>= limit $CHARGE_LIMIT%). Activating bypass."
                            update_prop_desc "⚡ Bypass Active ($CAPACITY% >= $CHARGE_LIMIT%)"
                            LAST_STATE="BYPASS_ON"
                        fi
                    else
                        if [ "$LAST_STATE" != "CHARGING" ]; then
                            echo 1 > "$BYPASS_NODE"
                            log "[Single Mode] Battery is $CAPACITY% (< limit $CHARGE_LIMIT%). Standard charging allowed."
                            update_prop_desc "🟢 Normal Charging ($CAPACITY% < $CHARGE_LIMIT%)"
                            LAST_STATE="CHARGING"
                        fi
                    fi
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