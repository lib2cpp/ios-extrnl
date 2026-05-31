// background.js — service worker расширения

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.set({ enabled: true, level: 10 });
});

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "GET_SETTINGS") {
    chrome.storage.local.get(["enabled", "level"], (data) => {
      sendResponse({ enabled: data.enabled ?? true, level: data.level ?? 10 });
    });
    return true;
  }
  if (msg.type === "SET_SETTINGS") {
    chrome.storage.local.set({ enabled: msg.enabled, level: msg.level });
    // Переслать в content script
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs[0]) {
        chrome.tabs.sendMessage(tabs[0].id, {
          type: "SETTINGS_CHANGED",
          enabled: msg.enabled,
          level: msg.level,
        });
      }
    });
  }
});
