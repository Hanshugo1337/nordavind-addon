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

test("sync-engine laster opp rosteret og markerer det sendt", async () => {
  const { SyncEngine } = require("../lib/sync-engine");
  const sendt = [];
  const watcher = {
    checkPendingExports: () => [],
    checkPendingEdits: () => [],
    checkPendingRoster: () => (sendt.length ? null : { capturedAt: 5000, characters: [{ name: "Revo" }] }),
    markRosterSent: (t) => sendt.push(t),
  };
  const api = { uploadRoster: async (p) => ({ ok: true, counts: { characters: p.characters.length } }) };
  const eng = new SyncEngine({ webUrl: "http://x", apiKey: "k", wowPath: "C:/nope", account: "A" });
  eng.watcher = watcher;
  eng.api = api;
  await eng._processRoster();
  assert.deepStrictEqual(sendt, [5000]);
});

test("avvist roster (4xx) markeres sendt saa koeen ikke laaser seg", async () => {
  const { SyncEngine } = require("../lib/sync-engine");
  const sendt = [];
  const watcher = {
    checkPendingRoster: () => ({ capturedAt: 5000, characters: [] }),
    markRosterSent: (t) => sendt.push(t),
  };
  const api = {
    uploadRoster: async () => { const e = new Error("avvist"); e.status = 422; throw e; },
  };
  const eng = new SyncEngine({ webUrl: "http://x", apiKey: "k", wowPath: "C:/nope", account: "A" });
  eng.watcher = watcher;
  eng.api = api;
  await eng._processRoster();
  // Serveren sa at dette rosteret er ubrukelig — aa sende det igjen for alltid
  // hjelper ingen. Brukeren maa fange paa nytt.
  assert.deepStrictEqual(sendt, [5000]);
});

test("statePath kan injiseres — pakket app maa ha en skrivbar sti", () => {
  // I en pakket app ligger __dirname inne i app.asar (skrivebeskyttet). Uten
  // injeksjon kastet _saveState hver gang, og rosteret ble lastet opp paa nytt
  // hver syklus fordi capturedAt aldri overlevde.
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "nlc-"));
  const egen = path.join(root, "min-state.json");
  const w = new SavedVarsWatcher(root, "TEST", egen);
  assert.strictEqual(w.statePath, egen);

  w.lastRosterCapturedAt = 4242;
  w._saveState();
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(egen, "utf-8")).rosterCapturedAt, 4242);
});

test("_saveState kaster ikke naar stien er uskrivbar", () => {
  // Ellers maskerer en feilet tilstandsskriving seg som en feilet opplasting.
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "nlc-"));
  const umulig = path.join(root, "finnes", "ikke", "state.json");
  const w = new SavedVarsWatcher(root, "TEST", umulig);
  assert.doesNotThrow(() => w._saveState());
});
