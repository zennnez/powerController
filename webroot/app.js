import { exec, toast, moduleInfo } from "./kernelsu.js";

let MODULE_DIR = "/data/adb/modules/oplusPowerController";
let STATUS_COMMAND = `sh ${MODULE_DIR}/get-status.sh`;
let USB_ONLINE_COMMAND = `sh ${MODULE_DIR}/get-usb-online.sh`;
let SET_CONFIG_COMMAND = `sh ${MODULE_DIR}/set-config.sh`;

const ONLINE_REFRESH_MS = 1_000;
const OFFLINE_USB_REFRESH_MS = 10_000;
const OFFLINE_FULL_REFRESH_MS = 300_000;

const elements = {
  state: document.querySelector("#controller-state"),
  capacity: document.querySelector("#capacity"),
  batteryStatus: document.querySelector("#battery-status"),
  usbOnline: document.querySelector("#usb-online"),
  usbType: document.querySelector("#usb-type"),
  bypass: document.querySelector("#bypass-enabled"),
  voltage: document.querySelector("#voltage"),
  current: document.querySelector("#current"),
  currentSource: document.querySelector("#current-source"),
  temperature: document.querySelector("#temperature"),
  updated: document.querySelector("#last-update"),
  form: document.querySelector("#config-form"),
  error: document.querySelector("#form-error"),
  save: document.querySelector("#save-button"),
  limit: document.querySelector("#charge-limit"),
  limitOutput: document.querySelector("#limit-output"),
};

let formDirty = false;
let refreshTimer;
let usbOnline = "N/A";
let lastFullRefresh = 0;

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
      }
    }
  } catch (e) {
    console.warn("Could not dynamically resolve moduleDir, using default path:", MODULE_DIR);
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
    UNAVAILABLE: "Node Unavailable",
  }[state] || "Unknown State";
}

function onlineLabel(value) {
  if (value === "1") return "Connected";
  if (value === "0") return "Disconnected";
  return "N/A";
}

function updateFormOutputs() {
  elements.limitOutput.value = elements.limit.value;
}

function validateForm() {
  const limit = Number(elements.limit.value);
  const valid = Number.isInteger(limit) && limit >= 0 && limit <= 100;
  elements.error.textContent = valid ? "" : "Charge limit must be an integer between 0 and 100";
  elements.save.disabled = !valid;
  return valid;
}

function render(status) {
  usbOnline = status.USB_ONLINE;
  lastFullRefresh = Date.now();
  elements.state.textContent = stateLabel(status.CONTROLLER_STATE);
  elements.capacity.textContent = status.CAPACITY === "N/A" ? "--" : status.CAPACITY;
  elements.batteryStatus.textContent = `System status: ${status.BATTERY_STATUS || "Unknown"}`;
  elements.usbOnline.textContent = onlineLabel(status.USB_ONLINE);
  elements.usbType.textContent = status.USB_TYPE === "N/A" ? "Type unavailable" : status.USB_TYPE;
  elements.bypass.textContent =
    status.BYPASS_ENABLED === "0"
      ? "0 · Charging Cut Off (Bypass On)"
      : status.BYPASS_ENABLED === "1"
        ? "1 · Charging Enabled"
        : "N/A";
  elements.voltage.textContent = formatMetric(status.VOLTAGE_NOW, 1_000_000, "V");
  elements.current.textContent = formatCurrent(status.CURRENT_NOW_MA);
  elements.currentSource.textContent =
    status.CURRENT_NOW_SOURCE === "battery/current_now"
      ? "Live battery input/output current"
      : `Source: ${status.CURRENT_NOW_SOURCE}`;
  elements.temperature.textContent = formatMetric(status.TEMPERATURE, 10, "°C");
  elements.updated.textContent = `Last update: ${new Date().toLocaleTimeString("en-US")}`;

  if (!formDirty) {
    elements.limit.value = status.CHARGE_LIMIT;
    updateFormOutputs();
    validateForm();
  }
}

async function refreshStatus(showError = false) {
  try {
    const result = await exec(STATUS_COMMAND);
    if (result.errno !== 0) {
      throw new Error(result.stderr || `Read failed (${result.errno})`);
    }
    render(parseStatus(result.stdout));
  } catch (error) {
    elements.updated.textContent = "Unable to read status. Ensure WebUI is opened in KernelSU / KernelSU Next.";
    if (showError) toast(error.message);
  }
}

async function refreshUsbOnline() {
  try {
    const result = await exec(USB_ONLINE_COMMAND);
    if (result.errno !== 0) {
      throw new Error(result.stderr || `USB status read failed (${result.errno})`);
    }

    const nextUsbOnline = result.stdout.trim();
    elements.usbOnline.textContent = onlineLabel(nextUsbOnline);

    if (nextUsbOnline === "1") {
      await refreshStatus(false);
    } else {
      usbOnline = nextUsbOnline;
      elements.state.textContent = stateLabel("UNPLUGGED");
      if (Date.now() - lastFullRefresh >= OFFLINE_FULL_REFRESH_MS) {
        await refreshStatus(false);
      }
    }
  } catch (error) {
    elements.updated.textContent = "Unable to read USB status";
  }
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

elements.limit.addEventListener("input", () => {
  formDirty = true;
  updateFormOutputs();
  validateForm();
});

elements.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!validateForm()) return;

  elements.save.disabled = true;
  elements.save.textContent = "Saving...";

  try {
    const limit = Number(elements.limit.value);
    const result = await exec(`${SET_CONFIG_COMMAND} ${limit}`);
    if (result.errno !== 0) {
      throw new Error(result.stderr || `Save failed (${result.errno})`);
    }
    formDirty = false;
    toast(result.stdout.trim() || "Configuration saved");
    await refreshStatus(true);
  } catch (error) {
    elements.error.textContent = error.message;
    toast(error.message);
  } finally {
    elements.save.textContent = "Save Configuration";
    validateForm();
  }
});

async function initialize() {
  await updateModuleDir();
  await refreshStatus(true);
  scheduleRefresh();
}

initialize();
