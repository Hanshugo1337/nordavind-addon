# Leveranse C — Proff companion desktop-app (Electron) — Implementasjonsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Erstatte localhost-dashboardet med en Electron tray-app som kjører i bakgrunnen, med auto-oppdatering, førstegangs-veiviser (erstatter `.env`), og en hardnet sync-motor som fikser mtime-bug-en.

**Architecture:** Electron main-prosess eier sync-motoren (gjenbruk av dagens `lib/`), tray-ikon, config (electron-store) og auto-update (electron-updater). Renderer gjenbruker dagens `public/`-dashboard, men henter status via IPC i stedet for HTTP mot `localhost:3333`. Kontrakten mot `nordavind.cc` er uendret.

**Tech Stack:** Node.js (CommonJS), Electron, electron-builder (NSIS), electron-updater, electron-store v8 (CommonJS), Node innebygd testrunner (`node --test`). Kun Windows.

**Uavhengig av A og B** — berører ikke addon-koden.

## Global Constraints

- **Web-kontrakt uendret:** samme `GET /api/loot/addon-export`, `POST/PATCH /api/loot/addon`, samme `NordavindLC_Import`-skriving og `pendingExport`/`pendingEdits`-lesing. Ingen web-endring.
- **Kun Windows** — ingen macOS/Linux-bygg.
- **Ingen OAuth** — API-nøkkel beholdes som autentisering.
- **CommonJS** — hele prosjektet bruker `require`/`module.exports` (ikke ESM). Derfor `electron-store@^8` (v9+ er ESM-only).
- **Behold sync-semantikk:** backpressure (`isSyncing`), teller-basert dedup (`lastExportCount`/`lastEditCount`) med reset-deteksjon. Ikke regrder disse.
- **Verifisering:** mtime-fiksen (Task 1) har ekte Node-tester (`node --test`). Electron-UI verifiseres manuelt (Task 8).

---

## Filstruktur

| Fil | Ansvar | Endring |
|-----|--------|---------|
| `companion/lib/watcher.js` | SavedVariables-lesing/skriving | **Modify:** fiks mtime-bug + atomisk skriving |
| `companion/test/watcher.test.js` | Tester for watcher | **Create:** mtime-bug-regresjon + atomisk skriving |
| `companion/lib/api-client.js` | HTTP mot nordavind.cc | **Keep:** uendret (`exportScoring`/`awardLoot`/`editAward`) |
| `companion/lib/lua-parser.js` | Lua ↔ JS | **Keep:** gjenbrukes |
| `companion/lib/sync-engine.js` | Sync-loop (uttrukket fra index.js) | **Create:** `fetchAndWriteScores`/`processExports`/`processEdits` + state |
| `companion/main.js` | Electron main | **Create:** tray, sync-loop, IPC, config, auto-update |
| `companion/preload.js` | Sikker IPC-bro | **Create:** `window.companion.*` |
| `companion/config.js` | electron-store-wrapper + auto-detect | **Create:** lagring + WoW-sti/konto-deteksjon |
| `companion/renderer/` | Statusvindu (fra `public/`) | **Create:** kopi av `public/`, `fetch` → IPC |
| `companion/wizard.html` + `wizard.js` | Førstegangs-veiviser | **Create:** GUI for sti/konto/nøkkel |
| `companion/package.json` | Manifest | **Modify:** Electron-deps, build-config; fjern express |
| `companion/index.js` | Gammel Express-server | **Delete:** erstattet av main.js (til slutt) |

---

### Task 1: Fiks mtime-bug + atomisk skriving i watcher (TDD)

**Files:**
- Modify: `companion/lib/watcher.js`
- Create: `companion/test/watcher.test.js`
- Modify: `companion/package.json` (test-script)

**Interfaces:**
- Consumes: `lib/lua-parser.js` (`parseSavedVariables`, `toSavedVariable`).
- Produces: `SavedVarsWatcher` der `checkPendingExports()` og `checkPendingEdits()` er uavhengige (egne mtime-spor), og `writeImportData` skriver atomisk (temp + rename).

**Bug:** i dag setter både `checkPendingExports` og `checkPendingEdits` delt `this.lastMtime`. Kjøres
exports først (index.js linje 191–192), ser edits `mtime <= lastMtime` og hopper over → edits tapes.

- [ ] **Step 1: Skriv den feilende testen**

Opprett `companion/test/watcher.test.js`:
```js
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
  w.statePath = path.join(root, "companion-state.json"); // isolate state
  return { w, svPath, root };
}

test("edits are not skipped when exports run first in the same cycle", () => {
  const { w } = makeWatcher(`{
    ["pendingExport"] = { { ["item"] = "ItemA", ["awardedTo"] = "Alice" } },
    ["pendingEdits"]  = { { ["item"] = "ItemB", ["newAwardedTo"] = "Bob", ["newCategory"] = "offspec" } },
  }`);
  const exports = w.checkPendingExports();
  const edits = w.checkPendingEdits();
  assert.strictEqual(exports.length, 1, "should see 1 export");
  assert.strictEqual(edits.length, 1, "should see 1 edit (bug makes this 0)");
});
```

- [ ] **Step 2: Legg til test-script og kjør — verifiser at den feiler**

I `companion/package.json` `scripts`: `"test": "node --test"`.
Run: `cd companion && npm test`
Expected: FAIL — «should see 1 edit» (edits.length === 0 med dagens delte mtime).

- [ ] **Step 3: Fiks — uavhengige mtime-spor**

I `watcher.js` konstruktør, erstatt `this.lastMtime = 0;` med:
```js
    this.lastExportMtime = 0;
    this.lastEditMtime = 0;
```
I `checkPendingExports`, erstatt `if (mtime <= this.lastMtime) return []; this.lastMtime = mtime;` med:
```js
    if (mtime <= this.lastExportMtime) return [];
    this.lastExportMtime = mtime;
```
I `checkPendingEdits`, tilsvarende med `this.lastEditMtime`. Nå advanserer de to strømmene hver for
seg — begge ser samme filendring.

- [ ] **Step 4: Kjør testen — verifiser at den passerer**

Run: `cd companion && npm test`
Expected: PASS.

- [ ] **Step 5: Legg til test + implementasjon for atomisk skriving**

Legg til i `watcher.test.js`:
```js
test("writeImportData writes atomically and preserves other globals", () => {
  const { w, svPath } = makeWatcher(`{ ["pendingExport"] = {} }`);
  w.writeImportData({ players: { Alice: { baseScore: 10 } }, generatedAt: 123 });
  const content = fs.readFileSync(svPath, "utf-8");
  assert.ok(content.includes("NordavindLC_Import"), "import written");
  assert.ok(content.includes("NordavindLC_DB"), "existing global preserved");
  assert.ok(!fs.existsSync(svPath + ".tmp"), "temp file cleaned up");
});
```
Run `npm test` → forvent FAIL på «temp file cleaned up» (skriving er ikke atomisk ennå).

I `writeImportData`, erstatt siste linje `fs.writeFileSync(this.svPath, existing, "utf-8");` med
atomisk temp+rename:
```js
    const tmp = this.svPath + ".tmp";
    fs.writeFileSync(tmp, existing, "utf-8");
    fs.renameSync(tmp, this.svPath);
```
Run `npm test` → forvent PASS (alle 2 tester).

- [ ] **Step 6: Commit**

```bash
git add companion/lib/watcher.js companion/test/watcher.test.js companion/package.json
git commit -m "fix(watcher): independent export/edit mtime tracking + atomic import write"
```

---

### Task 2: Trekk sync-motoren ut av index.js til gjenbrukbar modul

**Files:**
- Create: `companion/lib/sync-engine.js`

**Interfaces:**
- Consumes: `ApiClient`, `SavedVarsWatcher`.
- Produces: `class SyncEngine` med:
  - `constructor({ webUrl, apiKey, wowPath, account })`
  - `getStatus() -> { connected, lastSync, lastError, syncCount, playerCount, wowPath, account, webUrl, pendingAwards, pendingEdits }`
  - `getScores()` / `getLoot()` / `getTrades()`
  - `async syncScores()` / `async pollOnce()` (exports+edits med backpressure) / `async recalc(mode)`
  - `start()` (initial sync + intervaller) / `stop()`

Ren logikk-modul uten Electron/Express — mates av main.js. Løfter dagens funksjoner fra `index.js`
(`fetchAndWriteScores`/`processExports`/`processEdits`) inn i klassen, uendret oppførsel.

- [ ] **Step 1: Skriv SyncEngine**

```js
"use strict";
const { ApiClient } = require("./api-client");
const { SavedVarsWatcher } = require("./watcher");

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
    this.isSyncing = false;
    this._timers = [];
  }

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
      pendingAwards: db?.pendingExport ? this._len(db.pendingExport) - this.watcher.lastExportCount : 0,
      pendingEdits: db?.pendingEdits ? this._len(db.pendingEdits) - this.watcher.lastEditCount : 0,
    };
  }

  _len(x) { return Array.isArray(x) ? x.length : Object.keys(x).length; }
  _safeRead() { try { return this.watcher.read()?.NordavindLC_DB; } catch { return null; } }

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
      return data;
    } catch (err) { this.lastError = err.message; throw err; }
  }

  async _processExports() {
    try {
      for (const award of this.watcher.checkPendingExports()) {
        try { await this.api.awardLoot(award); this.watcher.markExportSent(); }
        catch (err) { this.lastError = err.message; break; }
      }
    } catch { /* file not ready */ }
  }

  async _processEdits() {
    try {
      for (const edit of this.watcher.checkPendingEdits()) {
        try { await this.api.editAward(edit); this.watcher.markEditSent(); }
        catch (err) { this.lastError = err.message; break; }
      }
    } catch { /* file not ready */ }
  }

  async pollOnce() {
    if (this.isSyncing) return;
    this.isSyncing = true;
    try { await this._processExports(); await this._processEdits(); }
    finally { this.isSyncing = false; }
  }

  async recalc(mode, cronSecret) {
    if (!cronSecret) throw new Error("CRON_SECRET ikke satt");
    const res = await fetch(`${this.webUrl}/api/scores/calculate?mode=${mode || "full"}`, {
      method: "POST", headers: { "x-cron-secret": cronSecret },
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
  stop() { this._timers.forEach(clearInterval); this._timers = []; }
}

module.exports = { SyncEngine };
```

- [ ] **Step 2: Røyktest at modulen laster**

Run: `cd companion && node -e "require('./lib/sync-engine'); console.log('ok')"`
Expected: `ok` (ingen syntaksfeil / manglende require).

- [ ] **Step 3: Commit**

```bash
git add companion/lib/sync-engine.js
git commit -m "refactor(companion): extract SyncEngine from index.js (Electron-agnostic)"
```

---

### Task 3: Config-modul (electron-store) + WoW-auto-deteksjon

**Files:**
- Create: `companion/config.js`
- Modify: `companion/package.json` (legg til `electron-store@^8`)

**Interfaces:**
- Produces:
  - `getConfig() -> { webUrl, apiKey, wowPath, account, cronSecret, startWithWindows }`
  - `setConfig(partial)` / `isConfigured() -> boolean`
  - `detectWowPath() -> string|null` / `detectAccounts(wowPath) -> string[]`

- [ ] **Step 1: Skriv config.js**

```js
"use strict";
const fs = require("fs");
const path = require("path");
const Store = require("electron-store");

const store = new Store({ name: "companion-config" });

function getConfig() {
  return {
    webUrl: store.get("webUrl", "https://nordavind.cc"),
    apiKey: store.get("apiKey", ""),
    wowPath: store.get("wowPath", ""),
    account: store.get("account", ""),
    cronSecret: store.get("cronSecret", ""),
    startWithWindows: store.get("startWithWindows", true),
  };
}
function setConfig(partial) { for (const [k, v] of Object.entries(partial)) store.set(k, v); }
function isConfigured() {
  const c = getConfig();
  return !!(c.apiKey && c.wowPath && c.account);
}

// Skann vanlige installasjonsstier for WoW retail.
function detectWowPath() {
  const candidates = [
    "C:\\Program Files (x86)\\World of Warcraft",
    "C:\\Program Files\\World of Warcraft",
    "D:\\World of Warcraft",
    "C:\\Games\\World of Warcraft",
  ];
  for (const p of candidates) {
    if (fs.existsSync(path.join(p, "_retail_", "WTF", "Account"))) return p;
  }
  return null;
}

// List konto-mapper under _retail_/WTF/Account/ (ekskluder SavedVariables o.l.)
function detectAccounts(wowPath) {
  try {
    const dir = path.join(wowPath, "_retail_", "WTF", "Account");
    return fs.readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory() && d.name !== "SavedVariables")
      .map((d) => d.name);
  } catch { return []; }
}

module.exports = { getConfig, setConfig, isConfigured, detectWowPath, detectAccounts };
```

- [ ] **Step 2: Legg til dependency**

Run: `cd companion && npm install electron-store@^8`
Expected: lagt til i `package.json` dependencies, ingen feil.

- [ ] **Step 3: Commit**

```bash
git add companion/config.js companion/package.json companion/package-lock.json
git commit -m "feat(companion): electron-store config + WoW path/account auto-detect"
```

---

### Task 4: Electron main — tray, sync-loop, IPC

**Files:**
- Create: `companion/main.js`
- Create: `companion/preload.js`
- Modify: `companion/package.json` (`main`, `electron` devDep, `start`-script)

**Interfaces:**
- Consumes: `SyncEngine`, `config.js`.
- Produces: Electron-app med tray-ikon, statusvindu, og IPC-kanaler `status`/`scores`/`loot`/`trades`/`sync`/`recalc`.

- [ ] **Step 1: preload.js — sikker IPC-bro**

```js
"use strict";
const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("companion", {
  getStatus: () => ipcRenderer.invoke("status"),
  getScores: () => ipcRenderer.invoke("scores"),
  getLoot: () => ipcRenderer.invoke("loot"),
  getTrades: () => ipcRenderer.invoke("trades"),
  sync: () => ipcRenderer.invoke("sync"),
  recalc: (mode) => ipcRenderer.invoke("recalc", mode),
});
```

- [ ] **Step 2: main.js — app, tray, vindu, IPC, sync**

```js
"use strict";
const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage } = require("electron");
const path = require("path");
const { SyncEngine } = require("./lib/sync-engine");
const { getConfig, isConfigured, setConfig } = require("./config");

let tray = null;
let statusWin = null;
let engine = null;

function createStatusWindow() {
  if (statusWin) { statusWin.show(); return; }
  statusWin = new BrowserWindow({
    width: 900, height: 640, show: false, autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true },
  });
  statusWin.loadFile(path.join(__dirname, "renderer", "index.html"));
  statusWin.on("close", (e) => { e.preventDefault(); statusWin.hide(); }); // skjul, ikke avslutt
  statusWin.once("ready-to-show", () => statusWin.show());
}

function trayIcon(state) {
  // 16x16 ensfarget prikk: grønn=ok, gul=synker, rød=feil. Enkel generert PNG (data-URI).
  const color = state === "ok" ? "#33cc33" : state === "sync" ? "#f0c040" : "#ff3333";
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="6" fill="${color}"/></svg>`;
  return nativeImage.createFromDataURL("data:image/svg+xml;base64," + Buffer.from(svg).toString("base64"));
}

function updateTray() {
  if (!tray || !engine) return;
  const s = engine.getStatus();
  const state = s.lastError ? "err" : s.connected ? "ok" : "sync";
  tray.setImage(trayIcon(state));
  tray.setToolTip(`NordavindLC — ${s.connected ? s.playerCount + " spillere" : "kobler til…"}`);
}

function buildTrayMenu() {
  return Menu.buildFromTemplate([
    { label: "Synk nå", click: () => engine.pollOnce().then(() => engine.syncScores()).catch(() => {}) },
    { label: "Åpne status", click: createStatusWindow },
    { type: "separator" },
    { label: "Avslutt", click: () => { app.quitting = true; app.quit(); } },
  ]);
}

function startEngine() {
  const c = getConfig();
  engine = new SyncEngine({ webUrl: c.webUrl, apiKey: c.apiKey, wowPath: c.wowPath, account: c.account });
  engine.start();
  setInterval(updateTray, 3000);
}

function registerIpc() {
  ipcMain.handle("status", () => engine.getStatus());
  ipcMain.handle("scores", () => engine.getScores());
  ipcMain.handle("loot", () => engine.getLoot());
  ipcMain.handle("trades", () => engine.getTrades());
  ipcMain.handle("sync", async () => { await engine.syncScores(); return engine.getStatus(); });
  ipcMain.handle("recalc", async (_e, mode) => engine.recalc(mode, getConfig().cronSecret));
}

app.whenReady().then(() => {
  tray = new Tray(trayIcon("sync"));
  tray.setContextMenu(buildTrayMenu());
  tray.on("click", createStatusWindow);
  registerIpc();

  if (!isConfigured()) {
    // Veiviser (Task 5) — midlertidig: åpne status uansett til den finnes.
    require("./wizard").openWizard(() => { startEngine(); });
  } else {
    startEngine();
  }
  // Start med Windows (Task 5 styrer flagget)
  app.setLoginItemSettings({ openAtLogin: getConfig().startWithWindows });
});

app.on("window-all-closed", (e) => { /* behold i tray, ikke avslutt */ });
app.on("before-quit", () => { if (engine) engine.stop(); });
```

- [ ] **Step 3: package.json — Electron-oppsett**

Endre `main` til `main.js`, legg til devDep `electron`, og scripts:
```json
  "main": "main.js",
  "scripts": { "start": "electron .", "test": "node --test" },
```
Run: `cd companion && npm install --save-dev electron`
Expected: Electron installert.

- [ ] **Step 4: Røyktest (uten full UI)**

Run: `cd companion && node -e "require('./main.js')" ` er ikke mulig (krever Electron-runtime).
I stedet: `node -e "require('./preload.js')"` forventes å feile med «contextBridge» kun i renderer —
verifiser i stedet syntaks: `node --check main.js && node --check preload.js`.
Expected: ingen syntaksfeil.

- [ ] **Step 5: Commit**

```bash
git add companion/main.js companion/preload.js companion/package.json companion/package-lock.json
git commit -m "feat(companion): Electron main with tray, status window and IPC sync"
```

---

### Task 5: Førstegangs-veiviser

**Files:**
- Create: `companion/wizard.html`, `companion/wizard.js`, `companion/wizard-preload.js`

**Interfaces:**
- Consumes: `config.js` (`detectWowPath`, `detectAccounts`, `setConfig`).
- Produces: `require("./wizard").openWizard(onDone)` — åpner et vindu; ved «Lagre» skriver config og kaller `onDone()`.

- [ ] **Step 1: wizard.js (main-side, åpner vindu + IPC)**

```js
"use strict";
const { BrowserWindow, ipcMain } = require("electron");
const path = require("path");
const { setConfig, detectWowPath, detectAccounts } = require("./config");

function openWizard(onDone) {
  const win = new BrowserWindow({
    width: 520, height: 520, resizable: false, autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, "wizard-preload.js"), contextIsolation: true },
  });
  win.loadFile(path.join(__dirname, "wizard.html"));

  ipcMain.handle("wizard:detect", () => {
    const wowPath = detectWowPath();
    return { wowPath, accounts: wowPath ? detectAccounts(wowPath) : [] };
  });
  ipcMain.handle("wizard:accounts", (_e, wowPath) => detectAccounts(wowPath));
  ipcMain.handle("wizard:save", (_e, cfg) => {
    setConfig({
      wowPath: cfg.wowPath, account: cfg.account, apiKey: cfg.apiKey,
      webUrl: cfg.webUrl || "https://nordavind.cc", cronSecret: cfg.cronSecret || "",
      startWithWindows: cfg.startWithWindows !== false,
    });
    win.close();
    onDone();
    return true;
  });
}
module.exports = { openWizard };
```

- [ ] **Step 2: wizard-preload.js**

```js
"use strict";
const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("wizard", {
  detect: () => ipcRenderer.invoke("wizard:detect"),
  accounts: (wowPath) => ipcRenderer.invoke("wizard:accounts", wowPath),
  save: (cfg) => ipcRenderer.invoke("wizard:save", cfg),
});
```

- [ ] **Step 3: wizard.html — GUI-steg (norsk)**

Ett enkelt skjema (gjenbruk `public/style.css` sitt mørke/gull-uttrykk): felt for WoW-sti
(forhåndsutfylt fra auto-detect), konto (dropdown fra `detectAccounts`), API-nøkkel, web-URL
(default nordavind.cc), valgfri CRON-secret, checkbox «Start med Windows». På load: kall
`window.wizard.detect()` og fyll feltene. På «Lagre»: `window.wizard.save({...})`.
```html
<!doctype html>
<html><head><meta charset="utf-8"><link rel="stylesheet" href="public/style.css"></head>
<body>
  <h1>NordavindLC Companion — oppsett</h1>
  <label>WoW-installasjonssti<input id="wowPath"></label>
  <label>Konto<select id="account"></select></label>
  <label>API-nøkkel<input id="apiKey"></label>
  <label>Web-URL<input id="webUrl" value="https://nordavind.cc"></label>
  <label>CRON-secret (valgfritt)<input id="cronSecret"></label>
  <label><input type="checkbox" id="startWithWindows" checked> Start med Windows</label>
  <button id="save">Lagre og start</button>
  <script src="wizard.js.browser"></script>
</body></html>
```
Og `wizard.js.browser` (renderer-side inline-script; kan legges direkte i html `<script>`):
```js
(async () => {
  const d = await window.wizard.detect();
  if (d.wowPath) document.getElementById("wowPath").value = d.wowPath;
  const sel = document.getElementById("account");
  sel.innerHTML = (d.accounts || []).map((a) => `<option>${a}</option>`).join("");
  document.getElementById("wowPath").addEventListener("change", async (e) => {
    const accs = await window.wizard.accounts(e.target.value);
    sel.innerHTML = accs.map((a) => `<option>${a}</option>`).join("");
  });
  document.getElementById("save").addEventListener("click", async () => {
    await window.wizard.save({
      wowPath: document.getElementById("wowPath").value,
      account: sel.value,
      apiKey: document.getElementById("apiKey").value,
      webUrl: document.getElementById("webUrl").value,
      cronSecret: document.getElementById("cronSecret").value,
      startWithWindows: document.getElementById("startWithWindows").checked,
    });
  });
})();
```
(Legg scriptet inline i `wizard.html` for å slippe ekstra fil; vist separat her for lesbarhet.)

- [ ] **Step 4: Syntakssjekk + commit**

Run: `cd companion && node --check wizard.js && node --check wizard-preload.js`
```bash
git add companion/wizard.html companion/wizard.js companion/wizard-preload.js
git commit -m "feat(companion): first-run setup wizard (path/account/key), replaces .env"
```

---

### Task 6: Renderer — statusvindu fra public/ via IPC

**Files:**
- Create: `companion/renderer/index.html`, `companion/renderer/app.js`, `companion/renderer/style.css`

**Interfaces:**
- Consumes: `window.companion.*` (fra preload.js).

Kopier dagens `public/`-innhold og bytt `fetch("/api/...")` med `window.companion.*`-kall.

- [ ] **Step 1: Kopier statiske filer**

Run: `cd companion && mkdir renderer && cp public/index.html renderer/index.html && cp public/style.css renderer/style.css`
(Behold `public/style.css` også — veiviseren refererer den.)

- [ ] **Step 2: renderer/app.js — bytt HTTP mot IPC**

Kopi av `public/app.js` med disse erstatningene (samme render-logikk, kun datakilde endres):
- `await fetch("/api/scores")` + `.json()` → `await window.companion.getScores()`
- `await fetch("/api/trades")` → `await window.companion.getTrades()`
- `await fetch("/api/loot")` → `await window.companion.getLoot()`
- `await fetch("/api/status")` → `await window.companion.getStatus()`
- `await fetch("/api/sync", { method: "POST" })` → `await window.companion.sync()`
- `await fetch("/api/recalc?mode=full", { method: "POST" })` → `await window.companion.recalc("full")`

Konkret eksempel (loadPlayers):
```js
async function loadPlayers() {
  const data = await window.companion.getScores();
  const players = Object.entries(data.players || {}).map(([name, p]) => ({ playerName: name, ...p }));
  window._playersData = players;
  renderPlayers(players);
}
```
Resten (`renderPlayers`, `loadTrades`, `loadLoot`, `loadSync`, `updateStatus`, sortering, tabs,
`setInterval`-ene) beholdes uendret bortsett fra datakilde-linjene over.

- [ ] **Step 3: Pek index.html til renderer/app.js**

I `renderer/index.html`, endre `<script src="app.js">` slik at den laster `renderer/app.js`
(relativ sti er allerede riktig siden fila ligger i samme mappe). Verifiser at `style.css`-referansen
peker på `style.css` i samme mappe.

- [ ] **Step 4: Syntakssjekk + commit**

Run: `cd companion && node --check renderer/app.js`
```bash
git add companion/renderer
git commit -m "feat(companion): status window renderer over IPC (from public dashboard)"
```

---

### Task 7: Auto-oppdatering + electron-builder-pakking

**Files:**
- Modify: `companion/package.json` (build-config, electron-updater, electron-builder)
- Modify: `companion/main.js` (autoUpdater-kobling)

**Interfaces:**
- Consumes: `electron-updater` (`autoUpdater`).

- [ ] **Step 1: Legg til deps**

Run: `cd companion && npm install electron-updater@^6 && npm install --save-dev electron-builder@^24`

- [ ] **Step 2: build-config i package.json**

```json
  "build": {
    "appId": "cc.nordavind.companion",
    "productName": "NordavindLC Companion",
    "win": { "target": "nsis" },
    "publish": [{ "provider": "github", "owner": "<owner>", "repo": "<addon-repo>" }],
    "files": ["main.js", "preload.js", "config.js", "wizard*.js", "wizard.html", "lib/**", "renderer/**", "public/**"]
  },
  "scripts": {
    "start": "electron .",
    "test": "node --test",
    "dist": "electron-builder"
  }
```
(`<owner>`/`<addon-repo>` fylles ut mot repoet der GitHub Releases publiseres — se Åpent spørsmål #1.)

- [ ] **Step 3: Koble autoUpdater i main.js**

Øverst i main.js: `const { autoUpdater } = require("electron-updater");`
I `app.whenReady().then(...)` etter tray-oppsett:
```js
  autoUpdater.checkForUpdatesAndNotify().catch(() => {});
  setInterval(() => autoUpdater.checkForUpdatesAndNotify().catch(() => {}), 6 * 60 * 60 * 1000);
```

- [ ] **Step 4: Verifiser pakking**

Run: `cd companion && npm run dist`
Expected: `dist/`-mappe med NSIS-installer (`.exe`). (Signering ikke påkrevd for privat guild-bruk;
Windows SmartScreen-advarsel aksepteres.)

- [ ] **Step 5: Commit**

```bash
git add companion/package.json companion/package-lock.json companion/main.js
git commit -m "feat(companion): electron-updater auto-update + electron-builder NSIS packaging"
```

---

### Task 8: Rydd bort Express + verifisering

**Files:**
- Delete: `companion/index.js`
- Modify: `companion/package.json` (fjern `express`)

- [ ] **Step 1: Fjern Express-serveren**

Run: `cd companion && npm uninstall express && git rm index.js`
(Alt fra index.js er nå i `SyncEngine` + `main.js`.)

- [ ] **Step 2: Manuell verifisering (reell gate)**

- [ ] Førstegangs: slett lagret config (`electron-store` fil i appdata) → start `npm start` →
  veiviser vises → auto-detektert sti/konto → fyll nøkkel → Lagre → sync starter, tray blir grønn.
- [ ] Tray: høyreklikk viser Synk nå / Åpne status / Avslutt. Venstreklikk åpner statusvindu.
  Lukk-knapp skjuler til tray (avslutter ikke).
- [ ] Statusvindu: spillere/scores/loot/trades vises via IPC (ikke HTTP). «Synk nå» oppdaterer.
- [ ] Award-regresjon: gjør en award i addon → `pendingExport` → dukker opp på nordavind.cc.
- [ ] **Edit-regresjon (mtime-bug):** gjør en award-**edit** i addon → verifiser at den
  eksporteres (PATCH) selv når en vanlig award skjedde samme poll-syklus.
- [ ] Auto-update: bump `version`, `npm run dist`, publiser release → kjørende app oppdaterer seg.

- [ ] **Step 3: Commit**

```bash
git add companion/package.json companion/package-lock.json
git commit -m "chore(companion): remove Express localhost server (replaced by Electron)"
```

---

## Self-Review (utført ved skriving)

- **Spec-dekning:** tray-app (Task 4), statusvindu via IPC (Task 6), auto-update (Task 7),
  førstegangs-veiviser (Task 5), mtime-bug-fiks + atomisk skriving (Task 1), backpressure/dedup
  bevart i `SyncEngine` (Task 2), WoW-auto-deteksjon (Task 3), Express fjernet (Task 8). ✔
- **Web-kontrakt:** `api-client.js` og `lua-parser.js` uendret; `writeImportData` skriver samme
  `NordavindLC_Import`; endepunktene like. ✔
- **Reliabilitet:** mtime splittet per strøm (Task 1) med ekte regresjonstest; atomisk temp+rename;
  `isSyncing`-backpressure og teller-dedup i `SyncEngine`. ✔
- **Placeholder-scan:** `<owner>`/`<addon-repo>` i Task 7 er bevisst utfyllings-felt (avhenger av
  Åpent spørsmål #1), ikke skjult TODO — eksplisitt markert. Resten er konkret kode. ✔
- **Type-konsistens:** IPC-kanalnavn (`status`/`scores`/`loot`/`trades`/`sync`/`recalc`) matcher
  mellom `preload.js`, `main.js` og `renderer/app.js`; `SyncEngine`-metodenavn matcher main.js-kall. ✔

## Åpne spørsmål (avklares under implementasjon)

1. **Auto-update-feed:** GitHub Releases i addon-repoet vs eget companion-repo (Task 7 `publish`).
2. **API-nøkkel-lagring:** electron-store (obfuskert) er valgt nivå; Windows Credential Manager er
   overkill for privat guild-bruk.
3. **Start med Windows:** default på (Task 4/5 `startWithWindows: true`), avslåbart i veiviser.

## Neste

Leveranse A (`2026-07-07-loot-detection-distributed.md`) og B (`2026-07-07-loot-distribution-flow.md`)
er separate. C er uavhengig og kan bygges når som helst.
