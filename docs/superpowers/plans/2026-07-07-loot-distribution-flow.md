# Leveranse B — Live-oppdaterende + redesignet fordelingsflyt — Implementasjonsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Løfte hele loot-fordelingsflyten: alle fire vinduene oppdaterer seg live, får visuell opprydding (ikoner/badges/timere), og award-wizarden får høyreklikk-kontekstmeny (roll-off, bytt kategori, omfordel award, hvisk/fjern/kopier) + Disenchant/Bank/Free award-mål.

**Architecture:** Bygg videre på eksisterende `NordavindLC_NS`-UI. Nye delte widgets i `Theme.lua`. Live-oppdatering ved at `Council.OnInterestReceived`/nye Comms-meldinger trigger en debounced re-render mens et vindu er åpent. Kontekstmeny via Blizzards moderne `MenuUtil.CreateContextMenu` (generisk API, ingen RC-kopi). Roll-off via `RandomRoll` + `CHAT_MSG_SYSTEM`-parsing. DE/Bank/Free gjenbruker award-sti men ekskluderes fra `pendingExport`/ukesteller. Web-kontrakten røres ikke.

**Tech Stack:** Lua, WoW-API (patch 12.0), `MenuUtil` (Menu-API 11.0+), AceComm/AceSerializer, eksisterende `NLC.Theme`/`NLC.Council`/`NLC.UI`.

**Avhenger av:** Leveranse A (distribuert deteksjon) — bygges etter A.

## Global Constraints

- **Originalitet:** INGEN frames, templates, layout, tekststrenger eller kode fra RCLootCouncil. Kun generelle WoW-API-teknikker. Behold `NLC.Theme` (gull/mørkt), dra-bare frames, klassefarger, rank-badges, norsk brukertekst.
- **Web-kontrakt uendret:** `NLC.RecordAward` → `pendingExport`/`pendingEdits` → companion → `POST/PATCH /api/loot/addon` røres ikke. Rangering bruker fortsatt importert `baseScore`/wishlist via `Scoring.Calculate`.
- **DE/Bank/Free teller ikke som loot:** ekskluderes fra `NLC.db.weeklyLoot` OG `pendingExport` (samme prinsipp som `tmog` i dag, men tmog eksporteres — DE/Bank/Free gjør IKKE).
- **Norsk brukertekst** i all ny UI-tekst.
- **Kun offiser** ser/bruker wizard-handlinger; raidere har read-only.
- **Verifisering:** WoW-API kan ikke kjøres headless. Automatisk gate = `luac -p <fil>` (hopp over hvis `luac` mangler). Reell gate = in-game via `/nordlc test`, `/nordlc testpopup`, `/nordlc testloot` + live raid.

---

## Filstruktur

| Fil | Ansvar | Endring |
|-----|--------|---------|
| `NordavindLC/UI/Theme.lua` | Delte widgets/stil | **Modify:** `CreateItemIcon`, `CreateTimerBadge`, `Debounce` |
| `NordavindLC/UI/CouncilFrame.lua` | Loot Detected-panel + interesse-popup | **Modify:** live re-render, ikoner, per-item responsteller |
| `NordavindLC/UI/RankingFrame.lua` | Award-wizard (hovedvindu) | **Modify:** live rebuild, ikoner, høyreklikk-meny, roll-off-visning, DE/Bank/Free-meny |
| `NordavindLC/Council.lua` | Session/award-logikk | **Modify:** live-refresh-trigger, roll-off-logikk, DE/Bank/Free award-sti, kategori-bytte |
| `NordavindLC/UI/TradeFrame.lua` | Trade-vindu | **Modify:** trade-timer-nedtelling, ikoner, sortering |
| `NordavindLC/Utils.lua` | Delte hjelpere | **Modify:** `GetBagItemTradeSeconds(bag, slot)` |
| `NordavindLC/Comms.lua` | Comms | **Modify:** valgfri `ROLL_RESULT`-kringkasting til raidere |

**Merk:** «syntakssjekk» = `luac -p "NordavindLC/<fil>.lua"` (ingen output = OK).

---

### Task 1: Delte Theme-widgets (ikon, timer-badge, debounce)

**Files:**
- Modify: `NordavindLC/UI/Theme.lua` (etter `CreateSeparator`, linje 89)

**Interfaces:**
- Produces:
  - `NLC.Theme.CreateItemIcon(parent, size) -> Button` — ikon-widget; `:SetItem(itemLink)` setter tekstur + tooltip-hover.
  - `NLC.Theme.CreateTimerBadge(parent) -> FontString` — liten badge; `:SetSeconds(sec)` viser «1t 12m» og fargelegger etter hastverk.
  - `NLC.Theme.Debounce(key, delay, fn)` — kansellerer forrige timer med samme `key`, kjører `fn` etter `delay`. Delt live-refresh-hjelper.

- [ ] **Step 1: Ikon-widget**

```lua
-- Item-ikon-knapp med tooltip. Kall :SetItem(link) for å fylle.
function NLC.Theme.CreateItemIcon(parent, size)
  size = size or 28
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(size, size)
  btn.tex = btn:CreateTexture(nil, "ARTWORK")
  btn.tex:SetAllPoints()
  btn.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim standard ikon-kant
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(0.788, 0.659, 0.298, 0.5)
  border:SetDrawLayer("BACKGROUND")
  function btn:SetItem(itemLink)
    self.itemLink = itemLink
    local icon = itemLink and select(5, C_Item.GetItemInfoInstant(itemLink))
    self.tex:SetTexture(icon or 134400) -- 134400 = default "?" ikon
  end
  btn:SetScript("OnEnter", function(self)
    if not self.itemLink then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.itemLink)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return btn
end
```

- [ ] **Step 2: Timer-badge**

```lua
-- Liten nedtellings-badge. Kall :SetSeconds(sec). Grønn >30m, gul >10m, rød ellers.
function NLC.Theme.CreateTimerBadge(parent)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  function fs:SetSeconds(sec)
    if not sec or sec <= 0 then
      self:SetText(NLC.Theme.MUTED .. "—|r")
      return
    end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local label = (h > 0) and (h .. "t " .. m .. "m") or (m .. "m")
    local color = (sec > 1800) and NLC.Theme.GREEN
      or (sec > 600) and NLC.Theme.ORANGE
      or NLC.Theme.RED
    self:SetText(color .. label .. "|r")
  end
  return fs
end
```

- [ ] **Step 3: Debounce-hjelper**

```lua
local _debounceTimers = {}
-- Kansellerer forrige timer med samme key og planlegger fn på nytt etter delay.
function NLC.Theme.Debounce(key, delay, fn)
  local t = _debounceTimers[key]
  if t then t:Cancel() end
  _debounceTimers[key] = C_Timer.NewTimer(delay, function()
    _debounceTimers[key] = nil
    fn()
  end)
end
```

- [ ] **Step 4: Syntakssjekk + commit**

Run: `luac -p "NordavindLC/UI/Theme.lua"`
```bash
git add NordavindLC/UI/Theme.lua
git commit -m "feat(theme): shared item-icon, timer-badge and debounce widgets"
```

---

### Task 2: Live re-render av award-wizard mens interesse kommer inn

**Files:**
- Modify: `NordavindLC/Council.lua` (`OnInterestReceived`, ny `IsWizardOpen` state)
- Modify: `NordavindLC/UI/RankingFrame.lua` (eksporter `IsShown`-guard)

**Interfaces:**
- Consumes: `NLC.Theme.Debounce`, `NLC.Council.BuildRanking`, `NLC.UI.ShowWizard`, `NLC.Council.GetActiveSessions`, `NLC.Council.GetWizardIndex`.
- Produces: `NLC.UI.IsWizardOpen() -> boolean`.

I dag bygges `session.ranked` kun i `CloseCollecting`. Her legger vi til at nye `INTEREST`
mens wizarden er åpen rebygger rangeringen for det viste itemet og re-renderer — debounced.

- [ ] **Step 1: Eksporter wizard-åpen-guard i RankingFrame**

Nederst i `RankingFrame.lua` (rankFrame er upvalue i fila):
```lua
function NLC.UI.IsWizardOpen()
  return rankFrame ~= nil and rankFrame:IsShown()
end
```

- [ ] **Step 2: Rebygg + re-render ved ny interesse (debounced)**

I `Council.lua`, på slutten av `OnInterestReceived` (etter at `session.interests[name]` er satt),
legg til:
```lua
  -- Live: hvis wizarden er åpen og dette itemet er i ranking-fasen, rebygg rangeringen
  -- og re-render (debounced ~1s for å unngå flimmer når mange svarer samtidig).
  if NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen() then
    NLC.Theme.Debounce("wizard-refresh", 1.0, function()
      local sessions = NLC.Council.GetActiveSessions()
      local idx = NLC.Council.GetWizardIndex()
      local cur = sessions[idx]
      if cur and cur.phase == "ranking" then
        cur.ranked = NLC.Council.BuildRanking(cur)
        NLC.UI.ShowWizard(sessions, idx)
      end
    end)
  end
```

**Merk:** `ShowWizard` kaller `ShowRanking` som allerede rydder gamle rader (linje 142–147) og
bygger på nytt — trygt å kalle gjentatte ganger. Scroll-posisjon nullstilles; akseptabelt for
balansert nivå (spec YAGNI: ingen scroll-bevaring).

- [ ] **Step 3: Syntakssjekk + commit**

Run: `luac -p "NordavindLC/Council.lua"` og `luac -p "NordavindLC/UI/RankingFrame.lua"`
```bash
git add NordavindLC/Council.lua NordavindLC/UI/RankingFrame.lua
git commit -m "feat(council): live wizard rebuild as INTEREST arrives (debounced)"
```

---

### Task 3: Live Loot Detected-panel + ikoner + per-item responsteller

**Files:**
- Modify: `NordavindLC/UI/CouncilFrame.lua` (`refreshLootPanel`, interesse-popup)

**Interfaces:**
- Consumes: `NLC.Theme.CreateItemIcon`.
- Produces: (ingen nye offentlige — intern visuell endring)

Leveranse A gjør allerede at `ShowLootDetected(items)` kalles på nytt når aggregerte rapporter
kommer inn (den er singleton + idempotent). Her forbedrer vi *radene*: ikon + looter-navn.

- [ ] **Step 1: Ikon + looter-navn i Loot Detected-rader**

I `refreshLootPanel` (CouncilFrame.lua linje ~330), i `for i, item`-løkka, før item-teksten,
legg til et ikon og utvid teksten med looter:
```lua
    -- Item-ikon
    local icon = NLC.Theme.CreateItemIcon(row, 32)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetItem(item.itemLink)

    -- Item-tekst (flyttet til høyre for ikonet)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 46, 6)
    text:SetWidth(330)
    text:SetJustifyH("LEFT")
    local itemLabel = (item.itemLink or "?") .. "  " .. T.MUTED .. "(ilvl " .. (item.ilvl or 0) .. ")|r"
    if item.armorType then
      itemLabel = itemLabel .. "  " .. T.GOLD_DIM .. "[" .. item.armorType .. "]|r"
    end
    text:SetText(itemLabel)

    -- Looter-navn (under item-teksten)
    if item.looter then
      local looterText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      looterText:SetPoint("LEFT", 46, -10)
      looterText:SetText(T.MUTED .. "looted av " .. item.looter .. "|r")
    end
```
(Erstatt den eksisterende `text`-blokken linje 344–352 med blokken over. `ROW_H` økes fra 42 til 44
for å få plass til looter-linja: endre `local ROW_H = 42` → `44` i `refreshLootPanel`.)

- [ ] **Step 2: Per-item responsteller i interesse-popup (offiser)**

Finn interesse-popup-renderingen i `CouncilFrame.lua` (funksjonen som viser item-radene i
`ShowMultiItemPopup`). For hvert item, legg til en liten teller som viser hvor mange som har svart
på nettopp det itemet. Antall svar per sessionIdx hentes fra Council. Legg først en getter i
`Council.lua`:
```lua
function NLC.Council.GetResponseCount(sessionIdx)
  local sessions = NLC.Council.GetActiveSessions()
  for _, s in ipairs(sessions) do
    if s.sessionIdx == sessionIdx then
      return NLC.Utils.TableCount(s.interests)
    end
  end
  return 0
end
```
I interesse-popupen (offiser-visning), på hver item-rad, legg til:
```lua
    if NLC.isOfficer then
      local respFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      respFS:SetPoint("RIGHT", -8, 0)
      respFS:SetText(T.MUTED .. NLC.Council.GetResponseCount(item.sessionIdx) .. " svar|r")
      row._respFS = respFS
    end
```
Og la popupens eksisterende live-ticker (nedtellingen finnes allerede) oppdatere `row._respFS`
hver tick: i tickeren, iterer radene og sett `row._respFS:SetText(...)` på nytt. (Popup-tickeren
finnes allerede for nedtelling — utvid den; ikke lag en ny.)

- [ ] **Step 3: Syntakssjekk + commit**

Run: `luac -p "NordavindLC/UI/CouncilFrame.lua"` og `luac -p "NordavindLC/Council.lua"`
```bash
git add NordavindLC/UI/CouncilFrame.lua NordavindLC/Council.lua
git commit -m "feat(ui): icons + looter on Loot Detected; per-item response counter"
```

---

### Task 4: Høyreklikk-kontekstmeny på wizard-kandidat

**Files:**
- Modify: `NordavindLC/UI/RankingFrame.lua` (kandidat-rad: høyreklikk-handler)
- Modify: `NordavindLC/Council.lua` (`ChangeCategory`, `ReassignCurrent` hjelpere)

**Interfaces:**
- Consumes: `MenuUtil.CreateContextMenu`, eksisterende `NLC.UI.ShowEditPopup`, `NLC.History.ApplyAwardEdit`, `NLC.Council.BuildRanking`, `NLC.Council.Award`.
- Produces:
  - `NLC.Council.ChangeCategory(name, newCategory)` — endrer kandidatens respons-kategori og rebygger.
  - `NLC.Council.WhisperCandidate(name)` — åpner hvisk til spilleren.

Bruk Blizzards moderne meny-API (`MenuUtil`), ikke `UIDropDownMenu` og *ingen* RC-meny.

- [ ] **Step 1: Kategori-bytte-hjelper i Council**

```lua
-- Endrer en kandidats respons-kategori i gjeldende session og rebygger rangeringen.
function NLC.Council.ChangeCategory(name, newCategory)
  local sessions = NLC.Council.GetActiveSessions()
  local idx = NLC.Council.GetWizardIndex()
  local session = sessions[idx]
  if not session or not session.interests[name] then return end
  session.interests[name].category = newCategory
  session.ranked = NLC.Council.BuildRanking(session)
  NLC.UI.ShowWizard(sessions, idx)
end

function NLC.Council.WhisperCandidate(name)
  ChatFrame_SendTell(name)
end
```

- [ ] **Step 2: Høyreklikk-handler på kandidat-rad**

I `RankingFrame.lua`, i kandidat-løkka i `ShowRanking` (etter at `row` er opprettet, ca. linje 189),
gjør raden klikkbar og åpne kontekstmeny på høyreklikk. Kun offiser:
```lua
    if NLC.isOfficer then
      row:EnableMouse(true)
      row:RegisterForClicks("RightButtonUp")
      row:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
          root:CreateTitle(c.name)

          -- Bytt kategori
          local catSub = root:CreateButton("Bytt kategori")
          for _, cat in ipairs({ "upgrade", "catalyst", "offspec", "tmog" }) do
            catSub:CreateButton(cat, function()
              NLC.Council.ChangeCategory(c.name, cat)
            end)
          end

          -- Omfordel / bytt award (gjenbruker eksisterende edit-popup + ApplyAwardEdit)
          root:CreateButton("Omfordel award…", function()
            local session = NLC.Council.GetActiveSessions()[NLC.Council.GetWizardIndex()]
            local entry = {
              item = session.itemLink, itemId = session.itemId,
              awardedTo = c.name, category = c.category, timestamp = time(),
            }
            NLC.UI.ShowEditPopup(entry, function(newRecipient, newCategory)
              NLC.History.ApplyAwardEdit(entry, newRecipient, newCategory)
            end)
          end)

          root:CreateDivider()
          root:CreateButton("Hvisk " .. c.name, function() NLC.Council.WhisperCandidate(c.name) end)
          root:CreateButton("Kopier navn", function()
            local eb = ChatEdit_ChooseBoxForSend()
            ChatEdit_ActivateChat(eb)
            eb:SetText(c.name)
          end)
        end)
      end)
    end
```

**Merk:** «Legg til i roll» legges til i denne menyen i Task 5. «Fjern kandidat» dekkes av at man
lar være å tildele; spec sitt «fjern fra dette itemets liste» = sett kategori til å ekskludere.
For eksplisitt fjerning, legg til:
```lua
          root:CreateButton("Fjern fra listen", function()
            local session = NLC.Council.GetActiveSessions()[NLC.Council.GetWizardIndex()]
            session.interests[c.name] = nil
            session.ranked = NLC.Council.BuildRanking(session)
            NLC.UI.ShowWizard(NLC.Council.GetActiveSessions(), NLC.Council.GetWizardIndex())
          end)
```

- [ ] **Step 3: Syntakssjekk + commit**

Run: `luac -p "NordavindLC/UI/RankingFrame.lua"` og `luac -p "NordavindLC/Council.lua"`
```bash
git add NordavindLC/UI/RankingFrame.lua NordavindLC/Council.lua
git commit -m "feat(wizard): right-click context menu (category/reassign/whisper/remove/copy)"
```

---

### Task 5: Roll-off mellom kandidater

**Files:**
- Modify: `NordavindLC/Council.lua` (roll-state, `RandomRoll`-styring, `CHAT_MSG_SYSTEM`-fangst)
- Modify: `NordavindLC/UI/RankingFrame.lua` (meny-inngang + inline visning)

**Interfaces:**
- Consumes: `RandomRoll`, `CHAT_MSG_SYSTEM`, `RANDOM_ROLL_RESULT` (global streng).
- Produces:
  - `NLC.Council.AddToRoll(name)` / `NLC.Council.StartRoll()` / `NLC.Council.GetRollState() -> { names, results, active }`.

For å avgjøre likestilte kandidater: legg 2+ til en roll-off, kjør `/roll` for hver via `RandomRoll`,
fang resultatene fra system-chat, vis inline i wizarden.

- [ ] **Step 1: Roll-state + event-frame i Council**

```lua
local _roll = { names = {}, results = {}, active = false }
local _rollFrame = CreateFrame("Frame")

function NLC.Council.GetRollState() return _roll end

function NLC.Council.AddToRoll(name)
  for _, n in ipairs(_roll.names) do if n == name then return end end
  table.insert(_roll.names, name)
  if NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen() then
    local s = NLC.Council.GetActiveSessions()
    NLC.UI.ShowWizard(s, NLC.Council.GetWizardIndex())
  end
end

-- Parse-mønster fra global streng: "%s rolls %d (%d-%d)"
local _rollPattern = _G.RANDOM_ROLL_RESULT
  :gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")

_rollFrame:SetScript("OnEvent", function(_, _, text)
  if not _roll.active then return end
  local who, roll = text:match(_rollPattern)
  if not who then return end
  who = who:match("^([^-]+)") or who
  -- Registrer kun kandidater i roll-lista
  for _, n in ipairs(_roll.names) do
    if n == who and not _roll.results[who] then
      _roll.results[who] = tonumber(roll)
      if NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen() then
        NLC.UI.ShowWizard(NLC.Council.GetActiveSessions(), NLC.Council.GetWizardIndex())
      end
      break
    end
  end
end)

function NLC.Council.StartRoll()
  if #_roll.names < 2 then
    NLC.Utils.Print("Legg til minst 2 kandidater i roll-offen.")
    return
  end
  _roll.results = {}
  _roll.active = true
  _rollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
  -- Be hver kandidat rulle. Egen klient ruller direkte; andre får en hvisk-instruks.
  for _, n in ipairs(_roll.names) do
    if n == UnitName("player") then
      RandomRoll(1, 100)
    else
      SendChatMessage("Roll-off for " .. (NLC.Council.GetActiveSessions()[NLC.Council.GetWizardIndex()].itemLink or "item") .. " — /roll 100 takk!", "WHISPER", nil, n)
    end
  end
  -- Lukk fangst-vinduet etter 15s.
  C_Timer.After(15, function()
    _roll.active = false
    _rollFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
  end)
end

function NLC.Council.ClearRoll()
  _roll = { names = {}, results = {}, active = false }
end
```

**Merk:** WoW tillater ikke at én klient kaster `/roll` for andre spillere. Modellen er derfor:
egen roll gjøres direkte; medkandidater bes rulle via hvisk, og deres `/roll 100` fanges fra
system-chat. Dette er ærlig og speiler hvordan roll-offs faktisk fungerer.

- [ ] **Step 2: Meny-inngang «Legg til i roll» + «Start roll»**

I kontekstmenyen fra Task 4, legg til øverst (etter tittel):
```lua
          root:CreateButton("Legg til i roll", function() NLC.Council.AddToRoll(c.name) end)
          if #NLC.Council.GetRollState().names >= 2 then
            root:CreateButton("Start roll (" .. #NLC.Council.GetRollState().names .. ")", function()
              NLC.Council.StartRoll()
            end)
          end
```

- [ ] **Step 3: Inline roll-visning i kandidat-rad**

I `ShowRanking`, i score-kolonnen (ca. linje 245–251), utvid til å vise roll-resultat hvis
kandidaten er i en aktiv roll-off:
```lua
    local rollState = NLC.Council.GetRollState and NLC.Council.GetRollState() or { names = {}, results = {} }
    local inRoll = false
    for _, n in ipairs(rollState.names) do if n == c.name then inRoll = true; break end end
    if inRoll then
      local rollVal = rollState.results[c.name]
      -- Marker høyeste roll som vinner
      local best, bestName = -1, nil
      for n, v in pairs(rollState.results) do if v > best then best, bestName = v, n end end
      local won = (c.name == bestName)
      scoreText:SetText((won and T.GREEN or T.GOLD_LIGHT) ..
        "🎲 " .. (rollVal and tostring(rollVal) or "…") .. (won and " ✓" or "") .. "|r")
    elseif c.roll then
      scoreText:SetText(T.GOLD_LIGHT .. "Roll: " .. c.roll .. "|r")
    else
      scoreText:SetText(T.GOLD_LIGHT .. string.format("%.1f", c.score) .. "|r")
    end
```
(Erstatt den eksisterende `if c.roll then ... else ... end`-blokken.)

- [ ] **Step 4: Nullstill roll ved award/advance**

I `Council.Award` (etter award sendt, før `AdvanceWizard`), legg til `NLC.Council.ClearRoll()`
så roll-staten ikke lekker til neste item.

- [ ] **Step 5: Syntakssjekk + commit**

Run: `luac -p "NordavindLC/Council.lua"` og `luac -p "NordavindLC/UI/RankingFrame.lua"`
```bash
git add NordavindLC/Council.lua NordavindLC/UI/RankingFrame.lua
git commit -m "feat(wizard): roll-off between candidates via RandomRoll + system-chat capture"
```

---

### Task 6: Disenchant / Bank / Free award-mål

**Files:**
- Modify: `NordavindLC/Council.lua` (`AwardTo` med spesial-mål)
- Modify: `NordavindLC/Core.lua` (`RecordAward` — ekskluder DE/Bank/Free fra `pendingExport`)
- Modify: `NordavindLC/UI/RankingFrame.lua` (liten meny ved «Award Later»)

**Interfaces:**
- Consumes: `NLC.RecordAward`, `NLC.Trade.Add`.
- Produces: `NLC.Council.AwardSpecial(target)` der `target ∈ {"disenchant","bank","free"}`.

DE/Bank/Free logges i historikk og legges i `pendingTrades` (så itemet kan trades videre), men
teller IKKE som loot: ikke i `weeklyLoot`, ikke i `pendingExport`.

- [ ] **Step 1: Utvid `RecordAward` til å hoppe over eksport for spesial-mål**

I `Core.lua` `RecordAward` (linje 209), legg til en `exportable`-parameter:
```lua
function NLC.RecordAward(item, awardedTo, awardedBy, boss, category, itemId, exportable)
  if exportable == nil then exportable = true end
  local entry = {
    item = item, awardedTo = awardedTo, awardedBy = awardedBy,
    boss = boss or "Unknown", category = category or "upgrade", timestamp = time(),
  }
  table.insert(NLC.db.lootHistory, entry)
  if exportable then
    table.insert(NLC.db.pendingExport, entry)   -- kun ekte spiller-awards eksporteres
  end
  local id = itemId or C_Item.GetItemInfoInstant(item)
  NLC.Trade.Add(item, id, awardedTo, awardedBy, boss, category)
end
```
Eksisterende kallere sender ikke `exportable` → defaulter til `true` → uendret oppførsel. ✔

- [ ] **Step 2: `AwardSpecial` i Council**

```lua
local SPECIAL_LABEL = { disenchant = "Disenchant", bank = "Guild Bank", free = "Free" }

-- Award til et ikke-spiller-mål. Teller ikke som loot; eksporteres ikke.
function NLC.Council.AwardSpecial(target)
  if not NLC.isOfficer or not UnitIsGroupLeader("player") then return end
  local sessions = NLC.Council.GetActiveSessions()
  local idx = NLC.Council.GetWizardIndex()
  local session = sessions[idx]
  if not session then return end
  local label = SPECIAL_LABEL[target] or target

  -- category = target så det er synlig i historikk/trade; exportable=false; ingen ukesteller.
  NLC.RecordAward(session.itemLink, label, UnitName("player"), session.boss, target, session.itemId, false)
  NLC.Utils.Print(session.itemLink .. " → " .. label .. " (teller ikke som loot)")

  session.phase = "awarded"
  NLC.Council.ClearRoll()
  NLC.Council.AdvanceWizard()
end
```
(Ingen `AWARD`-comms kringkastes for spesial-mål — det er ikke en spiller-tildeling. Ingen
`weeklyLoot`-økning.)

- [ ] **Step 3: Meny/knapp i wizarden**

I `RankingFrame.lua`, ved siden av `laterBtn` (bunn-venstre), legg til en «Annet»-knapp som åpner
en liten kontekstmeny. Kun offiser + leder:
```lua
    if NLC.isOfficer and UnitIsGroupLeader("player") then
      rankFrame.specialBtn = T.CreateButton(rankFrame, 120, 34, "Annet ▾")
      rankFrame.specialBtn:SetPoint("BOTTOMLEFT", 190, 16)
      rankFrame.specialBtn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
          root:CreateTitle("Send item til")
          root:CreateButton("Disenchant", function() NLC.Council.AwardSpecial("disenchant") end)
          root:CreateButton("Guild Bank", function() NLC.Council.AwardSpecial("bank") end)
          root:CreateButton("Free (gratis)", function() NLC.Council.AwardSpecial("free") end)
        end)
      end)
    end
```
(Opprett kun én gang, i `if not rankFrame then ... end`-blokken sammen med de andre knappene.)

- [ ] **Step 4: Syntakssjekk + commit**

Run: `luac -p "NordavindLC/Council.lua"`, `luac -p "NordavindLC/Core.lua"`, `luac -p "NordavindLC/UI/RankingFrame.lua"`
```bash
git add NordavindLC/Council.lua NordavindLC/Core.lua NordavindLC/UI/RankingFrame.lua
git commit -m "feat(wizard): Disenchant/Bank/Free award targets (not counted, not exported)"
```

---

### Task 7: Trade-vindu — nedtelling + ikoner + sortering

**Files:**
- Modify: `NordavindLC/Utils.lua` (`GetBagItemTradeSeconds`)
- Modify: `NordavindLC/UI/TradeFrame.lua` (ikon, timer-badge, sortering, periodisk refresh)

**Interfaces:**
- Consumes: `NLC.Theme.CreateItemIcon`, `NLC.Theme.CreateTimerBadge`, `C_TooltipInfo.GetBagItem`.
- Produces: `NLC.Utils.GetBagItemTradeSeconds(bag, slot) -> number|nil` — grovt anslag på gjenstående trade-sekunder.

- [ ] **Step 1: Grovt trade-sekund-anslag i Utils**

Bygger videre på Task 1 i Leveranse A (`IsTradeableBagItem`). Her henter vi ut tid-strengen og
anslår sekunder. Presisjon er bevisst grov (spec åpent spørsmål #3 — tooltip gir ofte kun «N t»).
```lua
-- Grovt anslag på gjenstående trade-tid i sekunder for item i (bag, slot), eller nil.
function NLC.Utils.GetBagItemTradeSeconds(bag, slot)
  local data = C_TooltipInfo and C_TooltipInfo.GetBagItem(bag, slot)
  if not data or not data.lines then return nil end
  local marker = _G.BIND_TRADE_TIME_REMAINING or "You may trade this item"
  marker = marker:gsub("%%s.*$", ""):gsub("%s+$", "")
  for _, line in ipairs(data.lines) do
    local text = line.leftText or ""
    if text:find(marker, 1, true) then
      local hours = tonumber(text:match("(%d+)%s*[Hht]")) or 0
      local mins  = tonumber(text:match("(%d+)%s*[Mm]")) or 0
      local sec = hours * 3600 + mins * 60
      if sec == 0 then sec = 7200 end -- fant linja, men klarte ikke parse → anta 2t
      return sec
    end
  end
  return nil
end
```

- [ ] **Step 2: Ikon + timer + sortering i trade-radene**

I `TradeFrame.lua` `refreshTradeFrame`, før radene bygges, sorter `pending` på gjenstående tid
(mest haster øverst). Utvid hver rad med ikon + timer-badge.

Sortering (etter `local pending = NLC.Trade.GetPending()`):
```lua
  -- Anslå gjenstående tid per entry og sorter stigende (minst tid = øverst).
  for _, entry in ipairs(pending) do
    local bag, slot = FindItemInBags(entry.itemId)
    entry._tradeSec = (bag and slot) and NLC.Utils.GetBagItemTradeSeconds(bag, slot) or nil
  end
  table.sort(pending, function(a, b)
    return (a._tradeSec or math.huge) < (b._tradeSec or math.huge)
  end)
```
(`FindItemInBags` er allerede definert i fila, linje 43.)

I `for i, entry`-løkka, legg til ikon (venstre) og timer-badge (høyre for «Til:»-linja):
```lua
    local icon = NLC.Theme.CreateItemIcon(row, 34)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetItem(entry.item)
    -- (flytt itemText/hover fra x=12 til x=48 for å gi plass til ikonet)

    local badge = NLC.Theme.CreateTimerBadge(row)
    badge:SetPoint("LEFT", 48, -8) -- på linje med "Til:"-teksten, mot høyre
    badge:ClearAllPoints()
    badge:SetPoint("RIGHT", -260, -8)
    badge:SetSeconds(entry._tradeSec)
```
(Juster `itemText:SetPoint("LEFT", 48, 8)` og hover tilsvarende.)

- [ ] **Step 3: Periodisk refresh mens vinduet er åpent**

Trade-timere teller ned — refresh vinduet hvert 30s mens det vises. I `NLC.UI.ShowTradeFrame`,
etter `tradeFrame:Show()`:
```lua
  if not tradeFrame._ticker then
    tradeFrame._ticker = C_Timer.NewTicker(30, function()
      if tradeFrame and tradeFrame:IsShown() then
        refreshTradeFrame()
      end
    end)
  end
```

- [ ] **Step 4: Syntakssjekk + commit**

Run: `luac -p "NordavindLC/Utils.lua"` og `luac -p "NordavindLC/UI/TradeFrame.lua"`
```bash
git add NordavindLC/Utils.lua NordavindLC/UI/TradeFrame.lua
git commit -m "feat(trade): countdown badge, icons and urgency sorting"
```

---

### Task 8: In-game verifisering (manuell — reell gate)

**Files:** ingen (test-task).

- [ ] **Step 1: Regresjon — eksisterende flyt**
  - `/reload`, `/nordlc test`, `/nordlc testpopup`, `/nordlc testloot`.
  - Forvent: alle fire vinduer åpner, ingen Lua-feil, gull/mørkt uttrykk intakt.

- [ ] **Step 2: Live-oppdatering**
  - Start council med flere items. Mens raidere svarer: wizarden viser nye kandidater fortløpende
    uten å lukke/åpne. Loot Detected fylles live (fra Leveranse A).
  - Forvent: debounce ~1s, ingen flimmer, responsteller stiger.

- [ ] **Step 3: Kontekstmeny**
  - Høyreklikk en kandidat → meny med bytt kategori / omfordel / hvisk / kopier / fjern / roll.
  - Test bytt kategori → kandidaten flyttes til ny kategori-gruppe. Omfordel → edit-popup lagrer
    og `/nordlc status` viser at Edit-teller øker (pendingEdits, web-kontrakt intakt).

- [ ] **Step 4: Roll-off**
  - Legg 2+ kandidater til roll, «Start roll». Egen `/roll` fanges; medkandidater får hvisk.
    Etter deres `/roll 100`: verdiene vises inline, høyeste markeres ✓.

- [ ] **Step 5: DE/Bank/Free**
  - «Annet ▾» → Disenchant. Item logges i historikk + dukker opp i Trade-vinduet, men
    `/nordlc status` Export-teller øker IKKE, og ukesteller for spilleren øker ikke.

- [ ] **Step 6: Trade-timer**
  - Åpne Trade-vindu med items som har trade-timer. Verifiser nedtellings-badge (farge/verdi) og
    at mest-haster sorteres øverst. Vent → refresh hvert 30s.

- [ ] **Step 7: Visuell + originalitet**
  - Alle fire vinduer bruker felles `Theme`-uttrykk (ikoner, badges). Ingen RC-likhet i layout/tekst.

- [ ] **Step 8: Commit testnotater (valgfritt)**
  - Skriv resultat under «## Testresultat» og commit.

---

## Self-Review (utført ved skriving)

- **Spec-dekning:** Live Loot Detected + responsteller (Task 3), live wizard-rebuild (Task 2),
  ikoner/badges via delt Theme (Task 1), høyreklikk-meny med bytt kategori/omfordel/hvisk/fjern/kopier
  (Task 4), roll-off (Task 5), Disenchant/Bank/Free ekskludert fra eksport+ukesteller (Task 6),
  trade-timer + ikoner + sortering (Task 7). ✔
- **Web-kontrakt:** `RecordAward` beholder `pendingExport` for ekte awards; DE/Bank/Free via ny
  `exportable=false`-parameter (default true → eksisterende kallere uendret). Omfordel gjenbruker
  `ApplyAwardEdit` → `pendingEdits`. Ingen endring i API/format. ✔
- **Originalitet:** `MenuUtil` (Blizzard), `RandomRoll`, `C_TooltipInfo`, egne Theme-widgets. Ingen
  RC-frames/tekst/struktur. ✔
- **Åpne spørsmål fra spec:** debounce = 1s (Task 2), ikon-caching (WoW cacher tekstur-ID internt,
  `SetItem` er billig), trade-tid grovt anslag (Task 7, presisjon bevisst deferred), roll-parsing via
  `RANDOM_ROLL_RESULT` (Task 5), enchanter-valg = generisk «Disenchant»-mål uten fast navn (Task 6 —
  enkleste nivå), roll-kringkasting til raidere er valgfri (ikke tatt med; wizard er offiser-verktøy). ✔
- **Type-konsistens:** `GetActiveSessions`/`GetWizardIndex`/`BuildRanking`/`ShowWizard`/`IsWizardOpen`
  brukt konsistent; `GetRollState` returnerer `{names,results,active}` overalt; `AwardSpecial(target)`
  og `RecordAward(...,exportable)` matcher. ✔

## Neste (etter B)

Leveranse C (Electron companion) har egen plan (`2026-07-07-companion-desktop-app.md`) og er uavhengig.
