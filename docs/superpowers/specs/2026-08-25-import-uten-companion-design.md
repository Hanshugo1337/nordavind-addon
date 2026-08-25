# Poeng inn og utdelinger ut, uten companion-appen

**Dato:** 2026-08-25
**Status:** Design, ikke implementert
**Spenner over:** `nordavind-addon` (NordavindLC), `nordavind-web`

## Problemet

Broen mellom addonet og nordavind.cc er i dag én desktop-app som kun står på GM-ens
maskin. Alt annet fungerer uten den — men to ting gjør ikke det:

1. **Poengene inn.** Uten `NordavindLC_Import` gir `Scoring.Calculate` 0 til alle, og
   `rankOrder[a.rank] or 99` setter samtlige i samme bøtte (`Council.lua:396`). Da
   avgjør den seedede terningen rekkefølgen. Lista ser like autoritativ ut som ellers.
2. **Utdelingene ut.** De blir liggende i `NordavindLC_DB.pendingExport` og når aldri
   nettsida. Kveldens loot teller da ikke mot `lootThisWeek`, og alle som fikk noe
   står som om de ikke fikk noe neste uke.

Dette er ikke teoretisk. Raidkvelden **24.08.2026** ledet en annen officer uten
companion. Rangeringa var blind hele kvelden, og utdelingene ligger fortsatt kun i
en Lua-fil på hennes maskin.

Forsøket på å løse det ved å sende henne appen feilet også: hun fikk ferdig
nedlastingslenke og punktvise instruksjoner, og installerte den ikke. Terskelen var
aldri API-nøkkelen — det var «installer en usignert 84 MB exe på gaming-PC-en din,
tjue minutter før pull».

## Målet

Hvem som helst av officerene skal kunne lede en kveld med ferske poeng og få
utdelingene registrert, **uten å installere noe og uten å få tilsendt en hemmelighet**.

Ikke-mål:

- **Pensjonere companion.** Den blir stående hos GM og gjør jobben automatisk der.
  Den skal bare ikke lenger være noe *andre* trenger.
- **Roster-import.** Den går fortsatt gjennom companion (`/nordroster` → watcher →
  `/api/roster/import`). Røres ikke.
- **Per-bruker-tokens eller Discord-innlogging inne i en app.** Unødvendig når
  nettsida allerede autentiserer med Discord.

## Hvorfor lim-inn, og ikke fil-opplasting

Vurdert og forkastet: la officeren dra `NordavindLC.lua` inn på nettsida. Parseren
finnes allerede (`companion/lib/lua-parser.js`, null avhengigheter, ren JS), så det
hadde vært mindre å bygge.

Forkastet fordi **fila er det vanskelige**. Den ligger i
`WTF\Account\<konto>\SavedVariables\` under installasjonsmappa — det måtte skrives et
PowerShell-skript bare for å finne den på GM-ens egen maskin. Og den er først
oppdatert etter full utlogging, så den kan ikke brukes midt i et raid.

En kopier-knapp krever ingen filbehandling og virker mens man står i instansen.

Fila beholdes som **feilsøkingsvei** når noe faktisk knekker, ikke som normalvei.

## Dataflyt

```
Normalveien (ingen gjør noe):
  Companion hos GM ──> NordavindLC_Import ──> GM-ens addon
                                                 └─ SCORE_SYNC over addon-comms
                                                      └─ alle officers i raidet

Kaldstart (ingen med data til stede):
  nordavind.cc/loot/addon ──[Kopier]──> utklippstavle
       └─ /nordlc import ──[Ctrl+V]──> NordavindLC_Import

Returveien (etter raidet):
  /nordlc export ──[Ctrl+C]──> nordavind.cc/loot/addon ──> /api/loot/addon
```

## Strengformatet

Én streng, begge veier, samme innpakning:

```
NLC1:<base64 av LibDeflate-komprimert AceSerializer-blob>
```

- **`NLC1`** er versjonsprefikset. Ukjent prefiks avvises med en setning som sier hva
  som er galt, ikke en Lua-feil.
- **LibDeflate og AceSerializer ligger allerede i addonet** (`NordavindLC.toc`), og
  har `EncodeForPrint`/`DecodeForPrint` som gir utklippstavle-trygge tegn.
- Nettsida trenger tilsvarende koding i JS. LibDeflate er deflate — `pako` eller
  `DecompressionStream("deflate")` i nettleseren dekker det; AceSerializer-formatet
  må skrives i JS (det er et enkelt, dokumentert tekstformat).

**Målt størrelse:** `NordavindLC_Import` i prod er **11 637 byte for 34 spillere**
(wishlistene tomme). Komprimert ligger det på 2–3 KB. En returstreng med en kvelds
utdelinger er under 1 KB. Begge deler limes uten problemer inn i en flerlinjes
`EditBox` — samme størrelsesorden som en WeakAura.

## Nettsida

Én ny side, `/loot/addon`, bak Discord-innlogging og officer-gate (`isLeader` finnes
allerede i `lib/auth.ts`). To halvdeler på samme side:

**Ut til addonet.** En Kopier-knapp. Innholdet bygges av nøyaktig samme kode som
`/api/loot/addon-export` bruker i dag — den logikken trekkes ut i en delt funksjon
slik at companion og lim-inn-veien aldri kan komme i utakt. Under knappen: når
pakka ble laget, og hvor mange spillere den dekker.

**Inn fra addonet.** Et tekstfelt. Innlimt streng dekodes, valideres og spilles
gjennom **den eksisterende** mottakslogikken i `/api/loot/addon` — den slår allerede
opp Discord-ID fra karakternavn og håndterer `category` og `note`. Den logikken
trekkes ut av route-handleren så begge veier (API-nøkkel og innlogget officer) deler
den.

Kvitteringen skal si hva som faktisk skjedde: «12 utdelinger lagret, 2 hoppet over
(fantes fra før), 1 ukjent spiller: *Sylesa*». Ikke «OK».

## Addonet

`/nordlc import` og `/nordlc export` åpner hver sin lille ramme med en flerlinjes
`EditBox`:

- **Import:** tom boks, Ctrl+V, `SetScript("OnTextChanged")` avkoder straks og
  skriver «34 spillere lastet, laget 14:32». Skriver til `NordavindLC_Import` og
  `NLC.db.importData` i samme slengen, så det virker uten `/reload`.
- **Eksport:** boksen fylles med strengen og `HighlightText()` kalles, så Ctrl+C
  holder. Innholdet er `NLC.db.pendingExport` — det samme companion laster opp.
  Etter bekreftet innliming på nettsida tømmes den (knapp: «Marker som sendt»).

Begge er **avlesning og innliming, ingen nettverk**. Addonet får aldri vite om
nordavind.cc finnes.

## Spredning over comms (lag 2)

Når en officer har ferske data, kringkastes de til de andre officerene:

- Ny meldingstype `SCORE_SYNC` i `Comms.lua`, komprimert som strengformatet over.
- Sendes ved `GROUP_ROSTER_UPDATE` fra en aktiv officer — samme sted `ACTIVATE`
  allerede sendes fra (`Core.lua:120`), som beviselig når hele raidet.
- Mottaker tar imot **kun hvis `generatedAt` er nyere** enn det den har. Da kan to
  officers med ulik ferskhet ikke overskrive hverandre feil vei.
- Rate-limit: maks én sending per officer per fem minutter, ellers får et roster som
  endrer seg mye (folk som logger inn) kringkastinga til å spamme.

Med dette limer normalt **ingen** inn noe. Lim-inn er kaldstarten.

## Advarslene (uten disse er resten halvferdig)

Det farligste 24.08 var ikke at data manglet — det var at ingenting sa fra.

1. **Rødt banner i rangeringsvinduet** når `importData` mangler eller er eldre enn
   sju dager: «Ingen poengdata — lista under er IKKE rangert».
2. **Sorteringa slås av** i samme tilfelle. Navnene vises alfabetisk innenfor
   kategori, så vinduet ikke later som om det rangerer.
3. **Poengkolonnen viser `?`, ikke `0`.** Null ser ut som en vurdering.
4. **Teller for usendte utdelinger** i panelet og i `/nordlc status`:
   «7 utdelinger ikke sendt til nettsida».
5. **Tre linjers statussjekk ved aktivering:**
   `Aktiv ✓ · Officer ✓ · Poeng: 34 spillere, 2 t gamle ✓` — og ved rødt, én setning
   om nøyaktig hva man gjør.

## Feilhåndtering

| Situasjon | Oppførsel |
|---|---|
| Ukjent versjonsprefiks | «Denne strengen er fra en nyere versjon av addonet.» Ingen Lua-feil. |
| Avkorta innliming (WoW kutter lange strenger) | Sjekksum i formatet → «Strengen ser avkorta ut, kopier på nytt». |
| Innlimt eksportstreng i importfeltet (og motsatt) | Kjennes igjen på innholdet, sier hva som skjedde. |
| Data eldre enn 7 døgn | Lastes, men banneret står gult: «Poengene er fra 18.08». |
| Ukjent karakternavn i retur | Raden hoppes over og navngis i kvitteringa. Resten lagres. |
| Dobbeltinnliming av samme kveld | Idempotent på `(item, awardedTo, timestamp)` — teller som «hoppet over». |

## Testing

- **Rundturstest** i en ny harness: encode → decode → samme tabell ut. Både for
  poengpakka og utdelingspakka.
- **Ekte data:** `NordavindLC_Import` fra prod (11 637 byte) gjennom rundturen, med
  påstand om at ingen felter faller bort.
- **Nettsida:** enhetstest på delt mottakslogikk — samme innhold via API-nøkkel og
  via innlogget officer skal gi identiske rader.
- **Manuelt, før release:** GM limer inn på en andre konto uten companion og
  bekrefter at rangeringa er identisk med nettsidas.

## Rekkefølge

1. Strengformat + rundturstest (ingen UI)
2. `/nordlc import` + nettsidas Kopier-knapp — **dette alene løser kaldstarten**
3. Advarslene
4. `/nordlc export` + mottak på nettsida
5. `SCORE_SYNC` over comms

Punkt 1–2 er det som betyr noe. Resten kan komme etterpå uten å rive noe.

## Åpne spørsmål

- Skal `/nordlc export` også ta med **manuelle** handler addonet ikke kjenner? Loot
  som deles ut ved å dra det rett inn i et handelsvindu finnes ikke i
  `pendingExport` i det hele tatt — addonet ser det aldri. En mulig vei er at
  `TradeFrame.lua` oppdager en fullført handel av et raid-item uten tilhørende
  utdeling og spør «hvem fikk dette?». Foreløpig utenfor omfanget her.
- AceSerializer i JS: skrive selv (lite format) eller sende JSON-i-deflate i stedet
  og la addonet slippe AceSerializer på inn-veien? Avgjøres når formatet skrives.
