"use strict";

const { ApiClient } = require("./api-client");
const { SavedVarsWatcher } = require("./watcher");

// Electron/Express-agnostic sync engine. Owns the score fetch/write loop and the
// export/edit poll with backpressure. Fed by the host (main.js / index.js).
class SyncEngine {
  constructor({ webUrl, apiKey, wowPath, account }) {
    this.webUrl = webUrl;
    this.api = new ApiClient(webUrl, apiKey);
    this.watcher = new SavedVarsWatcher(wowPath, account);
    this.wowPath = wowPath;
    this.account = account;
    this.lastScores = null;
    this.lastSyncTime = null;
    this.lastError = null;
    this.syncCount = 0;
    this.isSyncing = false; // backpressure — prevent overlapping poll runs
    this._timers = [];
  }

  _len(x) { return Array.isArray(x) ? x.length : Object.keys(x).length; }
  _safeRead() { try { return this.watcher.read()?.NordavindLC_DB; } catch { return null; } }

  getStatus() {
    const db = this._safeRead();
    return {
      connected: !!this.lastScores,
      lastSync: this.lastSyncTime,
      lastError: this.lastError,
      syncCount: this.syncCount,
      playerCount: this.lastScores ? Object.keys(this.lastScores.players || {}).length : 0,
      wowPath: this.wowPath,
      account: this.account,
      webUrl: this.webUrl,
      pendingAwards: db?.pendingExport ? Math.max(0, this._len(db.pendingExport) - this.watcher.lastExportCount) : 0,
      pendingEdits: db?.pendingEdits ? Math.max(0, this._len(db.pendingEdits) - this.watcher.lastEditCount) : 0,
    };
  }

  getScores() { return this.lastScores || { players: {}, generatedAt: null }; }

  getLoot() {
    const h = this._safeRead()?.lootHistory || [];
    return Array.isArray(h) ? h.slice(-50).reverse() : [];
  }

  getTrades() {
    const t = this._safeRead()?.pendingTrades || [];
    return Array.isArray(t) ? t : [];
  }

  async syncScores() {
    try {
      const data = await this.api.exportScoring();
      this.lastScores = data;
      this.lastSyncTime = new Date().toISOString();
      this.lastError = null;
      this.syncCount++;
      this.watcher.writeImportData(data);
      console.log(`[sync] Scores updated: ${Object.keys(data.players || {}).length} players (${this.lastSyncTime})`);
      return data;
    } catch (err) {
      this.lastError = err.message;
      console.error("[sync] Failed:", err.message);
      throw err;
    }
  }

  // A permanent client error (4xx, e.g. 404 "Character not found") will never succeed on
  // retry, so skip past it — otherwise it jams the whole queue forever. Transient errors
  // (network/5xx) still break so the batch retries next cycle.
  _isPermanent(err) {
    return typeof err.status === "number" && err.status >= 400 && err.status < 500;
  }

  async _processExports() {
    try {
      for (const award of this.watcher.checkPendingExports()) {
        try {
          await this.api.awardLoot(award);
          this.watcher.markExportSent();
          console.log(`[export] Synced: ${award.item} -> ${award.awardedTo}`);
        } catch (err) {
          this.lastError = err.message;
          if (this._isPermanent(err)) {
            console.warn(`[export] Skipping permanently-failing award: ${award.item} -> ${award.awardedTo} (${err.message})`);
            this.watcher.markExportSent(); // advance past the dead entry
            continue;
          }
          console.error(`[export] Failed: ${award.item} ->`, err.message);
          break; // transient — stop and retry next cycle
        }
      }
    } catch { /* file not ready yet */ }
  }

  async _processEdits() {
    try {
      for (const edit of this.watcher.checkPendingEdits()) {
        try {
          await this.api.editAward(edit);
          this.watcher.markEditSent();
          console.log(`[edit] Synced: ${edit.item} -> ${edit.newAwardedTo} (${edit.newCategory})`);
        } catch (err) {
          this.lastError = err.message;
          if (this._isPermanent(err)) {
            console.warn(`[edit] Skipping permanently-failing edit: ${edit.item} -> ${edit.newAwardedTo} (${err.message})`);
            this.watcher.markEditSent(); // advance past the dead entry
            continue;
          }
          console.error(`[edit] Failed: ${edit.item} ->`, err.message);
          break;
        }
      }
    } catch { /* file not ready yet */ }
  }

  async _processRoster() {
    try {
      const roster = this.watcher.checkPendingRoster();
      if (!roster) return;
      try {
        const svar = await this.api.uploadRoster(roster);
        this.watcher.markRosterSent(roster.capturedAt);
        console.log(`[roster] Lastet opp ${roster.characters.length} karakterer` +
          (svar?.counts ? ` (${svar.counts.withNote} med note)` : ""));
      } catch (err) {
        this.lastError = err.message;
        if (this._isPermanent(err)) {
          // Serveren sa at rosteret er ubrukelig — typisk avkuttet. Aa sende
          // det igjen for alltid hjelper ingen; brukeren maa fange paa nytt.
          console.warn(`[roster] Avvist av serveren, hopper over: ${err.message}`);
          this.watcher.markRosterSent(roster.capturedAt);
          return;
        }
        console.error("[roster] Opplasting feilet:", err.message);
      }
    } catch { /* file not ready yet */ }
  }

  async pollOnce() {
    if (this.isSyncing) return;
    this.isSyncing = true;
    try {
      await this._processExports();
      await this._processEdits();
      await this._processRoster();
    } finally {
      this.isSyncing = false;
    }
  }

  async recalc(mode, cronSecret) {
    if (!cronSecret) throw new Error("CRON_SECRET ikke satt");
    const res = await fetch(`${this.webUrl}/api/scores/calculate?mode=${mode || "full"}`, {
      method: "POST",
      headers: { "x-cron-secret": cronSecret },
      signal: AbortSignal.timeout(60000),
    });
    const result = await res.json();
    if (!res.ok) throw new Error(result.error || "Beregning feilet");
    await this.syncScores();
    return result;
  }

  start() {
    this.syncScores().catch(() => {});
    this._timers.push(setInterval(() => this.pollOnce(), 5000));
    this._timers.push(setInterval(() => this.syncScores().catch(() => {}), 10 * 60 * 1000));
  }

  stop() {
    this._timers.forEach(clearInterval);
    this._timers = [];
  }
}

module.exports = { SyncEngine };
