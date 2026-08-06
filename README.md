# ⚡ OnePlus / OPPO Bypass Charging Controller (oplusPowerController)

An advanced Magisk, KernelSU, KernelSU Next, and APatch bypass charging control module designed for the OnePlus Pad 2 Pro and compatible OPPO / OnePlus / Realme (OPlus) devices. It monitors battery levels, USB states, wattage, and temperatures in real time, managing hardware charging logic to cut off battery charging when reaching your set thresholds and powering the motherboard directly.

> ⚠️ **Note**: Developed for OnePlus Pad 2 Pro kernel power nodes (`/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable`). Other OPlus devices with matching factory kernel nodes are also supported.

> ❗ **Important**: When using bypass charging, ensure your charger power output exceeds your device power consumption.

---

## ✨ Advanced Features & Capabilities

* **🌐 Next-Gen WebUI Dashboard**: Native WebUI integration for KernelSU, KernelSU Next, APatch, and Magisk WebUI managers. Real-time monitoring of live voltage, current in mA, wattage ($W$), battery temperature, and charger state.
* **🔄 Flexible Control Modes**:
  * **Single Target Limit Mode**: Set a single charge cutoff threshold (e.g. $80\%$).
  * **Dual Band Hysteresis Mode**: Configure separate Upper ($85\%$) and Lower ($75\%$) limits. Cuts off charging at the upper limit and holds bypass mode until battery capacity drops below the lower limit.
* **🛡️ Thermal Guard Protection**: Automatically forces bypass charging if battery temperature reaches or exceeds a safety threshold (default $43^\circ\text{C}$), protecting your battery from high-temperature degradation.
* **⚡ Manual Override Switch**: Toggle instantly between **Auto Control**, **Force Bypass ON**, or **Force Charge ON**.
* **🎮 One-Tap Presets**:
  * **Desk / Gaming Mode**: $80\%$ Charge Limit (Optimized for continuous gaming and desktop use).
  * **Longevity Mode**: $70\%$ Charge Limit (Maximum long-term battery lifespan).
  * **Full Charge Mode**: $100\%$ Limit (Standard full charge for travel).
* **📱 Tactile UX & Auto-Save**: Debounced instant auto-save on slider adjustment, haptic vibration feedback (`navigator.vibrate`), pulsing LED status badges, and circular SVG power gauge visualizer.
* **📜 Live Log Viewer**: View, refresh, and clear system diagnostic logs directly inside WebUI.

---

## 📱 Compatibility Requirements

Your device kernel must expose the following power supply nodes:
* Bypass Control: `/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable`
* Battery Capacity: `/sys/class/power_supply/battery/capacity`
* USB Online Status: `/sys/class/power_supply/usb/online`

---

## 📦 Installation & Configuration

1. Download the `.zip` module package.
2. Flash in KernelSU, KernelSU Next, APatch, or Magisk, then reboot.
3. **Configuration**:
    * **WebUI**: Open KernelSU / KernelSU Next app -> Modules -> WebUI for `oplusPowerController`.
    * **File Configuration**: Manually edit `/data/adb/modules/oplusPowerController/config.txt`:
        ```ini
        MODE=SINGLE
        CHARGE_LIMIT=91
        UPPER_LIMIT=91
        LOWER_LIMIT=78
        THERMAL_GUARD=1
        MAX_TEMP=43
        OVERRIDE_MODE=AUTO
        ```
    * Configuration changes take effect on the fly without rebooting.

---

## 💡 Status Indicators

* 🟢 **Normal Charging**: Charging normally toward the target limit.
* ⚡ **Bypass Active**: Bypass mode active; motherboard powered directly from charger.
* 🛡️ **Thermal Guard Active**: Forced bypass due to high battery temperature.
* ⚡ **Forced Bypass ON**: Manual override forced bypass mode.
* 🟢 **Forced Charge ON**: Manual override forced charging mode.
* 💤 **Unplugged**: Charger disconnected; module in standby.
* 🔴 **Module Disabled**: Module disabled or marked for removal.

---

## ⚖️ Disclaimer

This module modifies low-level hardware power supply nodes. While safety fallbacks and validation logic are built-in, variations across system versions and custom kernels mean absolute safety cannot be guaranteed. **The user assumes all responsibility for any hardware damage, data loss, or system anomalies resulting from the use of this module.**
