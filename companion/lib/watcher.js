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
    this.statePath = path.join(__dirname, "..", "companion-state.json");
    this.lastMtime = 0;

    const state = this._loadState();
    this.lastExportCount = state.exportCount || 0;
    this.lastEditCount = state.editCount || 0;
  }

  _loadState() {
    try { return JSON.parse(fs.readFileSync(this.statePath, "utf-8")); }
    catch { return {}; }
  }

  _saveState() {
    fs.writeFileSync(this.statePath, JSON.stringify({
      exportCount: this.lastExportCount,
      editCount: this.lastEditCount,
    }), "utf-8");
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

    // Detect if SavedVariables were reset (e.g. addon reinstalled)
    if (pending.length < this.lastExportCount) {
      console.log(`[watcher] pendingExport reset detected (was ${this.lastExportCount}, now ${pending.length}) — resetting counter`);
      this.lastExportCount = 0;
      this._saveState();
    }

    if (pending.length <= this.lastExportCount) return [];
    return pending.slice(this.lastExportCount);
  }

  // Call after each successful export API call
  markExportSent() {
    this.lastExportCount++;
    this._saveState();
  }

  checkPendingEdits() {
    const stat = fs.statSync(this.svPath, { throwIfNoEntry: false });
    if (!stat) return [];

    const mtime = stat.mtimeMs;
    if (mtime <= this.lastMtime) return [];
    this.lastMtime = mtime;

    const vars = this.read();
    const db = vars?.NordavindLC_DB;
    if (!db?.pendingEdits) return [];

    const edits = Array.isArray(db.pendingEdits) ? db.pendingEdits : Object.values(db.pendingEdits);

    // Detect if SavedVariables were reset
    if (edits.length < this.lastEditCount) {
      console.log(`[watcher] pendingEdits reset detected (was ${this.lastEditCount}, now ${edits.length}) — resetting counter`);
      this.lastEditCount = 0;
      this._saveState();
    }

    if (edits.length <= this.lastEditCount) return [];
    return edits.slice(this.lastEditCount);
  }

  // Call after each successful edit API call
  markEditSent() {
    this.lastEditCount++;
    this._saveState();
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
