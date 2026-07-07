"use strict";

const Store = require("electron-store");
const { detectWowPath, detectAccounts } = require("./lib/wow-detect");

const store = new Store({ name: "companion-config" });

function getConfig() {
  return {
    webUrl: store.get("webUrl", "https://nordavind.cc"),
    apiKey: store.get("apiKey", ""),
    wowPath: store.get("wowPath", ""),
    account: store.get("account", ""),
    cronSecret: store.get("cronSecret", ""),
    startWithWindows: store.get("startWithWindows", true),
  };
}

function setConfig(partial) {
  for (const [k, v] of Object.entries(partial)) store.set(k, v);
}

function isConfigured() {
  const c = getConfig();
  return !!(c.apiKey && c.wowPath && c.account);
}

module.exports = { getConfig, setConfig, isConfigured, detectWowPath, detectAccounts, _store: store };
