# NordavindLC Companion App + Server Scoring Redesign

## Problem

Scoring data for loot council requires manual steps (click "Analyser" on website, run companion CLI, /reload in WoW). The addon-export endpoint recalculates everything on each request (slow, duplicated logic). The companion app is CLI-only with no visibility into what's happening.

## Solution

### Part 1: Server-side Score Calculation (nordavind-web)

**New `PlayerScore` model in Prisma:**

```
PlayerScore {
  id            String   @id
  playerName    String   @unique
  attendance    Int      (0-100)
  wclParse      Float
  defensives    Float
  healthPots    Float
  dpsPots       Float
  mplusEffort   Int      (0/5/10)
  role          String   (dps/healer/tank)
  rank          String   (raider/backup/trial)
  lootThisWeek  Int
  lootTotal     Int
  deathPenalty  Float
  baseScore     Float
  updatedAt     DateTime
}
```

**New endpoint: `POST /api/scores/calculate`**
- Authenticated with `x-cron-secret` header
- Runs the existing scoring logic from addon-export (WowAudit roster, WCL, Discord ranks, Raider.IO, DB attendance/loot)
- Upserts results into `PlayerScore` table
- Returns count of players updated

**Simplified `GET /api/loot/addon-export`**
- Reads from `PlayerScore` table (instant, no external API calls)
- Returns same format as before (`{ players: { ... }, generatedAt }`)
- Falls back to live calculation if no scores exist yet

**Two calculation modes:**

`POST /api/scores/calculate?mode=full` (pre-raid, 20:25):
- WCL parses, Raider.IO M+, attendance, Discord ranks, deaths/defensives, loot
- Everything from scratch

`POST /api/scores/calculate?mode=live` (during raid, every 10 min):
- WCL parses (updates after each boss kill)
- Deaths/defensives (updates per fight)
- Loot penalties (updates when items are awarded)
- Keeps Raider.IO, attendance, Discord ranks from the full calculation

**Cron schedule (external, via VPS crontab or systemd timer):**
- Monday + Wednesday 20:25 CET → `mode=full`
- Monday + Wednesday 20:30–23:00 CET every 10 min → `mode=live`
- Calls `POST /api/scores/calculate` with cron secret

### Part 2: Companion App (localhost web dashboard)

**Tech:** Node.js + Express + static HTML/CSS/JS (no build step, no framework)

**Design:** Simple dark theme (#1a1a2e background, #e0e0e0 text, #c9a84c gold accents). No custom fonts or animations.

**URL:** `http://localhost:3333`

**Pages/sections (single page, tabbed):**

1. **Spillere** — table of all players with scores, sortable by column. Columns: Name, Score, Attendance, Parse, M+, Rank, Loot (week), Loot (total)
2. **Trades** — pending trades list (items awarded but not traded). Shows item, awarded to, category, timestamp.
3. **Loot Log** — recent loot awards from the addon. Shows item, player, boss, category, timestamp.
4. **Sync** — status panel. Last sync time, next sync time, WoW path, connection status (green/red dot).

**Auto-sync behavior:**
- On startup: fetch scores from API, write to WoW SavedVariables
- Every 60 seconds: check WoW SavedVariables for new loot awards, sync to API
- Every 10 minutes (during raid hours): re-fetch scores from API
- Outside raid hours: fetch once on startup, then only watch for exports

**WoW SavedVariables integration:**
- Reads/writes `NordavindLC.lua` in WoW's WTF folder (same as current companion)
- Reuses existing `lua-parser.js` for reading/writing Lua tables

**Startup:**
- `Start Companion.bat` → starts server → auto-opens `localhost:3333` in default browser
- `.env` file for config (WoW path, account name, API key, web URL)

**No build step required.** Plain HTML served by Express. CSS inline or in a single file.

## Files Changed

### nordavind-web
- `prisma/schema.prisma` — add PlayerScore model
- `prisma/migrations/` — new migration
- `app/api/scores/calculate/route.ts` — new cron endpoint
- `app/api/loot/addon-export/route.ts` — simplify to read from DB
- `lib/scoring.ts` — extract shared scoring logic

### nordavind-addon/companion
- `index.js` — rewrite as Express server with API routes
- `public/index.html` — dashboard UI
- `public/style.css` — dark theme
- `public/app.js` — client-side JS (fetch data, render tables, auto-refresh)
- `lib/api-client.js` — keep, minor updates
- `lib/watcher.js` — keep, minor updates
- `lib/lua-parser.js` — keep as-is
- `package.json` — add express dependency
- `Start Companion.bat` — keep as-is

## Out of Scope

- Authentication/multi-user (only one officer uses it)
- Electron/desktop app packaging
- Mobile support
- Real-time WebSocket updates (polling is fine for 10-min intervals)
