# Council-logg og lootberegning — design

Dato: 2026-09-15. Berører fire repoer: `nordavind-addon` (Lua + companion),
`nordavind-web`, `nordavind-bot` (kun migrasjon).

## Bakgrunn

Revisjonen 14.–15.09 viste at det ikke går an å etterprøve lootfordelingen:
addonet vet hvem som trykket hva og hvordan lista så ut, men alt forsvinner når
councilet lukkes. Med WowAudit-sims lastet opp før hver utdeling gikk 3 av 11
upgrades 14.09 til den som sto øverst blant spillere med sim-gevinst — men om de
over trykket, er ukjent.

Samtidig ble tre ting funnet i beregningen:

- Normal-items (24.–26.08) teller like mye som Heroic i loot-trekket, selv om de
  er byttet ut. 35 av 119 upgrades i sesongen er Normal.
- Addonet ignorerer sims på alle tier-tokens og alt i tier-slot, fordi
  `tierGain = 0` er sant i Lua. Alle 23 raidere har nå 4+ brikker, så
  `tierGain` er 0 for alle.
- Addonet regner vanlige items i tier-slot som tier, regner ikke Curio som tier,
  og filtrerer ikke rolle-items. Nettsida gjør alle tre riktig.

## Del A — Council-logg

### Hva lagres

Et øyeblikksbilde per **utdeling til en spiller**, tatt i det offiseren trykker
tildel. Disenchant, guildbank, fri og hoppet over lagres ikke.

```json
{
  "v": 1,
  "svarte": 20,
  "addonBrukere": 22,
  "liste": [
    { "plass": 1, "navn": "Thunderbrave", "valg": "upgrade", "score": 52.9, "rank": "raider" },
    { "plass": 2, "navn": "Flygeknurr",   "valg": "upgrade", "score": 48.0, "rank": "raider", "notat": "BiS" },
    { "plass": 3, "navn": "Mohp",         "valg": "tmog",    "roll": 71,    "rank": "raider" }
  ],
  "utelatt":   [{ "navn": "Braxina", "valg": "upgrade", "grunn": "feil rustningstype" }],
  "passet":    ["Leonidazar"],
  "ikkeSvart": ["Tinux"]
}
```

- `liste` er `session.ranked` i den rekkefølgen offiseren så den, etter
  eventuelle kategoribytter og fjernede kandidater. `score` avrundes til én
  desimal. Tmog har `roll` i stedet for `score`. `rank` er `displayRank` når den
  finnes (ekte rang, ikke sorteringsverdien `bench`).
- `utelatt` er de som sendte interesse, men ble filtrert bort av `BuildRanking`,
  med grunn: `feil rustningstype`, `mangler sims`, `rolle-item`.
- `passet` er de som svarte på councilet uten interesse for dette itemet.
- `ikkeSvart` er addon-brukere fra roll call som aldri svarte.

### Addon (`NordavindLC/Council.lua`, `Core.lua`)

1. `CloseCollecting` fryser to lister på hver session:
   `session.responders` (kopi av `respondents`) og `session.addonUsers` (kopi av
   `_rollCallAcks`). I dag nullstilles begge ved neste `StartMultiSession`, så et
   item som tildeles senere ville mistet pass og ikke-svar.
2. `BuildRanking` skriver `session.excluded[name] = grunn` for hver kandidat den
   hopper over.
3. Ny ren funksjon `NLC.Council.BuildCouncilSnapshot(session)` bygger bildet fra
   `ranked`, `interests`, `excluded`, `responders` og `addonUsers`.
4. `DoAward` tar bildet og gir det til `NLC.RecordAward`. Bildet legges **kun på
   eksportkø-oppføringen**, ikke på historikkraden. I dag er det samme tabell i
   begge lister; eksportkøen får en kopi med `council`, så SavedVariables ikke
   lagrer bildet to ganger. `ApplyAwardEdit` matcher fortsatt på
   `timestamp` + `item` og fungerer uendret.
5. `AwardSpecial` tar ikke bilde.

### Companion (`companion/lib/api-client.js`)

`awardLoot` sender `council` med i POST-kroppen.

### Database (`nordavind-bot`)

Migrasjon `20260915000000_loot_drop_council`:

```sql
ALTER TABLE "loot_drops" ADD COLUMN "council" JSONB;
```

`LootDrop.council Json? @map("council")` i bot-skjemaet. Nettsida får samme felt
i sitt skjema **uten** egen migrasjon (boten eier migrasjonene).

### Nettside

- `lib/council.ts`: `parseCouncil(raw: unknown): CouncilSnapshot | null`.
  Godtar kun `v === 1`, riktige typer på alle felt, og maks 32 KB som JSON.
  Alt annet gir `null`.
- `POST /api/loot/addon`: lagrer `parseCouncil(body.council)`. Et ugyldig eller
  manglende bilde avviser **aldri** utdelingen — den lagres uten bilde, og
  avvisningen logges.
- `GET /api/loot/history`: tar med `council` **kun** når
  `session.user.isLeader`. Andre får ikke feltet i svaret.
- `app/loot/loot-client.tsx`: for officers får hver rad med bilde en
  «Council»-knapp som folder ut lista under raden. Mottakeren utheves. Står
  mottakeren ikke på plass 1, vises «Gitt til plass N». Står mottakeren ikke på
  lista, vises «Mottaker var ikke på lista». Deretter utelatt, passet og ikke
  svart.

## Del B — Normal-items teller ikke i loot-trekket

Regel: en utdeling teller i `lootThisWeek`, `lootTotal` og «færrest items» kun
når kategorien er `upgrade`/`catalyst` **og** itemet ikke er fra Normal.
Regelteksten endres ikke.

- `lib/loot-difficulty.ts` på nettsida: `itemDifficulty(item: string)` →
  `"normal" | "heroic" | "mythic" | null`. Leser context-feltet i `Hitem:`-strengen
  (felt 12 etter splitt på `:`, der felt 0 er `Hitem`): 3 = Normal, 5 = Heroic,
  6 = Mythic. Faller tilbake på bonus-ID 13333/13334/13335. Ukjent eller
  item uten lenke gir `null`, og teller som i dag.
- Filteret brukes begge steder loot telles til poeng: `fetchLootCounts` i
  `lib/scoring.ts` og kandidatberegningen i `app/api/loot/route.ts`.
- Addonet: ukestelleren i `DoAward` og `ApplyAwardEdit` hopper over Normal-items
  (`NLC.Utils.ItemDifficulty(link)`, samme regel). Importen fra nettsida bærer
  allerede de filtrerte tallene.
- Etter deploy kjøres full score-beregning, så `player_scores` og eksporten
  oppdateres med én gang.

## Del C — Addonets poengberegning lik nettsida

1. **Tier-gevinst 0 skal falle til sim.** `NLC.Scoring.Calculate` bruker tier-
   greina kun når `imported.tierGain` er et tall **større enn 0**. Ellers gis
   sim-poeng, som nettsidas `isTierPiece && tierGain ? tierGain : sim`.
2. **Hva er tier.** `BuildRanking` setter `isTier` kun for ekte tokens
   (`session.armorType`) og omni-tokens — itemnavn som inneholder «Curio»,
   «Nullcore» eller «Riftbloom», samme liste som nettsida. Tier-slot alene gjør
   ikke et item til tier.
3. **Rolle-items.** `addon-export` sender `itemRoller`: itemnavn i små bokstaver
   → `"tank"` eller `"healer"`, bygget fra `role` i `lib/loot-tables.ts`.
   Companion og addonet bærer hele importen videre uendret. I `BuildRanking`
   havner en kandidat hvis `imported.role` ikke er itemets rolle i `utelatt` med
   grunn `rolle-item`. Mangler `imported.role`, beholdes kandidaten.

## Testing

- **Addon (lupa-harnesser):**
  - `council_snapshot_harness.lua`: council med interesser, pass, ikke-svar og en
    utelatt kandidat → tildel → riktig bilde i eksportkøen, ikke på historikkraden.
    Et item tildelt senere beholder pass og ikke-svar etter at neste
    `StartMultiSession` har nullstilt de globale listene.
  - `ranking_harness.lua` utvides: `tierGain = 0` gir sim-poeng; tier-slot-item
    uten token bruker sim; Curio bruker tier-gevinst når den er > 0;
    rolle-item utelater feil rolle.
  - Ukesteller hopper over Normal-lenke.
- **Companion:** `api-client.test.js` bekrefter at `council` sendes.
- **Nettside (`node --test`):** `parseCouncil` (gyldig, feil versjon, feil type,
  for stort, mangler), `itemDifficulty` (context 3/5/6, bonus-fallback, uten
  lenke), og at loot-tellingen utelater Normal.
- **Database:** migrasjonen verifiseres i prod (`\d loot_drops`) før nettsida
  deployes.

## Utrulling

1. **Bot** med migrasjonen. Verifiser kolonnen.
2. **Nettside** (del A web, del B, `itemRoller`). Kjør full score-beregning og
   sjekk at Normal-trekket er borte for Mohp og Sniken.
3. **Companion** bygges og installeres.
4. **Addon** installeres lokalt og testes i raidet. Tagges ikke før et ekte raid
   har vist at bildene kommer fram og at rangeringen stemmer
   (`feedback_release_disiplin`).

Rekkefølgen er bare streng mellom 1 og 2: leser nettsida en kolonne som ikke
finnes, feiler alle spørringer mot `loot_drops`. Gamle addon- og
companion-versjoner sender ikke `council`, og da blir feltet tomt.

## Utenfor denne runden

- Etterregistrering av 19.08 fra DawnTools-handelsloggen.
- Frostscale's Mystic Frond 31.08 → Mohp, og de fire uregistrerte handlene.
- «Omfordel award» som mister endringen, og trade-oppryddingen.
- M+-innsamlingen.
- Om Heroic-items skal behandles som Normal når Mythic tar over.
