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
    icon: path.join(__dirname, "renderer", "logo.png"),
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true },
  });
  statusWin.loadFile(path.join(__dirname, "renderer", "index.html"));
  statusWin.on("close", (e) => {
    if (!app.quitting) { e.preventDefault(); statusWin.hide(); } // hide to tray, don't quit
  });
  statusWin.once("ready-to-show", () => statusWin.show());
}

function trayImage() {
  return nativeImage
    .createFromPath(path.join(__dirname, "renderer", "logo.png"))
    .resize({ width: 16, height: 16 });
}

// Tray icon is the logo; sync status is conveyed via the tooltip (colour dot emoji).
function updateTray() {
  if (!tray || !engine) return;
  const s = engine.getStatus();
  const dot = s.lastError ? "🔴" : s.connected ? "🟢" : "🟡";
  const state = s.lastError ? "Feil" : s.connected ? `${s.playerCount} spillere` : "kobler til…";
  tray.setToolTip(`${dot} NordavindLC — ${state}`);
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
  // userData er skrivbart; __dirname ligger inne i app.asar i en pakket app.
  const statePath = path.join(app.getPath("userData"), "companion-state.json");
  engine = new SyncEngine({ webUrl: c.webUrl, apiKey: c.apiKey, wowPath: c.wowPath, account: c.account, statePath });
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
  tray = new Tray(trayImage());
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
