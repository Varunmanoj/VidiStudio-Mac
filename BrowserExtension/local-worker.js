// Used only by the unpacked extension delivered with the desktop app.
importScripts("background.js");

const updateAlarm = "vidistudio-local-version";

async function checkInstalledVersion() {
  try {
    const response = await fetch(chrome.runtime.getURL("manifest.json"), {cache: "no-store"});
    if (!response.ok) return;
    const installed = await response.json();
    const loaded = chrome.runtime.getManifest();
    if (installed.name === loaded.name && installed.background?.service_worker === "local-worker.js" &&
        /^\d+\.\d+\.\d+$/.test(installed.version) && installed.version !== loaded.version) {
      chrome.runtime.reload();
    }
  } catch {
    // The installer may be replacing the directory. The next alarm retries.
  }
}

async function startUpdateChecks() {
  if (!await chrome.alarms.get(updateAlarm)) {
    await chrome.alarms.create(updateAlarm, {periodInMinutes: 1});
  }
  await checkInstalledVersion();
}

chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === updateAlarm) void checkInstalledVersion();
});
chrome.runtime.onInstalled.addListener(startUpdateChecks);
chrome.runtime.onStartup.addListener(startUpdateChecks);
