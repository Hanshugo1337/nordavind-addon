"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { SavedVarsWatcher } = require("../lib/watcher");
const { parseSavedVariables } = require("../lib/lua-parser");

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

test("writeImportData replaces a WoW-serialized import block without leaving an orphaned tail", () => {
  const { w, svPath } = makeWatcher(`{ ["pendingExport"] = {}, }`);
  // WoW's native serializer writes EVERY closing brace at column 0 (unlike the
  // companion's indented output). This is what Core.lua's logout write-back
  // produces, and it triggered the "unexpected symbol near '['" corruption.
  const wowStyle = [
    "NordavindLC_Import = {",
    '["players"] = {',
    '["Testshaman"] = {',
    '["baseScore"] = 36.2,',
    "},",
    '["Testpaladin"] = {',
    '["baseScore"] = 32,',
    "},",
    "},",
    '["generatedAt"] = "old",',
    "}",
    "",
  ].join("\n");
  fs.appendFileSync(svPath, wowStyle, "utf-8");

  w.writeImportData({ players: { Alice: { baseScore: 10 } }, generatedAt: 1 });
  const content = fs.readFileSync(svPath, "utf-8");

  assert.ok(content.includes("Alice"), "new import written");
  assert.ok(!content.includes("Testshaman"), "old import fully removed");
  assert.ok(!content.includes("Testpaladin"), "no orphaned tail left behind");

  const open = (content.match(/\{/g) || []).length;
  const close = (content.match(/\}/g) || []).length;
  assert.strictEqual(open, close, "braces balanced (valid Lua)");

  const vars = parseSavedVariables(content);
  assert.ok(vars.NordavindLC_DB, "existing global preserved");
  assert.strictEqual(vars.NordavindLC_Import.players.Alice.baseScore, 10, "new data parses");
});
