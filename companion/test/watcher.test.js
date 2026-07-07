"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { SavedVarsWatcher } = require("../lib/watcher");

function makeWatcher(dbBody) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "nlc-"));
  const svDir = path.join(root, "_retail_", "WTF", "Account", "TEST", "SavedVariables");
  fs.mkdirSync(svDir, { recursive: true });
  const svPath = path.join(svDir, "NordavindLC.lua");
  fs.writeFileSync(svPath, `NordavindLC_DB = ${dbBody}\n`, "utf-8");
  const w = new SavedVarsWatcher(root, "TEST");
  // Isolate from any real companion-state.json on this machine.
  w.statePath = path.join(root, "companion-state.json");
  w.lastExportCount = 0;
  w.lastEditCount = 0;
  return { w, svPath, root };
}

test("edits are not skipped when exports run first in the same cycle", () => {
  const { w } = makeWatcher(`{
    ["pendingExport"] = { { ["item"] = "ItemA", ["awardedTo"] = "Alice" }, },
    ["pendingEdits"] = { { ["item"] = "ItemB", ["newAwardedTo"] = "Bob", ["newCategory"] = "offspec" }, },
  }`);
  const exports = w.checkPendingExports();
  const edits = w.checkPendingEdits();
  assert.strictEqual(exports.length, 1, "should see 1 export");
  assert.strictEqual(edits.length, 1, "should see 1 edit (shared-mtime bug makes this 0)");
});

test("writeImportData preserves other globals and leaves no temp file", () => {
  const { w, svPath } = makeWatcher(`{ ["pendingExport"] = {}, }`);
  w.writeImportData({ players: { Alice: { baseScore: 10 } }, generatedAt: 123 });
  const content = fs.readFileSync(svPath, "utf-8");
  assert.ok(content.includes("NordavindLC_Import"), "import written");
  assert.ok(content.includes("NordavindLC_DB"), "existing global preserved");
  assert.ok(!fs.existsSync(svPath + ".tmp"), "temp file cleaned up");
});
