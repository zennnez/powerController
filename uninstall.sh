#!/system/bin/sh
# Safety fallback: restore default charging capability
BYPASS_NODE="/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable"
if [ -w "$BYPASS_NODE" ]; then
    echo 1 > "$BYPASS_NODE" 2>/dev/null
fi