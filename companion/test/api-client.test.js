"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { ApiClient } = require("../lib/api-client");

function fakeFetch(captured) {
  return async (url, opts) => {
    captured.url = url;
    captured.body = JSON.parse(opts.body);
    return { ok: true, json: async () => ({ ok: true, lootDropId: 1 }) };
  };
}

async function withFakeFetch(captured, fn) {
  const orig = global.fetch;
  global.fetch = fakeFetch(captured);
  try {
    await fn();
  } finally {
    global.fetch = orig;
  }
}

test("awardLoot sender note videre til API-et", async () => {
  const captured = {};
  await withFakeFetch(captured, () =>
    new ApiClient("https://nordavind.cc", "key").awardLoot({
      item: "Voidforged Greaves",
      awardedTo: "Reevo",
      awardedBy: "Fisk",
      boss: "Kaelthar",
      timestamp: 1755500000,
      category: "upgrade",
      note: "officer-avstemming 3-2-1 — oppmøte feilregistrert",
    })
  );
  assert.equal(captured.body.note, "officer-avstemming 3-2-1 — oppmøte feilregistrert");
  assert.equal(captured.body.category, "upgrade");
});

test("awardLoot uten note utelater feltet helt", async () => {
  const captured = {};
  await withFakeFetch(captured, () =>
    new ApiClient("https://nordavind.cc", "key").awardLoot({
      item: "Voidforged Greaves",
      awardedTo: "Reevo",
      awardedBy: "Fisk",
      boss: "Kaelthar",
      timestamp: 1755500000,
      category: "upgrade",
    })
  );
  // JSON.stringify dropper nøkler med verdi undefined, så API-et ser aldri
  // feltet og skriver NULL — i stedet for å overskrive med tom streng.
  assert.equal("note" in captured.body, false);
});

test("editAward sender fortsatt newCategory", async () => {
  const captured = {};
  await withFakeFetch(captured, () =>
    new ApiClient("https://nordavind.cc", "key").editAward({
      originalTimestamp: 1755500000,
      item: "Voidforged Greaves",
      newAwardedTo: "Braxina",
      newCategory: "offspec",
    })
  );
  assert.equal(captured.body.newCategory, "offspec");
  assert.equal(captured.body.newAwardedTo, "Braxina");
});
