// Universal offline wrapper for KernelSU and KernelSU Next WebUI bridge.
let callbackCounter = 0;

function getKsuObject() {
  if (typeof window !== "undefined") {
    if (window.ksu) return window.ksu;
    if (window.ksuNext) return window.ksuNext;
  }
  return null;
}

export function exec(command, options = {}) {
  return new Promise((resolve, reject) => {
    const callbackName = `exec_callback_${Date.now()}_${callbackCounter++}`;
    const ksuObj = getKsuObject();

    window[callbackName] = (errno, stdout, stderr) => {
      delete window[callbackName];
      resolve({ errno, stdout, stderr });
    };

    if (!ksuObj || typeof ksuObj.exec !== "function") {
      delete window[callbackName];
      reject(new Error("KernelSU / KernelSU Next WebUI API is unavailable."));
      return;
    }

    try {
      ksuObj.exec(command, JSON.stringify(options), callbackName);
    } catch (error) {
      delete window[callbackName];
      reject(error);
    }
  });
}

export function toast(message) {
  const ksuObj = getKsuObject();
  if (ksuObj && typeof ksuObj.toast === "function") {
    ksuObj.toast(message);
  } else {
    console.log("[Toast]", message);
  }
}

export function moduleInfo() {
  const ksuObj = getKsuObject();
  if (ksuObj && typeof ksuObj.moduleInfo === "function") {
    return Promise.resolve(ksuObj.moduleInfo());
  }
  return Promise.resolve("{}");
}

export function exit() {
  const ksuObj = getKsuObject();
  if (ksuObj && typeof ksuObj.exit === "function") {
    ksuObj.exit();
  }
}
