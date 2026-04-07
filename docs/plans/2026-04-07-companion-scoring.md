# Companion App + Server Scoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-calculate player scores on raid nights and serve them via a polished companion web dashboard that syncs data to WoW.

**Architecture:** Server stores scores in a `PlayerScore` DB table, calculated via cron on Mon/Wed. Full calc at 20:25 (all sources), live refresh every 10 min during raid (WCL + deaths + loot only). Companion app is an Express server at localhost:3333 with static HTML dashboard — fetches scores from API, writes to WoW SavedVariables, syncs loot awards back.

**Tech Stack:** Next.js API routes (nordavind-web), Prisma/PostgreSQL, Node.js/Express (companion), vanilla HTML/CSS/JS (dashboard)

**Repos:**
- `C:\Users\lovin\OneDrive\Documents\git\nordavind-web` — server scoring
- `C:\Users\lovin\OneDrive\Documents\git\nordavind-addon\companion` — companion app

---

## Part 1: Server-side Scoring (nordavind-web)

### Task 1: Add PlayerScore model to Prisma

**Files:**
- Modify: `prisma/schema.prisma`
- Create: `prisma/migrations/<timestamp>_add_player_scores/migration.sql`

- [ ] **Step 1: Add PlayerScore model to schema.prisma**

Add at the end of the file, before the closing:

```prisma
model PlayerScore {
  id            String   @id @default(uuid())
  playerName    String   @unique @map("player_name")
  attendance    Int      @default(0)
  wclParse      Float    @default(0)
  defensives    Float    @default(0)
  healthPots    Float    @default(0)
  dpsPots       Float    @default(0)
  mplusEffort   Int      @default(0) @map("mplus_effort")
  role          String   @default("dps")
  rank          String   @default("trial")
  lootThisWeek  Int      @default(0) @map("loot_this_week")
  lootTotal     Int      @default(0) @map("loot_total")
  deathPenalty  Float    @default(0) @map("death_penalty")
  baseScore     Float    @default(0) @map("base_score")
  className     String?  @map("class_name")
  updatedAt     DateTime @updatedAt @map("updated_at")

  @@map("player_scores")
}
```

- [ ] **Step 2: Create migration SQL**

Create file `prisma/migrations/20260407200000_add_player_scores/migration.sql`:

```sql
CREATE TABLE IF NOT EXISTS "player_scores" (
    "id" TEXT NOT NULL,
    "player_name" TEXT NOT NULL,
    "attendance" INTEGER NOT NULL DEFAULT 0,
    "wcl_parse" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "defensives" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "health_pots" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "dps_pots" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "mplus_effort" INTEGER NOT NULL DEFAULT 0,
    "role" TEXT NOT NULL DEFAULT 'dps',
    "rank" TEXT NOT NULL DEFAULT 'trial',
    "loot_this_week" INTEGER NOT NULL DEFAULT 0,
    "loot_total" INTEGER NOT NULL DEFAULT 0,
    "death_penalty" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "base_score" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "class_name" TEXT,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "player_scores_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "player_scores_player_name_key" ON "player_scores"("player_name");
```

- [ ] **Step 3: Commit**

```bash
cd C:\Users\lovin\OneDrive\Documents\git\nordavind-web
git add prisma/schema.prisma prisma/migrations/20260407200000_add_player_scores/
git commit -m "feat: add PlayerScore model for persistent scoring"
```

---

### Task 2: Extract shared scoring logic to lib/scoring.ts

**Files:**
- Create: `lib/scoring.ts`

This extracts the scoring formula and data-fetching from the 300-line `addon-export/route.ts` into a reusable module.

- [ ] **Step 1: Create lib/scoring.ts**

```typescript
import { prisma } from "@/lib/prisma";
import {
  batchGetCharacterPerformance,
  getGuildPerformanceData,
  type CharacterPerformance,
  type PlayerRaidStats,
} from "@/lib/warcraftlogs";

const WCL_ZONE_ID = 46;
const WCL_SERVER_REGION = "eu";
const WOWAUDIT_API_KEY = process.env.WOWAUDIT_API_KEY || "";
const HEALER_ROLES = new Set(["Healer", "Heal"]);

const CLASS_DEFENSIVE_COUNT: Record<string, number> = {
  "Death Knight":4,"Druid":4,"Hunter":4,"Mage":7,"Monk":3,"Paladin":4,
  "Priest":3,"Rogue":3,"Shaman":1,"Warlock":3,"Warrior":5,"Demon Hunter":3,"Evoker":2,
};

export interface PlayerScoreData {
  playerName: string;
  attendance: number;
  wclParse: number;
  defensives: number;
  healthPots: number;
  dpsPots: number;
  mplusEffort: number;
  role: string;
  rank: string;
  lootThisWeek: number;
  lootTotal: number;
  deathPenalty: number;
  baseScore: number;
  className: string | null;
}

// ---- Data source fetchers ----

export async function fetchRoster(): Promise<any[]> {
  const res = await fetch("https://wowaudit.com/v1/characters", {
    headers: { Authorization: WOWAUDIT_API_KEY, Accept: "application/json" },
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) throw new Error("WowAudit API error");
  return res.json();
}

export async function fetchDiscordMembers(): Promise<Map<string, string[]>> {
  const TOKEN = process.env.DISCORD_BOT_TOKEN;
  const GUILD_ID = process.env.GUILD_ID;
  const members = new Map<string, string[]>();
  if (!TOKEN || !GUILD_ID) return members;

  try {
    const res = await fetch(
      `https://discord.com/api/v10/guilds/${GUILD_ID}/members?limit=1000`,
      { headers: { Authorization: `Bot ${TOKEN}` }, signal: AbortSignal.timeout(10000) }
    );
    if (res.ok) {
      for (const m of await res.json()) {
        if (m.user?.id) members.set(m.user.id, m.roles || []);
      }
    }
  } catch (e) { console.warn("[scoring] Discord fetch error:", e); }
  return members;
}

export function buildNameToDiscordMap(discordMembers: Map<string, string[]>): Map<string, string> {
  // This requires fetching members again for nick/username info
  // We'll handle this in the calculate function
  return new Map();
}

export async function fetchMplusData(): Promise<Map<string, number>> {
  const mplusMap = new Map<string, number>();
  try {
    const rioRes = await fetch(
      "https://raider.io/api/v1/guilds/profile?region=eu&realm=draenor&name=Nordavind&fields=members",
      { signal: AbortSignal.timeout(15000) }
    );
    if (!rioRes.ok) return mplusMap;

    const guild = await rioRes.json();
    for (const m of guild.members || []) {
      const name = m.character?.name;
      if (!name) continue;
      try {
        const charRes = await fetch(
          `https://raider.io/api/v1/characters/profile?region=eu&realm=${encodeURIComponent(m.character.realm)}&name=${encodeURIComponent(name)}&fields=mythic_plus_previous_weekly_highest_level_runs,mythic_plus_weekly_highest_level_runs`,
          { signal: AbortSignal.timeout(5000) }
        );
        if (charRes.ok) {
          const charData = await charRes.json();
          const prevWeekRuns = charData.mythic_plus_previous_weekly_highest_level_runs?.length || 0;
          const currWeekRuns = charData.mythic_plus_weekly_highest_level_runs?.length || 0;
          mplusMap.set(name.toLowerCase(), prevWeekRuns > 0 ? prevWeekRuns : currWeekRuns);
        }
      } catch { /* individual char optional */ }
    }
  } catch (e) { console.warn("[scoring] Raider.IO error:", e); }
  return mplusMap;
}

export async function fetchAttendance(): Promise<{ attendanceCount: Map<string, number>; totalRaids: number }> {
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const recentRaids = await prisma.raid.findMany({
    where: { dateTime: { gte: thirtyDaysAgo, lte: new Date() }, status: { not: "cancelled" }, raidType: { not: "social" } },
    include: { attendance: { include: { user: true } } },
  });
  const raidsWithAttendance = recentRaids.filter(r => r.attendance.length > 0);
  const attendanceCount = new Map<string, number>();
  for (const raid of raidsWithAttendance) {
    for (const att of raid.attendance) {
      if (att.present) {
        attendanceCount.set(att.user.discordId, (attendanceCount.get(att.user.discordId) || 0) + 1);
      }
    }
  }
  return { attendanceCount, totalRaids: raidsWithAttendance.length };
}

export async function fetchLootCounts(): Promise<{ thisWeek: Map<string, number>; allTime: Map<string, number> }> {
  const now = new Date();
  const utcDay = now.getUTCDay();
  let daysSinceWed = (utcDay - 3 + 7) % 7;
  if (daysSinceWed === 0 && now.getUTCHours() < 6) daysSinceWed = 7;
  const resetStart = new Date(now);
  resetStart.setUTCDate(now.getUTCDate() - daysSinceWed);
  resetStart.setUTCHours(6, 0, 0, 0);

  const [lootThisWeekAll, lootAllTime] = await Promise.all([
    prisma.lootDrop.findMany({ where: { createdAt: { gte: resetStart } } }),
    prisma.lootDrop.findMany(),
  ]);

  const thisWeek = new Map<string, number>();
  const allTime = new Map<string, number>();
  for (const l of lootThisWeekAll) thisWeek.set(l.givenTo, (thisWeek.get(l.givenTo) || 0) + 1);
  for (const l of lootAllTime) allTime.set(l.givenTo, (allTime.get(l.givenTo) || 0) + 1);

  return { thisWeek, allTime };
}

// ---- Score calculation ----

export function calculateScore(p: {
  attendance: number; wclParse: number; mplusEffort: number;
  isDps: boolean; rank: string; lootThisWeek: number; lootTotal: number; deathPenalty: number;
}): number {
  let score = 0;
  score += Math.min(25, p.attendance * 0.25);
  score += Math.min(15, p.wclParse * 0.158);
  score += p.mplusEffort;
  score += p.isDps ? 5 : 0;
  score += p.rank === "raider" ? 5 : 0;
  score -= (p.lootThisWeek * 5) + (p.lootTotal * 2);
  score -= p.deathPenalty;
  return Math.round(score * 10) / 10;
}

// ---- Full + Live calculation ----

export async function calculateAllScores(mode: "full" | "live"): Promise<PlayerScoreData[]> {
  // Always needed: roster, loot, WCL, guild perf
  const roster = await fetchRoster();

  const dpsRoster = roster.filter((c: any) => !HEALER_ROLES.has(c.role));
  const healerRoster = roster.filter((c: any) => HEALER_ROLES.has(c.role));

  // WCL + guild perf (always refreshed — updates after each boss)
  let wclMap = new Map<string, CharacterPerformance>();
  let guildPerf = new Map<string, PlayerRaidStats>();
  if (process.env.WCL_CLIENT_ID) {
    const [dpsResult, hpsResult, guildPerfData] = await Promise.all([
      batchGetCharacterPerformance(dpsRoster, WCL_SERVER_REGION, WCL_ZONE_ID, undefined, "dps")
        .catch(() => new Map<string, CharacterPerformance>()),
      healerRoster.length > 0
        ? batchGetCharacterPerformance(healerRoster, WCL_SERVER_REGION, WCL_ZONE_ID, undefined, "hps")
            .catch(() => new Map<string, CharacterPerformance>())
        : Promise.resolve(new Map<string, CharacterPerformance>()),
      getGuildPerformanceData(WCL_ZONE_ID).catch(() => new Map<string, PlayerRaidStats>()),
    ]);
    wclMap = new Map([...dpsResult, ...hpsResult]);
    guildPerf = guildPerfData;
  }

  // Loot (always refreshed — changes during raid)
  const loot = await fetchLootCounts();

  // Full-only sources: M+, Discord, Attendance
  let mplusMap = new Map<string, number>();
  let discordMembers = new Map<string, string[]>();
  let nameToDiscord = new Map<string, string>();
  let attendanceData = { attendanceCount: new Map<string, number>(), totalRaids: 0 };

  if (mode === "full") {
    [mplusMap, discordMembers, attendanceData] = await Promise.all([
      fetchMplusData(),
      fetchDiscordMembers(),
      fetchAttendance(),
    ]);

    // Build name→discordId map from Discord nicknames
    const TOKEN = process.env.DISCORD_BOT_TOKEN;
    const GUILD_ID = process.env.GUILD_ID;
    if (TOKEN && GUILD_ID) {
      try {
        const res = await fetch(
          `https://discord.com/api/v10/guilds/${GUILD_ID}/members?limit=1000`,
          { headers: { Authorization: `Bot ${TOKEN}` }, signal: AbortSignal.timeout(10000) }
        );
        if (res.ok) {
          for (const m of await res.json()) {
            const names = [m.nick, m.user?.global_name, m.user?.username].filter(Boolean);
            for (const n of names) nameToDiscord.set(n.toLowerCase(), m.user.id);
          }
        }
      } catch { /* already have discordMembers */ }
    }
  } else {
    // Live mode: read M+, attendance, ranks from existing DB scores
    const existing = await prisma.playerScore.findMany();
    for (const s of existing) {
      mplusMap.set(s.playerName.toLowerCase(), s.mplusEffort);
    }
    // Still need discord + attendance for rank/attendance lookup
    // Read from existing scores instead of re-fetching
    const existingMap = new Map(existing.map(s => [s.playerName.toLowerCase(), s]));

    // We'll use existingMap below to fill in stable fields
    const guildConfig = await prisma.guildConfig.findFirst({ where: { guildId: process.env.GUILD_ID! } });

    const results: PlayerScoreData[] = [];
    for (const char of roster) {
      const nameLower = char.name.toLowerCase();
      const prev = existingMap.get(nameLower);

      const wcl = wclMap.get(nameLower);
      const wclParse = wcl?.medianParse ?? prev?.wclParse ?? 0;

      const raidStats = guildPerf.get(nameLower);
      const defCount = CLASS_DEFENSIVE_COUNT[char.class] || 2;
      const avgDefensives = raidStats && raidStats.totalFights > 0
        ? (raidStats.totalDefensives / raidStats.totalFights) / defCount : prev?.defensives ?? 0;
      const avgDeaths = raidStats && raidStats.totalFights > 0
        ? raidStats.totalDeaths / raidStats.totalFights : 0;
      const avgHealthPots = raidStats && raidStats.totalFights > 0
        ? raidStats.totalHealthConsumables / raidStats.totalFights : prev?.healthPots ?? 0;
      const avgDpsPots = raidStats && raidStats.totalFights > 0
        ? raidStats.totalDpsPots / raidStats.totalFights : prev?.dpsPots ?? 0;
      const deathPenalty = avgDeaths > 1.0 ? Math.round((avgDeaths - 1.0) * 3 * 10) / 10 : 0;

      // Stable fields from previous calculation
      const attendance = prev?.attendance ?? 100;
      const mplusEffort = prev?.mplusEffort ?? 0;
      const rank = prev?.rank ?? "trial";
      const role = prev?.role ?? "dps";

      const dbUser = await prisma.user.findFirst({
        where: { characters: { some: { name: { equals: char.name, mode: "insensitive" } } } },
      });
      const discordId = dbUser?.discordId || "";
      const lootThisWeek = loot.thisWeek.get(discordId) || 0;
      const lootAllTime = loot.allTime.get(discordId) || 0;
      const lootTotal = Math.max(0, lootAllTime - lootThisWeek);

      const isDps = char.role === "Melee" || char.role === "Ranged";
      const baseScore = calculateScore({ attendance, wclParse, mplusEffort, isDps, rank, lootThisWeek, lootTotal, deathPenalty });

      results.push({
        playerName: char.name,
        attendance, wclParse: Math.round(wclParse * 10) / 10,
        defensives: Math.round(avgDefensives * 10) / 10,
        healthPots: Math.round(avgHealthPots * 10) / 10,
        dpsPots: Math.round(avgDpsPots * 10) / 10,
        mplusEffort, role, rank, lootThisWeek, lootTotal, deathPenalty, baseScore,
        className: char.class || null,
      });
    }
    return results;
  }

  // Full mode: calculate everything from scratch
  const guildConfig = await prisma.guildConfig.findFirst({ where: { guildId: process.env.GUILD_ID! } });

  function getDiscordRank(discordId: string): "raider" | "backup" | "trial" {
    const roles = discordMembers.get(discordId);
    if (!roles || !guildConfig) return "trial";
    if (guildConfig.raiderRoleId && roles.includes(guildConfig.raiderRoleId)) return "raider";
    if (guildConfig.backupRoleId && roles.includes(guildConfig.backupRoleId)) return "backup";
    return "trial";
  }

  const results: PlayerScoreData[] = [];
  for (const char of roster) {
    const nameLower = char.name.toLowerCase();

    const dbUser = await prisma.user.findFirst({
      where: { characters: { some: { name: { equals: char.name, mode: "insensitive" } } } },
    });
    const discordId = dbUser?.discordId || nameToDiscord.get(nameLower) || "";

    const attended = attendanceData.attendanceCount.get(discordId) || 0;
    const attendance = attendanceData.totalRaids > 0 ? Math.round((attended / attendanceData.totalRaids) * 100) : 100;

    const wcl = wclMap.get(nameLower);
    const wclParse = wcl?.medianParse ?? 0;

    const raidStats = guildPerf.get(nameLower);
    const defCount = CLASS_DEFENSIVE_COUNT[char.class] || 2;
    const avgDefensives = raidStats && raidStats.totalFights > 0
      ? (raidStats.totalDefensives / raidStats.totalFights) / defCount : 0;
    const avgDeaths = raidStats && raidStats.totalFights > 0
      ? raidStats.totalDeaths / raidStats.totalFights : 0;
    const avgHealthPots = raidStats && raidStats.totalFights > 0
      ? raidStats.totalHealthConsumables / raidStats.totalFights : 0;
    const avgDpsPots = raidStats && raidStats.totalFights > 0
      ? raidStats.totalDpsPots / raidStats.totalFights : 0;

    const dungeonsDone = mplusMap.get(nameLower) || 0;
    const mplusEffort = dungeonsDone >= 4 ? 10 : dungeonsDone >= 2 ? 5 : 0;

    const isDps = char.role === "Melee" || char.role === "Ranged";
    const role = isDps ? "dps" : HEALER_ROLES.has(char.role) ? "healer" : "tank";
    const rank = getDiscordRank(discordId);

    const lootThisWeek = loot.thisWeek.get(discordId) || 0;
    const lootAllTime = loot.allTime.get(discordId) || 0;
    const lootTotal = Math.max(0, lootAllTime - lootThisWeek);

    const deathPenalty = avgDeaths > 1.0 ? Math.round((avgDeaths - 1.0) * 3 * 10) / 10 : 0;
    const baseScore = calculateScore({ attendance, wclParse, mplusEffort, isDps, rank, lootThisWeek, lootTotal, deathPenalty });

    results.push({
      playerName: char.name,
      attendance, wclParse: Math.round(wclParse * 10) / 10,
      defensives: Math.round(avgDefensives * 10) / 10,
      healthPots: Math.round(avgHealthPots * 10) / 10,
      dpsPots: Math.round(avgDpsPots * 10) / 10,
      mplusEffort, role, rank, lootThisWeek, lootTotal, deathPenalty, baseScore,
      className: char.class || null,
    });
  }

  return results;
}

// ---- Persist to DB ----

export async function saveScores(scores: PlayerScoreData[]): Promise<number> {
  let count = 0;
  for (const s of scores) {
    await prisma.playerScore.upsert({
      where: { playerName: s.playerName },
      create: { ...s, updatedAt: new Date() },
      update: { ...s, updatedAt: new Date() },
    });
    count++;
  }
  return count;
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/scoring.ts
git commit -m "feat: extract shared scoring logic to lib/scoring.ts"
```

---

### Task 3: Create cron endpoint POST /api/scores/calculate

**Files:**
- Create: `app/api/scores/calculate/route.ts`

- [ ] **Step 1: Create the endpoint**

```typescript
import { NextRequest, NextResponse } from "next/server";
import { calculateAllScores, saveScores } from "@/lib/scoring";

const CRON_SECRET = process.env.CRON_SECRET || "nordavind-cron-2026";

export async function POST(req: NextRequest) {
  const secret = req.headers.get("x-cron-secret");
  if (secret !== CRON_SECRET) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const mode = req.nextUrl.searchParams.get("mode") === "live" ? "live" : "full";

  try {
    console.log(`[scores] Calculating scores (mode=${mode})...`);
    const start = Date.now();
    const scores = await calculateAllScores(mode);
    const count = await saveScores(scores);
    const elapsed = ((Date.now() - start) / 1000).toFixed(1);
    console.log(`[scores] Done: ${count} players in ${elapsed}s`);

    return NextResponse.json({ ok: true, count, mode, elapsed: `${elapsed}s` });
  } catch (err: any) {
    console.error("[scores] Calculation error:", err);
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/api/scores/calculate/
git commit -m "feat: add POST /api/scores/calculate cron endpoint"
```

---

### Task 4: Simplify addon-export to read from PlayerScore

**Files:**
- Modify: `app/api/loot/addon-export/route.ts`

- [ ] **Step 1: Replace the entire route with DB read**

Replace the full contents of `app/api/loot/addon-export/route.ts` with:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

const ADDON_API_KEY = process.env.ADDON_API_KEY || "";

export async function GET(req: NextRequest) {
  const apiKey = req.headers.get("x-api-key");
  if (!ADDON_API_KEY || apiKey !== ADDON_API_KEY) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const scores = await prisma.playerScore.findMany();

    if (scores.length === 0) {
      return NextResponse.json({
        players: {},
        generatedAt: null,
        message: "No scores calculated yet. Run /api/scores/calculate first.",
      });
    }

    const players: Record<string, any> = {};
    let latestUpdate = new Date(0);

    for (const s of scores) {
      players[s.playerName] = {
        attendance: s.attendance,
        wclParse: s.wclParse,
        defensives: s.defensives,
        healthPots: s.healthPots,
        dpsPots: s.dpsPots,
        mplusEffort: s.mplusEffort,
        role: s.role,
        rank: s.rank,
        lootThisWeek: s.lootThisWeek,
        lootTotal: s.lootTotal,
        deathPenalty: s.deathPenalty,
        baseScore: s.baseScore,
      };
      if (s.updatedAt > latestUpdate) latestUpdate = s.updatedAt;
    }

    return NextResponse.json({
      players,
      generatedAt: latestUpdate.toISOString(),
    });
  } catch (err: any) {
    console.error("[addon-export]", err);
    return NextResponse.json({ error: "Failed" }, { status: 500 });
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/api/loot/addon-export/route.ts
git commit -m "refactor: addon-export reads from PlayerScore table instead of live calculation"
```

---

### Task 5: Set up cron on VPS

**Files:**
- None (VPS crontab configuration)

- [ ] **Step 1: SSH to VPS and add crontab entries**

```bash
ssh root@37.27.201.23 "crontab -l 2>/dev/null; echo '
# NordavindLC score calculation — Monday (1) and Wednesday (3)
# Full calculation at 20:25 CET
25 20 * * 1,3 curl -s -X POST -H \"x-cron-secret: nordavind-cron-2026\" \"http://localhost:3003/api/scores/calculate?mode=full\" >> /var/log/nordavind-scores.log 2>&1
# Live refresh every 10 min from 20:30 to 23:00 CET
30-59/10 20 * * 1,3 curl -s -X POST -H \"x-cron-secret: nordavind-cron-2026\" \"http://localhost:3003/api/scores/calculate?mode=live\" >> /var/log/nordavind-scores.log 2>&1
*/10 21-22 * * 1,3 curl -s -X POST -H \"x-cron-secret: nordavind-cron-2026\" \"http://localhost:3003/api/scores/calculate?mode=live\" >> /var/log/nordavind-scores.log 2>&1
'" | crontab -
```

Note: VPS timezone must be CET/CEST. Verify with `timedatectl` and adjust if needed.

---

## Part 2: Companion App

### Task 6: Rewrite companion as Express web dashboard

**Files:**
- Modify: `companion/package.json`
- Rewrite: `companion/index.js`
- Create: `companion/public/index.html`
- Create: `companion/public/style.css`
- Create: `companion/public/app.js`
- Keep: `companion/lib/lua-parser.js` (as-is)
- Keep: `companion/lib/api-client.js` (as-is)
- Keep: `companion/lib/watcher.js` (as-is)

- [ ] **Step 1: Update package.json with express dependency**

```json
{
  "name": "nordavind-companion",
  "version": "2.0.0",
  "description": "NordavindLC Companion — localhost dashboard for loot council scoring",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": {
    "express": "^4.21.0"
  }
}
```

- [ ] **Step 2: Rewrite index.js as Express server**

```javascript
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
    // Return last 50 entries, newest first
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
        console.log(`[export] Synced: ${award.item} -> ${award.awardedTo}`);
      } catch (err) {
        console.error(`[export] Failed: ${award.item} ->`, err.message);
      }
    }
  } catch { /* file not found yet */ }
}

// ---- Startup ----

app.listen(PORT, async () => {
  console.log(`NordavindLC Companion running at http://localhost:${PORT}`);

  // Auto-open in browser
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

  // Watch for loot exports every 5 seconds
  setInterval(() => processExports(), 5000);

  // Re-fetch scores every 10 minutes
  setInterval(async () => {
    try { await fetchAndWriteScores(); } catch { /* logged in function */ }
  }, 10 * 60 * 1000);
});
```

- [ ] **Step 3: Create public/style.css**

```css
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: #111; color: #e0e0e0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 14px; }

.header { background: #1a1a2e; padding: 16px 24px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #333; }
.header h1 { font-size: 18px; color: #c9a84c; font-weight: 600; }
.header .status { display: flex; align-items: center; gap: 8px; font-size: 13px; color: #888; }
.header .dot { width: 8px; height: 8px; border-radius: 50%; }
.dot.green { background: #2ecc71; }
.dot.red { background: #e74c3c; }

.tabs { display: flex; gap: 0; background: #1a1a2e; border-bottom: 1px solid #333; }
.tab { padding: 10px 20px; cursor: pointer; color: #888; border-bottom: 2px solid transparent; transition: all 0.15s; }
.tab:hover { color: #e0e0e0; }
.tab.active { color: #c9a84c; border-bottom-color: #c9a84c; }

.content { padding: 20px 24px; max-width: 1200px; }

table { width: 100%; border-collapse: collapse; }
th { text-align: left; padding: 8px 12px; font-size: 11px; text-transform: uppercase; color: #888; border-bottom: 1px solid #333; cursor: pointer; }
th:hover { color: #c9a84c; }
td { padding: 8px 12px; border-bottom: 1px solid #1a1a2e; }
tr:hover td { background: #1a1a2e; }

.score { color: #c9a84c; font-weight: 600; }
.rank-raider { color: #2ecc71; }
.rank-backup { color: #f0c040; }
.rank-trial { color: #e67e22; }

.sync-panel { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.sync-card { background: #1a1a2e; padding: 16px; border-radius: 6px; border: 1px solid #333; }
.sync-card h3 { font-size: 13px; color: #888; margin-bottom: 8px; text-transform: uppercase; }
.sync-card .value { font-size: 20px; color: #e0e0e0; }

.btn { padding: 8px 16px; background: #c9a84c; color: #111; border: none; border-radius: 4px; cursor: pointer; font-weight: 600; font-size: 13px; }
.btn:hover { background: #f0c866; }

.empty { color: #666; padding: 40px; text-align: center; }

.loot-item { color: #a335ee; }
.trade-row { display: flex; align-items: center; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #222; }
```

- [ ] **Step 4: Create public/index.html**

```html
<!DOCTYPE html>
<html lang="no">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>NordavindLC Companion</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div class="header">
    <h1>NordavindLC Companion</h1>
    <div class="status">
      <span id="status-text">Kobler til...</span>
      <span class="dot" id="status-dot"></span>
    </div>
  </div>

  <div class="tabs">
    <div class="tab active" data-tab="players">Spillere</div>
    <div class="tab" data-tab="trades">Trades</div>
    <div class="tab" data-tab="loot">Loot Log</div>
    <div class="tab" data-tab="sync">Sync</div>
  </div>

  <div class="content">
    <div id="tab-players">
      <table>
        <thead>
          <tr>
            <th data-sort="playerName">Navn</th>
            <th data-sort="baseScore">Score</th>
            <th data-sort="attendance">Attend</th>
            <th data-sort="wclParse">Parse</th>
            <th data-sort="mplusEffort">M+</th>
            <th data-sort="rank">Rank</th>
            <th data-sort="lootThisWeek">Loot (uke)</th>
            <th data-sort="lootTotal">Loot (total)</th>
            <th data-sort="deathPenalty">Deaths</th>
          </tr>
        </thead>
        <tbody id="players-body"></tbody>
      </table>
    </div>

    <div id="tab-trades" style="display:none">
      <div id="trades-list"></div>
    </div>

    <div id="tab-loot" style="display:none">
      <table>
        <thead>
          <tr>
            <th>Item</th>
            <th>Spiller</th>
            <th>Boss</th>
            <th>Kategori</th>
            <th>Tid</th>
          </tr>
        </thead>
        <tbody id="loot-body"></tbody>
      </table>
    </div>

    <div id="tab-sync" style="display:none">
      <div class="sync-panel">
        <div class="sync-card">
          <h3>Sist synkronisert</h3>
          <div class="value" id="sync-time">—</div>
        </div>
        <div class="sync-card">
          <h3>Spillere</h3>
          <div class="value" id="sync-players">0</div>
        </div>
        <div class="sync-card">
          <h3>WoW-sti</h3>
          <div class="value" id="sync-wow" style="font-size:13px">—</div>
        </div>
        <div class="sync-card">
          <h3>Server</h3>
          <div class="value" id="sync-url" style="font-size:13px">—</div>
        </div>
      </div>
      <br>
      <button class="btn" onclick="manualSync()">Synkroniser nå</button>
    </div>
  </div>

  <script src="app.js"></script>
</body>
</html>
```

- [ ] **Step 5: Create public/app.js**

```javascript
let currentSort = { key: "baseScore", asc: false };

// ---- Tab switching ----
document.querySelectorAll(".tab").forEach(tab => {
  tab.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
    tab.classList.add("active");
    const target = tab.dataset.tab;
    document.querySelectorAll("[id^='tab-']").forEach(el => el.style.display = "none");
    document.getElementById("tab-" + target).style.display = "";
    if (target === "trades") loadTrades();
    if (target === "loot") loadLoot();
    if (target === "sync") loadSync();
  });
});

// ---- Sorting ----
document.querySelectorAll("th[data-sort]").forEach(th => {
  th.addEventListener("click", () => {
    const key = th.dataset.sort;
    if (currentSort.key === key) currentSort.asc = !currentSort.asc;
    else { currentSort.key = key; currentSort.asc = key === "playerName"; }
    renderPlayers(window._playersData);
  });
});

// ---- Players ----
async function loadPlayers() {
  const res = await fetch("/api/scores");
  const data = await res.json();
  const players = Object.entries(data.players || {}).map(([name, p]) => ({ playerName: name, ...p }));
  window._playersData = players;
  renderPlayers(players);
}

function renderPlayers(players) {
  const sorted = [...players].sort((a, b) => {
    const va = a[currentSort.key], vb = b[currentSort.key];
    if (typeof va === "string") return currentSort.asc ? va.localeCompare(vb) : vb.localeCompare(va);
    return currentSort.asc ? va - vb : vb - va;
  });

  const tbody = document.getElementById("players-body");
  tbody.innerHTML = sorted.map(p => `
    <tr>
      <td>${p.playerName}</td>
      <td class="score">${p.baseScore.toFixed(1)}</td>
      <td>${p.attendance}%</td>
      <td>${p.wclParse.toFixed(1)}</td>
      <td>${p.mplusEffort}</td>
      <td><span class="rank-${p.rank}">${p.rank}</span></td>
      <td>${p.lootThisWeek}</td>
      <td>${p.lootTotal}</td>
      <td>${p.deathPenalty > 0 ? "-" + p.deathPenalty.toFixed(1) : "—"}</td>
    </tr>
  `).join("");
}

// ---- Trades ----
async function loadTrades() {
  const res = await fetch("/api/trades");
  const trades = await res.json();
  const el = document.getElementById("trades-list");
  if (trades.length === 0) { el.innerHTML = '<div class="empty">Ingen pending trades</div>'; return; }
  el.innerHTML = trades.map(t => `
    <div class="trade-row">
      <span class="loot-item">${t.item || "?"}</span>
      <span>→ ${t.awardedTo || "?"}</span>
      <span style="color:#888">${t.category || ""}</span>
    </div>
  `).join("");
}

// ---- Loot Log ----
async function loadLoot() {
  const res = await fetch("/api/loot");
  const loot = await res.json();
  const tbody = document.getElementById("loot-body");
  if (loot.length === 0) { tbody.innerHTML = '<tr><td colspan="5" class="empty">Ingen loot registrert</td></tr>'; return; }
  tbody.innerHTML = loot.map(l => {
    const time = l.timestamp ? new Date(l.timestamp * 1000).toLocaleString("nb-NO") : "—";
    return `
      <tr>
        <td class="loot-item">${l.item || "?"}</td>
        <td>${l.awardedTo || "?"}</td>
        <td>${l.boss || "?"}</td>
        <td>${l.category || "?"}</td>
        <td style="color:#888">${time}</td>
      </tr>
    `;
  }).join("");
}

// ---- Sync ----
async function loadSync() {
  const res = await fetch("/api/status");
  const s = await res.json();
  document.getElementById("sync-time").textContent = s.lastSync ? new Date(s.lastSync).toLocaleString("nb-NO") : "Aldri";
  document.getElementById("sync-players").textContent = s.playerCount;
  document.getElementById("sync-wow").textContent = s.wowPath || "—";
  document.getElementById("sync-url").textContent = s.webUrl || "—";
}

async function manualSync() {
  const btn = document.querySelector(".btn");
  btn.textContent = "Synkroniserer...";
  btn.disabled = true;
  await fetch("/api/sync", { method: "POST" });
  await loadPlayers();
  await loadSync();
  btn.textContent = "Synkroniser nå";
  btn.disabled = false;
}

// ---- Status bar ----
async function updateStatus() {
  try {
    const res = await fetch("/api/status");
    const s = await res.json();
    document.getElementById("status-dot").className = "dot " + (s.connected ? "green" : "red");
    document.getElementById("status-text").textContent = s.connected
      ? `${s.playerCount} spillere · sist sync ${s.lastSync ? new Date(s.lastSync).toLocaleTimeString("nb-NO") : "aldri"}`
      : (s.lastError || "Ikke tilkoblet");
  } catch {
    document.getElementById("status-dot").className = "dot red";
    document.getElementById("status-text").textContent = "Feil";
  }
}

// ---- Init ----
loadPlayers();
updateStatus();
setInterval(updateStatus, 10000);
setInterval(loadPlayers, 60000);
```

- [ ] **Step 6: Run npm install**

```bash
cd C:\Users\lovin\OneDrive\Documents\git\nordavind-addon\companion
npm install
```

- [ ] **Step 7: Commit**

```bash
cd C:\Users\lovin\OneDrive\Documents\git\nordavind-addon
git add companion/
git commit -m "feat: companion app v2 — Express web dashboard with auto-sync"
```

---

### Task 7: Deploy server changes

- [ ] **Step 1: Commit and push nordavind-web**

```bash
cd C:\Users\lovin\OneDrive\Documents\git\nordavind-web
git add prisma/ lib/scoring.ts app/api/scores/ app/api/loot/addon-export/
git commit -m "feat: server-side scoring with PlayerScore table and cron endpoint"
git push
```

- [ ] **Step 2: Deploy to VPS**

```bash
ssh root@37.27.201.23 "cd /root/nordavind-web && git pull && docker compose up -d --build"
```

- [ ] **Step 3: Run initial migration on VPS**

The migration runs automatically since nordavind-web uses Prisma. Verify:

```bash
ssh root@37.27.201.23 "docker logs nordavind-web --tail 20"
```

- [ ] **Step 4: Test the calculate endpoint**

```bash
ssh root@37.27.201.23 "curl -s -X POST -H 'x-cron-secret: nordavind-cron-2026' 'http://localhost:3003/api/scores/calculate?mode=full'"
```

Expected: `{"ok":true,"count":N,"mode":"full","elapsed":"Xs"}`

- [ ] **Step 5: Set up cron**

```bash
ssh root@37.27.201.23
crontab -e
```

Add:
```
25 20 * * 1,3 curl -s -X POST -H "x-cron-secret: nordavind-cron-2026" "http://localhost:3003/api/scores/calculate?mode=full" >> /var/log/nordavind-scores.log 2>&1
30-59/10 20 * * 1,3 curl -s -X POST -H "x-cron-secret: nordavind-cron-2026" "http://localhost:3003/api/scores/calculate?mode=live" >> /var/log/nordavind-scores.log 2>&1
*/10 21-22 * * 1,3 curl -s -X POST -H "x-cron-secret: nordavind-cron-2026" "http://localhost:3003/api/scores/calculate?mode=live" >> /var/log/nordavind-scores.log 2>&1
```

---

### Task 8: Push companion app

- [ ] **Step 1: Push**

```bash
cd C:\Users\lovin\OneDrive\Documents\git\nordavind-addon
git push
```

- [ ] **Step 2: Test locally**

```bash
cd companion
node index.js
```

Open http://localhost:3333 — verify dashboard shows players, sync status.
