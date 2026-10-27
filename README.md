# ⚡ OnePlus / OPPO Bypass Charging Controller (oplusPowerController)

[![Version](https://img.shields.io/badge/version-v97.0-green.svg)](module.prop)
[![VersionCode](https://img.shields.io/badge/versionCode-83-blue.svg)](module.prop)
[![Root Managers](https://img.shields.io/badge/Root-Magisk%20%7C%20KernelSU%20%7C%20KSU%20Next%20%7C%20APatch-orange.svg)](META-INF/com/google/android/update-binary)

An advanced, hardware-level battery management and bypass charging module engineered for **OnePlus Pad 2 Pro (sm8750)** and compatible **OPPO / OnePlus / Realme (OPlus)** devices running **KernelSU**, **KernelSU Next**, **APatch**, or **Magisk**.

It isolates battery charging at user-defined capacity limits while supplying power directly to the device motherboard from the external charger, reducing heat generation and extending long-term battery lifespan.

<p align="center">
  <img src=".github/assets/webui.jpg" alt="WebUI Dashboard Interface" width="440">
</p>

---

## 🛠️ Hardware Driver Architecture & Power Nodes

This module targets the single verified charging arbitration voter node on the **OnePlus Pad 2 Pro (sm8750)** `oplus_chg v2` driver (`vendor/oplus/kernel/charger/v2/oplus_configfs.c`):

* **Bypass / Charging Control Node**:
  `/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable`
  *(Writes to this node interface directly with the kernel's `chg_disable_votable` arbitration system via `MMI_CHG_VOTER`)*
* **Post-Write Hardware Verification**: `set_charging_state()` writes `0` (bypass/hold) or `1` (allow charging) and reads back the node value to verify that the hardware write took effect.
* **Strict Node Validation**: `required_power_nodes_available()` requires that `BYPASS_NODE` is writable, `CAPACITY_NODE` is readable, and `USB_ONLINE_NODE` is readable before allowing automation to run.

---

## ✨ Features & Hardware Protection Mechanisms

### 🔄 Flexible Charge Control Modes
* **Single Target Limit Mode**: Cuts off charging when battery capacity reaches `CHARGE_LIMIT` (default 91%).
* **Dual Band Hysteresis Mode**: Configures an `UPPER_LIMIT` (default 91%) and `LOWER_LIMIT` (default 78%). When battery reaches the upper limit, charging stops and bypass mode is held until capacity drops to the lower limit before resuming charging.
* **Plug-In Hysteresis Logic**: When plugging in at a capacity between lower and upper limits (e.g. 90%), bypass mode is immediately activated unless the device was actively charging up from below the lower limit.

### ⚡ Fast Charge & Smart Power *(merged from OnePlus-Pad-90W-Smart-Charge)*
* **Fast Charge (`FAST_CHARGE=OFF|SMART|MAX`)**: unlocks the system fast-charge settings and steps the `oplus_chg` `cool_down` level by battery temperature, only while the battery reports `Charging` (so it never fights bypass). Handled in `fast-charge.sh`, called from the main loop.
  * `SMART` *(default)*: `<42°C` level 0 (full output) · `42–45°C` level 1 (balanced) · `≥45°C` level 3 (heat fallback).
  * `MAX`: level 0 below 45°C so screen-on throttling is removed; level 2 at ≥45°C.
  * `OFF`: this module never touches `cool_down` or the charge settings.
  * `cool_down` is returned to 0 as soon as charging stops. Thermal Guard (`MAX_TEMP`, default 46°C) sits above every tier and cuts charging entirely.
* **Rated charge power**: no wattage is hard-coded. `service.sh` records the highest charge power seen while charging in `peak_watts`, and the WebUI shows it as the detected rating. Set `RATED_WATTS` (slider in the WebUI, 0 = Auto) to override it for your charger. It is informational and does not change charging behaviour.
* **Toggle app (optional)**: `apk/FastChargeToggle.apk` (source in `apk/source/`) adds a launcher icon and a Quick Settings tile that flip `MAX` ⇄ `SMART`. It works unchanged: at boot `service.sh` points `/data/local/tmp/toggle_fast_charge.sh` at `toggle-fast-charge.sh`, and the `/data/local/tmp/super_charge_unlocked` flag the tile reads is kept in sync with `FAST_CHARGE`. The WebUI **Fast Charge** card does the same thing.
* **Smart Power (`SMART_POWER=1|0`)**: `smart-power.sh` runs a background daemon with per-app profiles for the SM8750: CPU/GPU caps, 60/120Hz refresh, 540Hz touch sampling for games, Doze on screen-off, local `llama-server` boost. Casual-game packages can be added to `/sdcard/casual_powersave_games.txt` (hot-reloaded). Set `SMART_POWER=0` and reboot to disable. Live status is written to `/data/local/tmp/smart_power_status.json`, and profile changes are logged to `bypass.log`.

### 🛡️ Safety & Stability Features
* **Minimum Band Gap (`MIN_BAND_GAP=5%`)**: `normalize_dual_limits()` enforces at least 5% separation between `UPPER_LIMIT` and `LOWER_LIMIT` across WebUI, CLI, and `config.txt` to prevent fuel gauge reading jitter from rapidly cycling the charging IC.
* **Chatter Guard Dwell Timer (`MIN_DWELL_SECONDS=15s`)**: Automatic capacity-threshold transitions (`apply_auto_transition`) require at least 15 seconds between automatic flips. Manual overrides, thermal guard, unplug, and config updates react instantly.
* **Thermal Guard Protection (`THERMAL_HYSTERESIS=3°C`)**: Forces bypass mode when battery temperature reaches or exceeds `MAX_TEMP` (default 46°C, range 40–55°C). Requires temperature to drop 3°C below `MAX_TEMP` before releasing to prevent boundary flicker.
* **Sensor Sanity Check**: Validates `is_percentage "$CAPACITY"`. Glitched or unreadable sensor values ("N/A") freeze state without misfiring.
* **Boot State Seeding**: Seeds `LAST_STATE` from actual hardware node state on boot to prevent relay clicks between lower and upper limits.

### 🌐 WebUI Dashboard & Controls
* **Live Circular SVG Power Gauge**: Real-time capacity %, live wattage (W), voltage (V), current (mA), battery temperature (°C), charger type, and USB connection status.
* **1-Tap Controls & Instant Auto-Save**: Mode tabs, manual override switches, and presets execute `saveConfigImmediate()` instantly without waiting for slider debounces. Polling protection prevents background refresh from overwriting user selections.
* **Quick Presets**: Instant chips for **Desk / Gaming** (80%), **Longevity** (70%), and **Full Charge** (100%), with tap-to-toggle off capability and solid white deactive styling.
* **Integrated Live Log Viewer**: View, refresh, and clear system logs directly inside WebUI (`get-log.sh`, `clear-log.sh`).

### 🔘 Module Action Script (`action.sh`)
* Trigger via KernelSU, KernelSU Next, or APatch **Action button** on the module card (or run `su -c /data/adb/modules/oplusPowerController/action.sh`) to instantly toggle between **Forced Charge Mode** and **Auto Control Mode**.

---

## ⚙️ Configuration Reference (`config.txt`)

Stored at `/data/adb/modules/oplusPowerController/config.txt` and generated automatically if missing:

```ini
MODE=SINGLE           # Control mode: SINGLE or DUAL
CHARGE_LIMIT=91       # Single limit target percentage (0-100%)
UPPER_LIMIT=91        # Dual band upper limit (cuts charging)
LOWER_LIMIT=78        # Dual band lower limit (resumes charging)
THERMAL_GUARD=1       # Thermal guard safety: 1 (Enabled) or 0 (Disabled)
MAX_TEMP=46           # Thermal guard threshold temperature in °C (40-55°C)
OVERRIDE_MODE=AUTO    # Manual override mode: AUTO, FORCE_BYPASS, or FORCE_CHARGE
FAST_CHARGE=SMART     # Fast charge thermal tiering: OFF, SMART, or MAX
SMART_POWER=1         # Per-app CPU/GPU/refresh/touch daemon: 1 (Enabled) or 0 (Disabled), applied at boot
RATED_WATTS=0         # Rated charge power in W (0-150). 0 = auto, use the highest charge power seen
```

Adjustments can also be passed directly to `set-config.sh`:
```sh
su -c "/data/adb/modules/oplusPowerController/set-config.sh MODE=DUAL UPPER_LIMIT=90 LOWER_LIMIT=80"
```

---

## 💡 Status Badges (`module.prop`)

The `module.prop` description updates atomically via `printf` whenever status or configuration changes:

* 🟢 **Normal Charging**: Standard charging allowed up to target limit.
* ⚡ **Bypass Active**: Hardware bypass active; battery charging isolated.
* 🛡️ **Thermal Guard Active**: Forced bypass due to high battery temperature (>= `MAX_TEMP`).
* ⚡ **Forced Bypass ON**: Manual override forced bypass mode.
* 🟢 **Forced Charge ON**: Manual override forced charging mode.
* 💤 **Unplugged**: Charger disconnected; module in standby.
* 🔴 **Module Disabled**: Module disabled or marked for removal.
* ❌ **Device Unsupported**: Required kernel nodes missing or unwritable.

---

## 🙏 Credits

Fast Charge, the toggle app and Smart Power are ported from [OnePlus-Pad-90W-Smart-Charge](https://github.com/NinjaDraco/OnePlus-Pad-90W-Smart-Charge) by NinjaDraco. Not carried over: its `permissive magisk` SELinux rule, `system.prop`, forced `wm density 315` and the `wlan0` MTU clamp.
