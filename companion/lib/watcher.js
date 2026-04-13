"use strict";

const fs = require("fs");
const path = require("path");
const { parseSavedVariables, toSavedVariable } = require("./lua-parser");

class SavedVarsWatcher {
  constructor(wowPath, accountName) {
    this.svPath = path.join(
      wowPath, "_retail_", "WTF", "Account", accountName,
      "SavedVariables", "NordavindLC.lua"
    );
    this.lastMtime = 0;
    this.lastExportCount = 0;
    this.lastEditCount = 0;
  }

  exists() {
    return fs.existsSync(this.svPath);
  }

  read() {
    if (!this.exists()) return null;
    const content = fs.readFileSync(this.svPath, "utf-8");
    return parseSavedVariables(content);
  }

  checkPendingExports() {
    const stat = fs.statSync(this.svPath, { throwIfNoEntry: false });
    if (!stat) return [];

    const mtime = stat.mtimeMs;
    if (mtime <= this.lastMtime) return [];
    this.lastMtime = mtime;

    const vars = this.read();
    const db = vars?.NordavindLC_DB;
    if (!db?.pendingExport) return [];

    const pending = Array.isArray(db.pendingExport) ? db.pendingExport : Object.values(db.pendingExport);
    if (pending.length <= this.lastExportCount) return [];

    const newAwards = pending.slice(this.lastExportCount);
    this.lastExportCount = pending.length;
    return newAwards;
  }

  checkPendingEdits() {
    const stat = fs.statSync(this.svPath, { throwIfNoEntry: false });
    if (!stat) return [];

    const vars = this.read();
    const db = vars?.NordavindLC_DB;
    if (!db?.pendingEdits) return [];

    const edits = Array.isArray(db.pendingEdits) ? db.pendingEdits : Object.values(db.pendingEdits);
    if (edits.length <= this.lastEditCount) return [];

    const newEdits = edits.slice(this.lastEditCount);
    this.lastEditCount = edits.length;
    return newEdits;
  }

  writeImportData(scoringData) {
    let existing = "";
    if (this.exists()) {
      existing = fs.readFileSync(this.svPath, "utf-8");
    }

    const importStr = toSavedVariable("NordavindLC_Import", scoringData);

    if (existing.includes("NordavindLC_Import")) {
      existing = existing.replace(
        /NordavindLC_Import\s*=\s*(?:\{[^]*?\n\}|nil)/,
        importStr.trim()
      );
    } else {
      existing += "\n" + importStr;
    }

    fs.writeFileSync(this.svPath, existing, "utf-8");
  }
}

module.exports = { SavedVarsWatcher };
