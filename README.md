# ⚡ OnePlus Pad 2 Pro Bypass Charging Controller (oplusPowerController)

This is a Magisk, KernelSU, and KernelSU Next bypass charging control module designed for the OnePlus Pad 2 Pro and compatible OPPO / OnePlus / Realme (OPlus) devices. It monitors battery level and USB state in real time, controlling hardware charging logic to cut off battery charging when reaching a specified limit and switching to direct power supply (bypass power). This reduces device thermal throttling and extends battery lifespan.

> ⚠️ **Note**: This project is developed based on OnePlus Pad 2 Pro kernel power nodes. Other OPlus (OPPO / OnePlus / Realme) devices equipped with matching kernel nodes can also test and use this module.

> ❗ **Important**: When using bypass charging, ensure your charger power output exceeds the device power consumption. Otherwise, power deficits will draw from the battery. If any anomaly occurs, re-plug the charger or reboot the device.

## 💡 Why Use This Module?

Stock system charging limits (e.g. 80% limit or Game Space bypass) have notable drawbacks:
1. **Stock limits actively drain battery:** When battery capacity is above the set target, stock firmware actively drains the battery down to the threshold, causing unnecessary battery wear cycles.
2. **Stock bypass charging is restricted:** Only available during specific gaming scenarios and often relies on software current throttling rather than physical power path isolation.

This module directly manages the factory testing kernel node `/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable`. When reaching your designated threshold, it **physically cuts off the battery charging circuit**, delivering power from the charger directly to the mainboard. The battery remains in a idle protection state without charging or discharging.

## ✨ Key Features

* **🌐 Integrated WebUI Interface**: Full support for KernelSU and KernelSU Next WebUI dashboard. View live charger status, battery percentage, voltage, current in mA, temperature, and change charge limits dynamically.
* **🔄 Dynamic Status Display**: The module description in your root manager updates dynamically with real-time physical states (Normal Charging, Bypass Active, Unplugged, Disabled).
* **🔥 Hot Reloading Configuration**: Modify charge thresholds on the fly. Configuration changes take effect within **10 seconds** without requiring a reboot.
* **⚡ Hot Reset & Removal Protection**: Disabling or marking the module for removal immediately unlocks hardware charge restrictions within 10 seconds without rebooting.
* **🛡️ Safety & Failsafes**:
    * **Node Detection**: Automatically verifies required power supply nodes on boot. Halts safely if nodes are missing.
    * **Value Validation**: Strictly validates configuration inputs (0-100 integer range). Out-of-bounds or non-numeric inputs automatically fall back to the safe default (91%).
    * **Uninstall Fallback**: Re-enables full charging capability automatically if the module is disabled or removed.
* **🗂️ Log Self-Cleaning**: Built-in log rotation automatically clears `bypass.log` when it exceeds 1MB.

## 📱 Compatibility Requirements

Your device kernel must expose the following power supply nodes:
* Bypass Control: `/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable`
* Battery Capacity: `/sys/class/power_supply/battery/capacity`
* USB Online Status: `/sys/class/power_supply/usb/online`

## 📦 Installation & Configuration

1. Download the module `.zip` package from Releases.
2. Flash the module in KernelSU, KernelSU Next, APatch, or Magisk, then reboot.
3. **Configuration**:
    * **Via WebUI**: Open KernelSU / KernelSU Next app -> Modules -> WebUI for `oplusPowerController` to adjust the charge limit slider.
    * **Via File Manager**: Edit `/data/adb/modules/oplusPowerController/config.txt`:
        ```ini
        CHARGE_LIMIT=91  # Trigger bypass power supply when reaching this battery percentage
        ```
    * Save the file; changes apply automatically within seconds.

## 💡 Status Indicators

The module description in your module manager displays real-time status badges:
* 🟢 **Normal Charging**: Device is charging normally toward the target limit.
* ⚡ **Bypass Active**: Target charge limit reached; battery charging is cut off and power is supplied directly to the motherboard.
* 💤 **Unplugged**: Charger disconnected; module in standby.
* 🔴 **Module Disabled**: Module disabled or marked for removal; default charging restored.
* ❌ **Device Unsupported**: Required kernel nodes missing on this device.

## ⚖️ Disclaimer

This module modifies low-level hardware power supply nodes. While safety fallbacks and validation logic are built-in, variations across system versions and custom kernels mean absolute safety cannot be guaranteed. **The user assumes all responsibility for any hardware damage, data loss, or system anomalies resulting from the use of this module.**
