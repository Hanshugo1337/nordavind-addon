"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("wizard", {
  detect: () => ipcRenderer.invoke("wizard:detect"),
  accounts: (wowPath) => ipcRenderer.invoke("wizard:accounts", wowPath),
  save: (cfg) => ipcRenderer.invoke("wizard:save", cfg),
});
