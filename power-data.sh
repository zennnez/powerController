#!/system/bin/sh

DEFAULT_CHARGE_LIMIT=91
DEFAULT_UPPER_LIMIT=91
DEFAULT_LOWER_LIMIT=78
DEFAULT_MAX_TEMP=43

CONFIG_FILE="$MODDIR/config.txt"
# This is the ONLY confirmed, real charging-control node on the OnePlus Pad 2 Pro
# (sm8750) oplus_chg v2 driver. Verified directly against the factory kernel source
# (oplus_battery_attributes[] in vendor/oplus/kernel/charger/v2/oplus_configfs.c):
# writes here go through the kernel's chg_disable_votable arbitration system
# (MMI_CHG_VOTER), which is the safe, intended control path.
#
# We intentionally do NOT probe/write to other guessed node names
# (e.g. "charging_enabled", "battery_charging_enabled", "main/charging_enabled").
# Those don't exist in this device's driver and blindly writing 0/1 to whatever
# happens to pass an "-r" check on some future OTA is exactly the kind of
# uncontrolled write that can leave the charge IC/voter stack in a bad state.
BYPASS_NODE="/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable"
BATTERY_DIR="/sys/class/power_supply/battery"
USB_DIR="/sys/class/power_supply/usb"
CAPACITY_NODE="$BATTERY_DIR/capacity"
BATTERY_STATUS_NODE="$BATTERY_DIR/status"
VOLTAGE_NOW_NODE="$BATTERY_DIR/voltage_now"
TEMPERATURE_NODE="$BATTERY_DIR/temp"
USB_ONLINE_NODE="$USB_DIR/online"

# Writes only ever go to the single verified BYPASS_NODE above.
# state must be exactly "0" (bypass/hold) or "1" (allow charging) - anything
# else is refused so a config typo or bad caller can never send a stray value.
# Returns 0 on a verified successful write, 1 otherwise, so callers (service.sh)
# can tell the difference between "wrote fine" and "node rejected the write".
set_charging_state() {
    local state="$1"
    case "$state" in
        0|1) ;;
        *) return 1 ;;
    esac

    if [ ! -w "$BYPASS_NODE" ]; then
        return 1
    fi

    echo "$state" > "$BYPASS_NODE" 2>/dev/null

    # Verify the write actually took effect instead of assuming success.
    CURRENT_VAL=$(tr -d '\r\n' < "$BYPASS_NODE" 2>/dev/null)
    [ "$CURRENT_VAL" = "$state" ]
}

if [ -r "$USB_DIR/real_type" ]; then
    USB_TYPE_NODE="$USB_DIR/real_type"
elif [ -r "$USB_DIR/usb_type" ]; then
    USB_TYPE_NODE="$USB_DIR/usb_type"
else
    USB_TYPE_NODE="$USB_DIR/type"
fi

CURRENT_NOW_NODE="$BATTERY_DIR/current_now"
CURRENT_NOW_SOURCE="battery/current_now"

read_node() {
    if [ -r "$1" ]; then
        tr -d '\r\n' < "$1"
    else
        printf '%s' "N/A"
    fi
}

read_config_value() {
    grep -m 1 "^$1=" "$CONFIG_FILE" 2>/dev/null |
        cut -d= -f2 |
        awk '{print $1}'
}

is_percentage() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 0 ] && [ "$1" -le 100 ]
}

is_number() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

load_config() {
    MODE=$(read_config_value MODE)
    [ "$MODE" != "DUAL" ] && MODE="SINGLE"

    CHARGE_LIMIT=$(read_config_value CHARGE_LIMIT)
    ! is_percentage "$CHARGE_LIMIT" && CHARGE_LIMIT=$DEFAULT_CHARGE_LIMIT

    UPPER_LIMIT=$(read_config_value UPPER_LIMIT)
    ! is_percentage "$UPPER_LIMIT" && UPPER_LIMIT=$DEFAULT_UPPER_LIMIT

    LOWER_LIMIT=$(read_config_value LOWER_LIMIT)
    ! is_percentage "$LOWER_LIMIT" && LOWER_LIMIT=$DEFAULT_LOWER_LIMIT

    if [ "$UPPER_LIMIT" -le "$LOWER_LIMIT" ]; then
        if [ "$UPPER_LIMIT" -gt 5 ]; then
            LOWER_LIMIT=$((UPPER_LIMIT - 5))
        else
            UPPER_LIMIT=91
            LOWER_LIMIT=78
        fi
    fi

    THERMAL_GUARD=$(read_config_value THERMAL_GUARD)
    [ "$THERMAL_GUARD" != "0" ] && THERMAL_GUARD="1"

    MAX_TEMP=$(read_config_value MAX_TEMP)
    (! is_number "$MAX_TEMP" || [ "$MAX_TEMP" -lt 25 ] || [ "$MAX_TEMP" -gt 60 ]) && MAX_TEMP=$DEFAULT_MAX_TEMP

    OVERRIDE_MODE=$(read_config_value OVERRIDE_MODE)
    case "$OVERRIDE_MODE" in
        FORCE_BYPASS|FORCE_CHARGE) ;;
        *) OVERRIDE_MODE="AUTO" ;;
    esac
}

read_usb_type() {
    RAW_TYPE=$(read_node "$USB_TYPE_NODE")
    case "$RAW_TYPE" in
        *'['*']'*)
            printf '%s\n' "$RAW_TYPE" | sed -n 's/.*\[\([^]]*\)\].*/\1/p'
            ;;
        *)
            printf '%s' "$RAW_TYPE"
            ;;
    esac
}

normalize_current_ma() {
    case "$1" in
        ''|N/A|*[!0-9-]*)
            printf '%s' "N/A"
            return
            ;;
    esac

    ABS_CURRENT=${1#-}

    if [ "$ABS_CURRENT" -ge 10000 ]; then
        awk -v value="$1" 'BEGIN { printf "%.0f", value / 1000 }'
    else
        printf '%s' "$1"
    fi
}

calculate_wattage() {
    VOLT_RAW="$1"
    CURR_MA="$2"
    case "$VOLT_RAW" in
        ''|N/A|*[!0-9]*) printf '%s' "N/A"; return ;;
    esac
    case "$CURR_MA" in
        ''|N/A|*[!0-9-]*) printf '%s' "N/A"; return ;;
    esac

    awk -v v="$VOLT_RAW" -v a="$CURR_MA" 'BEGIN {
        volt_v = v / 1000000.0;
        curr_a = a / 1000.0;
        if (curr_a < 0) curr_a = -curr_a;
        printf "%.2f", volt_v * curr_a
    }'
}

load_power_data() {
    load_config
    CAPACITY=$(read_node "$CAPACITY_NODE")
    BATTERY_STATUS=$(read_node "$BATTERY_STATUS_NODE")
    USB_ONLINE=$(read_node "$USB_ONLINE_NODE")
    USB_TYPE=$(read_usb_type)
    VOLTAGE_NOW=$(read_node "$VOLTAGE_NOW_NODE")
    CURRENT_NOW_RAW=$(read_node "$CURRENT_NOW_NODE")
    CURRENT_NOW_MA=$(normalize_current_ma "$CURRENT_NOW_RAW")
    TEMPERATURE=$(read_node "$TEMPERATURE_NODE")
    BYPASS_ENABLED=$(read_node "$BYPASS_NODE")
    WATTAGE=$(calculate_wattage "$VOLTAGE_NOW" "$CURRENT_NOW_MA")

    if [ "$USB_ONLINE" = "0" ]; then
        CONTROLLER_STATE="UNPLUGGED"
    elif [ "$BYPASS_ENABLED" = "0" ]; then
        CONTROLLER_STATE="BYPASS"
    elif [ "$BYPASS_ENABLED" = "1" ]; then
        CONTROLLER_STATE="CHARGING"
    else
        CONTROLLER_STATE="UNAVAILABLE"
    fi
}

# All three must be present: the module can't safely automate charge limits
# without a writable control node, a readable capacity, and a readable USB
# online state. (Previously this used OR, so the module could report itself
# "available" while actually missing the one node it needs to do anything.)
required_power_nodes_available() {
    [ -w "$BYPASS_NODE" ] && [ -r "$CAPACITY_NODE" ] && [ -r "$USB_ONLINE_NODE" ]
}
