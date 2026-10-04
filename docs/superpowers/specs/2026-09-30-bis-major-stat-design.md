# BiS / Major / Stat upgrade, riktige tall og åpent council-vindu

Dato: 2026-09-30. Berører `nordavind-addon`, `nordavind-web` og `nordavind-bot`.

## Bakgrunn

Revo ba om innspill på loot i #raidprat 22.09 og i #loot-addon-feedback. Alle som svarte
ville ha en BiS-knapp, men de var uenige om major/minor. Revo har bestemt:

- Upgrade deles i **BiS** (det simulationcraft.org viser for specen), **Major upgrade** og
  **Stat upgrade**.
- Catalyst fjernes.
- Trekket etter mottatt loot avhenger av knappen.
- Alle tall bak rangeringen skal være oppdatert for alle spillere.
- Alle skal kunne se council-vinduet.

## Levert i tre deler

1. Knapper og trekk
2. Riktige tall
3. Council-vinduet for alle

Hver del kan tas i bruk alene. Del 3 bygger på del 1, fordi vinduet viser de nye kategoriene.

---

## Del 1: knapper og trekk

### Kategorier

Kategoriene lagres i databasen som tekst, `LootHistory.category`: `bis`, `major`, `stat`,
`offspec`, `tmog`. Det trengs ingen skjemaendring. Kommentaren på feltet i begge
`schema.prisma` oppdateres.

**Knappen går foran poengene.** Addonen sorterer i denne rekkefølgen: kategori, så rank
(raider > trial > backup), så poeng, så færrest items i sesongen, og til slutt seedet terning.

```
catOrder = { bis = 1, major = 2, stat = 3, offspec = 4, tmog = 5 }
```

### Trekk

| Kategori | Per item denne uka | Per item tidligere i sesongen |
|---|---|---|
| `bis` | 10 | 2 |
| `major` | 7 | 1,5 |
| `stat` | 5 | 1 |
| `upgrade`, `catalyst` (gamle rader) | 10 | 2 |
| `offspec`, `tmog` | 0 | 0 |

Gamle rader beholder dagens trekk, så ingen flytter seg på lista uten å ha fått noe nytt.

Tabellen står **to steder, og de to MÅ være like**:
- `nordavind-web/lib/scoring.ts`, som `LOOT_PENALTY` og erstatter `PENALISED`
- `nordavind-addon/NordavindLC/Scoring.lua`, som `LOOT_PENALTY` og erstatter
  `PENALISED_CATEGORIES`

Begge får kommentaren «MÅ matche» og peker på hverandre.

### Trekket regnes i poeng, ikke antall

I dag er formelen `lootPenalty(thisWeek, total) = thisWeek*10 + total*2`. Den blir
`lootPenalty(rows)`: summen av trekket for hver rad, der uka og resten av sesongen regnes
hver for seg.

- **Web:** `lib/scoring.ts` og `app/api/loot/route.ts` henter `category` og `createdAt` per
  rad i stedet for `count`. `category: { in: PENALISED }` byttes med «kategori finnes i
  `LOOT_PENALTY` med trekk > 0».
- **Eksporten** (`app/api/loot/addon-export/route.ts`) får to nye felt per spiller:
  `lootPenaltyWeek` og `lootPenaltySeason`, der trekket allerede er regnet ut. Feltene
  `lootThisWeek` og `lootTotal` beholdes, fordi uavgjort fortsatt avgjøres på antall.
  `baseScore` regnes med det nye trekket.
- **Addon:** `NLC.db.weeklyLoot` får `penalty[playerName]` i tillegg til `counts`. Når et
  item deles ut, legges `LOOT_PENALTY[cat].week` til. `Scoring.Calculate` bruker
  in-game-trekket når en reset er registrert, og ellers `lootPenaltyWeek` fra importen.
  Det følger samme regel som `WeeklyLootCount` bruker i dag.
- Items som teller i antallet: alle kategorier med trekk > 0. `CountsAsLoot` blir
  `LOOT_PENALTY[cat] ~= nil and week > 0`.

### Overgangen mellom versjoner

- Raidere på gammel addon sender `upgrade` eller `catalyst`. Council-addonen **gjør dem om til
  `major` når svaret kommer inn** (`OnInterestReceived`). De havner da verken bakerst eller
  forsvinner. Officeren kan rette kategorien i historikken etterpå.
- Eksport der `lootPenaltyWeek` mangler (gammel nettside): addonen faller tilbake til
  `lootThisWeek*10 + lootTotal*2`.

### Catalyst fjernes fra

- `UI/CouncilFrame.lua`: knapper og tooltips. Nye tooltips:
  - BiS: «Beste item for din spec ifølge simulationcraft.org»
  - Major: «Stor oppgradering»
  - Stat: «Liten oppgradering, mest stats»
- `Council.lua`: `catOrder` og `CAT_NO` (`bis = "BiS"`, `major = "Major"`,
  `stat = "Stat upgrade"`)
- `Core.lua`: `GYLDIGE`/`GYLDIGE_KAT` for manuelle kommandoer, hjelpetekst og testdata i
  `/nordlc test`
- `Utils.lua`: `GetAvailableCategories` gir `bis`/`major`/`stat` der den i dag gir `upgrade`.
  `catalyst` fjernes. Wishlist-filteret gjelder alle tre.
- `UI/HistoryFrame.lua`: velgeren for kategori
- Boten `commands/loot.js` og `events/interactionCreate.js`: knappene og etikettene. Den
  hardkodede `category: "upgrade"` i `loot.js:523` blir `major`.
- Regelteksten `nordavind-web/docs/sesong2-regler-discord.md` (og embed-varianten og
  `scripts/reglerEmbeds.js`): knappelinja, trekktabellen og setningen «Catalyst teller som
  upgrade». Regelteksten er på 5974 av 6000 tegn, så teksten må kortes der den endres.

Tier-regelen med +3/+1 i `Scoring.TierAdjustment` er uendret.

---

## Del 2: riktige tall

### Gjennomgang nå, én gang

Et script, `nordavind-web/scripts/datasjekk.ts`, kjøres i nettside-containeren. For hver
spiller på rosteret viser det:

- dato for siste WCL-parse brukt i poengene
- antall M+-uker registrert mot antall uker i sesongen
- grunnlaget for oppmøte (antall raid)
- om det finnes WowAudit-sim for Heroic og for Mythic

Det som mangler, rettes før neste raid. Revo får lista.

### Varsellampe

Eksporten får `mangler: string[]` per spiller. Nettsida avgjør grensene, og bare der:

- ingen parse siste 14 dager: «ingen parse siste 14 dager»
- ingen sim for graden: «ingen sim (Heroic)» / «ingen sim (Mythic)»
- M+-uker registrert < uker i sesongen minus 1: «M+ mangler for N uker»
- ingen oppmøteregistrering: «ingen oppmøte»

Addonen viser ⚠️ ved navnet i rangeringen og lista som tooltip. Addonen avgjør ingenting
selv. Tom eller manglende liste betyr ingen lampe.

---

## Del 3: council-vinduet for alle

- Officerens addon er den eneste som har importen, og den eneste som regner. Etter hver
  `BuildRanking` sendes kandidatlista ut som den nye meldingen **`RANKING`** til raidet.
  Det skjer på tidligst 2 sekunder etter forrige utsending. Innholdet er `sessionIdx`,
  `itemLink` og per kandidat: navn, klasse, kategori, poeng, poeng per ledd, notat, rank,
  `mangler`, ilvl-diff, tier-antall og kast.
- Raiderne regner aldri selv, så to versjoner kan ikke vise hvert sitt svar.
- Raiderne lagrer siste `RANKING` per `sessionIdx`. De åpner vinduet med
  **`/nordlc council`** eller knappen **«Se rangering»** i svarvinduet.
- Det brukes **samme `RankingFrame`**. Alle handlingsknapper (tildel, roll, senere, spesial,
  stem) er allerede låst til `NLC.isOfficer and NLC.IsLootLeader()`. Det sjekkes at ingen
  knapp slipper gjennom for raidere, og at klikk på en rad ikke gjør noe for dem.
- Under notatfeltet i svarvinduet står: «Notatet er synlig for hele raidet.»
- Gamle versjoner ignorerer ukjente meldingstyper (`Comms.OnMessage`). Det bekreftes i
  `comms_harness.lua`.

---

## Test

- **Lua** (`tests/ranking_harness.lua` og ny `tests/lootpenalty_harness.lua`):
  - sortering bis > major > stat > offspec > tmog
  - innkommende `upgrade`/`catalyst` blir `major`
  - trekk i poeng denne uka og i sesongen
  - fallback når eksporten mangler `lootPenaltyWeek`
  - gamle `upgrade`-rader gir 10/2
- **Web** (`node --test`): `lootPenalty` med de samme tilfellene og tallene som Lua-testen.
  Husk `.ts`-endelse på lib→lib-importer.
- **Comms:** `RANKING` går rundt: officer bygger, raider tar imot og viser den samme lista.
- **In-game:** `/nordlc test` med to klienter (officer og raider) før tag, etter `RELEASE.md`.
  Ingen tag før koden har kjørt i et ekte raid.

## Utenfor denne spec-en

- Automatisk sjekk av om BiS-påstanden stemmer. Det finnes ingen BiS-liste fra
  simulationcraft i dataene. Officers kan overprøve med «endre kategori», som finnes fra før.
- Endringer i vekter (oppmøte, WCL, M+, sim, rolle).
