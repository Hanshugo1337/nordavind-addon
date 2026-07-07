"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("companion", {
  getStatus: () => ipcRenderer.invoke("status"),
  getScores: () => ipcRenderer.invoke("scores"),
  getLoot: () => ipcRenderer.invoke("loot"),
  getTrades: () => ipcRenderer.invoke("trades"),
  sync: () => ipcRenderer.invoke("sync"),
  recalc: (mode) => ipcRenderer.invoke("recalc", mode),
});
