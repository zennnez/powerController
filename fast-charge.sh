#!/system/bin/sh
# Fast-charge thermal tiering, ported from OnePlus-Pad-90W-Smart-Charge.
# Sourced by service.sh, which provides log(), now_epoch() and get_temp_celsius().
# Reads FAST_CHARGE (OFF|SMART|MAX), BATTERY_STATUS and TEMPERATURE from power-data.sh.
#
#   SMART: <42C cool_down 0 (full output) | 42-45C level 1 (balanced) | >=45C level 3 (fallback)
#   MAX:   <45C cool_down 0 (no screen-on throttle) | >=45C level 2 (back off)
#   Thermal Guard (default 46C, service.sh) cuts charging entirely above both.
#   OFF:   this module never touches cool_down or the charge settings.
#
# Only acts while the battery reports "Charging", so it stays out of the way
# whenever bypass is active. cool_down is returned to 0 the first tick after
# charging stops, matching the original module.

FC_DIRTY=0
FC_LAST_LEVEL=""
FC_LAST_DESC=""
FC_LAST_SETTINGS_EPOCH=0
FC_SETTINGS_INTERVAL=30

fc_set_state() {
    [ "$1" = "$FC_LAST_DESC" ] && return 0
    FC_LAST_DESC="$1"
    printf '%s' "$1" > "$FAST_CHARGE_STATE_FILE" 2>/dev/null
}

fc_set_cool_down() {
    [ -w "$COOL_DOWN_NODE" ] && echo "$1" > "$COOL_DOWN_NODE" 2>/dev/null
    [ -w "$COOL_DOWN_NODE_ALT" ] && echo "$1" > "$COOL_DOWN_NODE_ALT" 2>/dev/null
    return 0
}

# Keep the QS-tile flag file in step with config.txt (covers manual edits).
fc_sync_flag() {
    if [ "$FAST_CHARGE" = "MAX" ]; then
        [ -f "$FAST_CHARGE_FLAG" ] || touch "$FAST_CHARGE_FLAG" 2>/dev/null
    else
        [ -f "$FAST_CHARGE_FLAG" ] && rm -f "$FAST_CHARGE_FLAG" 2>/dev/null
    fi
    return 0
}

fast_charge_reset() {
    if [ "$FC_DIRTY" = "1" ]; then
        fc_set_cool_down 0
        FC_DIRTY=0
        FC_LAST_LEVEL=""
        log "Fast charge: charging stopped or disabled, cool_down reset to 0."
    fi
    if [ "$FAST_CHARGE" = "OFF" ]; then
        fc_set_state "Disabled"
    else
        fc_set_state "Idle (not charging)"
    fi
}

fast_charge_tick() {
    local temp_c level desc nowt

    fc_sync_flag

    if [ "$FAST_CHARGE" = "OFF" ] || [ "$BATTERY_STATUS" != "Charging" ]; then
        fast_charge_reset
        return 0
    fi

    # Unreadable temperature: hold whatever is applied rather than guess.
    case "$TEMPERATURE" in
        ''|N/A|*[!0-9]*)
            fc_set_state "Temperature unreadable (holding)"
            return 0
            ;;
    esac
    temp_c=$(get_temp_celsius "$TEMPERATURE")

    if [ "$FAST_CHARGE" = "MAX" ]; then
        if [ "$temp_c" -lt 45 ]; then
            level=0; desc="Max fast charge (screen-on throttle removed)"
        else
            level=2; desc="Max mode back-off (>= 45C)"
        fi
    else
        if [ "$temp_c" -lt 42 ]; then
            level=0; desc="Smart fast charge (full output)"
        elif [ "$temp_c" -lt 45 ]; then
            level=1; desc="Smart fast charge (balanced, ~50W)"
        else
            level=3; desc="Smart fast charge (heat fallback)"
        fi
    fi

    # cool_down is a plain sysfs write, so re-assert it every tick in case
    # ColorOS resets it on screen-on.
    fc_set_cool_down "$level"
    FC_DIRTY=1
    fc_set_state "$desc"

    if [ "$level" != "$FC_LAST_LEVEL" ]; then
        log "Fast charge [$FAST_CHARGE]: ${temp_c}C -> cool_down $level ($desc)."
        FC_LAST_LEVEL="$level"
    fi

    # `settings put` is slow; apply on change and then only every 30s, in the background.
    nowt=$(now_epoch)
    if [ "$FC_LAST_SETTINGS_EPOCH" -eq 0 ] || [ $((nowt - FC_LAST_SETTINGS_EPOCH)) -ge "$FC_SETTINGS_INTERVAL" ]; then
        FC_LAST_SETTINGS_EPOCH=$nowt
        (
            settings put system single_speed_charge_state 1
            settings put system smart_charge_switch_state 0
            settings put system charge_protection_current_state 0
        ) >/dev/null 2>&1 &
    fi
}
