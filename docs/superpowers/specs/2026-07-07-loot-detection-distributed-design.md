# Leveranse A — Distribuert loot-deteksjon — Design

**Dato:** 2026-07-07
**Addon:** NordavindLC (v1.8.0 → neste)
**Gjelder:** `LootDetection.lua`, `Comms.lua`, `Core.lua`, `Utils.lua`, `UI/CouncilFrame.lua` (Loot Detected-panel)

---

## ⚠️ Originalitetskrav (MÅ følges)

NordavindLC skal **ikke** se ut som — eller være — en kopi av RCLootCouncil. Vi låner
kun *generelle WoW-API-teknikker* (hvilke events finnes, hvordan trade-vinduet fungerer),
aldri implementasjon.

**Vi tar IKKE fra RCLootCouncil:**
- Ingen kopiering av kode, funksjoner eller filstruktur.
- Ingen kopiering av deres status-bitmaske (`GetStatus`/`ShouldRollOnLoot`-systemet).
- Ingen kopiering av variabelnavn, kommentarer eller tekststrenger.
- Ingen bruk av deres klasser/moduler (`GroupLoot.lua`, `ml_core.lua`, `TradeUI.lua`).

**Vi beholder NordavindLC sin egen identitet:**
- Vårt `NordavindLC_NS`-namespace-mønster og fil-oppsett.
- Vår `NLC.Comms` (AceComm + AceSerializer), egne meldingstyper.
- Vår `shouldTrackItem`-filtrering og `Utils`-hjelpere.
- Norsk brukertekst, vårt eget scoring/council-system.

Implementasjonen skrives fra bunnen i vår stil. RC brukes kun som referanse for *hvilke*
API-er som finnes i patch 12.0.

---

## Mål

Gjenopprette loot-fangst i Midnight (patch 12.0). I dag fanger addonen **null items**
fordi den er avhengig av at offiserens ene klient ser alle loot-events i et 8-sekunders
vindu etter `ENCOUNTER_END`. Det fungerer ikke lenger:

- `START_LOOT_ROLL` fyrer kun for items offiseren selv kan rulle på.
- `ENCOUNTER_LOOT_RECEIVED` er upålitelig i 12.0.
- Midnight endret loot-leveringstiming (loot lander etter kampen).
- Midnight forbyr addon-comms *under* boss-encounters.

## Løsning (kjerneidé)

Flytt fangsten fra offiserens ene klient til **hver raiders** klient. Hver spiller
oppdager sin egen looted, tradeable loot lokalt, og rapporterer den til offiseren
etter kampen. Offiseren aggregerer til det eksisterende «Loot Detected»-panelet.

## Fangst-modell (besluttet)

- Vi fanger **kun tradeable items som en raider faktisk looter** til egen bag.
- Sikkerhetsnett for det som faller utenfor (utradeable, spiller uten addon):
  eksisterende `/nordlc add [item]` (shift-klikk) beholdes uendret.
- `/nordlc version` viser allerede hvem i raidet som mangler addon.

Dette er den realistiske modellen for hvordan loot faktisk fungerer i 12.0.

## Funksjonell spesifikasjon

### 1. Lokal deteksjon per raider (under kampen, ingen comms)

Ny/omskrevet `LootDetection.lua`:

- Registrer `LOOT_READY` (og behold `ENCOUNTER_START`/`ENCOUNTER_END` for boss-navn/state).
- Ved `LOOT_READY`: hvis `IsInInstance()` og loot-vinduet har items, enumerer
  `GetNumLootItems()` → `GetLootSlotLink(i)` → `GetLootSlotInfo(i)`. For hvert item
  som passerer `shouldTrackItem` (epic+, equippable eller tier-token, ikke warbound),
  merk det som en kandidat knyttet til gjeldende boss.
- Når spilleren faktisk looter items i egen bag: verifiser at itemet er **tradeable**
  (har en «kan handles i N timer»-linje i tooltip — scannes via `C_TooltipInfo`, samme
  mønster som eksisterende `IsWarbound`). Kun tradeable items legges i rapport-lista.
- Alt dette skjer lokalt — **ingen `NLC.Comms.Send` under encounter** (Midnight-krav).

Boss-navn hentes fra `ENCOUNTER_START`/`ENCOUNTER_END` som i dag; ellers `GetUnitName("target")`
som fallback.

### 2. Rapportering etter kampen

- Etter `ENCOUNTER_END` (success), start en kort debounce (~2s) så loot rekker å lande
  i bags, og samle opp items som looter etter kampen også.
- Deretter sender hver raider (også ikke-offiserer) sin liste via ny meldingstype
  `NLC.Comms.Send("LOOT_REPORT", { boss = ..., items = { {itemLink, itemId, ilvl,
  equipLoc, armorType, looter = <selv>}, ... } })`.
- Payloaden gjenbruker `NLC.Comms` (AceComm auto-chunker >255 byte; AceSerializer).

### 3. Aggregering hos offiseren

- Offiseren lytter på `LOOT_REPORT` (ny gren i `NLC.Comms.OnMessage`).
- Åpne et innsamlingsvindu (~5s) fra første `LOOT_REPORT`: samle items fra alle avsendere.
- De-dupliser (item kan kun looteres én gang; dedup på itemLink+looter, evt. loot-GUID
  hvis tilgjengelig).
- Når vinduet lukkes: vis eksisterende `NLC.UI.ShowLootDetected(items)` — offiseren
  fjerner junk og trykker «Start Council» som før. **Resten av flyten er uendret.**

### 4. Datastruktur

Item-formen som sendes/vises holdes lik dagens `droppedItems`-entry, slik at
`ShowLootDetected` → `StartMultiSession` fungerer uten endring nedstrøms:

```
{ itemLink, itemId, ilvl, equipLoc, armorType, boss, looter }
```

## Endringer per fil

- **`LootDetection.lua`** — omskrives: `LOOT_READY`-basert lokal fangst + tradeable-sjekk
  + debounce + send `LOOT_REPORT`. Fjern avhengigheten av `START_LOOT_ROLL`/8s-vindu som
  primærkilde. (Auto-roll-oppførselen — `RollOnLoot` — vurderes flyttet/beholdt separat,
  se Åpne spørsmål.)
- **`Comms.lua`** — ny meldingstype `LOOT_REPORT`; offiser-aggregering med innsamlingsvindu.
- **`Utils.lua`** — ny hjelper `IsTradeable(itemLink or bag,slot)` (tooltip-scan for
  trade-timer-linjen), i stil med `IsWarbound`.
- **`Core.lua`** — `LootDetection.Register()` kalles allerede i `Activate()` for alle raidere.
  I dag er det kun *visningen* av panelet (`showIfAny`/`ShowLootDetected`) som er offiser-gatet;
  selve innsamlingen kjører lokalt hos alle. Ny modell beholder dette: alle fanger egen loot,
  alle sender `LOOT_REPORT`, og kun offiseren viser det aggregerte panelet.
- **`UI/CouncilFrame.lua`** — `ShowLootDetected`/`refreshLootPanel` må tåle å oppdateres
  flere ganger mens rapporter kommer inn (grunnlag for Leveranse B sin live-oppdatering).

## Integrasjon med hjemmeside / loot council-score

Leveranse A er **score-nøytral**. Den endrer kun *hvordan* items havner i «Loot Detected»-panelet
— ikke scoring eller award-eksport. De detekterte itemene mates inn i `StartMultiSession` i
nøyaktig samme form som før, så interesse → rangering → award → `pendingExport` → companion →
`nordavind.cc` er uendret. Web-kontrakten (`NordavindLC_Import`, `pendingExport`/`pendingEdits`,
API-endepunktene) røres ikke.

*(Valgfri fremtidig utvidelse, utenfor scope: eksporter `LOOT_REPORT`-dataene til hjemmesiden
for drop-historikk/analyse — additivt, egen leveranse.)*

## Ikke inkludert (YAGNI)

- Ingen endring i selve council/interesse/wizard-flyten (det er Leveranse B).
- Ingen ny database/SavedVariables-struktur.
- Ingen håndtering av utradeable items utover manuelt `/nordlc add`.
- Ingen endring i web-kontrakten eller scoring.

## Åpne spørsmål (avklares i planen)

1. **Auto-roll:** dagens `LootDetection` ruller også automatisk på group loot
   (`RollOnLoot`). Beholdes den som en separat, uavhengig del, eller er den ute av scope?
2. **Trade-timer-tekst:** eksakt streng/mønster for «tradeable»-linjen i 12.0 må
   verifiseres in-game (via `/nordlc debug`).
3. **Innsamlingsvindu-lengde:** 5s er utgangspunkt; justeres etter test.

## Testing / verifisering

- `/nordlc debug` utvides til å logge `LOOT_READY`-slots, tradeable-sjekk, og sendte/mottatte
  `LOOT_REPORT`-meldinger.
- Test i faktisk raid: boss dør → hver raider looter → offiserens panel fylles med items
  fra hele raidet innen få sekunder.
- Test blandet raid (noen uten addon) → forvent at deres loot mangler, men `/nordlc add`
  dekker det.
- Test at ingen comms sendes under encounter (Midnight-krav) — kun etter `ENCOUNTER_END`.
