"use strict";

const test = require("node:test");
const assert = require("node:assert");
const { SyncEngine } = require("../lib/sync-engine");

// Build a SyncEngine with the watcher + api replaced by in-memory fakes.
function makeEngine(awardImpl, queue) {
  const engine = new SyncEngine({ webUrl: "http://x", apiKey: "k", wowPath: "C:/nope", account: "A" });
  let sentCount = 0;
  engine.watcher = {
    checkPendingExports: () => queue,
    markExportSent: () => { sentCount++; },
  };
  engine.api = { awardLoot: awardImpl };
  return { engine, getSent: () => sentCount };
}

test("permanent 404 award is skipped so the queue progresses", async () => {
  const calls = [];
  const api = async (award) => {
    calls.push(award.awardedTo);
    if (award.awardedTo === "Braxina") { const e = new Error("404 not found"); e.status = 404; throw e; }
    return {};
  };
  const { engine, getSent } = makeEngine(api, [{ awardedTo: "Braxina" }, { awardedTo: "Alice" }]);
  await engine._processExports();
  assert.deepStrictEqual(calls, ["Braxina", "Alice"], "both attempted — not stuck on Braxina");
  assert.strictEqual(getSent(), 2, "both advanced (skip + success)");
});

test("transient 500 breaks so the batch retries next cycle", async () => {
  const calls = [];
  const api = async (award) => {
    calls.push(award.awardedTo);
    const e = new Error("500 server error"); e.status = 500; throw e;
  };
  const { engine, getSent } = makeEngine(api, [{ awardedTo: "Bob" }, { awardedTo: "Alice" }]);
  await engine._processExports();
  assert.deepStrictEqual(calls, ["Bob"], "stops at first transient failure");
  assert.strictEqual(getSent(), 0, "nothing advanced");
});
