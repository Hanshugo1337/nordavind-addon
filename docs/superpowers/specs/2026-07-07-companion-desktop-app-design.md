# Leveranse C — Proff companion desktop-app (Electron) — Design

**Dato:** 2026-07-07
**Prosjekt:** NordavindLC Companion (dagens `companion/` v2.0.0 → v3)
**Uavhengig av A og B** — kan bygges når som helst; berører ikke addon-koden.

---

## Mål

Erstatte dagens localhost-dashboard (Node/Express, må ha nettleser + konsoll åpen) med en
ekte desktop-app som bare kjører i bakgrunnen. Hovedplage som løses: **brukeropplevelse.**

Ønsket opplevelse:
- **System tray-ikon** — appen lever i bakgrunnen, ingen nettleser eller konsoll å holde åpen.
- **Tydelig status** — koblet / synker / feil, sist synket, antall spillere, antall ventende awards.
- **Auto-oppdatering** — appen oppdaterer seg selv.
- **Førstegangs-veiviser** — GUI for WoW-sti / konto-navn / API-nøkkel (erstatter `.env`).

## Teknologivalg (besluttet)

**Electron.** Gjenbruker dagens JavaScript-kode og dashboard nesten som det er; lettest å
vedlikeholde for en utvikler som er ny på koding. RAM-fotavtrykk (~80–150 MB) er ubetydelig
ved siden av WoW. (Tauri ble vurdert som lettere å kjøre, men krever Rust — for tungt å eie alene.)

## Arkitektur

```
Electron main-prosess
  ├─ Sync-motor (gjenbruk av dagens lib/):
  │    ├─ api-client.js      (uendret — samme endepunkter mot nordavind.cc)
  │    ├─ watcher.js         (HARDNET — se Reliabilitet under)
  │    └─ lua-parser.js      (gjenbruk; vurder herding)
  │    + fetchAndWriteScores / processExports / processEdits (fra dagens index.js)
  ├─ Tray-ikon + kontekstmeny (Synk nå, Åpne status, Innstillinger, Avslutt)
  ├─ Auto-update (electron-updater mot GitHub Releases)
  └─ Config-lagring (electron-store i appdata, ikke .env)

Electron renderer (statusvindu)
  └─ Gjenbruk av dagens public/ (index.html + app.js + style.css),
     tilpasset til å hente status via IPC i stedet for HTTP mot localhost:3333
```

**Kontrakt mot hjemmesiden er UENDRET:** samme `GET /api/loot/addon-export`,
`POST/PATCH /api/loot/addon`, samme `NordavindLC_Import`-skriving og
`pendingExport`/`pendingEdits`-lesing. Ingen endring på web-siden kreves.

## Funksjonell spesifikasjon

### 1. Tray-app (kjerne-UX)

- Starter minimert til tray ved oppstart (valgfritt: start med Windows).
- Tray-tooltip/ikon reflekterer tilstand (grønn = synket nylig, gul = synker, rød = feil).
- Høyreklikk-meny: **Synk nå**, **Åpne status**, **Innstillinger**, **Avslutt**.
- Statusvindu åpnes ved venstreklikk; lukking skjuler til tray (avslutter ikke).

### 2. Statusvindu

- Gjenbruker dagens dashboard-innhold (status, scores, loot-historikk, trades).
- Data hentes via Electron IPC fra main-prosessen (ikke lenger Express på localhost:3333).
- Viser: koblingsstatus, sist synket, antall spillere, ventende awards/edits, siste feil.

### 3. Førstegangs-veiviser

- Ved første oppstart (ingen lagret config): GUI-steg for
  **WoW-installasjonssti**, **konto-navn**, **API-nøkkel**, **web-URL** (default nordavind.cc).
- Auto-detekter WoW-sti og konto-navn der mulig (skann standard installasjonsstier +
  `_retail_/WTF/Account/`).
- Lagres via electron-store i appdata (ikke klartekst `.env` i prosjektmappa).

### 4. Auto-oppdatering

- `electron-updater` mot GitHub Releases (samme repo som addonen ligger i).
- Sjekker ved oppstart + periodisk; laster ned og installerer i bakgrunnen, varsler bruker.
- Bygg/pakking via `electron-builder` (NSIS-installer for Windows).

### 5. Reliabilitet (kommer «gratis» med omskrivingen)

- **Fiks mtime-bug-en:** i dag oppdaterer *både* `checkPendingExports` og `checkPendingEdits`
  `this.lastMtime`, så den andre ser `mtime <= lastMtime` og hopper over. Awards-edits kan
  gå tapt. Fiks: les fila én gang per poll-syklus og sjekk exports+edits mot samme snapshot,
  eller ikke muter delt mtime mellom de to.
- **Atomisk skriving av `NordavindLC_Import`:** skriv til temp-fil + rename, for å unngå
  korrupt SavedVariables hvis skriving avbrytes.
- **Behold backpressure** (`isSyncing`) og teller-basert dedup (`lastExportCount`/`lastEditCount`)
  med reset-deteksjon.

## Endringer / ny struktur

- **`companion/`** — ny Electron-struktur:
  - `main.js` (Electron main: tray, sync-loop, auto-update, IPC, config)
  - `preload.js` (sikker IPC-bro)
  - gjenbruk `lib/api-client.js`, `lib/watcher.js` (hardnet), `lib/lua-parser.js`
  - `renderer/` (fra dagens `public/`, tilpasset IPC)
  - `package.json` — legg til `electron`, `electron-builder`, `electron-updater`, `electron-store`;
    fjern `express` (ikke lenger localhost-server).
- **Beholdes:** all sync-logikk og web-kontrakt.

## Ikke inkludert (YAGNI)

- Ingen macOS/Linux-bygg (kun Windows — det er der WoW + guild-medlemmene er).
- Ingen endring i hjemmesidens API.
- Ingen endring i addon-koden (A/B er separate leveranser).
- Ingen kontoinnlogging/OAuth — API-nøkkel beholdes som autentisering.

## Åpne spørsmål (avklares i planen)

1. **Auto-update-feed:** GitHub Releases i addon-repoet, eller eget companion-repo? Krever
   at CI publiserer signerte Electron-artefakter.
2. **API-nøkkel-lagring:** electron-store (obfuskert) vs Windows Credential Manager. Nøkkelen
   er uansett tilgjengelig lokalt for eieren; velg enkleste trygge nivå.
3. **Start med Windows:** på som default, eller valgfritt i innstillinger?

## Testing / verifisering

- Første oppstart uten config → veiviser vises → config lagres → sync starter.
- Tray-ikon reflekterer status; statusvindu viser korrekte tall via IPC.
- Award i addon → dukker opp i pending → eksporteres til nordavind.cc (verifiser mot web).
- Award-**edit** eksporteres korrekt (regresjonstest for mtime-bug-en).
- Auto-update: bump versjon, publiser release, verifiser at kjørende app oppdaterer seg.
