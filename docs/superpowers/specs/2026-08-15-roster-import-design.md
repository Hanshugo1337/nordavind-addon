# Roster-import: fra guild-roster til Discord-roller

**Dato:** 2026-08-15
**Status:** Design, ikke implementert
**Spenner over:** `nordavind-addon` (NordavindLC + companion), `nordavind-web`, `nordavind-bot`

## Problemet

Discord ble lagt om 2026-08-15: `Social` betyr nå «medlem av Nordavind in-game», og
alle andre er `Gjest`. Omleggingen avdekket at vi ikke har noen kilde til hvem som
faktisk er i guilden.

- Guilden nærmer seg **400 karakterer**; Discord har 152 medlemmer
- WowAudit dekker kun de **29** i raid-laget, ikke hele guilden
- Blizzards API gir ikke ut guild-noter — de finnes bare in-game
- Kun **16 %** av gjestene har charnavn i Discord-navnet sitt

Resultatet er at officers må vurdere folk for hånd, og at 40 personer fortsatt står
uavklart. Det skalerer ikke mot 400 karakterer.

## Målet

En officer trykker én knapp in-game. Ut kommer et **forslag** til rolleendringer i
Discord som en officer godkjenner.

Ikke-mål:
- Automatisk tildeling uten godkjenning (bevisst valgt bort, se «Godkjenning»)
- Å erstatte WowAudit for raid-rosteret
- Å importere officer notes (krever rettighet, ingen bruk foreløpig)

## Dataflyt

```
NordavindLC (in-game)
  └─ leser guild-roster → SavedVariables/NordavindLC.lua
       └─ Companion (Electron, watcher.js)
            └─ POST /api/roster/import → nordavind.cc
                 └─ bot internt API (:3100) → forslag
                      └─ officer godkjenner → roller settes
```

Hvert ledd finnes allerede for loot-data. Dette gjenbruker rørgata, ikke en ny.

## Leveranse A — addonet leser rosteret

Ny fil `NordavindLC/Roster.lua`. Addonet rører ikke guild-rosteret i dag (null treff
på `GetGuildRosterInfo`), så dette er helt nytt.

```lua
local name, rankName, rankIndex, level, class, zone, publicNote, officerNote
      = GetGuildRosterInfo(i)
```

Per karakter lagres: `name`, `rankIndex`, `rankName`, `level`, `class`,
`publicNote`, `daysOffline` (fra `GetGuildRosterLastOnline(i)`).

### Tre feller som må håndteres

**1. Offline-medlemmer er skjult som standard.** Uten
`C_GuildInfo.SetGuildRosterShowOffline(true)` returnerer `GetNumGuildMembers()` bare
de som er pålogget — altså ~10 i stedet for ~400. Dette er den feilen som ser ut som
om alt virker.

**2. Rosteret er throttlet.** `C_GuildInfo.GuildRoster()` er en *forespørsel*. Leser
man rett etterpå, får man forrige svar eller ingenting. Man må vente på
`GUILD_ROSTER_UPDATE`, og kallet er throttlet til ~10 sekunder. Importen må derfor
være hendelsesdrevet, ikke sekvensiell.

**3. SavedVariables skrives ikke før `/reload` eller utlogging.** Companion-en ser
ingenting før da. Brukeren må få beskjed i UI-et — ellers ser importen ut som den
henger.

### Skriveformat

Legges i `NordavindLCDB.pendingRosterImport` med `capturedAt` (unix) og `characters`.
Companion-ens Lua-parser (`companion/lib/lua-parser.js`) leser allerede vilkårlige
tabeller, så ingen parser-endring trengs.

## Leveranse B — companion laster opp

`companion/lib/api-client.js` får `uploadRoster(payload)` etter mønsteret til
`awardLoot()`: `x-api-key`, `Host: nordavind.cc`, timeout.
`companion/lib/watcher.js` får `pendingRosterImport` som ny overvåket nøkkel, med
samme mtime-sporing og reset-deteksjon som `pendingExport` og `pendingEdits`.

Rosteret er ~400 rader — én POST, ikke en kø. Ved feil: behold i SavedVariables og
prøv igjen neste syklus. Ved 4xx: hopp over og logg, slik `sync-engine.js` allerede
gjør for permanent feilende awards.

## Leveranse C — note-parseren

Malen som er kunngjort i `#gjeste-prat`:

```
Main:  Fornavn (optional) - Discordnavn - Main     →  Rolf - Revo - Main
Alt:   Mainnavn / Fornavn (optional) - ALT         →  Revo / Rolf - ALT
```

Parseren må være tolerant — dette er fritekst skrevet av 400 mennesker:

- Trim, kollaps whitespace, godta både `-` og `–`
- `Main`/`ALT` case-insensitivt, og som *siste* felt
- Fornavn er valgfritt, så feltantallet varierer (2 eller 3)
- Ukjent format → `unparsed`, aldri kast

Utfall per karakter: `main` (med Discordnavn), `alt` (med mainnavn), `unparsed`,
eller `empty`.

### Matching mot Discord

Discordnavn matches mot medlemmenes `displayName` og `user.username`,
case-insensitivt. **Discord-navn er ikke unike** — treffer et navn to medlemmer,
merkes raden `ambiguous` og går til manuell vurdering. Aldri gjett.

## Leveranse D — rank-mapping

| rankIndex | Rang | Discord |
|---|---|---|
| 1 | Guild Master | Guild Master + Social |
| 2 | Officer | Officer + Social |
| 3 | Officer | Officer + Social |
| 4 | Officer Alt | *alt* |
| 5 | Raider | Raider + Social |
| 6 | Backup | Backup + Social |
| 7 | Trial | Trial + Social |
| 8 | Alt | *alt* |
| 9 | Sosial / M+ | Social |
| 10 | Ny | Social, flagges |

Alle ti rangene betyr «er i guilden», så hele rosteret skal ha `Social`. Rangen
avgjør kun tilleggsrollen.

**Rank 2 og 3 heter begge «Officer».** Mapping på `rankName` kollapser dem eller
treffer feil, stille og uten feilmelding. Nøkkelen er alltid `rankIndex`.

**Alt-ranger (4 og 8) er ikke egne personer.** Teller de som det, blåses medlemstallet
opp. Alts kan også ligge i andre ranger, så rank 4/8 fanger ikke alle — noten er det
eneste som knytter en alt til et menneske.

Rank-tabellen legges i **konfig, ikke kode**. Ranger endres in-game uten forvarsel,
og en hardkodet tabell blir feil uten at noen merker det.

## Leveranse E — forslag og godkjenning

Boten produserer et forslag, ikke en endring. Valgt bevisst: en feilskrevet note skal
ikke kunne kaste noen ut av Discord uten at et menneske har sett det.

Forslaget grupperes:

| Gruppe | Handling |
|---|---|
| Får `Social` (+ evt. rangrolle) | er i rosteret, note matcher en Discord-bruker |
| Får endret rangrolle | rank in-game ≠ Discord-rolle |
| Mister `Social` | har Social, men står ikke i rosteret |
| Uidentifisert | i rosteret, men noten mangler eller er `unparsed` |
| Tvetydig | Discordnavn treffer flere medlemmer |
| Kun i Discord | Discord-medlem uten karakter i rosteret |

Officer godkjenner per gruppe eller per rad. Ved godkjenning kaller web bot-ens interne
API (`:3100`), som setter rollene. `events/guildMemberUpdate.js` holder allerede
`Social` og `Gjest` i synk begge veier, så importen trenger aldri røre `Gjest`
direkte — den setter `Social`, og boten rydder resten.

## Feilhåndtering

- **Ufullstendig roster** (færre enn f.eks. 50 karakterer) → avvis importen med
  melding om `SetGuildRosterShowOffline`. Dette er den farligste feilen: et halvt
  roster ser ut som at 350 personer har forlatt guilden og foreslår massefjerning.
- **Gammel import** (`capturedAt` eldre enn 24t) → advar, ikke bruk stille
- **Ukjent `rankIndex`** → behandle som «i guilden», flagg for gjennomgang
- Ingen sti fjerner en rolle uten godkjenning

## Testing

Companion har allerede `node --test` (10 tester grønne). Nytt:
- Note-parseren mot ekte, rotete noter — inkludert manglende fornavn, feil separator,
  tom note, og `ALT` uten mainnavn
- Rank-mapping med to «Officer»-rader, som verifiserer at `rankIndex` skiller dem
- Ufullstendig roster → avvist
- Alt som peker på en main som ikke finnes i rosteret

Addon-siden testes manuelt in-game; Lua-delen har ingen testrigg i dag.

## Åpne spørsmål

1. **Hvor bor forslaget?** Nettside (rikere UI, deler innlogging med søknadssystemet)
   eller Discord-embed med knapper (der officers allerede er)? Nettside anbefales
   gitt at ~400 rader skal vises.
2. **Hvor ofte?** Manuelt av officer, eller påminnelse ukentlig?
3. Skal `daysOffline` brukes til å foreslå opprydding i guilden in-game, eller kun
   vises? Det er et bedre grunnlag enn Discord-tekstaktivitet, som ikke fanger voice.

## Referanser

- Discord-omlegging og hva `Social` betyr nå: `nordavind-bot`, commit `3735e6a`
- Rolle-synk begge veier: `nordavind-bot/events/guildMemberUpdate.js`
- Eksisterende opplastingsmønster: `companion/lib/api-client.js`, `sync-engine.js`
- Lekkasjesjekk for kanalrettigheter: `nordavind-bot/scripts/lekkasjeSjekk.js`
