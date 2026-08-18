# Sim-poeng i addonet — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Addonet skal vise samme loot-poengsum som nordavind.cc for samme item, ved at nettsida regner sim ferdig og sender resultatet i eksporten.

**Architecture:** Per-item sim-utregning trekkes ut av `app/api/loot/route.ts` til en ren `lib/item-sim.ts`. Både `/api/loot` og `/api/loot/addon-export` kaller den. Eksporten sender ferdig regnet poeng per item per vanskelighetsgrad, og addonet legger tallet på `baseScore` i stedet for å regne selv.

**Tech Stack:** Next.js 15 / TypeScript (nordavind-web), Node.js + Electron (companion), Lua / WoW-addon (NordavindLC). Tester: `node --test`.

## Global Constraints

- All brukervendt tekst i addon og bot skal være på **norsk**.
- Kommentarer i Lua-filene skrives uten æøå der filen ellers unngår det — `Scoring.lua` bruker `aa/oe/ae` i nyere kommentarer. Følg fila.
- `nordavind-addon` har løse `.zip`-er og en gammel `.exe` i arbeidstreet. **Aldri `git add -A`** — legg til navngitte filer.
- Addon- og web-commits skal ha `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. Bot-commits skal **aldri** ha den.
- Det finnes **ingen Lua-testkjører og ingen `luac`**. Lua verifiseres med gjennomlesing og `/nordlc test` i spillet.
- `nordavind-web` kjører tester med `npm test`, som er `node --test lib/*.test.ts`. Testfiler må derfor ligge i `lib/` og hete `*.test.ts`.
- TOC-rekkefølgen er `Scoring.lua` (linje 26) før `Council.lua` (linje 28). Ikke bytt om.
- `toLuaTable` skriver nøkler som ikke er gyldige Lua-identifikatorer som **strenger**. Item-ID-er slås derfor opp med `tostring(itemId)`.
- Vanskelighetsgrader i WowAudit heter `"normal"`, `"heroic"`, `"mythic"`.

---

## Filstruktur

**Opprettes:**
- `nordavind-web/lib/item-sim.ts` — ren per-item sim-utregning. Henter ingenting selv.
- `nordavind-web/lib/item-sim.test.ts` — enhetstester for samme.

**Endres:**
- `nordavind-web/app/api/loot/route.ts` — inline-blokken (linje ~434–602) erstattes av ett kall.
- `nordavind-web/app/api/loot/addon-export/route.ts` — bygger `sims` per spiller, legger til `exportedAt`.
- `nordavind-addon/companion/test/watcher.test.js` — rundturstest for strengnøkler.
- `nordavind-addon/NordavindLC/Scoring.lua` — sim-ledd inn, `TierAdjustment` ut av scoringen.
- `nordavind-addon/NordavindLC/Council.lua` — kandidatfilter og vanskelighetsgrad.
- `nordavind-addon/NordavindLC/Core.lua` — testfixturen får `sims`.
- `nordavind-addon/NordavindLC/UI/RankingFrame.lua` — ferskhet og advarsler i wizarden.

---

### Task 1: Ren sim-funksjon i `lib/item-sim.ts`

**Files:**
- Create: `nordavind-web/lib/item-sim.ts`
- Test: `nordavind-web/lib/item-sim.test.ts`

**Interfaces:**
- Consumes: `TierSimEntry` og `TIER_SIMS` fra `lib/tier-sims.ts`.
- Produces: `simPointsForItem(input: SimInput): SimResult | null`, typene `SimInput`, `SimResult`, `WowAuditInstance`, `WowAuditDifficulty`.

Signaturen utvider skissen i spec-en med `className` og `role`, fordi tier-gain slår opp i `TIER_SIMS` på begge (`route.ts:526-542`).

- [ ] **Step 1: Skriv de fallerende testene**

```ts
// nordavind-web/lib/item-sim.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { simPointsForItem, type WowAuditInstance } from "./item-sim.ts";

function sims(pct: number, itemId = 1001, itemName = "Test Item"): WowAuditInstance[] {
  return [{
    difficulties: [{
      difficulty: "mythic",
      wishlist: {
        total_percentage: 100,
        encounters: [{
          encounter: "Test Boss",
          items: [{ id: itemId, name: itemName, score_by_spec: { Fury: { percentage: pct, score: 1 } } }],
        }],
      },
    }],
  }];
}

const base = {
  itemId: 1001,
  itemName: "Test Item",
  isTier: false,
  tierPieces: 0,
  className: "Warrior",
  role: "DPS",
  difficulty: "mythic" as const,
  sameSlotItems: null,
};

test("vanlig upgrade gir prosent ganger fire", () => {
  const r = simPointsForItem({ ...base, charSims: sims(2.5) });
  assert.equal(r?.points, 10);
  assert.equal(r?.pct, 2.5);
});

test("poengene har tak paa 20", () => {
  const r = simPointsForItem({ ...base, charSims: sims(6.5) });
  assert.equal(r?.points, 20);
});

test("null prosent uten tier gir ingen kandidat", () => {
  assert.equal(simPointsForItem({ ...base, charSims: sims(0) }), null);
});

test("manglende sim-tre gir ingen kandidat", () => {
  assert.equal(simPointsForItem({ ...base, charSims: [] }), null);
});

test("feil vanskelighetsgrad gir ingen kandidat", () => {
  const r = simPointsForItem({ ...base, charSims: sims(3), difficulty: "heroic" });
  assert.equal(r, null);
});

test("bedre item i samme slot skalerer poengene ned", () => {
  const tree = sims(2.0);
  tree[0].difficulties[0].wishlist.encounters[0].items.push({
    id: 2002, name: "Bedre Item", score_by_spec: { Fury: { percentage: 4.0, score: 1 } },
  });
  const r = simPointsForItem({
    ...base, charSims: tree, sameSlotItems: new Set(["bedre item"]),
  });
  // 2.0*4 = 8, skalert med 2.0/4.0 = 4
  assert.equal(r?.points, 4);
  assert.equal(r?.betterInSlot?.item, "Bedre Item");
});

test("tier-brikke med null prosent er fortsatt kandidat", () => {
  const r = simPointsForItem({
    ...base, charSims: sims(0), isTier: true, tierPieces: 1, className: "Warrior", role: "DPS",
  });
  assert.ok(r !== null);
  assert.ok(r!.points > 0);
});
```

- [ ] **Step 2: Kjør testene og se at de faller**

Run: `cd nordavind-web && npm test`
Expected: FAIL — `Cannot find module './item-sim.ts'`

- [ ] **Step 3: Implementer funksjonen**

```ts
// nordavind-web/lib/item-sim.ts
import { TIER_SIMS, type TierSimEntry } from "@/lib/tier-sims";

export type WowAuditDifficulty = "normal" | "heroic" | "mythic";

export interface WowAuditItem {
  id: number;
  name: string;
  score_by_spec?: Record<string, { percentage: number; score: number }>;
}

export interface WowAuditInstance {
  difficulties: {
    difficulty: string;
    wishlist: {
      total_percentage: number;
      encounters: { encounter?: string; items: WowAuditItem[] }[];
    };
  }[];
}

export interface SimInput {
  charSims: WowAuditInstance[];
  itemId: number | null;
  itemName: string;
  isTier: boolean;
  tierPieces: number;
  className: string | null;
  role: string | null;
  difficulty: WowAuditDifficulty;
  /** Itemnavn i smaa bokstaver som deler slot. Utledes av kallstedet. */
  sameSlotItems: Set<string> | null;
}

export interface SimResult {
  points: number;
  pct: number;
  spec: string | null;
  betterInSlot: { percent: number; boss: string; item: string } | null;
}

const HEALER_ROLES = new Set(["Healer", "Heal"]);

/** Tier-gevinst er marginal: brikka som aktiverer en bonus er verdt mest. */
function marginalGain(e: TierSimEntry, tierPieces: number): number {
  if (tierPieces === 0) return e.gain0to2 / 2;
  if (tierPieces === 1) return e.gain0to2;
  if (tierPieces === 2) return e.gain2to4 / 2;
  if (tierPieces === 3) return e.gain2to4;
  return 0;
}

function tierGainFor(className: string | null, role: string | null, tierPieces: number): number | null {
  if (!className) return null;
  const cls = className.toLowerCase();
  const tierRole = HEALER_ROLES.has(role || "") ? "healer" : role === "Tank" ? "tank" : "dps";
  let matching = TIER_SIMS.filter((t) => t.spec.toLowerCase().includes(cls) && t.role === tierRole);
  if (matching.length === 0) matching = TIER_SIMS.filter((t) => t.spec.toLowerCase().includes(cls));
  if (matching.length === 0) return null;
  const best = matching.reduce((a, b) =>
    marginalGain(b, tierPieces) > marginalGain(a, tierPieces) ? b : a
  );
  return marginalGain(best, tierPieces);
}

/**
 * Sim-poeng for ett item for én spiller. Returnerer null naar spilleren ikke er
 * kandidat: null prosent uten at itemet er en tier-brikke, eller ingen sims for
 * vanskelighetsgraden. Kandidatregelen bor her, slik at nettsida og addonet
 * ikke kan bli uenige om hvem som staar paa lista.
 */
export function simPointsForItem(input: SimInput): SimResult | null {
  const { charSims, itemId, itemName, isTier, tierPieces, difficulty, sameSlotItems } = input;

  const hasSims = charSims.some((i) =>
    i.difficulties.some((d) => d.difficulty === difficulty && d.wishlist.total_percentage > 0)
  );
  if (!hasSims) return null;

  let bestPct = 0;
  let bestSpec: string | null = null;
  for (const inst of charSims) {
    for (const diff of inst.difficulties) {
      if (diff.difficulty !== difficulty) continue;
      for (const enc of diff.wishlist.encounters) {
        for (const item of enc.items) {
          const match = (itemId != null && item.id === itemId)
            || item.name.toLowerCase() === itemName.toLowerCase();
          if (!match) continue;
          for (const [spec, data] of Object.entries(item.score_by_spec || {})) {
            if (data.percentage > bestPct) { bestPct = data.percentage; bestSpec = spec; }
          }
        }
      }
    }
  }

  if (bestPct <= 0 && !isTier) return null;

  let betterInSlot: SimResult["betterInSlot"] = null;
  if (bestPct > 0 && sameSlotItems && sameSlotItems.size > 0) {
    for (const inst of charSims) {
      for (const diff of inst.difficulties) {
        if (diff.difficulty !== difficulty) continue;
        for (const enc of diff.wishlist.encounters) {
          for (const wlItem of enc.items) {
            if (!sameSlotItems.has(wlItem.name.toLowerCase())) continue;
            for (const data of Object.values(wlItem.score_by_spec || {})) {
              if (data.percentage > bestPct && data.percentage > (betterInSlot?.percent || 0)) {
                betterInSlot = {
                  percent: data.percentage,
                  boss: enc.encounter || "Unknown",
                  item: wlItem.name,
                };
              }
            }
          }
        }
      }
    }
  }

  const tierGain = isTier ? tierGainFor(input.className, input.role, tierPieces) : null;
  const simValue = isTier && tierGain ? tierGain : bestPct;
  let points = Math.min(20, simValue * 4);
  if (betterInSlot && betterInSlot.percent > bestPct) {
    points = points * (bestPct / betterInSlot.percent);
  }

  return {
    points: Math.round(points * 10) / 10,
    pct: bestPct,
    spec: bestSpec,
    betterInSlot,
  };
}
```

- [ ] **Step 4: Kjør testene og se at de passerer**

Run: `cd nordavind-web && npm test`
Expected: PASS — alle sju nye tester, og de tolv eksisterende.

- [ ] **Step 5: Typesjekk**

Run: `cd nordavind-web && npx tsc --noEmit`
Expected: ingen utdata.

- [ ] **Step 6: Commit**

```bash
git add lib/item-sim.ts lib/item-sim.test.ts
git commit -m "feat(loot): ren per-item sim-utregning i lib/item-sim

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Koble `/api/loot` til den nye funksjonen

**Files:**
- Modify: `nordavind-web/app/api/loot/route.ts:434-602`

**Interfaces:**
- Consumes: `simPointsForItem`, `SimResult` fra Task 1.
- Produces: ingen nye. Oppførselen skal være **uendret** — dette er et rent uttrekk.

Blokken som erstattes strekker seg fra `hasSims`-sjekken (linje ~435) til og med `partialScore += simPoints` og `breakdownBefore.push(...)` (linje ~601-602). `sameSlotItems` bygges fortsatt i `route.ts`, siden det er lootbord-oppslag og ikke sim-logikk.

- [ ] **Step 1: Bytt ut blokken**

```ts
      const WOWAUDIT_DIFF = (wclDiffParam || "heroic") as WowAuditDifficulty;

      // Itemnavn som deler slot — lootbord-oppslag, ikke sim-logikk.
      let sameSlotItems: Set<string> | null = null;
      if (itemSlot) {
        const { getLootByInstance } = await import("@/lib/loot-tables");
        sameSlotItems = new Set<string>();
        for (const inst of getLootByInstance()) {
          for (const boss of inst.bosses) {
            for (const lootItem of boss.items) {
              if (lootItem.slot === itemSlot && lootItem.name.toLowerCase() !== itemName?.toLowerCase()) {
                sameSlotItems.add(lootItem.name.toLowerCase());
              }
            }
          }
        }
      }

      const sim = simPointsForItem({
        charSims: char.instances,
        itemId,
        itemName: itemName || "",
        isTier: isTierPiece,
        tierPieces: sheetData.get(char.name.toLowerCase())?.tierPieces || 0,
        className: rosterChar?.class || null,
        role: rosterChar?.role || null,
        difficulty: WOWAUDIT_DIFF,
        sameSlotItems,
      });
      if (!sim) continue;

      const bestUpgrade = { percentage: sim.pct, spec: sim.spec };
      if (sim.betterInSlot) {
        warningsBefore.push(
          `Bedre item fra ${sim.betterInSlot.boss}: ${sim.betterInSlot.item} (+${sim.betterInSlot.percent.toFixed(1)}%)`
        );
      }
      partialScore += sim.points;
      breakdownBefore.push({
        label: isTierPiece ? "Tier gain" : "Sim upgrade",
        points: sim.points,
      });
```

Importen legges øverst i fila:

```ts
import { simPointsForItem, type WowAuditDifficulty } from "@/lib/item-sim";
```

Den gamle `tierGain`-blokken (linje ~525-567) og `let simPoints`-blokken slettes. `tierSims`-importen i `route.ts` fjernes hvis den ikke brukes andre steder — sjekk med `grep -n "tierSims" app/api/loot/route.ts` før du sletter.

- [ ] **Step 2: Typesjekk**

Run: `cd nordavind-web && npx tsc --noEmit`
Expected: ingen utdata. Får du «`bestUpgrade.absolute` finnes ikke», er det et brukssted lenger nede som må leses fra `sim.pct` i stedet — `absolute` ble kun brukt til visning.

- [ ] **Step 3: Kjør testene**

Run: `cd nordavind-web && npm test`
Expected: PASS, 19 tester.

- [ ] **Step 4: Verifiser at oppførselen er uendret**

Start `npm run dev`, åpne loot-sida, velg et item flere spillere har sim på. Noter topp tre med poeng. Sammenlign med `git stash` av endringen. Tallene skal være identiske.

- [ ] **Step 5: Commit**

```bash
git add app/api/loot/route.ts
git commit -m "refactor(loot): /loot bruker den delte sim-funksjonen

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Eksporter sims per item

**Files:**
- Modify: `nordavind-web/app/api/loot/addon-export/route.ts`

**Interfaces:**
- Consumes: `simPointsForItem` fra Task 1, `getLootByInstance` fra `lib/loot-tables`.
- Produces: JSON-feltene `players[navn].sims[difficulty][itemIdSomStreng] = { p, u }` og toppnivå `exportedAt` (unix-sekunder).

Eksporten har i dag ikke WowAudit-simtreet — `fetchWishlists()` henter bare ID-lista. Den må hente `https://wowaudit.com/v1/characters` med fullt tre, slik `/api/loot` gjør via `fetchRoster()`.

- [ ] **Step 1: Bygg sims-kartet**

```ts
const DIFFICULTIES: WowAuditDifficulty[] = ["normal", "heroic", "mythic"];

/** Slot per itemnavn, og settet av navn som deler slot. Bygges én gang. */
function buildSlotIndex() {
  const slotOf = new Map<string, string>();
  const bySlot = new Map<string, Set<string>>();
  for (const inst of getLootByInstance()) {
    for (const boss of inst.bosses) {
      for (const it of boss.items) {
        const key = it.name.toLowerCase();
        slotOf.set(key, it.slot);
        if (!bySlot.has(it.slot)) bySlot.set(it.slot, new Set());
        bySlot.get(it.slot)!.add(key);
      }
    }
  }
  return { slotOf, bySlot };
}

// Bygges én gang per forespoersel, ikke per spiller — lootbordet er statisk.
const SLOT_INDEX = buildSlotIndex();

function buildSims(
  char: { name: string; instances: WowAuditInstance[]; class?: string; role?: string },
  tierPieces: number,
  itemIdByName: Map<string, number>
): Record<string, Record<string, { p: number; u: number }>> | undefined {
  const { slotOf, bySlot } = SLOT_INDEX;
  const out: Record<string, Record<string, { p: number; u: number }>> = {};

  for (const difficulty of DIFFICULTIES) {
    const perItem: Record<string, { p: number; u: number }> = {};
    for (const inst of getLootByInstance()) {
      for (const boss of inst.bosses) {
        for (const it of boss.items) {
          const key = it.name.toLowerCase();
          const itemId = itemIdByName.get(key) ?? null;
          if (itemId == null) continue; // uten ID kan addonet ikke slaa den opp
          const slot = slotOf.get(key);
          const sameSlot = slot ? new Set([...(bySlot.get(slot) || [])].filter((n) => n !== key)) : null;
          const sim = simPointsForItem({
            charSims: char.instances,
            itemId,
            itemName: it.name,
            isTier: it.isTier,
            tierPieces,
            className: char.class || null,
            role: char.role || null,
            difficulty,
            sameSlotItems: sameSlot,
          });
          if (!sim) continue;
          perItem[String(itemId)] = {
            p: sim.points,
            u: Math.round(sim.pct * 10) / 10,
          };
        }
      }
    }
    if (Object.keys(perItem).length > 0) out[difficulty] = perItem;
  }

  return Object.keys(out).length > 0 ? out : undefined;
}
```

`itemIdByName` bygges av WowAudit-treet, som er eneste sted ID og navn opptrer sammen:

```ts
function buildItemIdIndex(chars: { instances: WowAuditInstance[] }[]): Map<string, number> {
  const map = new Map<string, number>();
  for (const c of chars) {
    for (const inst of c.instances || []) {
      for (const diff of inst.difficulties || []) {
        for (const enc of diff.wishlist?.encounters || []) {
          for (const it of enc.items || []) {
            if (it.id > 0 && !map.has(it.name.toLowerCase())) map.set(it.name.toLowerCase(), it.id);
          }
        }
      }
    }
  }
  return map;
}
```

- [ ] **Step 2: Legg feltene i svaret**

I løkka som bygger `players[s.playerName]`, legg til `sims: buildSims(...)`. I `NextResponse.json({...})` legg til `exportedAt: Math.floor(Date.now() / 1000)`.

- [ ] **Step 3: Typesjekk og test**

Run: `cd nordavind-web && npx tsc --noEmit && npm test`
Expected: ingen typefeil, 19 tester passerer.

- [ ] **Step 4: Sjekk svaret manuelt**

Run: `curl -s -H "x-api-key: $ADDON_API_KEY" http://localhost:3000/api/loot/addon-export | head -c 2000`
Expected: `exportedAt` er et tall, og minst én spiller har `sims.mythic` eller `sims.heroic` med minst én item-ID som nøkkel.

Er `sims` `undefined` for alle, sjekk at `WOWAUDIT_API_KEY` er satt lokalt — uten den er treet tomt og alle faller ut på `hasSims`.

- [ ] **Step 5: Commit**

```bash
git add app/api/loot/addon-export/route.ts
git commit -m "feat(loot): eksporter sim-poeng per item til addonet

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Rundturstest for strengnøkler i companion

**Files:**
- Modify: `nordavind-addon/companion/test/watcher.test.js`

**Interfaces:**
- Consumes: `toLuaTable`, `parseLuaTable` fra `companion/lib/lua-parser.js`.
- Produces: ingen. Sikrer fella beskrevet i spec-en.

- [ ] **Step 1: Skriv testen**

```js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { toLuaTable, parseLuaTable } = require("../lib/lua-parser");

test("tallignende strengnoekler overlever skriv og les", () => {
  const input = { sims: { mythic: { "228254": { p: 12.4, u: 3.1 } } } };
  const lua = toLuaTable(input);
  assert.match(lua, /\["228254"\]/);
  const parsed = parseLuaTable(lua);
  assert.equal(parsed.sims.mythic["228254"].p, 12.4);
  assert.equal(parsed.sims.mythic["228254"].u, 3.1);
});
```

- [ ] **Step 2: Kjør testen**

Run: `cd nordavind-addon/companion && npm test`
Expected: PASS. Faller den på parsing, er det `parseLuaTable` som ikke håndterer `["..."]`-nøkler — fiks den før du går videre, ellers stopper importen i addonet.

- [ ] **Step 3: Commit**

```bash
git add companion/test/watcher.test.js
git commit -m "test(companion): strengnoekler overlever rundturen

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Sim-ledd i addonets scoring

**Files:**
- Modify: `nordavind-addon/NordavindLC/Scoring.lua:62-95`

**Interfaces:**
- Consumes: `imported.sims` fra Task 3.
- Produces: `NLC.Scoring.Calculate(imported, live, playerName)` leser nå `live.itemId` og `live.difficulty`.

- [ ] **Step 1: Legg sim inn i `Calculate`**

Rett etter `Base (web)`-linja, før tier-blokken:

```lua
  -- Sim-poeng kommer ferdig regnet fra nettsida. Noekkelen er en STRENG:
  -- companion-serialiseringen skriver alle ikke-identifikator-noekler slik, og
  -- itemId fra spillet er et tall. Uten tostring blir oppslaget nil, og det ville
  -- gitt "ingen sim -> 0 poeng" uten feilmelding midt i et raid.
  if imported and live and live.itemId and live.difficulty then
    local perDiff = imported.sims and imported.sims[live.difficulty]
    local entry = perDiff and perDiff[tostring(live.itemId)]
    if entry and entry.p then
      score = score + entry.p
      table.insert(breakdown, {
        label = string.format("Sim upgrade (%.1f %%)", entry.u or 0),
        value = entry.p,
      })
    end
  end
```

- [ ] **Step 2: Ta `TierAdjustment` ut av scoringen**

Slett blokken på linje ~88-92 (`if live and live.isTier and live.tierCount then ... end`). Selve funksjonen `NLC.Scoring.TierAdjustment` blir stående ubrukt til in-game-testen har bekreftet at tier-poeng nå kommer fra eksporten. Legg en kommentar over den:

```lua
-- UBRUKT fra 2026-08-01: tier-gevinst regnes av nettsida og kommer i sims.
-- Beholdes til in-game-testen har bekreftet at eksporten leverer tier-poeng.
```

- [ ] **Step 3: Les gjennom**

Det finnes ingen Lua-testkjører. Les hele `Calculate` på nytt og bekreft: `score` starter på `imported.baseScore`, sim legges på én gang, ingen `wl`-variabel er blitt foreldreløs.

- [ ] **Step 4: Commit**

```bash
git add NordavindLC/Scoring.lua
git commit -m "feat(scoring): sim-poeng fra eksporten i stedet for tier-bonus

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Kandidatfilter og vanskelighetsgrad i Council

**Files:**
- Modify: `nordavind-addon/NordavindLC/Council.lua:258-268` (wishlist-filteret), og der økta opprettes.

**Interfaces:**
- Consumes: `imported.sims` fra Task 3.
- Produces: `session.difficulty` — settes én gang per økt, leses av Task 5 via `live.difficulty`.

- [ ] **Step 1: Bestem vanskelighetsgrad når økta starter**

```lua
-- Graden avgjoeres EN gang per oekt. Per kandidat ville aapnet for at to
-- spillere ble maalt paa ulik grad av samme item.
local DIFF_BY_ID = { [14] = "normal", [15] = "heroic", [16] = "mythic" }

function NLC.Council.ResolveDifficulty()
  local _, _, difficultyID = GetInstanceInfo()
  local diff = DIFF_BY_ID[difficultyID or 0]
  if diff then return diff, false end
  -- Utenfor et raid (typisk /nordlc test) faller vi tilbake paa nettsidas
  -- standard, og sier fra at den ble gjettet.
  return "heroic", true
end
```

Sett `session.difficulty, session.difficultyGuessed = NLC.Council.ResolveDifficulty()` der økta bygges.

- [ ] **Step 2: Bytt ut wishlist-filteret**

Erstatt blokken på linje 258-268 med:

```lua
    -- Kandidatregelen bor i eksporten: finnes det en sim-oppfoering for itemet,
    -- er du kandidat paa Upgrade — ellers ikke. Nettsida og addonet kan da ikke
    -- vise ulike kandidatlister. Gjelder kun Upgrade, slik wishlist-filteret
    -- gjorde; catalyst og offspec staar uansett under i catOrder.
    if not skipCandidate and interest.category == "upgrade" and session.itemId then
      local perDiff = imported and imported.sims and imported.sims[session.difficulty]
      if not (perDiff and perDiff[tostring(session.itemId)]) then
        skipCandidate = true
      end
    end
```

- [ ] **Step 3: Send item og grad videre til scoringen**

`live`-tabellen bygges på linje ~226-244 og sendes inn på linje 246. Legg til to felter til slutt i tabellen, rett etter `isTier`:

```lua
      itemId = session.itemId,
      difficulty = session.difficulty,
```

- [ ] **Step 4: La `wishlist` stå i eksporten**

Addonet slutter å bruke feltet, men det skal **ikke** fjernes fra `addon-export`. Vi legger kun til felter, slik at eldre addon-versjoner fortsetter å virke gjennom overgangen.

- [ ] **Step 5: Les gjennom**

Bekreft at `session.difficulty` er satt før første kall til `Calculate`, ellers blir sim-poengene 0 for alle uten at noe feiler.

- [ ] **Step 5: Commit**

```bash
git add NordavindLC/Council.lua
git commit -m "feat(council): sim-oppfoering avgjoer kandidatur paa upgrade

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Testfixturen får sims

**Files:**
- Modify: `nordavind-addon/NordavindLC/Core.lua:418-441`

**Interfaces:**
- Consumes: ingen.
- Produces: `/nordlc test` dekker den nye kodestien.

Uten dette tester offline-kjøringen fortsatt den gamle stien, og er verdiløs for denne endringen. Item-ID-ene må matche `fakeItems` (111111, 222222, 333333).

- [ ] **Step 1: Utvid mock-dataene**

```lua
        NLC.db.importData.players[p.name] = {
          attendance = p.attendance, wclParse = p.wclParse, defensives = p.defensives,
          baseScore = p.baseScore, rank = p.rank, lootThisWeek = 0, lootTotal = 2,
          mplusEffort = 10, role = "dps", deathPenalty = 0,
          -- Noeklene er strenger, slik companion skriver dem.
          sims = {
            heroic = {
              ["111111"] = { p = p.sim1 or 0, u = 2.5 },
              ["222222"] = { p = p.sim2 or 0, u = 1.8 },
            },
          },
        }
```

Legg `sim1` og `sim2` på testspillerne. Gi `Testrogue` verdien 0 på begge, så filtreringen faktisk testes:

```lua
        { name = "Testwarrior",  ..., baseScore = 38.5, sim1 = 12.0, sim2 = 4.0 },
        { name = "Testshaman",   ..., baseScore = 36.2, sim1 = 8.0,  sim2 = 20.0 },
        { name = "Testpaladin",  ..., baseScore = 32.0, sim1 = 4.0,  sim2 = 0 },
        { name = "Testmage",     ..., baseScore = 25.8, sim1 = 20.0, sim2 = 6.0 },
        { name = "Testrogue",    ..., baseScore = 30.5, sim1 = 0,    sim2 = 0 },
```

Merk at item 333333 bevisst mangler i `sims` — da kan du se at ingen blir kandidat på Upgrade der.

- [ ] **Step 2: Test i spillet**

```
/reload
/nordlc test
```

Forventet:
- Item 111111: Testmage øverst blant upgrade-kandidatene (20 sim-poeng på 25,8 base).
- Item 222222: Testshaman har mest sim, men rank slår — Testwarrior og Testshaman er begge raidere, så Testshaman vinner der.
- Item 333333: ingen upgrade-kandidater. Tmog-kandidatene står fortsatt.
- Testrogue skal aldri stå som Upgrade-kandidat.

- [ ] **Step 3: Commit**

```bash
git add NordavindLC/Core.lua
git commit -m "test(core): testfixturen dekker sim-poeng og filtrering

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Advarsler i wizarden

**Files:**
- Modify: `nordavind-addon/NordavindLC/UI/RankingFrame.lua`
- Modify: `nordavind-addon/NordavindLC/Scoring.lua` (`GetWarnings`)

**Interfaces:**
- Consumes: `imported.sims`, toppnivå `exportedAt` fra Task 3, `session.difficultyGuessed` fra Task 6.
- Produces: ingen.

Disse tre varslene er det som gjør regelen om officer-kontroll gjennomførbar. Skal officers bekrefte at grunnlaget stemmer før tildeling, må grunnlaget kunne ses.

- [ ] **Step 1: Advar om spiller uten sim-data i det hele tatt**

I `NLC.Scoring.GetWarnings`, etter parse-advarselen:

```lua
  -- Ingen oppfoering for ETT item er regelen, ikke en feil. Mangler spilleren
  -- sims HELT, er det som regel ukoblet karakter eller feilstavet navn — det
  -- skal ses, ikke bli en stille null.
  if not imported.sims or next(imported.sims) == nil then
    table.insert(warnings, "Ingen sim-data")
  end
```

- [ ] **Step 2: Vis alder på importen og gjettet grad i tittelen**

Tittelen settes i dag på `RankingFrame.lua:159`:

```lua
  rankFrame.title:SetText(T.GOLD .. "Loot Council|r  " .. T.MUTED .. "—|r  " .. (session.itemLink or "?"))
```

Bytt den mot:

```lua
  -- Officers skal bekrefte at grunnlaget stemmer foer tildeling. Da maa
  -- grunnlaget kunne ses: hvor gammelt oeyeblikksbildet er, og om graden
  -- ble gjettet.
  local suffix = ""
  local exportedAt = NLC.db.importData and NLC.db.importData.exportedAt
  if exportedAt then
    local hours = (time() - exportedAt) / 3600
    local age = hours < 1 and "under 1 t"
      or string.format("%.0f t", hours)
    -- Et raid varer 2,5 t, saa en eksport fra samme dag er alltid grei.
    -- Er den eldre, har companion-appen sannsynligvis ikke kjoert.
    local color = hours > 12 and "|cffff4444" or "|cff888888"
    suffix = suffix .. "  " .. color .. "Import: " .. age .. " gammel|r"
  else
    suffix = suffix .. "  |cffff4444Ingen importdato|r"
  end
  if session.difficultyGuessed then
    suffix = suffix .. "  |cffffcc00Grad gjettet: Heroic|r"
  end

  rankFrame.title:SetText(
    T.GOLD .. "Loot Council|r  " .. T.MUTED .. "—|r  " .. (session.itemLink or "?") .. suffix
  )
```

- [ ] **Step 3: Test i spillet**

```
/reload
/nordlc test
```

Forventet: alderslinja vises. Sett `NordavindLC_DB.importData.exportedAt = time() - 60*60*20` i konsollet og kjør `/nordlc test` igjen — linja skal bli rød. Utenfor et raid skal grad-advarselen alltid vises.

- [ ] **Step 4: Commit**

```bash
git add NordavindLC/UI/RankingFrame.lua NordavindLC/Scoring.lua
git commit -m "feat(ui): ferskhet, manglende sim-data og gjettet grad i wizarden

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Etter planen

**In-game-test kreves før merge.** Denne endringen legger seg på toppen av de fem portene som allerede står i `project_nordavind_addon_todo` — restriksjons-gating, roll-off, bag-scan, ShowMenu/RW og avstemmings-comms. Sim-poengene er en sjette: at et ekte item med ekte sims gir samme tall i addonet som på nordavind.cc.

**Companion må bygges på nytt.** `npm run dist` og reinstaller lokalt. Uten det henter den kjørende appen fortsatt gammel eksport uten `sims`, og addonet får ingenting.

**`lib/tier-sims.ts` må oppdateres til sesong 2** før dette gir riktige tier-tall. Fila inneholder sesong 1-data. Planen flytter tier-utregningen; den fikser ikke dataene.
