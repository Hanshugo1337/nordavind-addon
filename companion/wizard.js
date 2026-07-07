"use strict";

const { BrowserWindow, ipcMain } = require("electron");
const path = require("path");
const { setConfig, detectWowPath, detectAccounts } = require("./config");

function openWizard(onDone) {
  const win = new BrowserWindow({
    width: 520, height: 560, resizable: false, autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, "wizard-preload.js"), contextIsolation: true },
  });
  win.loadFile(path.join(__dirname, "wizard.html"));

  ipcMain.handle("wizard:detect", () => {
    const wowPath = detectWowPath();
    return { wowPath, accounts: wowPath ? detectAccounts(wowPath) : [] };
  });
  ipcMain.handle("wizard:accounts", (_e, wowPath) => detectAccounts(wowPath));
  ipcMain.handle("wizard:save", (_e, cfg) => {
    setConfig({
      wowPath: cfg.wowPath,
      account: cfg.account,
      apiKey: cfg.apiKey,
      webUrl: cfg.webUrl || "https://nordavind.cc",
      cronSecret: cfg.cronSecret || "",
      startWithWindows: cfg.startWithWindows !== false,
    });
    win.close();
    onDone();
    return true;
  });
}

module.exports = { openWizard };
