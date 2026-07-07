# Leveranse A — Distribuert loot-deteksjon — Implementasjonsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gjenopprette loot-fangst i Midnight ved at hver raiders klient fanger egen tradeable looted loot og rapporterer den til offiseren etter kampen.

**Architecture:** Skriv om `LootDetection.lua` fra offiser-sentrert 8s-vindu til distribuert modell: hver klient finner sin egen tradeable looted loot ved å **skanne bags for items med aktiv trade-timer** etter `ENCOUNTER_END`, og sender en `LOOT_REPORT` via `NLC.Comms` **så snart addon-comms er tillatt igjen** (gated på ekte restriksjonsstatus, ikke en gjettet timer). Offiseren aggregerer og viser eksisterende «Loot Detected»-panel. Ingen kode fra RCLootCouncil; web-kontrakten røres ikke.

**Tech Stack:** Lua, WoW-API (patch 12.0), AceComm-3.0 + AceSerializer-3.0, eksisterende `NordavindLC_NS`-namespace.

## Global Constraints

- **Originalitet:** INGEN kopi av RCLootCouncil-kode, variabelnavn, bitmaske, tekst eller struktur. Kun generelle WoW-API-teknikker. (Ref. spec «Originalitetskrav».)
- **Web-kontrakt uendret:** `NordavindLC_Import`, `pendingExport`/`pendingEdits`, API-endepunkter røres ikke. Leveranse A er score-nøytral.
- **Ingen addon-comms mens restriksjon er aktiv** (Midnight): `NLC.Comms.Send` gates på faktisk restriksjonsstatus via `ADDON_RESTRICTION_STATE_CHANGED` / `C_RestrictedActions`. Vi gjetter *ikke* på encounter-timing — rapporten flushes når restriksjonen løftes.
- **Norsk brukertekst** i all `NLC.Utils.Print`-output.
- **Modulstil:** CommonLua via `NordavindLC_NS`-namespace, `require`-fri (globalt namespace-objekt).
- **Verifisering:** WoW-API kan ikke kjøres headless. Automatisk gate = Lua syntaks-sjekk (`luac -p <fil>` hvis Lua er installert; ellers hopp over og stol på in-game). Reell gate = strukturert in-game-test via `/nordlc debug`.

---

## Teknikk-grunnlag (fra RC-gjennomgang 2026-07-07 — kun som referanse, ingen kopi)

To generelle WoW-API-teknikker ble bekreftet ved å studere RCLootCouncil, og er foldet inn her:

1. **Bag-scan for trade-timer** i stedet for slot-korrelasjon. Robust fangst = skann alle bags
   etter kampen og plukk items som har en aktiv «kan handles i N»-timer. Unngår skjøre
   `LOOT_READY`/`LOOT_SLOT_CLEARED`-slot→bag-koblinger (itemID-kollisjoner, timing).
2. **Ekte restriksjonsstatus** for comms-gating. `ADDON_RESTRICTION_STATE_CHANGED` +
   `C_RestrictedActions.IsAddOnRestrictionActive` forteller *presist* når addon-comms er blokkert
   (encounter/challenge). Vi gater sending på dette og flusher når det løftes — ikke på en gjettet
   4s-timer.

Alt implementeres fra bunnen i vår stil (`NordavindLC_NS`, `NLC.Utils`, `NLC.Comms`). Ingen
RC-variabelnavn, bitmaske, struktur eller tekst.

---

## Filstruktur

| Fil | Ansvar | Endring |
|-----|--------|---------|
| `NordavindLC/Utils.lua` | Delte hjelpere | **Modify:** ny `IsTradeableBagItem(bag, slot)` |
| `NordavindLC/LootDetection.lua` | Lokal loot-fangst per klient | **Rewrite:** bag-scan for trade-timer etter kampen + restriksjonsgated `LOOT_REPORT`-send |
| `NordavindLC/Comms.lua` | Addon-kommunikasjon | **Modify:** ny `LOOT_REPORT`-meldingstype + offiser-aggregering |
| `NordavindLC/Core.lua` | Init, aktivering | **Modify:** wire aggregering; bekreft `Register()` for alle |
| `NordavindLC/UI/CouncilFrame.lua` | Loot Detected-panel | **Modify:** `ShowLootDetected` tåler gjentatte oppdateringer |

**Merk:** `luac -p` er kun syntakssjekk. Der en task sier «kjør syntakssjekk», menes:
`luac -p "NordavindLC/<fil>.lua"` (forventet: ingen output = OK). Har du ikke `luac`,
noter det og gå videre til in-game-verifisering.

---

### Task 1: `IsTradeableBagItem`-hjelper

**Files:**
- Modify: `NordavindLC/Utils.lua` (etter `IsWarbound`, ca. linje 104)

**Interfaces:**
- Produces: `NLC.Utils.IsTradeableBagItem(bag, slot) -> boolean` — true hvis item-et i bag/slot har «kan handles i N»-linjen (BoP looted innen trade-vinduet).

Denne booleanen er filteret bag-scannen i Task 2 bruker. (Leveranse B utvider senere samme
tooltip-scan til å returnere *gjenstående sekunder* for nedtellings-badgen — ikke nødvendig her.)

- [ ] **Step 1: Implementer hjelperen**

Bruk `C_TooltipInfo.GetBagItem` og sjekk mot den globale strengen `BIND_TRADE_TIME_REMAINING`
(WoW-global: «You may trade this item ... for the next %s.»). Vi matcher på den lokaliserte
prefiksen for å være språk-uavhengig. (Moderne strukturert tooltip-API — ikke legacy
`GameTooltip`+`TextLeftN`-parsing.)

```lua
-- Returnerer true hvis item-et i (bag, slot) fortsatt kan handles (BoP i trade-vindu).
function NLC.Utils.IsTradeableBagItem(bag, slot)
  if not bag or not slot then return false end
  local data = C_TooltipInfo and C_TooltipInfo.GetBagItem(bag, slot)
  if not data or not data.lines then return false end
  -- Bygg et match-mønster fra den globale strengen (fjern %s-halen).
  local marker = _G.BIND_TRADE_TIME_REMAINING or "You may trade this item"
  marker = marker:gsub("%%s.*$", ""):gsub("%s+$", "")
  for _, line in ipairs(data.lines) do
    local text = line.leftText or ""
    if text:find(marker, 1, true) then
      return true
    end
  end
  return false
end
```

- [ ] **Step 2: Syntakssjekk**

Run: `luac -p "NordavindLC/Utils.lua"`
Expected: ingen output (OK). (Hopp over hvis `luac` mangler.)

- [ ] **Step 3: Commit**

```bash
git add NordavindLC/Utils.lua
git commit -m "feat(utils): add IsTradeableBagItem for trade-window detection"
```

---

### Task 2: Skriv om LootDetection — bag-scan-fangst (ingen comms)

**Files:**
- Rewrite: `NordavindLC/LootDetection.lua`

**Interfaces:**
- Consumes: `NLC.Utils.IsTradeableBagItem`, eksisterende `shouldTrackItem` (behold intern), `NLC.active`.
- Produces:
  - `NLC.LootDetection.Register()` / `Unregister()` (uendret signatur)
  - `NLC.LootDetection.ScanBags()` — skanner bags, legger nye tradeable items i `reportItems`.
  - `NLC.LootDetection.GetReport() -> { {itemLink, itemId, ilvl, equipLoc, armorType, boss, looter}, ... }`
  - `NLC.LootDetection._setDetected(items)` / `GetDroppedItems()` / `RemoveItem(i)` / `GetCurrentBoss()` / `ToggleDebug()` (behold for panel/kompat).

Denne task-en gjør fangsten lokal via bag-scan. Sending (restriksjonsgated) skjer i Task 3.

- [ ] **Step 1: Erstatt event-registrering og state**

Behold `ENCOUNTER_START`/`ENCOUNTER_END` (boss-kontekst) og `START_LOOT_ROLL` (kun auto-roll,
se Step 4). **Fjern** `LOOT_READY`/`LOOT_SLOT_CLEARED`/`ENCOUNTER_LOOT_RECEIVED`/`CHAT_MSG_LOOT`
som fangstkilde — bag-scan erstatter dem. `BAG_UPDATE_DELAYED` registreres kun *midlertidig* i
innsamlingsvinduet etter kampen (Task 3), så vi fanger loot som lander sent uten faste timere.

```lua
function NLC.LootDetection.Register()
  if isRegistered then return end
  lootFrame:RegisterEvent("ENCOUNTER_START")
  lootFrame:RegisterEvent("ENCOUNTER_END")
  lootFrame:RegisterEvent("START_LOOT_ROLL")            -- kun auto-roll
  lootFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED") -- comms-gate (Task 3)
  isRegistered = true
end
```

State (erstatt gammel blokk):
```lua
local currentBoss = nil
local reportItems = {}      -- tradeable items DENNE klienten har looted (venter på send)
local reportedGUIDs = {}    -- session-vid dedup: itemGUID -> true (hvert fysisk item rapporteres én gang)
local detectedItems = {}    -- aggregert liste hos offiser (mates av Comms, vises i panelet)
local collecting = false    -- true mens innsamlingsvinduet etter kampen er åpent
local collectTimer = nil
local commsRestricted = false -- true når addon-comms er blokkert (encounter/challenge)
local pendingSend = false   -- true hvis en rapport venter på at restriksjon løftes
local debugMode = false
```

- [ ] **Step 2: `ScanBags` — plukk nye tradeable items fra bags**

Kjernen i fangsten. Skann alle bags; for hvert item som er tradeable (`IsTradeableBagItem`) og
passerer `shouldTrackItem`, dedup på **item-GUID** (moderne `ItemLocation`/`C_Item.GetItemGUID`)
og legg til i `reportItems`. GUID-dedup gjør at items fra tidligere bosser (som fortsatt har timer)
ikke rapporteres på nytt, og at gjentatte scans i vinduet ikke duplikerer.

```lua
function NLC.LootDetection.ScanBags()
  for bag = 0, 4 do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link and NLC.Utils.IsTradeableBagItem(bag, slot) then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local guid = C_Item.DoesItemExist(loc) and C_Item.GetItemGUID(loc)
        if guid and not reportedGUIDs[guid] then
          local itemID = C_Item.GetItemInfoInstant(link)
          local track, ilvl, equipLoc, armorType = shouldTrackItem(link, itemID)
          if track then
            reportedGUIDs[guid] = true
            table.insert(reportItems, {
              itemLink = link, itemId = itemID, ilvl = ilvl or 0,
              equipLoc = equipLoc, armorType = armorType,
              boss = currentBoss, looter = UnitName("player"),
            })
            dbg("Rapport +: " .. link)
          end
        end
      end
    end
  end
end
```

- [ ] **Step 3: Behold auto-roll i START_LOOT_ROLL (uendret oppførsel, ingen fangst her)**

Behold eksisterende auto-roll-logikk i `START_LOOT_ROLL`-grenen. Fjern all kode som la items i
`droppedItems`/rapport derfra — fangsten skjer nå kun via `ScanBags`.

```lua
elseif event == "START_LOOT_ROLL" then
  local rollID = ...
  if not rollID then return end
  local link = GetLootRollItemLink(rollID)
  local isLeader = UnitIsGroupLeader("player")
  if isLeader then
    RollOnLoot(rollID, 1)
  else
    if link then
      local _, _, _, _, _, itemType = C_Item.GetItemInfo(link)
      if itemType ~= "Miscellaneous" and itemType ~= "Companion Pets" then
        RollOnLoot(rollID, 0)
      end
    else
      RollOnLoot(rollID, 0)
    end
  end
```

- [ ] **Step 4: Panel-kompat + reset-hjelpere**

```lua
function NLC.LootDetection.GetReport() return reportItems end
function NLC.LootDetection.GetCurrentBoss() return currentBoss end

-- Offiser-panelet leser aggregert liste (settes av Comms i Task 4):
function NLC.LootDetection._setDetected(items) detectedItems = items end
function NLC.LootDetection.GetDroppedItems() return detectedItems end
function NLC.LootDetection.RemoveItem(index) table.remove(detectedItems, index) end
```

(Fjern den gamle `droppedItems`-referansen; panelet og `Start Council` bruker nå `detectedItems`.)

- [ ] **Step 5: Syntakssjekk**

Run: `luac -p "NordavindLC/LootDetection.lua"`
Expected: ingen output (OK).

- [ ] **Step 6: Commit**

```bash
git add NordavindLC/LootDetection.lua
git commit -m "refactor(loot): capture via post-combat trade-timer bag scan (GUID-deduped)"
```

---

### Task 3: Innsamlingsvindu + restriksjonsgated LOOT_REPORT

**Files:**
- Modify: `NordavindLC/LootDetection.lua` (ENCOUNTER-grener, BAG_UPDATE_DELAYED, restriksjon, send)

**Interfaces:**
- Consumes: `NLC.Comms.Send` (finnes), `NLC.LootDetection.ScanBags`, `C_RestrictedActions`.
- Produces: kaller `NLC.Comms.Send("LOOT_REPORT", { boss=..., items=reportItems })` når comms er tillatt.

- [ ] **Step 1: ENCOUNTER_START — sett boss (dedup beholdes session-vid)**

```lua
if event == "ENCOUNTER_START" then
  local encounterID, name = ...
  currentBoss = name or "Unknown Boss"
  dbg("ENCOUNTER_START: " .. currentBoss)
```

(`reportedGUIDs` nullstilles *ikke* per boss — det er session-vid dedup, nullstilles i
`Register()`/`Unregister()`. `reportItems` tømmes først når en rapport faktisk er sendt, Step 3.)

- [ ] **Step 2: ENCOUNTER_END — åpne innsamlingsvindu, skann på BAG_UPDATE_DELAYED**

Loot lander etter kampen. I stedet for én gjettet debounce: åpne et innsamlingsvindu, skann bags
hver gang loot lander (`BAG_UPDATE_DELAYED`), og lukk vinduet etter en maks-varighet — så prøv å sende.

```lua
elseif event == "ENCOUNTER_END" then
  local encounterID, name, difficultyID, groupSize, success = ...
  if name then currentBoss = name end
  if not (success == 1 or success == true) then
    dbg("Encounter feilet, ingen innsamling.")
    return
  end
  -- Åpne innsamlingsvindu: skann på hver BAG_UPDATE_DELAYED, lukk etter maks 12s.
  collecting = true
  NLC.LootDetection.ScanBags()                 -- første scan (loot som allerede er landet)
  lootFrame:RegisterEvent("BAG_UPDATE_DELAYED")
  if collectTimer then collectTimer:Cancel() end
  collectTimer = C_Timer.NewTimer(12, function()
    collectTimer = nil
    collecting = false
    lootFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
    NLC.LootDetection.TrySendReport()
  end)
  dbg("ENCOUNTER_END success, samler loot (maks 12s).")

elseif event == "BAG_UPDATE_DELAYED" then
  if collecting then NLC.LootDetection.ScanBags() end
```

- [ ] **Step 3: Restriksjonsgated send (`TrySendReport`)**

`ADDON_RESTRICTION_STATE_CHANGED` gir presis status for om addon-comms er blokkert. Vi sender kun
når det ikke er blokkert; ellers markerer vi `pendingSend` og flusher når restriksjonen løftes.

```lua
elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
  -- Bit-satt status; sjekk ekte tilstand for de comms-blokkerende typene (encounter/challenge).
  commsRestricted =
    (C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Encounter) or false)
    or (C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.ChallengeMode) or false)
  dbg("Comms-restriksjon: " .. tostring(commsRestricted))
  if not commsRestricted and pendingSend then
    NLC.LootDetection.TrySendReport()
  end
```

```lua
function NLC.LootDetection.TrySendReport()
  if #reportItems == 0 then
    pendingSend = false
    dbg("Ingen tradeable items å rapportere.")
    return
  end
  if commsRestricted then
    pendingSend = true
    dbg("Comms blokkert — venter på at restriksjon løftes (" .. #reportItems .. " items).")
    return
  end
  NLC.Comms.Send("LOOT_REPORT", { boss = currentBoss, items = reportItems })
  dbg("Sendte LOOT_REPORT: " .. #reportItems .. " items")
  reportItems = {}
  pendingSend = false
end
```

**Merk:** encounter-restriksjonen løftes normalt idet kampen slutter, så `TrySendReport` fra
innsamlingsvinduet (Step 2) vil oftest gå rett gjennom. Gaten er sikkerhetsnettet som gjør at vi
aldri sender mens comms faktisk er blokkert, uansett timing.

- [ ] **Step 4: Nullstill dedup i Register/Unregister + oppdater debug**

```lua
-- i Register(): reportItems = {}; reportedGUIDs = {}; pendingSend = false
-- i Unregister(): som over + avregistrer BAG_UPDATE_DELAYED, cancel collectTimer

function NLC.LootDetection.ToggleDebug()
  debugMode = not debugMode
  NLC.Utils.Print("Loot debug: " .. (debugMode and "|cff00ff00PÅ|r" or "|cffff0000AV|r"))
  if debugMode then
    NLC.Utils.Print("  currentBoss=" .. tostring(currentBoss))
    NLC.Utils.Print("  reportItems=" .. #reportItems .. "  commsRestricted=" .. tostring(commsRestricted))
  end
end
```

- [ ] **Step 5: Syntakssjekk + commit**

Run: `luac -p "NordavindLC/LootDetection.lua"`
```bash
git add NordavindLC/LootDetection.lua
git commit -m "feat(loot): restriction-gated LOOT_REPORT after post-combat collection window"
```

---

### Task 4: Comms — offiser-aggregering av LOOT_REPORT

**Files:**
- Modify: `NordavindLC/Comms.lua` (`OnMessage`)

**Interfaces:**
- Consumes: `NLC.LootDetection.GetCurrentBoss` (fallback boss), `NLC.UI.ShowLootDetected`, `NLC.LootDetection._setDetected`.
- Produces: offiser bygger aggregert liste og kaller `ShowLootDetected` etter innsamlingsvindu.

- [ ] **Step 1: Ny gren i `OnMessage` for LOOT_REPORT**

Behold etter active-sjekken (kun aktive offiserer aggregerer). Legg til:

```lua
elseif msgType == "LOOT_REPORT" then
  if not NLC.isOfficer then return end
  NLC.Council.OnLootReport(sender, data)
```

- [ ] **Step 2: Aggregering med innsamlingsvindu**

```lua
local _agg = {}          -- itemKey -> item
local _aggTimer = nil
local _aggBoss = nil

function NLC.Council.OnLootReport(sender, data)
  if not data or not data.items then return end
  _aggBoss = data.boss or _aggBoss
  for _, it in ipairs(data.items) do
    local key = (it.itemId or 0) .. ":" .. (it.looter or sender)
    if not _agg[key] then _agg[key] = it end
  end
  -- Åpne/forleng et 5s innsamlingsvindu fra første rapport.
  if _aggTimer then _aggTimer:Cancel() end
  _aggTimer = C_Timer.NewTimer(5, function()
    _aggTimer = nil
    local items = {}
    for _, it in pairs(_agg) do table.insert(items, it) end
    _agg = {}
    if #items > 0 then
      NLC.LootDetection._setDetected(items)
      NLC.UI.ShowLootDetected(items)
    end
  end)
end
```

- [ ] **Step 3: Syntakssjekk + commit**

Run: `luac -p "NordavindLC/Comms.lua"`
```bash
git add NordavindLC/Comms.lua
git commit -m "feat(comms): officer aggregates LOOT_REPORT into Loot Detected panel"
```

---

### Task 5: Core-wiring + panel tåler gjentatte oppdateringer

**Files:**
- Modify: `NordavindLC/Core.lua` (bekreft `Register()` for alle; ingen offiser-gating på fangst)
- Modify: `NordavindLC/UI/CouncilFrame.lua` (`ShowLootDetected` idempotent ved re-kall)

**Interfaces:**
- Consumes: alt fra Task 2–4.

- [ ] **Step 1: Bekreft at `Activate()` registrerer deteksjon for alle**

I `Core.lua` `NLC.Activate()` finnes `NLC.LootDetection.Register()` allerede (linje ~183).
Bekreft at den IKKE er bak en `isOfficer`-sjekk (alle raidere må skanne egne bags). Ingen
kodeendring om den allerede er ugated — noter i commit.

- [ ] **Step 2: Gjør `ShowLootDetected` trygg å kalle på nytt**

Bekreft at gjentatte kall (hvis en sen `LOOT_REPORT` kommer) ikke dupliserer frames — bruker
allerede singleton `lootPanel` + `refreshLootPanel`. Legg til guard så et åpent panel re-fylles:

```lua
function NLC.UI.ShowLootDetected(items)
  if not NLC.isOfficer then return end
  -- (eksisterende frame-opprettelse uendret)
  refreshLootPanel(items)
  lootPanel:Show()
end
```

- [ ] **Step 3: Syntakssjekk + commit**

Run: `luac -p "NordavindLC/Core.lua"` og `luac -p "NordavindLC/UI/CouncilFrame.lua"`
```bash
git add NordavindLC/Core.lua NordavindLC/UI/CouncilFrame.lua
git commit -m "chore(loot): wire distributed detection; idempotent Loot Detected panel"
```

---

### Task 6: In-game verifisering (manuell — reell gate)

**Files:** ingen (test-task).

Ingen automatisk test er mulig (WoW-API). Utfør denne sjekklista i spillet og noter resultat.

- [ ] **Step 1: Last inn og aktiver**
  - `/reload`, gå i raid, `/nordlc activate`, `/nordlc debug`.
  - Forvent: «Loaded», «Aktivert», debug PÅ.

- [ ] **Step 2: Bekreft comms-gating mot ekte restriksjon**
  - Pull en boss. I debug: «Comms-restriksjon: true» under kampen, «...: false» etter.
  - Forvent: ingen «Sendte LOOT_REPORT» mens restriksjon er true. Hvis loot ryddes før restriksjon
    løftes: «Comms blokkert — venter...», så «Sendte LOOT_REPORT» straks den løftes.

- [ ] **Step 3: Bekreft distribuert fangst via bag-scan**
  - Boss dør, alle looter. På offiserens skjerm: «Loot Detected»-panelet fylles med items fra
    flere lootere innen ~5–12s (innsamlingsvindu + aggregering).
  - Forvent: items med korrekt looter-navn, ilvl, tier-badge der relevant. Sen loot (lander etter
    kampen) fanges også — `BAG_UPDATE_DELAYED` trigger ny scan mens vinduet er åpent.

- [ ] **Step 4: Bekreft tradeable-filter + GUID-dedup**
  - Et utradeable/soulbound item skal IKKE dukke opp. Et epic tradeable item skal.
  - Loot fra en tidligere boss (fortsatt med timer i bag) skal IKKE rapporteres på nytt.

- [ ] **Step 5: Bekreft nedstrøms uendret**
  - «Start Council» → interesse-popup → wizard → award → trade fungerer som før.
  - `/nordlc status`: Export-teller øker ved award (web-kontrakt intakt).

- [ ] **Step 6: Blandet raid (hvis mulig)**
  - En spiller uten addon looter et item → det mangler i panelet → `/nordlc add [item]` legger
    det til manuelt.

- [ ] **Step 7: Commit testnotater (valgfritt)**
  - Skriv kort resultat i denne fila under en «## Testresultat»-overskrift og commit.

---

## Self-Review (utført ved skriving)

- **Spec-dekning:** Distribuert fangst via bag-scan (Task 2), tradeable-modell (Task 1–2),
  restriksjonsgated send (Task 3), aggregering + panel (Task 4–5), `/nordlc add`-fallback
  (eksisterende, verifisert Task 6), ingen comms mens restriksjon aktiv (Task 3 + verifisert
  Task 6), web-kontrakt urørt (ingen endring i export-sti). ✔
- **RC-gjennomgang foldet inn:** bag-scan (erstatter slot-korrelasjon) + ekte restriksjonsstatus
  (erstatter gjettet 4s-timer). Kun teknikk lånt; all kode i vår stil, ingen RC-navn/struktur. ✔
- **Åpne spørsmål fra spec** håndteres: auto-roll beholdt uendret (Task 2 Step 3); trade-timer-streng
  via `BIND_TRADE_TIME_REMAINING` (Task 1, verifiseres in-game); innsamlingsvindu = 12s klient /
  5s offiser (justeres etter Task 6). ✔
- **Placeholder-scan:** ingen TBD; all kode konkret. WoW-API-detaljer som ikke kan verifiseres
  headless er eksplisitt merket for in-game-sjekk i Task 6. ✔
- **Type-konsistens:** `reportItems`/`reportedGUIDs`/`detectedItems`/`_agg` navngitt konsistent;
  `GetReport` (klient) vs `GetDroppedItems`/`_setDetected` (panel) tydelig adskilt. ✔

## Neste (etter A)

Leveranse B (fordelingsflyt: live + redesign + høyreklikk-meny med roll-off / bytt kategori /
omfordel award / hvisk-fjern-kopier + Disenchant/Bank/Free) og Leveranse C (Electron companion)
har egne specs; planer skrives når A er verifisert. B kan gjenbruke Task 1-tooltip-scannen utvidet
til å returnere gjenstående trade-tid for nedtellings-badgen.
