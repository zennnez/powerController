#!/system/bin/sh
# Fast-charge control, ported from OnePlus-Pad-90W-Smart-Charge.
# Sourced by service.sh, which provides log(), now_epoch() and get_temp_celsius().
# Reads FAST_CHARGE (OFF|SMART|MAX), BATTERY_STATUS, TEMPERATURE, WATTAGE and
# RATED_EFFECTIVE (rated charge power in W: manual or detected) from power-data.sh.
#
#   SMART: target power is a share of the rated power, by battery temperature:
#            <42C  100% (cool_down 0, full output)
#            42-45C FC_PCT_WARM % | >=45C FC_PCT_HOT %
#          cool_down is stepped (0..FC_MAX_LEVEL) every FC_ADJUST_SECONDS until the
#          measured charge power is near the target. With no rating known yet it
#          falls back to fixed levels: 42-45C -> 1, >=45C -> 3.
#   MAX:   <45C cool_down 0 (no screen-on throttle) | >=45C level 2 (back off)
#   OFF:   this module never touches cool_down or the charge settings.
#
# Thermal Guard (default 46C, service.sh) cuts charging entirely above all of these.
# Only acts while the battery reports "Charging", so it stays out of the way
# whenever bypass is active. cool_down returns to 0 the first tick after charging stops.
# Assumes a higher cool_down level means more throttling (levels 0-3, as the
# original module used).

FC_PCT_WARM=60
FC_PCT_HOT=35
FC_MAX_LEVEL=3
FC_ADJUST_SECONDS=5

FC_BAND=""
FC_LEVEL=0
FC_LAST_ADJ=0
FC_OUT_LEVEL=0
FC_OUT_DESC=""
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
    FC_BAND=""
    FC_LEVEL=0
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

# Sets FC_OUT_LEVEL / FC_OUT_DESC for SMART mode at integer temperature $1.
fc_smart_level() {
    local t="$1" band base pct target meas nowt

    if [ "$t" -lt 42 ]; then
        FC_BAND=0; FC_LEVEL=0
        FC_OUT_LEVEL=0; FC_OUT_DESC="Smart fast charge (full output)"
        return 0
    elif [ "$t" -lt 45 ]; then
        band=1; base=1; pct=$FC_PCT_WARM
    else
        band=2; base=3; pct=$FC_PCT_HOT
    fi

    case "$RATED_EFFECTIVE" in
        ''|N/A|*[!0-9]*)
            # No rating yet (nothing detected, none set): fixed levels.
            FC_BAND=""; FC_LEVEL=$base
            FC_OUT_LEVEL=$base
            FC_OUT_DESC="Smart fast charge (fixed level $base, rating unknown)"
            return 0
            ;;
    esac

    target=$(awk -v r="$RATED_EFFECTIVE" -v p="$pct" 'BEGIN { printf "%.0f", r * p / 100 }')
    nowt=$(now_epoch)

    if [ "$band" != "$FC_BAND" ]; then
        # Entered a new temperature band: start from the fixed level, then adjust.
        FC_BAND=$band; FC_LEVEL=$base; FC_LAST_ADJ=$nowt
    elif [ $((nowt - FC_LAST_ADJ)) -ge "$FC_ADJUST_SECONDS" ]; then
        case "$WATTAGE" in
            ''|N/A) ;;
            *)
                if awk -v m="$WATTAGE" -v t="$target" 'BEGIN { exit !(m > t * 1.10) }' && [ "$FC_LEVEL" -lt "$FC_MAX_LEVEL" ]; then
                    FC_LEVEL=$((FC_LEVEL + 1)); FC_LAST_ADJ=$nowt
                elif awk -v m="$WATTAGE" -v t="$target" 'BEGIN { exit !(m < t * 0.75) }' && [ "$FC_LEVEL" -gt 0 ]; then
                    FC_LEVEL=$((FC_LEVEL - 1)); FC_LAST_ADJ=$nowt
                fi
                ;;
        esac
    fi

    FC_OUT_LEVEL=$FC_LEVEL
    FC_OUT_DESC="Smart fast charge (target ${target}W of ${RATED_EFFECTIVE}W)"
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
        fc_smart_level "$temp_c"
        level=$FC_OUT_LEVEL; desc=$FC_OUT_DESC
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
