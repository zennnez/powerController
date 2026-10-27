#!/system/bin/sh
# Safety fallback: restore default charging capability
BYPASS_NODE="/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable"
if [ -w "$BYPASS_NODE" ]; then
    echo 1 > "$BYPASS_NODE" 2>/dev/null
fi
# Fast charge / smart power cleanup. CPU/GPU caps and sched tweaks are runtime
# only and clear on reboot; the refresh-rate settings persist, so drop them.
for node in /sys/devices/virtual/oplus_chg/battery/cool_down /sys/class/oplus_chg/battery/cool_down; do
    [ -w "$node" ] && echo 0 > "$node" 2>/dev/null
done
settings delete system peak_refresh_rate 2>/dev/null
settings delete system min_refresh_rate 2>/dev/null
rm -f /data/local/tmp/super_charge_unlocked \
      /data/local/tmp/toggle_fast_charge.sh \
      /data/local/tmp/fast_charge_state \
      /data/local/tmp/smart_power_status.json \
      /data/local/tmp/smart_power_daemon.pid 2>/dev/null
