# BiS / Major / Stat upgrade — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Erstatt Upgrade/Catalyst med BiS/Major/Stat (knappen går foran poengene, trekk per knapp), vis manglende data ved hver spiller, og la alle raidere se council-rangeringen.

**Architecture:** Trekk-tabellen er en ren funksjon i hvert språk: `nordavind-web/lib/loot-penalty.ts` og `NLC.Scoring.PenaltyFor` i Lua. Tabellene er identiske og testes med de samme tallene. Nettsida regner trekket i poeng og sender dem i eksporten. Addonen sorterer på kategori og legger in-game-trekk oppå. Raiderne får rangeringen fra officerens addon (`SESSION_CLOSE` finnes fra før, og `RANKING` er ny for oppdateringer), og de regner aldri selv.

**Tech Stack:** Next.js + Prisma (TypeScript, `node --test`), WoW-addon Lua 5.1 (tester i Lua via `lupa`), discord.js-bot (Node).

**Spec:** `nordavind-addon/docs/superpowers/specs/2026-09-30-bis-major-stat-design.md`

**Avvik fra spec-en (oppdaget under planlegging, bekreft med Revo):**
- Del 3 er langt på vei bygget. `CloseCollecting` sender allerede rangeringen til alle med `SESSION_CLOSE`, og `/nordlc council` finnes. Det som mangler: raiderne får beskjed om at vinduet finnes, rangeringen sendes på nytt når den endres, og kommandoen virker for raidere. Knappen «Se rangering» i svarvinduet er unødvendig, fordi popupen lukkes i det rangeringen kommer. Den erstattes av en chatlinje.
- «Ingen parse siste 14 dager» går ikke å regne ut. Parse-datoen lagres ikke, bare medianen. Den erstattes av to regler: «ingen parse» (parse er 0) og «poengene er N døgn gamle» (`PlayerScore.updatedAt` er eldre enn 48 timer). Den siste fanger nettopp tilfellet der beregningen har stoppet.
- «Ingen oppmøte» droppes fra lampen. Oppmøte faller tilbake til 100 %, og det finnes ingen billig kilde i eksporten. Datasjekken i del 2 dekker det én gang.

## Global Constraints

- Kategorier: `bis`, `major`, `stat`, `offspec`, `tmog`. Gamle rader kan være `upgrade` eller `catalyst`.
- Trekk (per item, denne uka / tidligere i sesongen): `bis` 10 / 2, `major` 7 / 1,5, `stat` 5 / 1, `upgrade` 10 / 2, `catalyst` 10 / 2, `offspec` og `tmog` 0 / 0.
- Sorteringen i addonen: kategori (`bis=1, major=2, stat=3, offspec=4, tmog=5`), så rank, så poeng, så færrest items, så seedet terning.
- Innkommende `upgrade` og `catalyst` fra gamle klienter blir `major`.
- Addonen er Lua 5.1: ingen `goto`, `//`, `<<`, `>>`, og ingen ikke-ASCII i identifikatorer.
- nordavind-web: lib→lib-importer i filer som testes med `node --test`, MÅ ha `.ts`-endelse.
- All tekst brukerne ser, er på norsk.
- Ingen tag, push eller deploy uten Revos OK. Addon-tag først etter at koden har kjørt i et ekte raid (`RELEASE.md`).
- Addon-repoet har ukommittert Roll- og tier-arbeid (`Core.lua`, `Council.lua`, `UI/RankingFrame.lua`, `tests/ranking_harness.lua`). Det skal IKKE committes sammen med dette. Stage bare filene hver oppgave nevner, og bruk `git add -p` der en fil har begge deler.

## Review Focus

1. Et item deles ut to ganger samme kveld til samme spiller før ny import. In-game-trekket må summere per kategori (for eksempel 10 + 5), ikke antall × 10. Dette testes i Task 3.
2. Import fra en nettside som ikke er deployet ennå, uten `lootPenaltyWeek`. Addonen må falle tilbake til `lootThisWeek × 10` og ikke gi 0. Dette testes i Task 3.
3. En raider på gammel addon trykker «Upgrade». Hen må havne i Major-gruppa, ikke bakerst. Dette testes i Task 4.
4. En officer endrer kategori i historikken fra BiS til Stat. Ukestrekket må flyttes med (−10 + 5), ikke bare antallet. Dette testes i Task 4.
5. En raider åpner `/nordlc council` og klikker på et navn. Ingen meny og ingen tildeling skal skje. Dette testes i Task 9.

---

## Del 1: knapper og trekk

### Task 1: Trekk-tabellen på nettsida (ren funksjon)

**Files:**
- Create: `nordavind-web/lib/loot-penalty.ts`
- Test: `nordavind-web/lib/loot-penalty.test.ts`

**Interfaces:**
- Produces:
  - `LOOT_PENALTY: Record<string, { week: number; season: number }>`
  - `PENALISED_CATEGORIES: string[]`
  - `penaltyFor(category: string | null | undefined): { week: number; season: number }`
  - `type LootRow = { givenTo: string; category: string | null; createdAt: Date }`
  - `type LootTally = { countWeek: number; countSeason: number; penaltyWeek: number; penaltySeason: number }`
  - `tallyLoot(rows: LootRow[], resetStart: Date): Map<string, LootTally>`
  - `EMPTY_TALLY: LootTally`

- [ ] **Step 1: Skriv testen som skal feile**

```ts
// nordavind-web/lib/loot-penalty.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { penaltyFor, tallyLoot, PENALISED_CATEGORIES } from "./loot-penalty.ts";

const RESET = new Date("2026-09-30T05:00:00Z");
const DENNE = new Date("2026-09-30T20:00:00Z");
const FORRIGE = new Date("2026-09-22T20:00:00Z");

test("trekket per kategori — MÅ matche LOOT_PENALTY i addonets Scoring.lua", () => {
  assert.deepEqual(penaltyFor("bis"), { week: 10, season: 2 });
  assert.deepEqual(penaltyFor("major"), { week: 7, season: 1.5 });
  assert.deepEqual(penaltyFor("stat"), { week: 5, season: 1 });
  // Gamle rader fra før 30.09 beholder dagens trekk.
  assert.deepEqual(penaltyFor("upgrade"), { week: 10, season: 2 });
  assert.deepEqual(penaltyFor("catalyst"), { week: 10, season: 2 });
  assert.deepEqual(penaltyFor("offspec"), { week: 0, season: 0 });
  assert.deepEqual(penaltyFor("tmog"), { week: 0, season: 0 });
  assert.deepEqual(penaltyFor(null), { week: 0, season: 0 });
  assert.deepEqual(penaltyFor("disenchant"), { week: 0, season: 0 });
});

test("bare kategorier med trekk regnes som loot", () => {
  assert.deepEqual([...PENALISED_CATEGORIES].sort(), ["bis", "catalyst", "major", "stat", "upgrade"]);
});

test("tallyLoot summerer trekk i poeng, ikke antall × 10", () => {
  const t = tallyLoot([
    { givenTo: "a", category: "bis", createdAt: DENNE },
    { givenTo: "a", category: "stat", createdAt: DENNE },
    { givenTo: "a", category: "major", createdAt: FORRIGE },
    { givenTo: "a", category: "upgrade", createdAt: FORRIGE },
    { givenTo: "a", category: "offspec", createdAt: DENNE },
    { givenTo: "b", category: "major", createdAt: DENNE },
  ], RESET);
  assert.deepEqual(t.get("a"), { countWeek: 2, countSeason: 2, penaltyWeek: 15, penaltySeason: 3.5 });
  assert.deepEqual(t.get("b"), { countWeek: 1, countSeason: 0, penaltyWeek: 7, penaltySeason: 0 });
  assert.equal(t.get("c"), undefined);
});
```

- [ ] **Step 2: Kjør testen og se at den feiler**

Run: `cd nordavind-web && node --test lib/loot-penalty.test.ts`
Expected: FAIL, «Cannot find module './loot-penalty.ts'»

- [ ] **Step 3: Skriv implementasjonen**

```ts
// nordavind-web/lib/loot-penalty.ts
/**
 * Trekk per item, per kategori. Vedtatt 30.09.2026: knappen går foran poengene,
 * og BiS koster mest fordi det er det mest verdifulle du kan få.
 *
 * MÅ matche LOOT_PENALTY i nordavind-addon/NordavindLC/Scoring.lua. Står de
 * ulikt, straffes samme item ulikt avhengig av om importen har rukket å
 * oppdatere seg, og raidet ser en annen rekkefølge enn nettsida.
 *
 * `upgrade` og `catalyst` er rader fra før knappene ble delt. De beholder det
 * gamle trekket, så ingen flytter seg på lista uten å ha fått noe nytt.
 * Offspec og tmog koster ingenting — tar du noe du ikke spiller med, skal det
 * ikke koste deg neste item.
 */
export const LOOT_PENALTY: Record<string, { week: number; season: number }> = {
  bis: { week: 10, season: 2 },
  major: { week: 7, season: 1.5 },
  stat: { week: 5, season: 1 },
  upgrade: { week: 10, season: 2 },
  catalyst: { week: 10, season: 2 },
};

export const PENALISED_CATEGORIES = Object.keys(LOOT_PENALTY);

const INGEN = { week: 0, season: 0 };

export function penaltyFor(category: string | null | undefined): { week: number; season: number } {
  return (category && LOOT_PENALTY[category]) || INGEN;
}

export type LootRow = { givenTo: string; category: string | null; createdAt: Date };
export type LootTally = { countWeek: number; countSeason: number; penaltyWeek: number; penaltySeason: number };
export const EMPTY_TALLY: LootTally = { countWeek: 0, countSeason: 0, penaltyWeek: 0, penaltySeason: 0 };

/**
 * Rader fra sesongen → antall og trekk per mottaker. Alt fra `resetStart` og
 * framover er «denne uka», resten er «tidligere i sesongen». Antallet brukes
 * fortsatt ved uavgjort (færrest items vinner); trekket i poeng går i scoren.
 */
export function tallyLoot(rows: LootRow[], resetStart: Date): Map<string, LootTally> {
  const out = new Map<string, LootTally>();
  for (const r of rows) {
    const p = penaltyFor(r.category);
    if (p.week === 0 && p.season === 0) continue;
    const t = out.get(r.givenTo) ?? { ...EMPTY_TALLY };
    if (r.createdAt >= resetStart) {
      t.countWeek += 1;
      t.penaltyWeek += p.week;
    } else {
      t.countSeason += 1;
      t.penaltySeason += p.season;
    }
    out.set(r.givenTo, t);
  }
  return out;
}
```

- [ ] **Step 4: Kjør testen og se at den passerer**

Run: `cd nordavind-web && node --test lib/loot-penalty.test.ts`
Expected: PASS, 3 tester

- [ ] **Step 5: Commit**

```bash
cd nordavind-web
git add lib/loot-penalty.ts lib/loot-penalty.test.ts
git commit -m "feat(loot): trekk per kategori — bis/major/stat, gamle rader beholder 10/2"
```

---

### Task 2: Nettsida regner trekket i poeng og sender det til addonen

**Files:**
- Modify: `nordavind-web/lib/scoring.ts:83-103` (`fetchLootCounts`), `:149-170` (`lootPenalty`, `calculateScore`) og kallerne rundt `:303-315` og `:393-433`
- Modify: `nordavind-web/app/api/loot/route.ts:366-379` (spørringen), `:551-553` (tellingen) og `:737-743` (trekket)
- Modify: `nordavind-web/app/api/loot/addon-export/route.ts:4`, `:143-181`
- Modify: `nordavind-web/app/api/loot/addon/route.ts:126`
- Modify: `nordavind-web/prisma/schema.prisma:361`, `nordavind-bot/prisma/schema.prisma:383` (bare kommentaren)
- Test: `nordavind-web/lib/loot-penalty.test.ts` (utvides)

**Interfaces:**
- Consumes: `tallyLoot`, `EMPTY_TALLY`, `PENALISED_CATEGORIES`, `LootTally` fra Task 1
- Produces:
  - `fetchLootTally(): Promise<Map<string, LootTally>>` (erstatter `fetchLootCounts`)
  - `lootPenalty(penaltyWeek: number, penaltySeason: number): number`
  - `calculateScore({ ..., lootPenaltyWeek, lootPenaltySeason, ... })` (erstatter `lootThisWeek`/`lootTotal` i parameteret)
  - Eksportfeltene per spiller: `lootPenaltyWeek: number`, `lootPenaltySeason: number` (i tillegg til `lootThisWeek` og `lootTotal`)

- [ ] **Step 1: Utvid testen med `lootPenalty`**

Legg til i `lib/loot-penalty.test.ts`. `lootPenalty` flyttes til `loot-penalty.ts`, så den kan testes uten Prisma:

```ts
import { lootPenalty } from "./loot-penalty.ts";

test("lootPenalty er summen av uke- og sesongtrekket", () => {
  assert.equal(lootPenalty(15, 3.5), 18.5);
  assert.equal(lootPenalty(0, 0), 0);
});
```

- [ ] **Step 2: Kjør og se at den feiler**

Run: `cd nordavind-web && node --test lib/loot-penalty.test.ts`
Expected: FAIL, «lootPenalty is not a function» eller en eksportfeil

- [ ] **Step 3: Flytt `lootPenalty` til `lib/loot-penalty.ts`**

Legg til nederst i `lib/loot-penalty.ts`:

```ts
/**
 * Trekket som går i scoren. −10 per item denne uka var målt, ikke gjettet
 * (median gap mellom naboer i lista er 0,5 poeng); BiS beholder det, Major og
 * Stat koster mindre.
 */
export function lootPenalty(penaltyWeek: number, penaltySeason: number): number {
  return penaltyWeek + penaltySeason;
}
```

I `lib/scoring.ts`: slett den gamle `lootPenalty` (linje 149-156 med kommentaren), og legg til øverst:

```ts
import { tallyLoot, lootPenalty, PENALISED_CATEGORIES, type LootTally } from "@/lib/loot-penalty";
export { lootPenalty };
```

`export { lootPenalty }` beholder importen `import { ..., lootPenalty, ... } from "@/lib/scoring"` i `app/api/loot/route.ts:13`.

- [ ] **Step 4: Bytt `fetchLootCounts` med `fetchLootTally`**

Erstatt hele `fetchLootCounts` i `lib/scoring.ts`:

```ts
export async function fetchLootTally(): Promise<Map<string, LootTally>> {
  const resetStart = weeklyResetStart();
  const cfg = await prisma.guildConfig.findFirst({ where: { guildId: process.env.GUILD_ID! } });
  const seasonStart = cfg?.seasonStartAt ?? SEASON_START_FALLBACK;

  // Samme kategorifilter som app/api/loot/route.ts — begge leser lib/loot-penalty.ts.
  const rows = await prisma.lootDrop.findMany({
    where: { createdAt: { gte: seasonStart }, category: { in: PENALISED_CATEGORIES } },
    select: { givenTo: true, category: true, createdAt: true },
  });
  return tallyLoot(rows, resetStart);
}
```

- [ ] **Step 5: Endre `calculateScore` og kallerne**

```ts
export function calculateScore(p: {
  attendance: number; wclParse: number; mplusEffort: number;
  isDps: boolean; rank: string; lootPenaltyWeek: number; lootPenaltySeason: number; deathPenalty: number;
}): number {
  let score = 0;
  score += attendancePoints(p.attendance);
  score += wclParsePoints(p.wclParse);
  score += p.mplusEffort;
  score += p.isDps ? 5 : 0;
  // Rank er en sorteringsbøtte, ikke poeng — se app/api/loot/route.ts.
  score -= lootPenalty(p.lootPenaltyWeek, p.lootPenaltySeason);
  score -= p.deathPenalty;
  return Math.round(score * 10) / 10;
}
```

Finn der `loot` hentes i `calculateAllScores` (`grep -n "fetchLootCounts" lib/scoring.ts`), og bytt `fetchLootCounts()` med `fetchLootTally()`. I live-grenen (rundt linje 303) og i full-grenen (rundt linje 393) erstattes de tre linjene `const lootThisWeek = … / const lootAllTime = … / const lootTotal = …` med:

```ts
      const tally = loot.get(discordId) ?? EMPTY_TALLY;
      const lootThisWeek = tally.countWeek;
      const lootTotal = tally.countSeason;
```

(Importer også `EMPTY_TALLY` fra `@/lib/loot-penalty`.) Live-grenens `calculateScore({ ... lootThisWeek, lootTotal, ... })` blir `calculateScore({ ..., lootPenaltyWeek: tally.penaltyWeek, lootPenaltySeason: tally.penaltySeason, ... })`. I full-grenen legges `lootPenaltyWeek: tally.penaltyWeek, lootPenaltySeason: tally.penaltySeason` til i `ScoreContext`-interfacet og i `contexts.push`, og kallet på linje ~429 bruker `ctx.lootPenaltyWeek` og `ctx.lootPenaltySeason`. `PlayerScoreData` lagrer fortsatt antallet (`lootThisWeek` og `lootTotal`), så databasen er urørt.

- [ ] **Step 6: Loot-councilet (`app/api/loot/route.ts`)**

Erstatt `PENALISED` og `Promise.all` på linje 366-379 med:

```ts
    // Trekk per kategori — lib/loot-penalty.ts, samme tabell som addonet.
    const lootTally = tallyLoot(
      await prisma.lootDrop.findMany({
        where: { createdAt: { gte: seasonStart }, category: { in: PENALISED_CATEGORIES } },
        select: { givenTo: true, category: true, createdAt: true },
      }),
      resetStart,
    );
```

Importer `tallyLoot`, `PENALISED_CATEGORIES` og `EMPTY_TALLY` fra `@/lib/loot-penalty`. Linje 551-553 blir:

```ts
      // Antall brukes til varsler og uavgjort; trekket i poeng går i scoren.
      const tally = lootTally.get(discordId) ?? EMPTY_TALLY;
      const lootThisWeek = tally.countWeek;
      const lootTotal = tally.countSeason;
```

Linje 738 blir `const penalty = lootPenalty(tally.penaltyWeek, tally.penaltySeason);`.
Kjør `grep -n "lootThisWeekAll\|lootAllTime" app/api/loot/route.ts`. Det skal gi 0 treff.

- [ ] **Step 7: Eksporten (`app/api/loot/addon-export/route.ts`)**

Linje 4: `import { fetchLootTally, calculateScore } from "@/lib/scoring";` og `import { EMPTY_TALLY } from "@/lib/loot-penalty";`. I `Promise.all` byttes `fetchLootCounts()` med `fetchLootTally()`, og variabelen heter fortsatt `lootCounts`. Linje 145-160 blir:

```ts
      const tally = lootCounts.get(discordId) ?? EMPTY_TALLY;
      const lootThisWeek = tally.countWeek;
      const lootTotal = tally.countSeason;

      const isDps = s.role === "dps";
      const freshBaseScore = calculateScore({
        attendance: s.attendance,
        wclParse: s.wclParse,
        mplusEffort: s.mplusEffort,
        isDps,
        rank: s.rank,
        lootPenaltyWeek: tally.penaltyWeek,
        lootPenaltySeason: tally.penaltySeason,
        deathPenalty: s.deathPenalty,
      });
```

I `players[s.playerName] = { ... }`, rett etter `lootTotal,`:

```ts
        // Trekket i poeng (bis 10 / major 7 / stat 5 denne uka). Addonet legger
        // in-game-utdelinger oppå dette; antallet over brukes kun ved uavgjort.
        lootPenaltyWeek: tally.penaltyWeek,
        lootPenaltySeason: tally.penaltySeason,
```

- [ ] **Step 8: Standardkategori og skjema-kommentar**

`app/api/loot/addon/route.ts:126`: `category: category ?? "major",`
Begge `schema.prisma`: `category String? // bis | major | stat | offspec | tmog (gamle rader: upgrade | catalyst)`

- [ ] **Step 9: Typer og tester**

Run: `cd nordavind-web && npx tsc --noEmit && npm test`
Expected: ingen typefeil, alle tester grønne (inkludert de 4 i `loot-penalty.test.ts`)
Run: `grep -rn "fetchLootCounts\|\"catalyst\"\]" app lib`. Expected: 0 treff.

- [ ] **Step 10: Commit**

```bash
cd nordavind-web
git add lib/loot-penalty.ts lib/loot-penalty.test.ts lib/scoring.ts app/api/loot/route.ts app/api/loot/addon-export/route.ts app/api/loot/addon/route.ts prisma/schema.prisma
git commit -m "feat(loot): trekket regnes i poeng per kategori, og eksporten sender det"
cd ../nordavind-bot && git add prisma/schema.prisma && git commit -m "docs(schema): nye loot-kategorier i kommentaren"
```

---

### Task 3: Trekk-tabellen i addonen og ⚠️ for manglende data

**Files:**
- Modify: `nordavind-addon/NordavindLC/Scoring.lua:5-9` (`WEEKLY_LOOT_PENALTY`), `:75-83` (`PENALISED_CATEGORIES`, `CountsAsLoot`), `:134-146` (session loot i `Calculate`), `GetWarnings`
- Create: `nordavind-addon/tests/lootpenalty_harness.lua`

**Interfaces:**
- Produces:
  - `NLC.Scoring.PenaltyFor(category) -> { week = n, season = n }`
  - `NLC.Scoring.CountsAsLoot(category) -> bool` (samme navn, ny kilde)
  - `NLC.Scoring.AddWeeklyAward(playerName, category, sign)`: sign er `1` eller `-1`, og kallet oppdaterer både `counts` og `penalty` i `NLC.db.weeklyLoot`
  - `NLC.Scoring.ImportedWeekPenalty(imported) -> number`
  - Importfeltet `imported.mangler` (liste med strenger) vises i `GetWarnings` som `"Mangler: <tekst>"`

- [ ] **Step 1: Skriv harnessen som skal feile**

```lua
-- tests/lootpenalty_harness.lua
-- Trekk per kategori. Tallene MAA treffe nordavind-web/lib/loot-penalty.ts.
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/lootpenalty_harness.lua',encoding='utf-8').read())"

NordavindLC_NS = {
  Scoring = {},
  db = { weeklyLoot = { counts = {}, penalty = {}, resetTimestamp = 1 }, importData = nil },
  Utils = { Print = function() end },
}
dofile("NordavindLC/Scoring.lua")
local NLC = NordavindLC_NS
local S = NLC.Scoring

local function lik(p, uke, sesong, hva)
  assert(p.week == uke and p.season == sesong,
    hva .. ": fikk " .. tostring(p.week) .. "/" .. tostring(p.season))
end
lik(S.PenaltyFor("bis"), 10, 2, "bis")
lik(S.PenaltyFor("major"), 7, 1.5, "major")
lik(S.PenaltyFor("stat"), 5, 1, "stat")
lik(S.PenaltyFor("upgrade"), 10, 2, "gammel upgrade")
lik(S.PenaltyFor("catalyst"), 10, 2, "gammel catalyst")
lik(S.PenaltyFor("offspec"), 0, 0, "offspec")
lik(S.PenaltyFor("tmog"), 0, 0, "tmog")
lik(S.PenaltyFor(nil), 0, 0, "nil")
lik(S.PenaltyFor("disenchant"), 0, 0, "disenchant")
assert(S.CountsAsLoot("stat") and not S.CountsAsLoot("offspec"), "CountsAsLoot")
print("tabellen             : OK -> 10/2, 7/1.5, 5/1, som nettsida")

-- Review Focus 1: to utdelinger samme kveld summeres per kategori.
S.AddWeeklyAward("Mohp", "bis", 1)
S.AddWeeklyAward("Mohp", "stat", 1)
assert(NLC.db.weeklyLoot.counts["Mohp"] == 2, "antall")
assert(NLC.db.weeklyLoot.penalty["Mohp"] == 15, "trekk: " .. tostring(NLC.db.weeklyLoot.penalty["Mohp"]))
local _, bd = S.Calculate({ baseScore = 50, lootThisWeek = 0, lootPenaltyWeek = 0 }, nil, "Mohp")
local score = S.Calculate({ baseScore = 50, lootThisWeek = 0, lootPenaltyWeek = 0 }, nil, "Mohp")
assert(score == 35, "50 - 15 skal gi 35, fikk " .. score)
-- Importen har allerede sett bis-en: bare stat-en kommer i tillegg.
score = S.Calculate({ baseScore = 40, lootThisWeek = 1, lootPenaltyWeek = 10 }, nil, "Mohp")
assert(score == 35, "40 - (15-10) skal gi 35, fikk " .. score)
print("session-trekk        : OK -> summeres i poeng")

-- Review Focus 2: gammel eksport uten lootPenaltyWeek.
assert(S.ImportedWeekPenalty({ lootThisWeek = 2 }) == 20, "fallback 2 x 10")
assert(S.ImportedWeekPenalty({ lootThisWeek = 1, lootPenaltyWeek = 5 }) == 5, "nytt felt vinner")
print("gammel eksport       : OK -> faller tilbake til antall x 10")

-- Retting trekker fra igjen.
S.AddWeeklyAward("Mohp", "bis", -1)
assert(NLC.db.weeklyLoot.penalty["Mohp"] == 5 and NLC.db.weeklyLoot.counts["Mohp"] == 1, "angre")
S.AddWeeklyAward("Mohp", "offspec", 1)
assert(NLC.db.weeklyLoot.counts["Mohp"] == 1, "offspec teller ikke")
print("angre/offspec        : OK")

-- Mangler-lista fra nettsida blir advarsler.
local w = S.GetWarnings({ rank = "raider", mangler = { "ingen parse", "ingen sim (Mythic)" } }, "Mohp")
local funnet = 0
for _, x in ipairs(w) do if x:find("^Mangler: ") then funnet = funnet + 1 end end
assert(funnet == 2, "to mangler-advarsler, fikk " .. funnet)
print("mangler              : OK -> vises som advarsel")
```

- [ ] **Step 2: Kjør og se at den feiler**

Run: `cd nordavind-addon && python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/lootpenalty_harness.lua',encoding='utf-8').read())"`
Expected: FAIL, «attempt to call a nil value (field 'PenaltyFor')»

- [ ] **Step 3: Skriv implementasjonen i `Scoring.lua`**

Erstatt linje 5-9 (`WEEKLY_LOOT_PENALTY`):

```lua
-- Trekk per item, per kategori. MÅ matche LOOT_PENALTY i
-- nordavind-web/lib/loot-penalty.ts — står de ulikt, straffes samme item ulikt
-- avhengig av om importen har rukket å oppdatere seg.
-- upgrade/catalyst er gamle rader fra før knappene ble delt (30.09.2026).
local LOOT_PENALTY = {
  bis      = { week = 10, season = 2 },
  major    = { week = 7,  season = 1.5 },
  stat     = { week = 5,  season = 1 },
  upgrade  = { week = 10, season = 2 },
  catalyst = { week = 10, season = 2 },
}
local INGEN_TREKK = { week = 0, season = 0 }

function NLC.Scoring.PenaltyFor(category)
  return (category and LOOT_PENALTY[category]) or INGEN_TREKK
end
```

Erstatt `PENALISED_CATEGORIES` og `CountsAsLoot` (linje 75-83):

```lua
-- Hvilke kategorier som teller som loot: de som har trekk. Offspec og tmog er
-- fritatt, og det står likt på nettsida (PENALISED_CATEGORIES i loot-penalty.ts).
function NLC.Scoring.CountsAsLoot(category)
  return LOOT_PENALTY[category or ""] ~= nil
end

-- Én utdeling (sign = 1) eller én angret utdeling (sign = -1) denne uka.
-- Antallet brukes ved uavgjort, trekket i poeng går i scoren.
function NLC.Scoring.AddWeeklyAward(playerName, category, sign)
  if not NLC.Scoring.CountsAsLoot(category) then return end
  NLC.db.weeklyLoot = NLC.db.weeklyLoot or { resetTimestamp = 0, counts = {} }
  local wl = NLC.db.weeklyLoot
  wl.counts = wl.counts or {}
  wl.penalty = wl.penalty or {}
  local p = NLC.Scoring.PenaltyFor(category).week
  wl.counts[playerName] = math.max(0, (wl.counts[playerName] or 0) + sign)
  wl.penalty[playerName] = math.max(0, (wl.penalty[playerName] or 0) + sign * p)
end

-- Ukestrekket nettsida allerede har regnet med. Gammel eksport uten feltet
-- (nettsida ikke deployet ennå) faller tilbake til den gamle formelen.
function NLC.Scoring.ImportedWeekPenalty(imported)
  if not imported then return 0 end
  if type(imported.lootPenaltyWeek) == "number" then return imported.lootPenaltyWeek end
  return (imported.lootThisWeek or 0) * 10
end
```

I `Calculate` erstattes blokken fra `local wl = NLC.db.weeklyLoot` til og med `end end` (linje 138-146):

```lua
    local wl = NLC.db.weeklyLoot
    if playerName and wl and wl.resetTimestamp and wl.resetTimestamp > 0 then
      -- In-game-trekket siden reset, minus det importen allerede har med.
      -- Gamle SavedVariables uten `penalty` har bare antall; de regnes x10.
      local ingame = (wl.penalty and wl.penalty[playerName])
        or (((wl.counts and wl.counts[playerName]) or 0) * 10)
      local extra = ingame - NLC.Scoring.ImportedWeekPenalty(imported)
      if extra > 0 then
        score = score - extra
        table.insert(breakdown, { label = "Session loot", value = -extra })
      end
    end
```

I `GetWarnings`, rett før `if imported.rank == "trial" then`:

```lua
  -- Nettsida avgjør hva som mangler (lib/datamangler.ts); addonet bare viser det.
  for _, m in ipairs(imported.mangler or {}) do
    table.insert(warnings, "Mangler: " .. m)
  end
```

- [ ] **Step 4: Kjør og se at den passerer**

Run: samme kommando som i Step 2.
Expected: fem `OK`-linjer, ingen feil. Kjør også `simpoeng_harness.lua`, som fortsatt skal passere.

- [ ] **Step 5: Commit**

```bash
cd nordavind-addon
git add NordavindLC/Scoring.lua tests/lootpenalty_harness.lua
git commit -m "feat(scoring): trekk per kategori og mangler-advarsler, som nettsida"
```

---

### Task 4: Council sorterer BiS > Major > Stat, og gamle svar blir Major

**Files:**
- Modify: `nordavind-addon/NordavindLC/Council.lua:6` (`catOrder`), `:240-262` (`OnInterestReceived`), `:467-471` (`CAT_NO`), `:538-561` (`DoAward`)
- Modify: `nordavind-addon/NordavindLC/UI/HistoryFrame.lua:9`, `:56-68`
- Test: `nordavind-addon/tests/ranking_harness.lua` (legg nye tilfeller nederst, og rør ikke det ukommitterte Roll/tier-innholdet)

**Interfaces:**
- Consumes: `NLC.Scoring.AddWeeklyAward` fra Task 3
- Produces: `NLC.Council.NormaliserKategori(cat) -> string` (`upgrade`/`catalyst` → `major`, resten uendret)

- [ ] **Step 1: Skriv testene som skal feile (nederst i `ranking_harness.lua`)**

```lua
-- --- BiS/Major/Stat (30.09.2026) ---
assert(NLC.Council.NormaliserKategori("upgrade") == "major", "gammel upgrade -> major")
assert(NLC.Council.NormaliserKategori("catalyst") == "major", "gammel catalyst -> major")
assert(NLC.Council.NormaliserKategori("bis") == "bis", "bis urort")
assert(NLC.Council.NormaliserKategori("tmog") == "tmog", "tmog urort")

local kat = {
  itemLink = "|cffa335ee|Hitem:1::::::::90:::::|h[Test]|h|r", itemId = 1, ilvl = 678,
  equipLoc = "INVTYPE_FINGER", boss = "Test", timer = 90, phase = "ranking", interests = {
    ["Moggin"]     = { category = "stat",    class = "WARLOCK" },
    ["Areniir"]    = { category = "bis",     class = "PRIEST"  },
    ["Shotgrogg"]  = { category = "major",   class = "WARRIOR" },
    ["Bobletount"] = { category = "offspec", class = "PALADIN" },
  },
}
local r = NLC.Council.BuildRanking(kat)
local rekke = {}
for _, c in ipairs(r) do table.insert(rekke, c.category) end
assert(table.concat(rekke, ",") == "bis,major,stat,offspec", "rekkefolge: " .. table.concat(rekke, ","))
print("bis > major > stat   : OK -> knappen gaar foran poengene")

-- Review Focus 3: gammel klient sender «upgrade».
kat.interests = {}
NLC.Council._testSettAktive({ kat })
NLC.Council.OnInterestReceived("Moggin-TarrenMill", kat.sessionIdx, "upgrade", 670, 0, nil, nil)
assert(kat.interests["Moggin"].category == "major", "upgrade fra gammel klient ble ikke major")
print("gammel klient        : OK -> upgrade blir major")
```

Finnes det ikke allerede en testkrok for `activeSessions`, legges den til i `Council.lua` (rett over `function NLC.Council.OnInterestReceived`):

```lua
-- Kun for tester i tests/: setter aktive sesjoner uten aa gaa via comms.
function NLC.Council._testSettAktive(liste)
  activeSessions = liste
  for i, s in ipairs(liste) do s.sessionIdx = s.sessionIdx or i end
end
```

- [ ] **Step 2: Kjør og se at den feiler**

Run: `cd nordavind-addon && python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/ranking_harness.lua',encoding='utf-8').read())"`
Expected: FAIL, «attempt to call a nil value (field 'NormaliserKategori')»

- [ ] **Step 3: Skriv implementasjonen**

`Council.lua:6`:

```lua
-- Knappen går foran poengene (vedtatt 30.09.2026): alle BiS over alle Major.
local catOrder = { bis = 1, major = 2, stat = 3, offspec = 4, tmog = 5 }

-- Klienter på gammel versjon sender upgrade/catalyst. De skal verken havne
-- bakerst (ukjent kategori = 99) eller forsvinne, så de regnes som Major.
-- Officeren kan rette kategorien i historikken etterpå.
local GAMMEL_KATEGORI = { upgrade = "major", catalyst = "major" }
function NLC.Council.NormaliserKategori(cat)
  return GAMMEL_KATEGORI[cat] or cat
end
```

I `OnInterestReceived`, i tabellen `session.interests[name] = {`, byttes `category = category,` med `category = NLC.Council.NormaliserKategori(category),`.

`CAT_NO` (linje 468-471):

```lua
local CAT_NO = {
  bis = "BiS", major = "Major", stat = "Stat upgrade",
  offspec = "Offspec", tmog = "Transmog", pass = "Pass",
  upgrade = "Oppgradering", catalyst = "Catalyst",
  disenchant = "Disenchant", bank = "Guildbank", free = "Fri",
}
```

(`upgrade` og `catalyst` beholdes bare for å kunne vise gamle rader.)

I `DoAward`: `local category = "upgrade"` og `c.category or "upgrade"` blir `"major"`. Blokken som øker `weeklyLoot.counts` (linje 555-560) erstattes med:

```lua
  -- Ukestrekket i SavedVariables (nullstilles onsdag). Kun kategorier med
  -- trekk teller — se NLC.Scoring.CountsAsLoot.
  NLC.Scoring.AddWeeklyAward(playerName, category, 1)
```

`HistoryFrame.lua:9`: `local CATEGORIES = { "bis", "major", "stat", "offspec", "tmog" }`
`HistoryFrame.lua:56-68`: blokken inne i `if wl and wl.counts and editedAt ...` erstattes med:

```lua
    if oldRecipient then NLC.Scoring.AddWeeklyAward(oldRecipient, oldCategory, -1) end
    if newRecipient then NLC.Scoring.AddWeeklyAward(newRecipient, newCategory, 1) end
```

- [ ] **Step 4: Review Focus 4, test at retting i historikken flytter trekket**

Legg til i `tests/lootpenalty_harness.lua`:

```lua
-- Retting i historikken: BiS -> Stat flytter 10 ut og 5 inn.
NLC.db.weeklyLoot = { counts = {}, penalty = {}, resetTimestamp = 1 }
S.AddWeeklyAward("Sondi", "bis", 1)
S.AddWeeklyAward("Sondi", "bis", -1)
S.AddWeeklyAward("Sondi", "stat", 1)
assert(NLC.db.weeklyLoot.penalty["Sondi"] == 5 and NLC.db.weeklyLoot.counts["Sondi"] == 1, "bis->stat")
print("historikk-retting    : OK -> trekket flyttes med")
```

- [ ] **Step 5: Kjør alle berørte harnesser**

Run: `for h in ranking lootpenalty session comms; do python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/${h}_harness.lua',encoding='utf-8').read())" || echo "FEIL: $h"; done`
Expected: ingen `FEIL:`-linjer

- [ ] **Step 6: Commit (bare dine hunks, ikke Roll/tier-arbeidet)**

```bash
cd nordavind-addon
git add -p NordavindLC/Council.lua tests/ranking_harness.lua   # velg KUN hunks fra denne oppgaven
git add NordavindLC/UI/HistoryFrame.lua tests/lootpenalty_harness.lua
git commit -m "feat(council): bis > major > stat, og upgrade fra gamle klienter blir major"
```

---

### Task 5: Knappene, menyene og kommandoene

**Files:**
- Modify: `nordavind-addon/NordavindLC/Utils.lua:388-482` (`GetAvailableCategories`)
- Modify: `nordavind-addon/NordavindLC/UI/CouncilFrame.lua:10-16`, `:101-106`, `:150`, `:161`, og notatfeltet
- Modify: `nordavind-addon/NordavindLC/UI/RankingFrame.lua:29-34`, `:298`
- Modify: `nordavind-addon/NordavindLC/Core.lua:416`, `:449-455`, `:676-682`
- Test: `nordavind-addon/tests/tiertoken_harness.lua` og `tests/lootwindow_harness.lua` (oppdater forventningene)

**Interfaces:**
- Consumes: kategorinavnene fra Global Constraints
- Produces: `GetAvailableCategories` returnerer `{ bis, major, stat, offspec, tmog }` (bool). `upgrade` og `catalyst` finnes ikke lenger i tabellen.

- [ ] **Step 1: Oppdater forventningene i harnessene (de skal feile)**

Run: `cd nordavind-addon && grep -n "upgrade\|catalyst" tests/tiertoken_harness.lua tests/lootwindow_harness.lua tests/popupcache_harness.lua`
Der en test leser `result.upgrade` fra `GetAvailableCategories`, bytt til `result.major`, og legg til en linje som sjekker at `result.bis == result.major and result.stat == result.major`. Der en test sjekker `result.catalyst`, bytt til `assert(result.catalyst == nil, "catalyst skal vaere borte")`.

- [ ] **Step 2: Kjør og se at de feiler**

Run: `for h in tiertoken lootwindow popupcache; do python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/${h}_harness.lua',encoding='utf-8').read())" || echo "FEIL: $h"; done`
Expected: `FEIL:` for de filene som ble endret

- [ ] **Step 3: `Utils.GetAvailableCategories`**

Behold hele logikken, som regner et internt `upgrade`-flagg. Slett de tre `result.catalyst = true`-blokkene og `catalyst = false` i starttabellen. Rett før `return result` nederst, og i de to tidlige `return result` inne i token-grenen og jewelry-grenen, kalles en hjelper. Legg den over funksjonen:

```lua
-- Tre knapper der det før var én. Alle tre er tilgjengelige på nøyaktig de
-- samme itemene som «Upgrade» var — valget mellom dem er spillerens.
local function DelOppgradering(result)
  result.bis, result.major, result.stat = result.upgrade, result.upgrade, result.upgrade
  result.upgrade = nil
  return result
end
```

Hver `return result` i funksjonen blir `return DelOppgradering(result)`. Kommentaren om wishlist-filteret (linje 463-467) oppdateres: «forlot kun catalyst» blir «forlot kun offspec».

- [ ] **Step 4: Svarvinduet (`CouncilFrame.lua`)**

`CATEGORY_TIPS`:

```lua
local CATEGORY_TIPS = {
  bis     = "Beste item for din spec ifølge simulationcraft.org.",
  major   = "Stor oppgradering for main spec.",
  stat    = "Liten oppgradering, mest stats.",
  offspec = "Du trenger dette for off spec\n(annen rolle enn main).",
  tmog    = "Du vil ha dette itemet for transmog\n(utseende).",
  pass    = "Du trenger ikke dette itemet.",
}
```

`allCategories`:

```lua
  local allCategories = {
    { id = "bis",     label = "|cffff8000BiS|r",          width = 60 },
    { id = "major",   label = T.GOLD_LIGHT .. "Major|r",  width = 70 },
    { id = "stat",    label = T.GREEN .. "Stat|r",        width = 60 },
    { id = "offspec", label = "|cff3399ffOffspec|r",      width = 80 },
    { id = "tmog",    label = T.GOLD .. "Tmog|r",         width = 60 },
  }
```

Linje 150 og 161, `if cat.id == "upgrade" and rowData.noteBox`, blir begge `if MED_NOTAT[cat.id] and rowData.noteBox`, med `local MED_NOTAT = { bis = true, major = true, stat = true }` øverst i fila.

Notatfeltet: finn der `rowData.noteBox` lages (`grep -n "noteBox = " NordavindLC/UI/CouncilFrame.lua`). Sett en ledetekst som vises og skjules sammen med feltet:

```lua
    -- Hele raidet ser council-vinduet siden 30.09.2026, notatet inkludert.
    local noteHint = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteHint:SetPoint("TOPLEFT", rowData.noteBox, "BOTTOMLEFT", 0, -2)
    noteHint:SetText(T.MUTED .. "Notatet er synlig for hele raidet.|r")
    noteHint:Hide()
    rowData.noteBox:HookScript("OnShow", function() noteHint:Show() end)
    rowData.noteBox:HookScript("OnHide", function() noteHint:Hide() end)
```

(Bruk samme foreldre-variabel som noteBox er laget på, `row` eller tilsvarende.)

- [ ] **Step 5: Rangeringen (`RankingFrame.lua`)**

`CATEGORY_LABELS`:

```lua
local CATEGORY_LABELS = {
  bis      = "|cffff8000BiS|r",
  major    = T.GOLD_LIGHT .. "Major upgrade|r",
  stat     = T.GREEN .. "Stat upgrade|r",
  offspec  = "|cff3399ffOffspec|r",
  tmog     = T.GOLD .. "Tmog|r",
}
```

Linje 298: `for _, cat in ipairs({ "bis", "major", "stat", "offspec", "tmog" }) do`

- [ ] **Step 6: Kommandoene (`Core.lua`)**

Linje 416 og 453: `{ bis = true, major = true, stat = true, offspec = true, tmog = true }`. Linje 455: standard `"major"`.
Linje 449: `NLC.Utils.Print("  Legg paa bis/major/stat/offspec/tmog til slutt (standard: major).")`. Linje 452-kommentaren: `bis/major/stat/offspec/tmog`.
Testdataene (676-682): `Testwarrior` blir `bis`, `Testshaman` blir `major`, `Testpaladin` blir `stat`. Resten er uendret.

- [ ] **Step 7: Kjør hele harness-settet fra `RELEASE.md` pluss `lootpenalty`**

Run: `for h in ranking lootpanel popupcache comms bagbacklog session tiertoken manualscan lootwindow tooltipapi theme lootroll roster errorcapture trade avvisning inaktivlogg aggregering simpoeng lootpenalty; do python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/${h}_harness.lua',encoding='utf-8').read())" || echo "FEIL: $h"; done`
Expected: ingen `FEIL:`
Run: `grep -rn "catalyst" NordavindLC --include=*.lua | grep -v Libs`
Expected: bare `Scoring.lua` (LOOT_PENALTY), `Council.lua` (GAMMEL_KATEGORI og CAT_NO) og kommentarer

- [ ] **Step 8: Commit**

```bash
git add NordavindLC/Utils.lua NordavindLC/UI/CouncilFrame.lua tests/tiertoken_harness.lua tests/lootwindow_harness.lua tests/popupcache_harness.lua
git add -p NordavindLC/UI/RankingFrame.lua NordavindLC/Core.lua   # kun hunks fra denne oppgaven
git commit -m "feat(ui): BiS/Major/Stat-knapper, catalyst fjernet, notat-varsel"
```

---

### Task 6: Boten, `/loot` i Discord

**Files:**
- Create: `nordavind-bot/utils/lootKategorier.js`
- Modify: `nordavind-bot/commands/loot.js:204-205`, `:298-303`, `:343-344`, `:523`
- Modify: `nordavind-bot/events/interactionCreate.js:737`, `:759-760`

**Interfaces:**
- Produces: `module.exports = { KATEGORIER: string[], ETIKETTER: Record<string,string> }`

- [ ] **Step 1: Lag den delte modulen**

```js
// utils/lootKategorier.js
// Én liste for /loot-embeden og knappene. Sto før på tre steder med catalyst.
// Samme kategorier som addonet og nettsida (nordavind-web/lib/loot-penalty.ts).
const KATEGORIER = ["bis", "major", "stat", "offspec", "tmog"];
const ETIKETTER = {
  bis: "🏆 BiS",
  major: "⬆️ Major upgrade",
  stat: "📈 Stat upgrade",
  offspec: "🔄 Offspec",
  tmog: "👗 Tmog",
};
module.exports = { KATEGORIER, ETIKETTER };
```

- [ ] **Step 2: Bruk den i `loot.js` og `interactionCreate.js`**

Hvert par `const categories = [...]; const labels = {...};` (loot.js 204-205, loot.js 343-344 og interactionCreate.js 759-760) erstattes med:

```js
  const { KATEGORIER: categories, ETIKETTER: labels } = require("../utils/lootKategorier");
```

Knappene i `loot.js` (298-303):

```js
      const row = new ActionRowBuilder().addComponents(
        new ButtonBuilder().setCustomId("loot:interest:bis").setLabel("BiS").setEmoji("🏆").setStyle(ButtonStyle.Success),
        new ButtonBuilder().setCustomId("loot:interest:major").setLabel("Major").setEmoji("⬆️").setStyle(ButtonStyle.Primary),
        new ButtonBuilder().setCustomId("loot:interest:stat").setLabel("Stat").setEmoji("📈").setStyle(ButtonStyle.Primary),
        new ButtonBuilder().setCustomId("loot:interest:offspec").setLabel("Offspec").setEmoji("🔄").setStyle(ButtonStyle.Secondary),
        new ButtonBuilder().setCustomId("loot:interest:tmog").setLabel("Tmog").setEmoji("👗").setStyle(ButtonStyle.Secondary),
      );
```

(Fem knapper er maks per rad i Discord. Det går akkurat.)
`loot.js:523`: `category: "major",`, og kommentaren over oppdateres til «category: { in: PENALISED_CATEGORIES }».
`interactionCreate.js:737`-kommentaren: `// bis, major, stat, offspec, tmog`.

- [ ] **Step 3: Sjekk**

Run: `cd nordavind-bot && node -e "require('./commands/loot.js'); require('./events/interactionCreate.js'); console.log('ok')"`
Expected: `ok`
Run: `grep -rn "catalyst" commands events utils`. Expected: 0 treff.

- [ ] **Step 4: Commit**

```bash
cd nordavind-bot
git add utils/lootKategorier.js commands/loot.js events/interactionCreate.js
git commit -m "feat(loot): BiS/Major/Stat i /loot, catalyst fjernet"
```

---

### Task 7: Regelteksten

**Files:**
- Modify: `nordavind-web/docs/sesong2-regler-discord.md:76`, `:88-95`
- Modify: `nordavind-web/docs/sesong2-regler-embeds.md` (tilsvarende avsnitt)
- Modify: `nordavind-bot/scripts/reglerEmbeds.js` (tilsvarende tekst)

- [ ] **Step 1: Skriv loot-delen på nytt i `sesong2-regler-discord.md`**

Linje 76 blir:

```
Knapper: **BiS – Major – Stat – Offspec – Tmog**. BiS = det simulationcraft.org viser for specen din. **Knappen går foran poengene**: alle BiS står over alle Major, osv.
```

Trekk-blokken (88-95) blir:

````
Og trekkene:

```
Loot mottatt   denne uken / tidligere i sesongen
  BiS            −10 / −2
  Major           −7 / −1,5
  Stat            −5 / −1
Deaths          −3 per snitt-død over 1.0 per fight
```

**Offspec og tmog teller ingen steder.** Alle kan se council-vinduet med `/nordlc council`.
````

- [ ] **Step 2: Tell tegnene. Grensa er 6000.**

Run: `cd nordavind-web && node -e "console.log(require('fs').readFileSync('docs/sesong2-regler-discord.md','utf8').length)"`
Expected: ≤ 6000. Er den over, kort ned avsnittet «Nytt i sesong 2: sims veier mye mindre …» (linje 97) til én setning: «Sims veier lite: oppmøte og prestasjon teller mest.»

- [ ] **Step 3: Gjør de samme endringene i `sesong2-regler-embeds.md` og `reglerEmbeds.js`**

Run: `grep -n -i "catalyst\|Upgrade –" nordavind-web/docs/sesong2-regler-embeds.md nordavind-bot/scripts/reglerEmbeds.js`
Erstatt hvert treff med teksten fra Step 1. Expected etterpå: 0 treff.

- [ ] **Step 4: Commit (ikke post noe i Discord)**

```bash
cd nordavind-web && git add docs/sesong2-regler-discord.md docs/sesong2-regler-embeds.md && git commit -m "docs(regler): BiS/Major/Stat og nye trekk"
cd ../nordavind-bot && git add scripts/reglerEmbeds.js && git commit -m "docs(regler): BiS/Major/Stat i embedsene"
```

Å poste regelteksten i Discord er Revos avgjørelse. Den postes ikke i denne planen.

---

## Del 2: riktige tall

### Task 8: `mangler` i eksporten og datasjekk-script

**Files:**
- Create: `nordavind-web/lib/datamangler.ts`
- Test: `nordavind-web/lib/datamangler.test.ts`
- Modify: `nordavind-web/app/api/loot/addon-export/route.ts` (henter M+ og legger `mangler` i hver spiller)
- Create: `nordavind-web/scripts/datasjekk.mjs`

**Interfaces:**
- Produces:
  - `SCORE_STALE_HOURS = 48`
  - `type ManglerInput = { wclParse: number | null; scoreUpdatedAt: Date; hasSims: boolean; simsOk: boolean; difficulty: string; mplusLastWeek: number | null }`
  - `manglerFor(i: ManglerInput, now?: Date): string[]`
  - Eksportfeltet `mangler: string[]` per spiller, som `NLC.Scoring.GetWarnings` (Task 3) leser

- [ ] **Step 1: Skriv testen som skal feile**

```ts
// nordavind-web/lib/datamangler.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { manglerFor } from "./datamangler.ts";

const NA = new Date("2026-09-30T18:00:00Z");
const ok = {
  wclParse: 62, scoreUpdatedAt: new Date("2026-09-30T06:00:00Z"),
  hasSims: true, simsOk: true, difficulty: "mythic", mplusLastWeek: 8,
};

test("alt på plass gir tom liste", () => {
  assert.deepEqual(manglerFor(ok, NA), []);
});

test("hver mangel får sin egen linje", () => {
  assert.deepEqual(manglerFor({ ...ok, wclParse: 0 }, NA), ["ingen parse"]);
  assert.deepEqual(manglerFor({ ...ok, wclParse: null }, NA), ["ingen parse"]);
  assert.deepEqual(manglerFor({ ...ok, hasSims: false }, NA), ["ingen sim (Mythic)"]);
  assert.deepEqual(manglerFor({ ...ok, mplusLastWeek: null }, NA), ["ingen M+-data"]);
  assert.deepEqual(
    manglerFor({ ...ok, scoreUpdatedAt: new Date("2026-09-27T18:00:00Z") }, NA),
    ["poengene er 3 døgn gamle"],
  );
});

test("feilet sim-henting utestenger ingen — da er det ikke spillerens mangel", () => {
  assert.deepEqual(manglerFor({ ...ok, hasSims: false, simsOk: false }, NA), []);
});

test("0 dungeons forrige uke er data, ikke mangel", () => {
  assert.deepEqual(manglerFor({ ...ok, mplusLastWeek: 0 }, NA), []);
});
```

- [ ] **Step 2: Kjør og se at den feiler**

Run: `cd nordavind-web && node --test lib/datamangler.test.ts`
Expected: FAIL, «Cannot find module»

- [ ] **Step 3: Skriv implementasjonen**

```ts
// nordavind-web/lib/datamangler.ts
/**
 * Hva mangler bak en spillers poeng? Vises som advarsel ved navnet i
 * council-vinduet, så alle ser når tallene ikke er til å stole på.
 *
 * Grensene står KUN her; addonet viser lista og avgjør ingenting selv.
 *
 * Parse-dato lagres ikke (bare medianen), så «ingen parse siste 14 dager» går
 * ikke å regne ut. `scoreUpdatedAt` fanger det viktigste i stedet: at
 * beregningen har stoppet og alle tallene er gamle.
 */
export const SCORE_STALE_HOURS = 48;

export type ManglerInput = {
  wclParse: number | null;
  scoreUpdatedAt: Date;
  hasSims: boolean;
  /** false = WowAudit svarte ikke. Da er det vår feil, ikke spillerens. */
  simsOk: boolean;
  difficulty: string;
  /** Dungeons siste registrerte uke; null = ingen M+-rader i det hele tatt. */
  mplusLastWeek: number | null;
};

const GRAD: Record<string, string> = { normal: "Normal", heroic: "Heroic", mythic: "Mythic" };

export function manglerFor(i: ManglerInput, now: Date = new Date()): string[] {
  const ut: string[] = [];
  if (!i.wclParse) ut.push("ingen parse");
  const timer = (now.getTime() - i.scoreUpdatedAt.getTime()) / 3_600_000;
  if (timer > SCORE_STALE_HOURS) ut.push(`poengene er ${Math.floor(timer / 24)} døgn gamle`);
  if (i.simsOk && !i.hasSims) ut.push(`ingen sim (${GRAD[i.difficulty] ?? i.difficulty})`);
  if (i.mplusLastWeek === null) ut.push("ingen M+-data");
  return ut;
}
```

- [ ] **Step 4: Kjør og se at den passerer**

Run: `cd nordavind-web && node --test lib/datamangler.test.ts`
Expected: PASS, 4 tester

- [ ] **Step 5: Koble det inn i eksporten**

I `app/api/loot/addon-export/route.ts`: importer `manglerFor` fra `@/lib/datamangler` og `getMplusEffort` fra `@/lib/mplus-data`. Etter `if (scores.length === 0) { ... }`:

```ts
    // M+ per spiller, samme kilde som scoren — kun for mangler-lista.
    const mplus = await getMplusEffort(scores.map((s) => ({ playerName: s.playerName })));
```

I `players[s.playerName] = { ... }`, etter `simPct`:

```ts
        mangler: manglerFor({
          wclParse: s.wclParse,
          scoreUpdatedAt: s.updatedAt,
          hasSims: sims.map.get(s.playerName.toLowerCase())?.hasSims ?? false,
          simsOk: sims.status === "ok",
          difficulty,
          mplusLastWeek: mplus.get(s.playerName.toLowerCase())?.lastWeekDungeons ?? null,
        }),
```

Run: `npx tsc --noEmit && npm test`. Expected: grønt.

- [ ] **Step 6: Datasjekk-scriptet**

```js
// nordavind-web/scripts/datasjekk.mjs
// Kjøres INNE i nordavind-web-containeren:
//   docker exec -i nordavind-web node - < scripts/datasjekk.mjs            (bare les)
//   docker exec -i -e BEREGN=1 nordavind-web node - < scripts/datasjekk.mjs (regn poengene på nytt først)
// Leser samme eksport som addonet får, så lista viser nøyaktig det raidet ser.
const base = `http://localhost:${process.env.PORT || 3000}`;

if (process.env.BEREGN) {
  const r = await fetch(`${base}/api/scores/calculate?mode=full`, {
    method: "POST", headers: { "x-cron-secret": process.env.CRON_SECRET ?? "" },
  });
  console.log("beregning:", r.status, await r.text());
}

for (const grad of ["heroic", "mythic"]) {
  const r = await fetch(`${base}/api/loot/addon-export?difficulty=${grad}`, {
    headers: { "x-api-key": process.env.ADDON_API_KEY ?? "" },
  });
  if (!r.ok) { console.log(grad, "HTTP", r.status); continue; }
  const d = await r.json();
  console.log(`\n== ${grad} (sims: ${d.kilder?.sims}, generert ${d.generatedAt})`);
  const rader = Object.entries(d.players).sort(([a], [b]) => a.localeCompare(b));
  let ok = 0;
  for (const [navn, p] of rader) {
    if (!p.mangler?.length) { ok++; continue; }
    console.log(`${navn.padEnd(16)} parse ${String(p.wclParse).padStart(5)}  oppm ${String(p.attendance).padStart(3)}%  M+ ${String(p.mplusEffort).padStart(4)}  → ${p.mangler.join(", ")}`);
  }
  console.log(`${ok} av ${rader.length} uten mangler`);
}
```

- [ ] **Step 7: Commit**

```bash
cd nordavind-web
git add lib/datamangler.ts lib/datamangler.test.ts app/api/loot/addon-export/route.ts scripts/datasjekk.mjs
git commit -m "feat(export): mangler-liste per spiller + datasjekk-script"
```

---

## Del 3: council-vinduet for alle

### Task 9: Raiderne får og kan åpne rangeringen

**Files:**
- Modify: `nordavind-addon/NordavindLC/Council.lua`: `OnSessionClose` (~linje 880), ny `BroadcastRanking`, kall i `ChangeCategory`, `RemoveCandidate`, `RollCategory` og i `DoAward`-løkka som bygger resten på nytt
- Modify: `nordavind-addon/NordavindLC/Comms.lua` (ny gren `RANKING` rett etter `SESSION_CLOSE`)
- Modify: `nordavind-addon/NordavindLC/UI/RankingFrame.lua` (sjekk at klikk på navn og raden gjør ingenting uten `isOfficer`)
- Test: `nordavind-addon/tests/comms_harness.lua` (utvides)

**Interfaces:**
- Consumes: `NLC.Theme.Debounce(key, delay, fn)`, `NLC.Comms.Send(msgType, data)`, `NLC.Utils.ErGruppeleder(sender)`
- Produces:
  - `NLC.Council.BroadcastRanking(session)`: officer, debounce 2 s per `sessionIdx`
  - `NLC.Council.OnRanking(data)`: raider, `data = { sessionIdx, ranked }`
  - Meldingstypen `"RANKING"`

- [ ] **Step 1: Skriv testene som skal feile (i `comms_harness.lua`)**

Følg mønsteret for `SESSION_CLOSE` rundt linje 173 (`motta(type, data, avsender)` og `_G.LEDER_NAVN`). Legg en stub for `NLC.Council.OnRanking` ved siden av stubben for `OnSessionClose` i harnessen, med teller `_G.__rangering`:

```lua
-- --- RANKING: oppdatert rangering, samme leder-port som SESSION_CLOSE ---
_G.__rangering = 0
motta("RANKING", { sessionIdx = 1, ranked = {} }, "Prectus-Kazzak")
assert(_G.__rangering == 0, "RANKING fra en ikke-leder ble godtatt")
motta("RANKING", { sessionIdx = 1, ranked = {} }, _G.LEDER_NAVN)
assert(_G.__rangering == 1, "RANKING fra lederen naadde ikke fram")
print("RANKING               : OK -> kun fra lederen")
```

- [ ] **Step 2: Kjør og se at den feiler**

Run: `cd nordavind-addon && python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/comms_harness.lua',encoding='utf-8').read())"`
Expected: FAIL, «RANKING fra lederen naadde ikke fram»

- [ ] **Step 3: Comms-grenen**

I `Comms.lua`, rett etter `SESSION_CLOSE`-grenen:

```lua
  -- Oppdatert rangering etter at officeren byttet kategori, fjernet noen,
  -- rullet eller delte ut. Samme port som SESSION_CLOSE: den baerer det raidet
  -- ser, saa den maa komme fra den som leder.
  elseif msgType == "RANKING" then
    if not fraLeder then
      NLC.Utils.Diag("RANKING avvist - ikke fra lederen: " .. tostring(sender))
      return
    end
    if not NLC.isOfficer and NLC.Council.OnRanking then
      NLC.Council.OnRanking(data)
    end
```

- [ ] **Step 4: Council-sida**

Erstatt `OnSessionClose`:

```lua
function NLC.Council.OnSessionClose(data)
  activeSessions = data
  currentWizardIndex = 1
  -- Alle kan se rangeringen siden 30.09.2026 — men ingen skal faa et vindu
  -- dyttet i fanget midt i en pull. En linje i chatten, saa aapner den som vil.
  NLC.Utils.Print("Rangeringen er klar. Skriv |cffffd100/nordlc council|r for aa se den.")
end

-- Raider: oppdatert rangering for ett item. Vinduet tegnes paa nytt kun hvis
-- det allerede er aapent paa akkurat dette itemet.
function NLC.Council.OnRanking(data)
  if not data or not data.sessionIdx then return end
  for i, s in ipairs(activeSessions) do
    if s.sessionIdx == data.sessionIdx then
      s.ranked = data.ranked
      if i == currentWizardIndex and NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen() then
        NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      end
      return
    end
  end
end

-- Officer: send rangeringen paa nytt etter en endring. Debounce per item, saa
-- tre raske kategoribytter blir én melding og ikke tre.
function NLC.Council.BroadcastRanking(session)
  if not NLC.isOfficer or not session or session.phase ~= "ranking" then return end
  NLC.Theme.Debounce("ranking-" .. tostring(session.sessionIdx), 2, function()
    NLC.Comms.Send("RANKING", { sessionIdx = session.sessionIdx, ranked = session.ranked })
  end)
end
```

Legg til `NLC.Council.BroadcastRanking(session)` rett etter `session.ranked = NLC.Council.BuildRanking(session)` i `ChangeCategory`, `RemoveCandidate` og `RollCategory`. I `DoAward`-løkka som bygger de andre sesjonene på nytt: `s.ranked = NLC.Council.BuildRanking(s)` etterfølges av `NLC.Council.BroadcastRanking(s)`.

- [ ] **Step 5: Review Focus 5, raideren kan ikke klikke seg til noe**

Run: `grep -n "OnMouseUp\|OnClick" NordavindLC/UI/RankingFrame.lua`
Gå gjennom hvert treff. Alle handlinger skal ligge inne i `if NLC.isOfficer` eller `if NLC.isOfficer and NLC.IsLootLeader()`. Linje 284 (navnemenyen) og 443 (tildel) er allerede sperret. Finner du en handler som ikke er sperret, legg til `if not NLC.isOfficer then return end` som første linje i den. Skriv resultatet av gjennomgangen i commit-meldinga.

- [ ] **Step 6: Kjør harnessene**

Run: `for h in comms session ranking; do python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/${h}_harness.lua',encoding='utf-8').read())" || echo "FEIL: $h"; done`
Expected: ingen `FEIL:`

- [ ] **Step 7: Commit**

```bash
git add NordavindLC/Comms.lua tests/comms_harness.lua
git add -p NordavindLC/Council.lua NordavindLC/UI/RankingFrame.lua   # kun hunks fra denne oppgaven
git commit -m "feat(council): alle kan se rangeringen — RANKING-oppdateringer og /nordlc council for raidere"
```

---

## Utrulling (manuelt, kun med Revos OK)

### Task 10: Datasjekk, deploy og in-game-test

- [ ] **Step 1: Deploy nettsida og boten (spør Revo først)**

```bash
ssh root@37.27.201.23 "cd /root/nordavind-web && git pull && docker compose up -d --build"
ssh root@37.27.201.23 "cd /root/nordavind && git pull && docker compose up -d --build"
```

Nettsida først: addonen tåler gammel eksport (Task 3), men ikke omvendt.

- [ ] **Step 2: Datasjekken**

```bash
ssh root@37.27.201.23 "docker exec -i -e BEREGN=1 nordavind-web node --input-type=module -" < nordavind-web/scripts/datasjekk.mjs
```

Gi Revo lista. Rett det som mangler: be spillerne simme, sjekk karakterkoblinger og kjør M+-innsamlingen. Kjør scriptet igjen uten `BEREGN` til lista er tom eller bare har forklarte unntak.

- [ ] **Step 3: In-game med to klienter**

`/nordlc test` på officer-klienten. Sjekk:
- svarvinduet har BiS, Major, Stat, Offspec, Tmog og ingen Catalyst
- rangeringen er gruppert BiS → Major → Stat
- ⚠️-advarslene vises ved navnet
- raider-klienten får chatlinja, og `/nordlc council` viser samme liste uten knapper
- et kategoribytte hos officer kommer fram hos raideren innen ca. 2 sekunder

- [ ] **Step 4: Ekte raid, deretter tag**

Etter `RELEASE.md`: ingen tag før koden har kjørt i et ekte raid. Taggen lages av Revo eller etter Revos OK.

---

## Self-review (gjort)

- **Spec-dekning:**
  - Kategorier, sortering og overgang: Task 4
  - Trekktabellen: Task 1 og 3
  - Trekk i poeng: Task 2 og 3
  - Eksportfeltene: Task 2
  - Catalyst ut av addon, bot og regler: Task 5, 6 og 7
  - Datasjekk: Task 8 og 10
  - Varsellampe: Task 3 og 8
  - Vindu for alle: Task 9
  - Notat-varsel: Task 5
  - Tester: i hver oppgave
- **Navn på tvers av oppgavene:** `PenaltyFor`, `AddWeeklyAward`, `ImportedWeekPenalty`, `NormaliserKategori`, `BroadcastRanking`, `OnRanking`, `lootPenaltyWeek`/`lootPenaltySeason`, `mangler`, `fetchLootTally`, `tallyLoot`, `EMPTY_TALLY` og `LootTally` er brukt likt overalt.
- **Avvik fra spec** står øverst og må bekreftes av Revo.
