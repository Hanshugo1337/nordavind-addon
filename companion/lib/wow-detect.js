"use strict";

// Pure-fs WoW install/account detection. No Electron dependency, so it is unit-testable
// headlessly (config.js layers electron-store on top).

const fs = require("fs");
const path = require("path");

// Scan common retail install paths for a WoW folder with a WTF/Account dir.
function detectWowPath() {
  const candidates = [
    "C:\\Program Files (x86)\\World of Warcraft",
    "C:\\Program Files\\World of Warcraft",
    "D:\\World of Warcraft",
    "C:\\Games\\World of Warcraft",
  ];
  for (const p of candidates) {
    if (fs.existsSync(path.join(p, "_retail_", "WTF", "Account"))) return p;
  }
  return null;
}

// List account folders under _retail_/WTF/Account/ (excluding the shared SavedVariables dir).
function detectAccounts(wowPath) {
  try {
    const dir = path.join(wowPath, "_retail_", "WTF", "Account");
    return fs.readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory() && d.name !== "SavedVariables")
      .map((d) => d.name);
  } catch { return []; }
}

module.exports = { detectWowPath, detectAccounts };
