"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { ApiClient } = require("../lib/api-client");
const { SavedVarsWatcher } = require("../lib/watcher");

test("uploadRoster sender payload med api-noekkel", async () => {
  const kall = [];
  global.fetch = async (url, opts) => {
    kall.push({ url, opts });
    return { ok: true, json: async () => ({ ok: true, counts: { characters: 377 } }) };
  };
  const api = new ApiClient("https://nordavind.cc", "hemmelig");
  const svar = await api.uploadRoster({ capturedAt: 123, characters: [{ name: "Revo" }] });

  assert.strictEqual(svar.counts.characters, 377);
  assert.match(kall[0].url, /\/api\/roster$/);
  assert.strictEqual(kall[0].opts.headers["x-api-key"], "hemmelig");
  assert.strictEqual(JSON.parse(kall[0].opts.body).capturedAt, 123);
});

test("uploadRoster kaster med status ved feil, saa den kan proeves igjen", async () => {
  global.fetch = async () => ({ ok: false, status: 422, text: async () => "avvist" });
  const api = new ApiClient("https://nordavind.cc", "hemmelig");
  await assert.rejects(
    () => api.uploadRoster({ capturedAt: 1, characters: [] }),
    (err) => err.status === 422
  );
});

test("samme roster lastes ikke opp to ganger", () => {
  // Samme oppsett som test/watcher.test.js: konstruktoeren bygger stien selv
  // fra (wowPath, accountName), og statePath maa overstyres slik at testen
  // ikke skriver i den ekte companion-state.json paa maskinen.
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "nlc-"));
  const svDir = path.join(root, "_retail_", "WTF", "Account", "TEST", "SavedVariables");
  fs.mkdirSync(svDir, { recursive: true });
  fs.writeFileSync(path.join(svDir, "NordavindLC.lua"), `NordavindLC_DB = {
    ["pendingRosterImport"] = {
      ["capturedAt"] = 1755280000,
      ["characters"] = { { ["name"] = "Revo", ["rankIndex"] = 5 }, },
    },
  }
`, "utf-8");

  const w = new SavedVarsWatcher(root, "TEST");
  w.statePath = path.join(root, "companion-state.json");
  w.lastRosterCapturedAt = 0;

  const foerste = w.checkPendingRoster();
  assert.ok(foerste, "fikk ikke rosteret foerste gang");
  assert.strictEqual(foerste.capturedAt, 1755280000000);

  w.markRosterSent(foerste.capturedAt);
  assert.strictEqual(w.checkPendingRoster(), null, "samme roster ble hentet paa nytt");
});
