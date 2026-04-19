#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const express = require("express");
const { ApiClient } = require("./lib/api-client");
const { SavedVarsWatcher } = require("./lib/watcher");
const { exec } = require("child_process");

// Load .env
const envPath = path.join(__dirname, ".env");
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, "utf-8").split("\n")) {
    const [key, ...rest] = line.split("=");
    if (key && rest.length > 0) process.env[key.trim()] = rest.join("=").trim();
  }
}

const WEB_URL = process.env.NORDAVIND_WEB_URL || "https://nordavind.cc";
const API_KEY = process.env.ADDON_API_KEY;
const WOW_PATH = process.env.WOW_INSTALL_PATH;
const ACCOUNT = process.env.WOW_ACCOUNT_NAME;
const PORT = 3333;

if (!API_KEY || !WOW_PATH || !ACCOUNT) {
  console.error("Missing required env vars. Copy .env.example to .env and fill in values.");
  process.exit(1);
}

const api = new ApiClient(WEB_URL, API_KEY);
const watcher = new SavedVarsWatcher(WOW_PATH, ACCOUNT);
const app = express();

app.use(express.static(path.join(__dirname, "public")));

// ---- State ----
let lastScores = null;
let lastSyncTime = null;
let lastError = null;
let syncCount = 0;
let isSyncing = false; // backpressure — prevent overlapping poll runs

// ---- API routes for the dashboard ----

app.get("/api/status", (req, res) => {
  res.json({
    connected: !!lastScores,
    lastSync: lastSyncTime,
    lastError,
    syncCount,
    wowPath: WOW_PATH,
    account: ACCOUNT,
    webUrl: WEB_URL,
    playerCount: lastScores ? Object.keys(lastScores.players || {}).length : 0,
  });
});

app.get("/api/scores", (req, res) => {
  if (!lastScores) return res.json({ players: {}, generatedAt: null });
  res.json(lastScores);
});

app.get("/api/loot", (req, res) => {
  try {
    const vars = watcher.read();
    const db = vars?.NordavindLC_DB;
    const history = db?.lootHistory || [];
    const recent = Array.isArray(history) ? history.slice(-50).reverse() : [];
    res.json(recent);
  } catch {
    res.json([]);
  }
});

app.get("/api/trades", (req, res) => {
  try {
    const vars = watcher.read();
    const db = vars?.NordavindLC_DB;
    const trades = db?.pendingTrades || [];
    res.json(Array.isArray(trades) ? trades : []);
  } catch {
    res.json([]);
  }
});

app.post("/api/sync", async (req, res) => {
  try {
    await fetchAndWriteScores();
    res.json({ ok: true, lastSync: lastSyncTime });
  } catch (err) {
    res.json({ ok: false, error: err.message });
  }
});

app.post("/api/recalc", async (req, res) => {
  const secret = process.env.CRON_SECRET;
  if (!secret) {
    return res.json({ ok: false, error: "CRON_SECRET not set in .env" });
  }
  try {
    const mode = req.query.mode || "full";
    const calcRes = await fetch(`${WEB_URL}/api/scores/calculate?mode=${mode}`, {
      method: "POST",
      headers: { "x-cron-secret": secret },
      signal: AbortSignal.timeout(60000),
    });
    const result = await calcRes.json();
    if (!calcRes.ok) throw new Error(result.error || "Calculation failed");
    await fetchAndWriteScores();
    res.json({ ok: true, ...result, lastSync: lastSyncTime });
  } catch (err) {
    res.json({ ok: false, error: err.message });
  }
});

// ---- Core sync logic ----

async function fetchAndWriteScores() {
  try {
    const data = await api.exportScoring();
    lastScores = data;
    lastSyncTime = new Date().toISOString();
    lastError = null;
    syncCount++;

    watcher.writeImportData(data);
    console.log(`[sync] Scores updated: ${Object.keys(data.players || {}).length} players (${lastSyncTime})`);
  } catch (err) {
    lastError = err.message;
    console.error("[sync] Failed:", err.message);
    throw err;
  }
}

async function processExports() {
  try {
    const awards = watcher.checkPendingExports();
    for (const award of awards) {
      try {
        await api.awardLoot(award);
        watcher.markExportSent(); // Only advance counter after confirmed success
        console.log(`[export] Synced: ${award.item} -> ${award.awardedTo}`);
      } catch (err) {
        console.error(`[export] Failed: ${award.item} ->`, err.message);
        break; // Stop and retry on next poll cycle
      }
    }
  } catch { /* file not found yet */ }
}

async function processEdits() {
  try {
    const edits = watcher.checkPendingEdits();
    for (const edit of edits) {
      try {
        await api.editAward(edit);
        watcher.markEditSent(); // Only advance counter after confirmed success
        console.log(`[edit] Synced: ${edit.item} -> ${edit.newAwardedTo} (${edit.newCategory})`);
      } catch (err) {
        console.error(`[edit] Failed: ${edit.item} ->`, err.message);
        break; // Stop and retry on next poll cycle
      }
    }
  } catch { /* file not found yet */ }
}

// ---- Startup ----

app.listen(PORT, async () => {
  console.log(`NordavindLC Companion running at http://localhost:${PORT}`);
  console.log(`[state] Export count resumed from: ${watcher.lastExportCount}, edit count: ${watcher.lastEditCount}`);

  const url = `http://localhost:${PORT}`;
  try {
    exec(`start "" "${url}"`, (err) => { if (err) console.log("Open browser manually:", url); });
  } catch { console.log("Open browser manually:", url); }

  // Initial sync
  try {
    await fetchAndWriteScores();
  } catch (err) {
    console.error("Initial sync failed:", err.message);
  }

  // Poll for loot exports and edits every 5 seconds (with backpressure)
  setInterval(async () => {
    if (isSyncing) return;
    isSyncing = true;
    try {
      await processExports();
      await processEdits();
    } finally {
      isSyncing = false;
    }
  }, 5000);

  // Re-fetch scores every 10 minutes
  setInterval(async () => {
    try { await fetchAndWriteScores(); } catch { /* logged in function */ }
  }, 10 * 60 * 1000);
});
