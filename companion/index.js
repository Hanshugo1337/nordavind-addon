#!/usr/bin/env node
"use strict";

// Allow self-signed cert when connecting to server via IP
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

const fs = require("fs");
const path = require("path");
const { ApiClient } = require("./lib/api-client");
const { SavedVarsWatcher } = require("./lib/watcher");

// Load .env
const envPath = path.join(__dirname, ".env");
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, "utf-8").split("\n")) {
    const [key, ...rest] = line.split("=");
    if (key && rest.length > 0) process.env[key.trim()] = rest.join("=").trim();
  }
}

const WEB_URL = process.env.NORDAVIND_WEB_URL || "https://nordavind.no";
const API_KEY = process.env.ADDON_API_KEY;
const WOW_PATH = process.env.WOW_INSTALL_PATH;
const ACCOUNT = process.env.WOW_ACCOUNT_NAME;

if (!API_KEY || !WOW_PATH || !ACCOUNT) {
  console.error("Missing required env vars. Copy .env.example to .env and fill in values.");
  process.exit(1);
}

const api = new ApiClient(WEB_URL, API_KEY);
const watcher = new SavedVarsWatcher(WOW_PATH, ACCOUNT);

const command = process.argv[2] || "watch";

async function importScoring() {
  console.log("Fetching scoring data from", WEB_URL, "...");
  const data = await api.exportScoring();
  const playerCount = Object.keys(data.players || {}).length;
  console.log(`Got ${playerCount} players, generated at ${data.generatedAt}`);

  watcher.writeImportData(data);
  console.log("Written to SavedVariables. Type /reload in WoW to load the data.");
}

async function processExports() {
  const awards = watcher.checkPendingExports();
  for (const award of awards) {
    try {
      const result = await api.awardLoot(award);
      console.log(`  Synced: ${award.item} -> ${award.awardedTo} (id: ${result.lootDropId})`);
    } catch (err) {
      console.error(`  Failed to sync: ${award.item} ->`, err.message);
    }
  }
  return awards.length;
}

async function watch() {
  console.log("NordavindLC Companion — watching for changes...");
  console.log(`  WoW: ${WOW_PATH}`);
  console.log(`  Account: ${ACCOUNT}`);
  console.log(`  API: ${WEB_URL}`);

  if (!watcher.exists()) {
    console.log("\nSavedVariables file not found yet. It will be created after your first /reload with the addon loaded.");
  }

  // Auto-import on startup
  try {
    await importScoring();
  } catch (err) {
    console.error("Auto-import failed:", err.message);
  }

  console.log("\nWatching for loot awards... (Ctrl+C to stop)");
  setInterval(async () => {
    try {
      const count = await processExports();
      if (count > 0) console.log(`Processed ${count} award(s)`);
    } catch (err) {
      console.error("Watch error:", err.message);
    }
  }, 5000);
}

async function main() {
  switch (command) {
    case "import":
      await importScoring();
      break;
    case "watch":
      await watch();
      break;
    default:
      console.log("Usage: nordavind-companion [import|watch]");
      console.log("  import  — fetch scoring data and write to SavedVariables");
      console.log("  watch   — auto-import + watch for loot awards (default)");
  }
}

main().catch(err => {
  console.error("Fatal:", err.message);
  process.exit(1);
});
