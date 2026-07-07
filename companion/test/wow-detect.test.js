"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { detectAccounts } = require("../lib/wow-detect");

test("detectAccounts lists account folders and excludes SavedVariables", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "wow-"));
  const accBase = path.join(root, "_retail_", "WTF", "Account");
  fs.mkdirSync(path.join(accBase, "12345#1"), { recursive: true });
  fs.mkdirSync(path.join(accBase, "67890#2"), { recursive: true });
  fs.mkdirSync(path.join(accBase, "SavedVariables"), { recursive: true });

  const accounts = detectAccounts(root).sort();
  assert.deepStrictEqual(accounts, ["12345#1", "67890#2"]);
});

test("detectAccounts returns empty array for a missing path", () => {
  assert.deepStrictEqual(detectAccounts("C:/definitely/not/here"), []);
});
