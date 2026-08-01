# Sim-poeng i addonet — design

**Dato:** 2026-08-01
**Berører:** `nordavind-web` (uttrekk + eksport), `nordavind-addon` (scoring, wizard), `companion` (rundtur)

## Problemet

Addonet og nettsida rangerer loot-kandidater på ulikt grunnlag.

Nettsidas kandidat-score er `partialScore + attNet`, der `partialScore` inkluderer `simPoints` på 0–20 (`app/api/loot/route.ts:601`). Addonets score er `imported.baseScore` pluss en tier-justering (`Scoring.lua:62-92`), og `baseScore` fra `calculateScore()` inneholder oppmøte, parse, M+, rolle og straffene — **ingen sim**.

Sim-upgrade er per item per spiller og finnes kun på nettsida, fordi den kommer fra WowAudit-treet `char.instances[].difficulties[].wishlist.encounters[].items[].score_by_spec{}`. Addonet har aldri fått tallet.

Konsekvensen er at rekkefølgen i raidet og rekkefølgen på nordavind.cc avviker systematisk — ikke bare ved uavgjort. Deler officers ut fra addonet, har sims i praksis nær null vekt in-game, mens regelverket og officer-diskusjonen forutsetter at de veier 20 av 75.

Addonet bruker sims indirekte i dag: `upgrade`-kandidater uten itemet på wishlisten filtreres bort (`Council.lua:258-268`).

## Avgjørelser

| Spørsmål | Valg |
|---|---|
| Hva må være likt | **Nøyaktig samme tall**, inkludert same-slot-justering og tier-gain |
| Ferskhet | **Vis alder og advar** i wizarden; ingen frysing av sim ved raidstart |
| Tier | **Nettsida regner**, addonets live-telling blir informasjon, ikke poeng |
| Kandidatur på Upgrade | **Krever sim > 0 %**, og regelen skrives inn i regelteksten |
| Dataform | Nettsida sender **ferdig regnet poeng**, ikke ingredienser |

Rå prosent i eksporten ble forkastet: da måtte same-slot-logikken ha slot-data i Lua og tier-gain ha `tier-sims` i Lua. Det er to nye kopier av logikk som skal holdes i takt for hånd, og det bryter med kravet om nøyaktig samme tall. Kodebasen har allerede betalt for det mønsteret med fem kopier av ukesgrensa og to ulike `CLASS_DEFENSIVE_COUNT`-tabeller.

Live henting fra companion ble vurdert og forkastet som umulig: WoW-addons kan ikke lese filer eller snakke med en lokal prosess under kjøring. SavedVariables ved innlogging er eneste kanal, og `/reload`-begrensningen kan derfor bare gjøres synlig, ikke designes bort.

## Arkitektur

Kjernegrepet er å flytte per-item-utregningen ut av `route.ts` og inn i `lib/`, slik at begge sider kaller samme funksjon. Uten uttrekket må eksporten kopiere beregningen, og da har vi bygget nøyaktig feilen dette skal fjerne.

Ny `nordavind-web/lib/item-sim.ts`:

```ts
export function simPointsForItem(input: {
  charSims: WowAuditInstances;   // char.instances fra WowAudit
  itemId: number | null;
  itemName: string;
  isTier: boolean;
  tierPieces: number;            // antall brikker spilleren har
  difficulty: "normal" | "heroic" | "mythic";
  sameSlotItems: Set<string> | null;  // itemnavn som deler slot, utledet av kallstedet
}): { points: number; pct: number; spec: string | null } | null
```

Funksjonen er ren: den henter ingenting selv, men får WowAudit-treet og lootbord-oppslaget inn som argumenter. Da kan den testes med `node --test` uten nett og uten database, slik `lib/attendance.ts` og `lib/weekly-reset.ts` allerede testes.

Returnerer `null` når spilleren ikke er kandidat — altså `pct <= 0` og itemet ikke er en tier-brikke, eller når spilleren mangler sims for vanskelighetsgraden. Kandidatregelen bor dermed ett sted.

`app/api/loot/route.ts` kaller den for det ene itemet councilet står i. `app/api/loot/addon-export/route.ts` kaller den i en løkke over lootbordet × roster. Med ~30 spillere og ~45 items er det noen tusen enkle utregninger.

Sidegevinst: `route.ts` blir kortere. Beregningen ligger i dag inline i en 400 linjer lang løkke som også henter WCL, oppmøte og loot-tellere, og det er halve grunnen til at avviket kunne oppstå usett.

## Datakontrakt

Eksporten utvides per spiller:

```
players["Revohunt"] = {
  -- som i dag: baseScore, rank, lootThisWeek, lootTotal, wishlist, ...
  sims = {
    mythic = { ["228254"] = { p = 12.4, u = 3.1 }, ... },
    heroic = { ... },
  },
}
```

`p` er ferdig sim-poeng (0–20, same-slot og tier innregnet). `u` er rå upgrade-prosent og brukes **kun** til visning i breakdownen. Korte navn fordi de gjentas tusenvis av ganger i en tekstfil.

Bare vanskelighetsgrader spilleren har sims for tas med. Mangler hun sims helt, utelates `sims` — det er signalet «ikke vurdert på denne bossen».

På toppnivå legges `exportedAt` ved siden av dagens `generatedAt`. De to er ikke det samme: `generatedAt` sier når scorene sist ble regnet, mens ferskhetsadvarselen trenger å vite når eksporten ble skrevet.

`exportedAt` er **unix-sekunder som tall**, ikke ISO-streng. Addonet sammenligner den direkte mot `time()`; en streng måtte parses i Lua uten dato-bibliotek.

Størrelsen lander på rundt 130 kB med tre vanskelighetsgrader og full roster. SavedVariables-filer er rutinemessig flere megabyte.

### Strengnøkler

`toLuaTable` (`companion/lib/lua-parser.js:136-142`) skriver alle nøkler som ikke er gyldige Lua-identifikatorer som strenger: `["228254"] = ...`. Addonet får item-ID fra spillet som et **tall**. Slår man opp direkte, blir resultatet `nil`, og det gir «ingen sim → 0 poeng» uten feilmelding midt i et raid.

Addonet skal derfor slå opp med `tostring(itemId)`. Serialiseringen endres ikke — den brukes også til å lese `pendingExport` tilbake, og en fungerende toveis-kontrakt er ikke verdt å røre for kosmetikk.

### Bakoverkompatibilitet

Vi legger kun til felter. `wishlist` blir liggende i eksporten selv om addonet slutter å bruke det til filtrering, slik at eldre addon-versjoner fortsetter å virke.

## Addonet

`NLC.Scoring.Calculate(imported, live, playerName)` tar allerede item-spesifikk kontekst via `live` (`isTier`, `tierCount`). Sim føyer seg inn der: `live.itemId` og en økt-bestemt `live.difficulty`. Oppslaget er `imported.sims[difficulty][tostring(itemId)]`, og `p` legges på med egen linje i breakdownen — «Sim upgrade 12,4 (3,1 %)» — så officeren ser hvor poengene kommer fra.

`TierAdjustment` slutter å gi poeng. Live-tellingen av brikker blir stående i wizarden som informasjon. Funksjonen slettes ikke med én gang; den blir stående ubrukt til in-game-testen har bekreftet at tier-poengene faktisk kommer fra eksporten.

Kandidatfilteret i `Council.lua:258-268` erstattes: finnes det en oppføring i `sims`, er du kandidat; finnes den ikke, er du det ikke. Wishlist-oppslaget fjernes.

Kravet gjelder **kun kategorien Upgrade**, som wishlist-filteret gjør i dag. Catalyst og offspec får sim-poeng hvis oppføringen finnes, ellers 0. Siden `catOrder` sorterer dem under Upgrade, kan sim-poeng der ikke flytte noen forbi en upgrade-kandidat. Tmog er urørt — den bruker terningkast som score.

Paritet er dermed definert for Upgrade. For de øvrige kategoriene har nettsida ingen tilsvarende liste å være enig med, siden den ikke kjenner kategorivalg.

## Feilhåndtering

**Vanskelighetsgrad** avgjøres én gang når økta starter, via `select(3, GetInstanceInfo())` → 14/15/16 → `normal`/`heroic`/`mythic`. Per kandidat ville åpnet for at to spillere ble målt på ulik grad. Lar den seg ikke bestemme — typisk `/nordlc test` utenfor et raid — faller vi tilbake til `heroic`, som er nettsidas standard, og wizarden sier fra at graden ble gjettet.

**Manglende sims** er ikke en feil, det er regelen: ingen oppføring betyr ikke kandidat på Upgrade. Men mangler en spiller `sims` helt, er det som regel den kjente datafeilen — ukoblet karakter eller feilstavet navn. Det vises som advarsel på lista («ingen sim-data»), ikke som en stille null, slik at det faller inn under regelen om åpenbare feil i grunnlaget.

**Ferskhet:** wizarden viser alderen på `exportedAt` og markerer den rødt over 12 timer. Et raid varer 2,5 time, så en eksport fra samme dag er alltid grei; er den eldre, har companion-appen sannsynligvis ikke kjørt.

Disse tre varslene er det som gjør den nye regelen om officer-kontroll gjennomførbar: skal officers bekrefte at grunnlaget stemmer før tildeling, må grunnlaget kunne ses.

## Testing

`lib/item-sim.test.ts` med `node --test`: vanlig upgrade, taket på 20, same-slot-nedskalering, tier-brikke, 0 % ikke-tier utelatt, 0 % tier tatt med, manglende sim-tre.

`companion/test/watcher.test.js` får en rundturstest på at et nøstet kart med tallignende strengnøkler overlever skriv → les. Det er fella fra strengnøkkel-avsnittet, og den fortjener en test framfor en kommentar.

Addonet har ingen testkjører, så `/nordlc test`-fixturen i `Core.lua` utvides med et `sims`-blokk. Uten det tester offline-kjøringen fortsatt den gamle kodestien.

Pariteten kan ikke bevises av enhetstester alene — den hviler på at `route.ts` og eksporten kaller samme funksjon. Det er derfor uttrekket er hele poenget, ikke en opprydding på si.

## Regelteksten

Skrevet inn i `nordavind-web/docs/sesong2-regler-discord.md` samtidig med dette designet:

- **0 %-regelen:** gir itemet deg 0 % i sim, er du ikke kandidat på Upgrade. Offspec og Tmog er fortsatt åpne. Tier-brikker er unntatt.
- **Officer-kontroll:** itemet går til den øverste, men officers bekrefter først at grunnlaget stemmer — riktig kategori, riktig oppmøte, riktig karakter koblet. Kontrollen gjelder tallene som går inn, ikke hvem som burde vinne. Avslutningslinja er justert fra «valget tas ikke av et menneske» til at rekkefølgen bestemmes av tallene mens menneskene kontrollerer at tallene er riktige.

## Forutsetninger og avgrensninger

**`lib/tier-sims.ts` inneholder fortsatt sesong 1-data.** Tier-avgjørelsen — at nettsida regner og addonet viser — forutsetter at den oppdateres til sesong 2. Uten det flytter vi feil tall fra ett verktøy til to. Dette står allerede på lista over ting som må gjøres før 18. august og løses ikke her.

**Loot-vektene røres ikke.** Forslaget om Performance 25 / Sims 8 ligger til avstemming hos officers. Dette designet flytter sim-tallet dit det mangler; hvilken vekt det får, avgjøres uavhengig. Endres vekten senere, endres den i `lib/item-sim.ts` og forplanter seg til begge sider av seg selv — noe som er et argument for uttrekket i seg selv.

**Ingen frysing av sims.** Vurdert og valgt bort til fordel for ferskhetsadvarsel. Vil man senere hindre at noen re-simmer seg oppover midt i et raid, er det en egen endring.
