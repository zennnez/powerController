#!/system/bin/sh

DEFAULT_CHARGE_LIMIT=91
DEFAULT_UPPER_LIMIT=91
DEFAULT_LOWER_LIMIT=78
DEFAULT_MAX_TEMP=43

CONFIG_FILE="$MODDIR/config.txt"
BYPASS_NODE="/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable"
BATTERY_DIR="/sys/class/power_supply/battery"
USB_DIR="/sys/class/power_supply/usb"
CAPACITY_NODE="$BATTERY_DIR/capacity"
BATTERY_STATUS_NODE="$BATTERY_DIR/status"
VOLTAGE_NOW_NODE="$BATTERY_DIR/voltage_now"
TEMPERATURE_NODE="$BATTERY_DIR/temp"
USB_ONLINE_NODE="$USB_DIR/online"

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
        UPPER_LIMIT=91
        LOWER_LIMIT=78
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

required_power_nodes_available() {
    [ -r "$BYPASS_NODE" ] &&
        [ -r "$CAPACITY_NODE" ] &&
        [ -r "$USB_ONLINE_NODE" ]
}
