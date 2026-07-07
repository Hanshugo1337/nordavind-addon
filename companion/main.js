"use strict";

const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage } = require("electron");
const path = require("path");
const { autoUpdater } = require("electron-updater");
const { SyncEngine } = require("./lib/sync-engine");
const { getConfig, isConfigured } = require("./config");

let tray = null;
let statusWin = null;
let engine = null;

function createStatusWindow() {
  if (statusWin) { statusWin.show(); return; }
  statusWin = new BrowserWindow({
    width: 900, height: 640, show: false, autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true },
  });
  statusWin.loadFile(path.join(__dirname, "renderer", "index.html"));
  statusWin.on("close", (e) => {
    if (!app.quitting) { e.preventDefault(); statusWin.hide(); } // hide to tray, don't quit
  });
  statusWin.once("ready-to-show", () => statusWin.show());
}

function trayIcon(state) {
  const color = state === "ok" ? "#33cc33" : state === "sync" ? "#f0c040" : "#ff3333";
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="6" fill="${color}"/></svg>`;
  return nativeImage.createFromDataURL("data:image/svg+xml;base64," + Buffer.from(svg).toString("base64"));
}

function updateTray() {
  if (!tray || !engine) return;
  const s = engine.getStatus();
  const state = s.lastError ? "err" : s.connected ? "ok" : "sync";
  tray.setImage(trayIcon(state));
  tray.setToolTip(`NordavindLC — ${s.connected ? s.playerCount + " spillere" : "kobler til…"}`);
}

function buildTrayMenu() {
  return Menu.buildFromTemplate([
    { label: "Synk nå", click: () => engine && engine.pollOnce().then(() => engine.syncScores()).catch(() => {}) },
    { label: "Åpne status", click: createStatusWindow },
    { type: "separator" },
    { label: "Avslutt", click: () => { app.quitting = true; app.quit(); } },
  ]);
}

function startEngine() {
  const c = getConfig();
  engine = new SyncEngine({ webUrl: c.webUrl, apiKey: c.apiKey, wowPath: c.wowPath, account: c.account });
  engine.start();
  setInterval(updateTray, 3000);
}

function registerIpc() {
  ipcMain.handle("status", () => engine.getStatus());
  ipcMain.handle("scores", () => engine.getScores());
  ipcMain.handle("loot", () => engine.getLoot());
  ipcMain.handle("trades", () => engine.getTrades());
  ipcMain.handle("sync", async () => { await engine.syncScores(); return engine.getStatus(); });
  ipcMain.handle("recalc", async (_e, mode) => engine.recalc(mode, getConfig().cronSecret));
}

app.whenReady().then(() => {
  tray = new Tray(trayIcon("sync"));
  tray.setContextMenu(buildTrayMenu());
  tray.on("click", createStatusWindow);
  registerIpc();

  if (!isConfigured()) {
    require("./wizard").openWizard(() => { startEngine(); });
  } else {
    startEngine();
  }

  app.setLoginItemSettings({ openAtLogin: getConfig().startWithWindows });

  autoUpdater.checkForUpdatesAndNotify().catch(() => {});
  setInterval(() => autoUpdater.checkForUpdatesAndNotify().catch(() => {}), 6 * 60 * 60 * 1000);
});

app.on("window-all-closed", () => { /* stay in tray, do not quit */ });
app.on("before-quit", () => { app.quitting = true; if (engine) engine.stop(); });
