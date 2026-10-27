#!/system/bin/sh

# ==============================
# Path and Variable Definitions
# ==============================
case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=. ;;
esac
. "$MODDIR/power-data.sh"
. "$MODDIR/fast-charge.sh"

MAX_SIZE=1048576
LOG_FILE="$MODDIR/bypass.log"
BASE_DESC="Bypass charging controller with WebUI & thermal protection."

# Minimum seconds between automatic capacity-threshold charging-state flips.
# This only guards the auto crossing points (Single Mode's one limit, Dual
# Mode's upper/lower limits) - manual override, unplug, disable, and thermal
# guard all still react instantly since those need to be immediate. Without
# this, a fuel gauge reporting e.g. 90/91/90/91 right at a threshold could
# flip the charging node on/off every second, which is harder on the charge
# circuitry than a normal charge/bypass cycle.
MIN_DWELL_SECONDS=15
AUTO_LAST_CHANGE_EPOCH=0

# Degrees below MAX_TEMP the temperature must drop to before Thermal Guard
# releases bypass, so a reading sitting right at the threshold doesn't
# flicker the charging node the same way a too-narrow capacity band would.
THERMAL_HYSTERESIS=3

LAST_STATE=""
LAST_CONFIG_HASH=""
OFFLINE_FULL_CHECK_INTERVAL=300
OFFLINE_USB_CHECK_INTERVAL=10

VERSION_STR=$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2 | tr -d '\r\n ')
[ -z "$VERSION_STR" ] && VERSION_STR="v97.0"

VERSION_CODE_STR=$(grep '^versionCode=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2 | tr -d '\r\n ')
[ -z "$VERSION_CODE_STR" ] && VERSION_CODE_STR="83"

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

now_epoch() {
    date +%s 2>/dev/null || echo 0
}

# Applies an automatic capacity-threshold charging-state change, but only if
# either the config just changed (always apply instantly - the user asked
# for it) or at least MIN_DWELL_SECONDS have passed since the last automatic
# flip (chatter guard). If neither is true, it silently holds the current
# state for this tick rather than flipping.
#   $1 = node value to write (0 or 1)
#   $2 = new LAST_STATE label
#   $3 = log message
#   $4 = module.prop status text
apply_auto_transition() {
    local new_state="$1" new_label="$2" msg="$3" desc="$4"
    local nowt elapsed

    if [ "$CONFIG_CHANGED" -ne 1 ]; then
        nowt=$(now_epoch)
        elapsed=$((nowt - AUTO_LAST_CHANGE_EPOCH))
        if [ "$elapsed" -lt "$MIN_DWELL_SECONDS" ]; then
            return 0
        fi
    fi

    set_charging_state "$new_state" || log "Warning: Bypass control node write failed or unverified (wanted $new_state)."
    log "$msg"
    update_prop_desc "$desc"
    LAST_STATE="$new_label"
    AUTO_LAST_CHANGE_EPOCH=$(now_epoch)
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

if set_charging_state 1; then
    log "Safety fallback executed: Default charging enabled."
else
    log "Error: Failed to write bypass control node ($BYPASS_NODE). Module cannot control charging."
fi

if [ ! -f "$CONFIG_FILE" ]; then
    {
        echo "MODE=SINGLE"
        echo "CHARGE_LIMIT=$DEFAULT_CHARGE_LIMIT"
        echo "UPPER_LIMIT=$DEFAULT_UPPER_LIMIT"
        echo "LOWER_LIMIT=$DEFAULT_LOWER_LIMIT"
        echo "THERMAL_GUARD=1"
        echo "MAX_TEMP=$DEFAULT_MAX_TEMP"
        echo "OVERRIDE_MODE=AUTO"
        echo "FAST_CHARGE=$DEFAULT_FAST_CHARGE"
        echo "SMART_POWER=$DEFAULT_SMART_POWER"
    } > "$CONFIG_FILE"
    log "Config file missing. Auto-generated config.txt with default values."
fi

load_power_data
update_prop_desc "🥳 Initialized"
LAST_CONFIG_HASH="${MODE}_${CHARGE_LIMIT}_${UPPER_LIMIT}_${LOWER_LIMIT}_${THERMAL_GUARD}_${MAX_TEMP}_${OVERRIDE_MODE}_${FAST_CHARGE}"

log "Module $VERSION_STR (code $VERSION_CODE_STR) started. Config: MODE=$MODE CHARGE_LIMIT=$CHARGE_LIMIT UPPER_LIMIT=$UPPER_LIMIT LOWER_LIMIT=$LOWER_LIMIT THERMAL_GUARD=$THERMAL_GUARD MAX_TEMP=$MAX_TEMP OVERRIDE_MODE=$OVERRIDE_MODE FAST_CHARGE=$FAST_CHARGE SMART_POWER=$SMART_POWER NODE_WRITABLE=$NODE_WRITABLE"

# FastChargeToggle.apk runs /data/local/tmp/toggle_fast_charge.sh; point it at this module.
printf '#!/system/bin/sh\nexec sh "%s/toggle-fast-charge.sh"\n' "$MODDIR" > /data/local/tmp/toggle_fast_charge.sh 2>/dev/null
chmod 755 /data/local/tmp/toggle_fast_charge.sh 2>/dev/null

# Smart power daemon (exits immediately when SMART_POWER=0).
nohup sh "$MODDIR/smart-power.sh" >/dev/null 2>&1 &

# Seed LAST_STATE from the real node value we just confirmed above, instead of
# leaving it blank. Without this, Dual Mode's hysteresis logic had a bug: if the
# battery booted sitting between LOWER_LIMIT and UPPER_LIMIT (e.g. 85% with a
# 78/91 band), the very first loop iteration had no history to go on and always
# fell through to "activate bypass", even though we had just enabled charging
# one line above. That caused an immediate, pointless bypass->charge->bypass
# relay click and cut off charging that should have continued up to the upper
# limit. Seeding from the real post-fallback state fixes that.
case "$BYPASS_ENABLED" in
    0) LAST_STATE="BYPASS_ON" ;;
    1) LAST_STATE="CHARGING" ;;
    *) LAST_STATE="" ;;
esac

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
            echo "FAST_CHARGE=$DEFAULT_FAST_CHARGE"
            echo "SMART_POWER=$DEFAULT_SMART_POWER"
        } > "$CONFIG_FILE"
        log "Config file missing. Auto-generated config.txt with default values."
    fi

    load_power_data

    CURRENT_CONFIG_HASH="${MODE}_${CHARGE_LIMIT}_${UPPER_LIMIT}_${LOWER_LIMIT}_${THERMAL_GUARD}_${MAX_TEMP}_${OVERRIDE_MODE}_${FAST_CHARGE}"
    CONFIG_CHANGED=0
    if [ "$CURRENT_CONFIG_HASH" != "$LAST_CONFIG_HASH" ]; then
        CONFIG_CHANGED=1
        LAST_CONFIG_HASH="$CURRENT_CONFIG_HASH"
    fi

    if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
        if [ "$LAST_STATE" != "DISABLED" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
            set_charging_state 1 || log "Warning: Bypass control node write failed or unverified (wanted 1)."
            log "Module disabled or marked for removal. Reverting to standard charging."
            fast_charge_reset
            update_prop_desc "🔴 Module Disabled"
            LAST_STATE="DISABLED"
        fi
    elif [ "$USB_ONLINE" != "1" ]; then
        if [ "$LAST_STATE" != "UNPLUGGED" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
            set_charging_state 1 || log "Warning: Bypass control node write failed or unverified (wanted 1)."
            log "Charger unplugged (Battery $CAPACITY%). Resetting node to charging state."
            fast_charge_reset
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
            if [ "$LAST_STATE" != "FORCE_BYPASS" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
                set_charging_state 0 || log "Warning: Bypass control node write failed or unverified (wanted 0)."
                log "Manual override active: Forced Bypass Power Supply ON."
                update_prop_desc "⚡ Forced Bypass ON"
                LAST_STATE="FORCE_BYPASS"
            fi
        elif [ "$OVERRIDE_MODE" = "FORCE_CHARGE" ]; then
            if [ "$LAST_STATE" != "FORCE_CHARGE" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
                set_charging_state 1 || log "Warning: Bypass control node write failed or unverified (wanted 1)."
                log "Manual override active: Forced Charging ON."
                update_prop_desc "🟢 Forced Charge ON"
                LAST_STATE="FORCE_CHARGE"
            fi
        else
            # 2. Thermal Guard Safety Evaluation
            TEMP_C=$(get_temp_celsius "$TEMPERATURE")
            # Once guard is active, require the temp to drop THERMAL_HYSTERESIS
            # degrees below MAX_TEMP before releasing, instead of the exact same
            # value it tripped at - avoids flicker for a reading sitting right
            # on the boundary.
            if [ "$LAST_STATE" = "THERMAL_GUARD_ACTIVE" ]; then
                THERMAL_RELEASE_POINT=$((MAX_TEMP - THERMAL_HYSTERESIS))
            else
                THERMAL_RELEASE_POINT=$MAX_TEMP
            fi
            if [ "$THERMAL_GUARD" = "1" ] && [ "$TEMP_C" -ge "$THERMAL_RELEASE_POINT" ]; then
                if [ "$LAST_STATE" != "THERMAL_GUARD_ACTIVE" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
                    set_charging_state 0 || log "Warning: Bypass control node write failed or unverified (wanted 0)."
                    log "Thermal Guard triggered: Battery Temp ${TEMP_C}°C >= ${MAX_TEMP}°C limit! Forcing bypass mode."
                    update_prop_desc "🛡️ Thermal Guard Active (${TEMP_C}°C)"
                    LAST_STATE="THERMAL_GUARD_ACTIVE"
                fi
            elif ! is_percentage "$CAPACITY"; then
                # 3. Sensor Sanity Check
                # CAPACITY came back unreadable/garbage (e.g. "N/A" or a glitched
                # read). Previously this fell straight into the numeric -ge/-le
                # comparisons below, which is undefined behavior on a bad string
                # and could silently misfire the charging state off a bad read.
                # Instead: leave the charging node exactly as it is this tick
                # (do nothing) and just log it, rate-limited to once per
                # transition so a flaky sensor doesn't spam the log.
                if [ "$LAST_STATE" != "SENSOR_ERROR" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
                    log "Warning: Battery capacity unreadable ('$CAPACITY'). Holding current charging state until sensor recovers."
                    update_prop_desc "⚠️ Sensor Error (holding state)"
                    LAST_STATE="SENSOR_ERROR"
                fi
            else
                # 4. Normal Automated Control Logic
                if [ "$MODE" = "DUAL" ]; then
                    # Dual Threshold Hysteresis Mode
                    if [ "$CAPACITY" -ge "$UPPER_LIMIT" ]; then
                        if [ "$LAST_STATE" != "BYPASS_ON" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
                            apply_auto_transition 0 "BYPASS_ON" \
                                "[Dual Mode] Battery reached $CAPACITY% (>= upper limit $UPPER_LIMIT%). Activating bypass." \
                                "⚡ Bypass Active ($CAPACITY% >= $UPPER_LIMIT%)"
                        fi
                    elif [ "$CAPACITY" -le "$LOWER_LIMIT" ]; then
                        if [ "$LAST_STATE" != "CHARGING" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
                            apply_auto_transition 1 "CHARGING" \
                                "[Dual Mode] Battery dropped to $CAPACITY% (<= lower limit $LOWER_LIMIT%). Resuming charging." \
                                "🟢 Normal Charging ($CAPACITY% <= $LOWER_LIMIT%)"
                        fi
                    else
                        # Capacity is between LOWER_LIMIT and UPPER_LIMIT (e.g. 78% < 90% < 91%)
                        if [ "$LAST_STATE" = "CHARGING" ] || [ "$LAST_STATE" = "WAITING_UP" ]; then
                            if [ "$LAST_STATE" != "WAITING_UP" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
                                set_charging_state 1 || log "Warning: Bypass control node write failed or unverified (wanted 1)."
                                log "[Dual Mode] Battery is $CAPACITY%. Continuing charging until upper limit $UPPER_LIMIT%."
                                update_prop_desc "🟢 Charging Active (Waiting for $UPPER_LIMIT%)"
                                LAST_STATE="WAITING_UP"
                            fi
                        else
                            # Default to Bypass ON if plugged in above lower limit or coming down
                            if [ "$LAST_STATE" != "WAITING_DOWN" ] && [ "$LAST_STATE" != "BYPASS_ON" ]; then
                                set_charging_state 0 || log "Warning: Bypass control node write failed or unverified (wanted 0)."
                                log "[Dual Mode] Battery is $CAPACITY% (> lower limit $LOWER_LIMIT%). Activating bypass until capacity drops to $LOWER_LIMIT%."
                                update_prop_desc "⚡ Bypass Active (Waiting for $LOWER_LIMIT%)"
                                LAST_STATE="WAITING_DOWN"
                            elif [ "$LAST_STATE" != "WAITING_DOWN" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
                                set_charging_state 0 || log "Warning: Bypass control node write failed or unverified (wanted 0)."
                                log "[Dual Mode] Battery is $CAPACITY%. Holding bypass until capacity drops to $LOWER_LIMIT%."
                                update_prop_desc "⚡ Bypass Active (Waiting for $LOWER_LIMIT%)"
                                LAST_STATE="WAITING_DOWN"
                            fi
                        fi
                    fi
                else
                    # Single Charge Limit Mode
                    if [ "$CAPACITY" -ge "$CHARGE_LIMIT" ]; then
                        if [ "$LAST_STATE" != "BYPASS_ON" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
                            apply_auto_transition 0 "BYPASS_ON" \
                                "[Single Mode] Battery reached $CAPACITY% (>= limit $CHARGE_LIMIT%). Activating bypass." \
                                "⚡ Bypass Active ($CAPACITY% >= $CHARGE_LIMIT%)"
                        fi
                    else
                        if [ "$LAST_STATE" != "CHARGING" ] || [ "$CONFIG_CHANGED" -eq 1 ]; then
                            apply_auto_transition 1 "CHARGING" \
                                "[Single Mode] Battery is $CAPACITY% (< limit $CHARGE_LIMIT%). Standard charging allowed." \
                                "🟢 Normal Charging ($CAPACITY% < $CHARGE_LIMIT%)"
                        fi
                    fi
                fi
            fi
        fi
    fi
    
    # Fast-charge thermal tiering (plugged in and module enabled only; the
    # unplugged branch above `continue`s before reaching here).
    if [ "$LAST_STATE" != "DISABLED" ]; then
        fast_charge_tick
    fi

    if [ -f "$LOG_FILE" ]; then
        FILE_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
            : > "$LOG_FILE"
            log "Log size exceeded 1MB. Auto-cleared log file."
        fi
    fi
    
    sleep 1
done