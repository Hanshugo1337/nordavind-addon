# Leveranse B — Live-oppdaterende + redesignet fordelingsflyt — Design

**Dato:** 2026-07-07
**Addon:** NordavindLC
**Avhenger av:** Leveranse A (distribuert deteksjon) — bygges etter A.
**Gjelder:** `UI/CouncilFrame.lua`, `UI/RankingFrame.lua`, `UI/TradeFrame.lua`, `UI/Theme.lua`, `Council.lua`

---

## ⚠️ Originalitetskrav (MÅ følges)

Fordelingsvinduene skal **ikke** ligne på RCLootCouncil sine. Vi henter **ingen** frames,
templates, layout eller tekststrenger fra RC — kun generelle WoW-API-teknikker
(f.eks. item-ikon via `C_Item.GetItemIconByID`, trade-timer via tooltip-scan).

**Vi beholder NordavindLC sin visuelle identitet:**
- Vår `Theme.lua` (gull/mørkt uttrykk, `ApplyBackdrop`, `CreateTitleBar`, `CreateButton`).
- Dra-bare frames, vår kolonnestruktur, våre klassefarger og rank-badges.
- Norsk brukertekst.

Redesignet er en *opprydding og forsterkning av vårt eget uttrykk* — ikke en etterligning.

---

## Mål

Løfte hele loot-fordelingsflyten på to akser:

1. **Live-oppdatering** — vinduene skal oppdatere seg selv fortløpende i stedet for å vise
   ett øyeblikksbilde som blir utdatert.
2. **Visuell/UX-opprydding (balansert nivå)** — ikoner, badges, timere og ryddigere layout,
   men behold grunnstrukturen i hvert vindu (ikke full ombygging fra bunnen).

## Omfang (besluttet: «Balansert»)

Live-oppdatering overalt + solid visuell opprydding, men grunnstrukturen i hvert vindu
beholdes. Kontrollert risiko på en live CurseForge-addon.

## Funksjonell spesifikasjon — per vindu

### 1. Loot Detected-panel (offiser) — `UI/CouncilFrame.lua`

- **Live:** oppdateres i sanntid ettersom `LOOT_REPORT` trikler inn (fra Leveranse A),
  i stedet for ett engangs-øyeblikksbilde. `refreshLootPanel` kalles på nytt for hver
  batch uten flimmer.
- **Redesign:** hver rad viser item-ikon, looter-navn, ilvl, og tier-badge der relevant.
  Ryddigere justering; behold eksisterende «fjern rad»-knapp og «Start Council»-knapp.

### 2. Interesse-popup (alle raiders) — `UI/CouncilFrame.lua`

- **Live:** raider har allerede live nedtelling. Offiseren får en live per-item
  responsteller (hvor mange har svart på hvert item) i stedet for kun samlet chat-melding.
- **Redesign:** item-ikoner foran hver rad, tydeligere kategoriknapper, equipped-sammenligning
  vises inline (ilvl-diff finnes allerede — gjør den tydeligere).

### 3. Award-wizard (offiser) — `UI/RankingFrame.lua` — HOVEDVINDUET

- **Live:** i dag bygges `session.ranked` kun én gang i `Council.CloseCollecting`. Endres
  til at rangeringen **rebygges og re-renderes live** når `INTEREST` kommer inn under
  innsamling — kandidater dukker opp/oppdateres fortløpende. `NLC.Council.OnInterestReceived`
  trigger en debounced `BuildRanking` + `ShowRanking`-refresh mens wizarden er åpen.
- **Redesign:** item-ikon i tittel, penere kolonnelayout (RANK/NAME/SCORE/ILVL/TIER/INFO
  finnes — juster spacing/ikoner), tydeligere kategori-grupper og award-flyt. Behold
  bekreftelsesdialogen (`NORDLC_CONFIRM_AWARD`) og navigasjonspilene.
- **Høyreklikk-kontekstmeny på kandidat** (generisk WoW-mønster, egen implementasjon —
  *ingen* kopi av RC sin meny). Handlinger:
  - **Legg til i roll** — legg kandidat(er) til en roll-off. Når ≥2 er lagt til: «Start roll»
    kjører `RandomRoll(1,100)` for hver, fanger `CHAT_MSG_SYSTEM`-rollene, og viser resultatet
    inline i wizarden (høyeste vinner markeres). For å avgjøre likestilte kandidater.
  - **Bytt kategori** — endre kandidatens respons (upgrade/catalyst/offspec/tmog) direkte;
    trigger `BuildRanking`-refresh.
  - **Omfordel / bytt award** — endre vinneren etter at itemet er tildelt, uten å gå via
    Trade/History. Oppdaterer `pendingTrades` + historikk + eksport-edit (`pendingEdits`).
  - **Hvisk / fjern / kopier** — hvisk spilleren, fjern kandidaten fra dette itemets liste,
    kopier navn/item-link.
- **Award-mål: Disenchant / Bank / Free** — i tillegg til å tildele en spiller kan offiseren
  sende itemet til en utpekt *enchanter* (disenchant), *guild bank*, eller «Free» (gratis).
  - Velges via en liten knapp/meny nederst i wizarden (ved siden av «Award Later»).
  - Logges i `lootHistory`, og legges i `pendingTrades` (så itemet kan trades til enchanter/
    banker). **Teller ikke som loot** for scoring/ukesteller (samme håndtering som `tmog`).
  - **Web-kontrakt:** disenchant/bank/free legges **ikke** i `pendingExport` (ingen spiller
    skal «belastes» loot på hjemmesiden). Kun ekte spiller-awards eksporteres, som før.

### 4. Trade-vindu (offiser) — `UI/TradeFrame.lua`

- **Live:** oppdaterer allerede på trade-complete. Legg til **2t trade-timer-nedtelling**
  per item (kobler på Leveranse A sin tradeable-sporing) med periodisk refresh.
- **Redesign:** item-ikoner, avstands-indikator (bruker `CheckInteractDistance` som finnes),
  og sortering på gjenstående trade-tid (mest haster øverst).

### 5. Felles — `UI/Theme.lua`

- Legg til gjenbrukbare hjelpere i *vår* stil: item-ikon-widget (`C_Item.GetItemIconByID`),
  liten nedtellings-badge, og en enkel «live refresh»-hjelper (debounce) som alle fire
  vinduene deler. Ingen RC-templates.

## Endringer per fil

- **`UI/Theme.lua`** — nye delte widgets (ikon, timer-badge, refresh-debounce).
- **`UI/CouncilFrame.lua`** — live re-render av Loot Detected + interesse-popup; ikoner/badges.
- **`UI/RankingFrame.lua`** — live rebuild/re-render av rangering; visuell opprydding;
  høyreklikk-kontekstmeny (roll / bytt kategori / omfordel / hvisk-fjern-kopier); knapp/meny
  for Disenchant/Bank/Free award-mål.
- **`UI/TradeFrame.lua`** — trade-timer-nedtelling + ikoner + sortering.
- **`Council.lua`** — `OnInterestReceived`/`CloseCollecting` trigger debounced live-refresh
  av wizarden mens den er åpen; roll-off-logikk (`RandomRoll` + `CHAT_MSG_SYSTEM`-fangst);
  `Award`/`RecordAward` utvides med disenchant/bank/free-mål (ekskludert fra ukesteller og
  `pendingExport`); kategori-bytte og omfordeling.
- **`Comms.lua`** — evt. ny meldingstype for å kringkaste roll-resultat/omfordeling til raidernes
  read-only wizard (avklares i planen).

## Integrasjon med hjemmeside / loot council-score

Award-eksporten er sømmen mot hjemmesiden og **må holdes uendret**: `NLC.RecordAward` →
`pendingExport`/`pendingEdits` → companion → `POST/PATCH /api/loot/addon`. Live-oppdateringen
og redesignet endrer kun *visning og tidspunkt for re-render* — ikke award-datastrukturen eller
web-kontrakten. Rangeringen bruker fortsatt samme importerte `baseScore`/wishlist fra hjemmesiden
via `Scoring.Calculate`. Så loot council-scoren og web-synkingen fungerer nøyaktig som før.

## Ikke inkludert (YAGNI)

- Ingen full ombygging fra bunnen av noen vindu (det er «Full overhaling», valgt bort).
- Ingen endring i award-eksport-formatet eller web-kontrakten.
- Ingen endring i scoring-logikken (`Scoring.lua`) — kun visning.
- Ingen nye slash-kommandoer eller SavedVariables.
- Detaljert pixel-design låses ikke i spec — prinsipper her, finjustering under
  implementasjon (lettere å iterere live in-game).

## Åpne spørsmål (avklares i planen)

1. **Live-rebuild-frekvens:** debounce-lengde for wizard-refresh (unngå flimmer / for hyppig
   `BuildRanking`). Utgangspunkt ~1s.
2. **Ikon-caching:** unngå å hente ikoner på nytt for hver refresh.
3. **Trade-timer-kilde:** eksakt gjenstående-tid per item må hentes/estimeres (tooltip gir
   ofte kun «N timer», ikke sekunder) — presisjon avklares under implementasjon.
4. **Roll-off-fangst:** parsing av `CHAT_MSG_SYSTEM` for `RandomRoll`-resultat (lokalisering/
   format), og hvordan roll vises sammen med score-kolonnen.
5. **Enchanter/banker-mål:** hvordan velge/utpeke enchanter (fast navn i config vs. velg i UI).
6. **Kringkasting av roll/omfordeling** til raidernes read-only wizard — egen meldingstype?

## Testing / verifisering

- Loot Detected fylles live mens rapporter kommer inn (test med flere raidere).
- Wizard viser nye kandidater fortløpende mens folk svarer, uten å måtte lukkes/åpnes.
- Trade-vindu viser nedtellende timer og sorterer korrekt.
- Visuell sjekk: alle fire vinduer bruker felles `Theme`-uttrykk, ingen RC-likhet.
- Regresjonstest: `/nordlc test`, `/nordlc testpopup`, `/nordlc testloot` fungerer fortsatt.
