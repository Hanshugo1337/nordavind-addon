"use strict";

const fs = require("fs");
const path = require("path");
const { parseSavedVariables, toSavedVariable } = require("./lua-parser");

/**
 * Replace an existing top-level `name = <table|nil>` assignment with `replacement`.
 *
 * Uses brace-depth scanning (string-aware) to find the exact end of the value,
 * so it works whether the block was written by the companion (only the outer `}`
 * at column 0) or re-serialized by WoW on logout (every `}` at column 0). The old
 * `/\{[^]*?\n\}/` regex matched lazily to the FIRST column-0 `}` — for WoW-written
 * blocks that is an inner brace, so the rest was left orphaned at file scope and
 * produced "unexpected symbol near '['". Returns null if the global isn't present.
 */
function replaceGlobalAssignment(content, name, replacement) {
  const m = new RegExp(`^${name}\\s*=\\s*`, "m").exec(content);
  if (!m) return null;

  const valueStart = m.index + m[0].length;
  let end;

  if (content[valueStart] === "{") {
    let depth = 0, inStr = false, strChar = "";
    let pos = valueStart;
    for (; pos < content.length; pos++) {
      const ch = content[pos];
      if (inStr) {
        if (ch === "\\") { pos++; continue; }
        if (ch === strChar) inStr = false;
        continue;
      }
      if (ch === '"' || ch === "'") { inStr = true; strChar = ch; continue; }
      if (ch === "{") depth++;
      else if (ch === "}") { depth--; if (depth === 0) { pos++; break; } }
    }
    if (depth !== 0) return null; // unbalanced — don't risk a corrupt splice
    end = pos;
  } else if (content.startsWith("nil", valueStart)) {
    end = valueStart + 3;
  } else {
    return null;
  }

  return content.slice(0, m.index) + replacement + content.slice(end);
}

class SavedVarsWatcher {
  constructor(wowPath, accountName) {
    this.svPath = path.join(
      wowPath, "_retail_", "WTF", "Account", accountName,
      "SavedVariables", "NordavindLC.lua"
    );
    this.statePath = path.join(__dirname, "..", "companion-state.json");
    // Independent mtime tracking per stream — a shared mtime made whichever ran
    // second (exports vs edits) skip the file it hadn't processed yet.
    this.lastExportMtime = 0;
    this.lastEditMtime = 0;

    const state = this._loadState();
    this.lastExportCount = state.exportCount || 0;
    this.lastEditCount = state.editCount || 0;
    this.lastRosterCapturedAt = state.rosterCapturedAt || 0;
  }

  _loadState() {
    try { return JSON.parse(fs.readFileSync(this.statePath, "utf-8")); }
    catch { return {}; }
  }

  _saveState() {
    fs.writeFileSync(this.statePath, JSON.stringify({
      exportCount: this.lastExportCount,
      editCount: this.lastEditCount,
      rosterCapturedAt: this.lastRosterCapturedAt || 0,
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
    if (mtime <= this.lastExportMtime) return [];
    this.lastExportMtime = mtime;

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
    if (mtime <= this.lastEditMtime) return [];
    this.lastEditMtime = mtime;

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

    const replaced = replaceGlobalAssignment(existing, "NordavindLC_Import", importStr.trim());
    if (replaced !== null) {
      existing = replaced;
    } else {
      existing = existing.replace(/\s*$/, "") + "\n" + importStr;
    }

    // Atomic write: temp file + rename, so an interrupted write can't corrupt SavedVariables.
    const tmp = this.svPath + ".tmp";
    fs.writeFileSync(tmp, existing, "utf-8");
    fs.renameSync(tmp, this.svPath);
  }
  checkPendingRoster() {
    const stat = fs.statSync(this.svPath, { throwIfNoEntry: false });
    if (!stat) return null;

    const vars = this.read();
    const roster = vars?.NordavindLC_DB?.pendingRosterImport;
    if (!roster?.characters) return null;

    // Oeyeblikksbilde, ikke koe: last opp kun hvis fangsten er nyere enn den
    // vi allerede har sendt. Ellers lastes samme roster opp ved hver syklus.
    const capturedAt = Number(roster.capturedAt) || 0;
    if (capturedAt <= (this.lastRosterCapturedAt || 0)) return null;

    return {
      capturedAt: capturedAt * 1000, // Lua time() er sekunder, JS bruker ms
      characters: Array.isArray(roster.characters)
        ? roster.characters
        : Object.values(roster.characters),
    };
  }

  markRosterSent(capturedAt) {
    this.lastRosterCapturedAt = Math.floor(capturedAt / 1000);
    this._saveState();
  }

}

module.exports = { SavedVarsWatcher };
