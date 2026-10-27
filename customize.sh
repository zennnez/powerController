# Runs during install (sourced by install_module).
MODS=/data/adb/modules
OLD_SMART="$MODS/oneplus_smart_charge_power_opt"   # OnePlus-Pad-90W-Smart-Charge, now merged into this module
OLD_SELF="$MODS/oplusPowerController"              # earlier versions of this module

# 1) Replace the standalone Smart Charge module.
if [ -d "$OLD_SMART" ]; then
    ui_print "- Removing old OnePlus Pad 90W Smart Charge module (merged into this one)"
    touch "$OLD_SMART/remove" "$OLD_SMART/disable" 2>/dev/null
    # Stop its running daemon and watchdog so they don't fight this module until reboot.
    pkill -f "$OLD_SMART/service.sh" 2>/dev/null
    pkill -f smart_power_daemon.sh 2>/dev/null
    rm -f /data/local/tmp/smart_power_daemon.pid /data/local/tmp/smart_power_opt.log 2>/dev/null
fi

# 2) Replace an older installed copy of this module, keeping the user's settings.
if [ -f "$OLD_SELF/config.txt" ]; then
    ui_print "- Replacing previous Bypass Charging Controller, keeping your settings"
    cp "$OLD_SELF/config.txt" "$MODPATH/config.txt" 2>/dev/null
    # Old default Thermal Guard (43C) cut charging before the fast-charge tiers; move it to the new default.
    if grep -q '^MAX_TEMP=43$' "$MODPATH/config.txt" 2>/dev/null; then
        sed -i 's/^MAX_TEMP=43$/MAX_TEMP=46/' "$MODPATH/config.txt"
        ui_print "- Thermal Guard threshold 43C -> 46C"
    fi
fi
[ -f "$OLD_SELF/peak_watts" ] && cp "$OLD_SELF/peak_watts" "$MODPATH/peak_watts" 2>/dev/null
if [ -d "$OLD_SELF" ]; then
    # Old daemon keeps running until reboot; stop it so the new one takes over cleanly.
    pkill -f "$OLD_SELF/service.sh" 2>/dev/null
    # Make sure charging isn't left in bypass by the old daemon.
    echo 1 > /sys/devices/virtual/oplus_chg/battery/mmi_charging_enable 2>/dev/null
fi

# Seed the casual-game list used by smart-power.sh; never overwrite the user's copy.
if [ -f "$MODPATH/casual_powersave_games.txt" ] && [ ! -f /sdcard/casual_powersave_games.txt ]; then
    cp "$MODPATH/casual_powersave_games.txt" /sdcard/casual_powersave_games.txt 2>/dev/null
fi
ui_print "- Fast charge + smart power included (see README). Optional toggle app: apk/FastChargeToggle.apk in the module folder."
ui_print "- Reboot to finish."
