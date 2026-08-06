import { exec, toast, moduleInfo } from "./kernelsu.js";

let MODULE_DIR = "/data/adb/modules/oplusPowerController";
let STATUS_COMMAND = `sh ${MODULE_DIR}/get-status.sh`;
let USB_ONLINE_COMMAND = `sh ${MODULE_DIR}/get-usb-online.sh`;
let SET_CONFIG_COMMAND = `sh ${MODULE_DIR}/set-config.sh`;
let GET_LOG_COMMAND = `sh ${MODULE_DIR}/get-log.sh`;
let CLEAR_LOG_COMMAND = `sh ${MODULE_DIR}/clear-log.sh`;

const ONLINE_REFRESH_MS = 1_000;
const OFFLINE_USB_REFRESH_MS = 10_000;

const elements = {
  state: document.querySelector("#controller-state"),
  pulseDot: document.querySelector("#pulse-dot"),
  capacity: document.querySelector("#capacity"),
  wattage: document.querySelector("#wattage"),
  gaugeProgress: document.querySelector("#gauge-progress"),
  batteryStatus: document.querySelector("#battery-status"),
  usbOnline: document.querySelector("#usb-online"),
  usbType: document.querySelector("#usb-type"),
  bypass: document.querySelector("#bypass-enabled"),
  voltage: document.querySelector("#voltage"),
  current: document.querySelector("#current"),
  currentSource: document.querySelector("#current-source"),
  tempDisplay: document.querySelector("#temp-display"),
  updated: document.querySelector("#last-update"),
  form: document.querySelector("#config-form"),
  error: document.querySelector("#form-error"),
  autosave: document.querySelector("#autosave-indicator"),
  limit: document.querySelector("#charge-limit"),
  limitOutput: document.querySelector("#limit-output"),
  upper: document.querySelector("#upper-limit"),
  upperOutput: document.querySelector("#upper-output"),
  lower: document.querySelector("#lower-limit"),
  lowerOutput: document.querySelector("#lower-output"),
  maxTemp: document.querySelector("#max-temp"),
  tempOutput: document.querySelector("#temp-output"),
  groupSingle: document.querySelector("#group-single"),
  groupDual: document.querySelector("#group-dual"),
  modeSingleBtn: document.querySelector("#mode-single"),
  modeDualBtn: document.querySelector("#mode-dual"),
  presetDesk: document.querySelector("#preset-desk"),
  presetLongevity: document.querySelector("#preset-longevity"),
  presetFull: document.querySelector("#preset-full"),
  overrideAuto: document.querySelector("#override-auto"),
  overrideBypass: document.querySelector("#override-bypass"),
  overrideCharge: document.querySelector("#override-charge"),
  logContent: document.querySelector("#log-content"),
  refreshLogBtn: document.querySelector("#refresh-log-btn"),
  clearLogBtn: document.querySelector("#clear-log-btn"),
};

let activeMode = "SINGLE";
let activeOverride = "AUTO";
let formDirty = false;
let autoSaveTimer = null;
let refreshTimer;
let usbOnline = "N/A";

function vibrate(ms = 20) {
  if (typeof navigator !== "undefined" && typeof navigator.vibrate === "function") {
    try {
      navigator.vibrate(ms);
    } catch (_) {}
  }
}

async function updateModuleDir() {
  try {
    const rawInfo = await moduleInfo();
    if (rawInfo) {
      const parsed = typeof rawInfo === "string" ? JSON.parse(rawInfo) : rawInfo;
      if (parsed && parsed.moduleDir) {
        MODULE_DIR = parsed.moduleDir;
        STATUS_COMMAND = `sh ${MODULE_DIR}/get-status.sh`;
        USB_ONLINE_COMMAND = `sh ${MODULE_DIR}/get-usb-online.sh`;
        SET_CONFIG_COMMAND = `sh ${MODULE_DIR}/set-config.sh`;
        GET_LOG_COMMAND = `sh ${MODULE_DIR}/get-log.sh`;
        CLEAR_LOG_COMMAND = `sh ${MODULE_DIR}/clear-log.sh`;
      }
    }
  } catch (e) {
    console.warn("Using default module directory path:", MODULE_DIR);
  }
}

function parseStatus(text) {
  return Object.fromEntries(
    text
      .trim()
      .split("\n")
      .map((line) => {
        const separator = line.indexOf("=");
        return separator < 0
          ? [line, ""]
          : [line.slice(0, separator), line.slice(separator + 1)];
      }),
  );
}

function formatMetric(value, divisor, unit) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return "N/A";
  return `${(numeric / divisor).toFixed(divisor === 1 ? 0 : 2)} ${unit}`;
}

function formatCurrent(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return "N/A";
  const normalized = Object.is(numeric, -0) ? 0 : numeric;
  const absolute = Math.abs(normalized);
  const digits = absolute >= 100 ? 0 : absolute >= 10 ? 1 : absolute >= 1 ? 2 : 3;
  return `${normalized.toFixed(digits)} mA`;
}

function stateLabel(state) {
  return {
    UNPLUGGED: "Charger Disconnected",
    BYPASS: "Bypass Active",
    CHARGING: "Normal Charging Allowed",
    FORCE_BYPASS: "Manual Force Bypass",
    FORCE_CHARGE: "Manual Force Charge",
    UNAVAILABLE: "Node Unavailable",
  }[state] || "Unknown State";
}

function updatePulseDot(state, isThermal = false) {
  elements.pulseDot.className = "pulse-dot";
  if (isThermal) {
    elements.pulseDot.classList.add("dot-amber");
  } else if (state === "BYPASS" || state === "FORCE_BYPASS") {
    elements.pulseDot.classList.add("dot-cyan");
  } else if (state === "CHARGING" || state === "FORCE_CHARGE") {
    elements.pulseDot.classList.add("dot-green");
  } else if (state === "UNAVAILABLE") {
    elements.pulseDot.classList.add("dot-red");
  }
}

function updateGauge(capacityPercent, controllerState) {
  const cap = Number(capacityPercent);
  if (!Number.isFinite(cap)) return;

  const circumference = 283;
  const offset = circumference - (circumference * Math.min(100, Math.max(0, cap))) / 100;
  elements.gaugeProgress.style.strokeDashoffset = offset;

  if (controllerState === "BYPASS" || controllerState === "FORCE_BYPASS") {
    elements.gaugeProgress.style.stroke = "#00bcd4";
  } else {
    elements.gaugeProgress.style.stroke = "#4caf50";
  }
}

function updateOutputs() {
  elements.limitOutput.value = elements.limit.value;
  elements.upperOutput.value = elements.upper.value;
  elements.lowerOutput.value = elements.lower.value;
  elements.tempOutput.value = elements.maxTemp.value;
}

function validateForm() {
  if (activeMode === "DUAL") {
    const upperVal = Number(elements.upper.value);
    const lowerVal = Number(elements.lower.value);
    const valid = upperVal > lowerVal;
    elements.error.textContent = valid ? "" : "Upper limit must be greater than lower limit";
    return valid;
  }
  elements.error.textContent = "";
  return true;
}

function renderUI(status) {
  usbOnline = status.USB_ONLINE;
  activeMode = status.MODE || "SINGLE";
  activeOverride = status.OVERRIDE_MODE || "AUTO";

  elements.state.textContent = stateLabel(status.CONTROLLER_STATE);
  elements.capacity.textContent = status.CAPACITY === "N/A" ? "--" : status.CAPACITY;
  elements.wattage.textContent = status.WATTAGE === "N/A" ? "0.00 W" : `${status.WATTAGE} W`;
  elements.batteryStatus.textContent = `System Status: ${status.BATTERY_STATUS || "Unknown"}`;
  elements.usbOnline.textContent = status.USB_ONLINE === "1" ? "Connected" : status.USB_ONLINE === "0" ? "Disconnected" : "N/A";
  elements.usbType.textContent = status.USB_TYPE === "N/A" ? "Type Unavailable" : status.USB_TYPE;
  elements.bypass.textContent = status.BYPASS_ENABLED === "0" ? "0 · Cut Off (Bypass ON)" : status.BYPASS_ENABLED === "1" ? "1 · Charging Allowed" : "N/A";
  elements.voltage.textContent = formatMetric(status.VOLTAGE_NOW, 1_000_000, "V");
  elements.current.textContent = formatCurrent(status.CURRENT_NOW_MA);
  elements.currentSource.textContent = status.CURRENT_NOW_SOURCE === "battery/current_now" ? "Live battery current" : status.CURRENT_NOW_SOURCE;

  const rawTemp = Number(status.TEMPERATURE);
  const tempC = Number.isFinite(rawTemp) ? (rawTemp >= 200 ? (rawTemp / 10).toFixed(1) : rawTemp.toFixed(1)) : "--";
  elements.tempDisplay.textContent = `${tempC} °C`;

  updateGauge(status.CAPACITY, status.CONTROLLER_STATE);
  updatePulseDot(status.CONTROLLER_STATE);
  elements.updated.textContent = `Last update: ${new Date().toLocaleTimeString("en-US")}`;

  setModeVisual(activeMode);
  setOverrideVisual(activeOverride);

  if (!formDirty) {
    if (status.CHARGE_LIMIT) elements.limit.value = status.CHARGE_LIMIT;
    if (status.UPPER_LIMIT) elements.upper.value = status.UPPER_LIMIT;
    if (status.LOWER_LIMIT) elements.lower.value = status.LOWER_LIMIT;
    if (status.MAX_TEMP) elements.maxTemp.value = status.MAX_TEMP;
    updateOutputs();
    validateForm();
    updatePresetVisual();
  }
}

function setModeVisual(mode) {
  activeMode = mode;
  if (mode === "DUAL") {
    elements.modeDualBtn.classList.add("active");
    elements.modeSingleBtn.classList.remove("active");
    elements.groupDual.style.display = "grid";
    elements.groupSingle.style.display = "none";
  } else {
    elements.modeSingleBtn.classList.add("active");
    elements.modeDualBtn.classList.remove("active");
    elements.groupSingle.style.display = "grid";
    elements.groupDual.style.display = "none";
  }
  validateForm();
}

function setOverrideVisual(override) {
  activeOverride = override;
  elements.overrideAuto.classList.toggle("active", override === "AUTO");
  elements.overrideBypass.classList.toggle("active", override === "FORCE_BYPASS");
  elements.overrideCharge.classList.toggle("active", override === "FORCE_CHARGE");
}

function updatePresetVisual() {
  const limitVal = Number(elements.limit.value);
  const isSingle = activeMode === "SINGLE";
  elements.presetDesk.classList.toggle("active", isSingle && limitVal === 80);
  elements.presetLongevity.classList.toggle("active", isSingle && limitVal === 70);
  elements.presetFull.classList.toggle("active", isSingle && limitVal === 100);
}

function togglePreset(targetLimit, chipElement) {
  vibrate(20);
  const isActive = chipElement.classList.contains("active");

  if (isActive) {
    // Tapping active preset disables it and reverts to default 91%
    chipElement.classList.remove("active");
    elements.limit.value = 91;
  } else {
    // Activate preset
    setModeVisual("SINGLE");
    elements.limit.value = targetLimit;
  }

  triggerAutoSave();
}

async function refreshStatus(showError = false) {
  try {
    const result = await exec(STATUS_COMMAND);
    if (result.errno !== 0) throw new Error(result.stderr || `Read failed (${result.errno})`);
    renderUI(parseStatus(result.stdout));
  } catch (error) {
    elements.updated.textContent = "Unable to read status. Ensure WebUI is opened in KernelSU / KSU Next.";
    if (showError) toast(error.message);
  }
}

async function refreshUsbOnline() {
  try {
    const result = await exec(USB_ONLINE_COMMAND);
    if (result.errno !== 0) throw new Error(result.stderr);
    const nextUsb = result.stdout.trim();
    elements.usbOnline.textContent = nextUsb === "1" ? "Connected" : "Disconnected";
    if (nextUsb === "1") await refreshStatus(false);
  } catch (_) {}
}

function scheduleRefresh() {
  window.clearTimeout(refreshTimer);
  const delay = usbOnline === "1" ? ONLINE_REFRESH_MS : OFFLINE_USB_REFRESH_MS;
  refreshTimer = window.setTimeout(async () => {
    if (usbOnline === "1") {
      await refreshStatus(false);
    } else {
      await refreshUsbOnline();
    }
    scheduleRefresh();
  }, delay);
}

async function saveConfig() {
  if (!validateForm()) return;
  elements.autosave.style.opacity = "1";
  elements.autosave.textContent = "Saving...";

  try {
    const args = [
      `MODE=${activeMode}`,
      `CHARGE_LIMIT=${elements.limit.value}`,
      `UPPER_LIMIT=${elements.upper.value}`,
      `LOWER_LIMIT=${elements.lower.value}`,
      `MAX_TEMP=${elements.maxTemp.value}`,
      `OVERRIDE_MODE=${activeOverride}`,
    ].join(" ");

    const result = await exec(`${SET_CONFIG_COMMAND} ${args}`);
    if (result.errno !== 0) throw new Error(result.stderr || "Save failed");

    formDirty = false;
    vibrate(15);
    elements.autosave.textContent = "Saved";
    setTimeout(() => {
      elements.autosave.style.opacity = "0";
    }, 1500);
    await refreshStatus(false);
  } catch (err) {
    elements.error.textContent = err.message;
    toast(err.message);
  }
}

function triggerAutoSave() {
  formDirty = true;
  updateOutputs();
  updatePresetVisual();
  if (!validateForm()) return;

  window.clearTimeout(autoSaveTimer);
  autoSaveTimer = window.setTimeout(async () => {
    await saveConfig();
  }, 400);
}

// Log Fetching & Clearing
async function fetchLogs() {
  try {
    elements.logContent.textContent = "Loading logs...";
    const result = await exec(GET_LOG_COMMAND);
    elements.logContent.textContent = result.stdout.trim() || "Log file is empty.";
  } catch (err) {
    elements.logContent.textContent = `Failed to load logs: ${err.message}`;
  }
}

async function clearLogs() {
  try {
    vibrate(20);
    const result = await exec(CLEAR_LOG_COMMAND);
    toast(result.stdout.trim() || "Logs cleared");
    await fetchLogs();
  } catch (err) {
    toast(err.message);
  }
}

// Attach Auto-Save Handlers to All Settings Controls
[elements.limit, elements.upper, elements.lower, elements.maxTemp].forEach((control) => {
  control.addEventListener("input", triggerAutoSave);
  control.addEventListener("change", triggerAutoSave);
});

elements.modeSingleBtn.addEventListener("click", () => {
  vibrate(15);
  setModeVisual("SINGLE");
  triggerAutoSave();
});

elements.modeDualBtn.addEventListener("click", () => {
  vibrate(15);
  setModeVisual("DUAL");
  triggerAutoSave();
});

elements.presetDesk.addEventListener("click", () => {
  togglePreset(80, elements.presetDesk);
});

elements.presetLongevity.addEventListener("click", () => {
  togglePreset(70, elements.presetLongevity);
});

elements.presetFull.addEventListener("click", () => {
  togglePreset(100, elements.presetFull);
});

elements.overrideAuto.addEventListener("click", () => {
  vibrate(15);
  setOverrideVisual("AUTO");
  triggerAutoSave();
});

elements.overrideBypass.addEventListener("click", () => {
  vibrate(15);
  setOverrideVisual("FORCE_BYPASS");
  triggerAutoSave();
});

elements.overrideCharge.addEventListener("click", () => {
  vibrate(15);
  setOverrideVisual("FORCE_CHARGE");
  triggerAutoSave();
});

elements.refreshLogBtn.addEventListener("click", fetchLogs);
elements.clearLogBtn.addEventListener("click", clearLogs);

async function initialize() {
  await updateModuleDir();
  await refreshStatus(true);
  await fetchLogs();
  scheduleRefresh();
}

initialize();
