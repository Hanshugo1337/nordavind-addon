# Award Editing + Role Priority + LootThisWeek Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add award history/editing UI, DPS role priority in scoring, and persistent weekly loot tracking with Wednesday auto-reset.

**Architecture:** New `UI/HistoryFrame.lua` holds the shared edit popup and history list. Scoring gets a role bonus field. LootThisWeek moves from ephemeral importData mutation to a persisted `weeklyLoot` table in SavedVariables with automatic reset.

**Tech Stack:** WoW Lua addon (no test framework — verification via in-game `/nordlc` commands and visual inspection)

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `NordavindLC/Scoring.lua` | Modify | Add +10 DPS role bonus; use `weeklyLoot.counts` for warnings |
| `NordavindLC/Core.lua` | Modify | Init `weeklyLoot` in DB; Wednesday reset check; `/nordlc history` command |
| `NordavindLC/Council.lua` | Modify | Increment `weeklyLoot.counts` on award instead of mutating importData |
| `NordavindLC/UI/HistoryFrame.lua` | Create | Shared edit popup + history list frame |
| `NordavindLC/UI/TradeFrame.lua` | Modify | Add Endre button per row, wired to shared edit popup |
| `NordavindLC/NordavindLC.toc` | Modify | Register `UI/HistoryFrame.lua` |
| `nordavind-web/app/api/loot/addon/route.ts` | Modify | Add PATCH handler to update existing LootDrop by timestamp |
| `nordavind-web/lib/scoring.ts` | Modify | Include wishlist item IDs in export per player |
| `nordavind-web/app/api/loot/addon-export/route.ts` | Modify | Add `wishlist` field per player |
| `NordavindLC/Council.lua` | Modify | Filter upgrade candidates by wishlist |
| `NordavindLC/UI/RankingFrame.lua` | Modify | Show equipped item link per candidate row |
| `nordavind-addon/companion/lib/api-client.js` | Modify | Add `editAward()` method |
| `nordavind-addon/companion/lib/watcher.js` | Modify | Detect and return `pendingEdits` from SavedVariables |
| `nordavind-addon/companion/index.js` | Modify | Process `pendingEdits` same as `pendingExports` |

---

### Task 1: Role Priority in Ranking

DPS always ranks above Tanks/Healers regardless of score. Score only determines order within the same role.

**Files:**
- Modify: `NordavindLC/Council.lua`

- [ ] **Step 1: Add `role` to candidates in `BuildRanking` and sort by role tier**

In `Council.lua`, `BuildRanking` (line 196). Add `role` to each candidate and update the sort:

```lua
function NLC.Council.BuildRanking(session)
  local candidates = {}

  for name, interest in pairs(session.interests) do
    local imported = NLC.Scoring.GetImportedScore(name)
    local live = {
      equippedIlvl = interest.equippedIlvl,
      tierCount = interest.tierCount,
      isTier = session.equipLoc and (
        session.equipLoc == "INVTYPE_HEAD" or
        session.equipLoc == "INVTYPE_SHOULDER" or
        session.equipLoc == "INVTYPE_CHEST" or
        session.equipLoc == "INVTYPE_ROBE" or
        session.equipLoc == "INVTYPE_HAND" or
        session.equipLoc == "INVTYPE_LEGS"
      ),
    }

    local score, breakdown = NLC.Scoring.Calculate(imported, live)
    local warnings = NLC.Scoring.GetWarnings(imported)

    local roll = nil
    if interest.category == "tmog" then
      roll = math.random(0, 100)
    end

    local role = imported and imported.role or "dps"

    table.insert(candidates, {
      name = name,
      class = interest.class,
      category = interest.category,
      note = interest.note,
      score = roll or score,
      roll = roll,
      breakdown = (not roll) and breakdown or nil,
      warnings = warnings,
      rank = imported and imported.rank or "trial",
      role = role,
      equippedIlvl = interest.equippedIlvl,
      tierCount = interest.tierCount,
      ilvlDiff = (session.ilvl or 0) - (interest.equippedIlvl or 0),
    })
  end

  local catOrder = { upgrade = 1, catalyst = 2, offspec = 3, tmog = 4 }
  -- roleTier: dps always above tank/healer within same category
  local roleTier = { dps = 1, tank = 2, healer = 2 }

  table.sort(candidates, function(a, b)
    local ca, cb = catOrder[a.category] or 99, catOrder[b.category] or 99
    if ca ~= cb then return ca < cb end
    local ra, rb = roleTier[a.role] or 2, roleTier[b.role] or 2
    if ra ~= rb then return ra < rb end
    return a.score > b.score
  end)

  return candidates
end
```

- [ ] **Step 2: Show role label in RankingFrame**

Find where candidate rows are built in `UI/RankingFrame.lua`. After the player name, add a small role label. Search for where `c.name` is displayed in the ranking rows, and add:

```lua
-- Role label (shown after name)
local roleColors = { dps = "|cffff4444", tank = "|cff4488ff", healer = "|cff44ff88" }
local roleLabel = (roleColors[c.role] or "") .. (c.role or "dps") .. "|r"
-- Append to name display or add as a separate small fontstring
```

- [ ] **Step 3: Verify in-game**

Run `/nordlc test`. Open the ranking wizard. All DPS candidates should appear above any Tank/Healer candidate within the same category (upgrade block), regardless of score. Within DPS, higher score ranks first.

- [ ] **Step 4: Commit**

```bash
git add NordavindLC/Council.lua NordavindLC/UI/RankingFrame.lua
git commit -m "feat: DPS always ranks above tank/healer in loot council"
```

---

### Task 2: LootThisWeek — Persistent Weekly Tracking

**Files:**
- Modify: `NordavindLC/Core.lua`
- Modify: `NordavindLC/Council.lua`
- Modify: `NordavindLC/Scoring.lua`

- [ ] **Step 1: Add `weeklyLoot` to DB init in `Core.lua`**

In the `ADDON_LOADED` block where `NordavindLC_DB` is initialized (around line 27), add `weeklyLoot`:

```lua
NordavindLC_DB = NordavindLC_DB or {
  importData = { players = {} },
  lootHistory = {},
  config = { officers = {}, timer = 90 },
  pendingExport = {},
  pendingTrades = {},
  weeklyLoot = { resetTimestamp = 0, counts = {} },
}
NordavindLC_DB.weeklyLoot = NordavindLC_DB.weeklyLoot or { resetTimestamp = 0, counts = {} }
```

- [ ] **Step 2: Add Wednesday reset helper and check in `Core.lua`**

Add this helper function just before `NLC.CheckOfficer()`:

```lua
local function GetLastWednesdayResetUTC()
  -- Epoch (Jan 1 1970) was Thursday. First Wednesday = Jan 7 1970 = day 6.
  -- EU WoW reset = Wednesday 09:00 UTC
  local FIRST_RESET = 6 * 86400 + 9 * 3600  -- 550800
  local WEEK = 7 * 86400
  local now = time()
  local weeksSince = math.floor((now - FIRST_RESET) / WEEK)
  return FIRST_RESET + weeksSince * WEEK
end
```

Then in the `PLAYER_ENTERING_WORLD` event handler, add a reset check after the existing IsInRaid logic:

```lua
-- Weekly loot reset check (Wednesday 09:00 UTC)
local lastReset = GetLastWednesdayResetUTC()
if NLC.db.weeklyLoot.resetTimestamp < lastReset then
  NLC.db.weeklyLoot.counts = {}
  NLC.db.weeklyLoot.resetTimestamp = lastReset
  NLC.Utils.Print("Ukentlig loot-teller nullstilt.")
end
```

- [ ] **Step 3: Update `Council.lua` to use `weeklyLoot.counts`**

In `Council.lua`, find the award block that mutates importData (around line 270-274). Replace:

```lua
local imported = NLC.Scoring.GetImportedScore(playerName)
if imported then
  imported.lootThisWeek = (imported.lootThisWeek or 0) + 1
  imported.baseScore = (imported.baseScore or 0) - 15
end
```

With:

```lua
-- Track weekly loot count in SavedVariables (resets each Wednesday)
NLC.db.weeklyLoot = NLC.db.weeklyLoot or { resetTimestamp = 0, counts = {} }
NLC.db.weeklyLoot.counts[playerName] = (NLC.db.weeklyLoot.counts[playerName] or 0) + 1
```

- [ ] **Step 4: Update `Scoring.lua` warnings to use `weeklyLoot.counts`**

In `GetWarnings`, replace the `lootThisWeek` check:

```lua
function NLC.Scoring.GetWarnings(imported, playerName)
  local warnings = {}
  if not imported then
    table.insert(warnings, "No web data")
    return warnings
  end
  if imported.attendance and imported.attendance < 80 then
    table.insert(warnings, string.format("Low attendance: %d%%", imported.attendance))
  end
  if imported.wclParse and imported.wclParse < 25 then
    table.insert(warnings, string.format("Low parse: %d", imported.wclParse))
  end
  if imported.defensives and imported.defensives < 0.8 then
    table.insert(warnings, string.format("Low defensives: %.1f/fight", imported.defensives))
  end
  -- Use persisted weekly count instead of ephemeral importData field
  local weeklyCount = NLC.db.weeklyLoot and NLC.db.weeklyLoot.counts and
    NLC.db.weeklyLoot.counts[playerName] or imported.lootThisWeek or 0
  if weeklyCount > 0 then
    table.insert(warnings, string.format("%d loot denne uka", weeklyCount))
  end
  if imported.rank == "trial" then
    table.insert(warnings, "Trial")
  elseif imported.rank == "backup" then
    table.insert(warnings, "Backup")
  end
  return warnings
end
```

- [ ] **Step 5: Fix callers of `GetWarnings` — add `playerName` argument**

Search for all calls to `NLC.Scoring.GetWarnings(` in the codebase:

```bash
grep -rn "GetWarnings" NordavindLC/
```

Each call like `NLC.Scoring.GetWarnings(imported)` must become `NLC.Scoring.GetWarnings(imported, playerName)`. Find where `playerName` is available in context (it will be in the ranking/council loop) and pass it through.

- [ ] **Step 6: Verify in-game**

Award an item via `/nordlc test`. Check that the awarded player now shows "1 loot denne uka" in the council ranking. Run `/reload` — the count should persist. Run `/nordlc status` to confirm the addon is still active.

- [ ] **Step 7: Commit**

```bash
git add NordavindLC/Core.lua NordavindLC/Council.lua NordavindLC/Scoring.lua
git commit -m "feat: persist weekly loot counts in SavedVariables with Wednesday auto-reset"
```

---

### Task 3: Create HistoryFrame.lua with Shared Edit Popup

**Files:**
- Create: `NordavindLC/UI/HistoryFrame.lua`
- Modify: `NordavindLC/NordavindLC.toc`

- [ ] **Step 1: Add `UI/HistoryFrame.lua` to TOC**

In `NordavindLC.toc`, add the new file after `UI/TradeFrame.lua`:

```
UI/TradeFrame.lua
UI/HistoryFrame.lua
```

- [ ] **Step 2: Create `UI/HistoryFrame.lua` with namespace and edit popup**

Create the file with the shared edit popup. The popup is pre-filled with current values, has a text input for player name and a dropdown for category:

```lua
-- UI/HistoryFrame.lua
-- Award history browser + shared edit popup for TradeFrame and HistoryFrame.

local NLC = NordavindLC_NS
local T = NLC.Theme

NLC.History = NLC.History or {}

local CATEGORIES = { "upgrade", "catalyst", "offspec", "tmog" }
local editPopup = nil
local historyFrame = nil
local HISTORY_ROW_HEIGHT = 44
local HISTORY_WIDTH = 580

-- ============================================================
-- SHARED EDIT POPUP
-- ============================================================

-- NLC.UI.ShowEditPopup(entry, onSave)
-- entry: { item, itemId, awardedTo, category, ... }
-- onSave: function(newRecipient, newCategory) called when user clicks Lagre
function NLC.UI.ShowEditPopup(entry, onSave)
  if not editPopup then
    editPopup = CreateFrame("Frame", "NordavindLCEditPopup", UIParent, "BackdropTemplate")
    editPopup:SetSize(360, 200)
    editPopup:SetPoint("CENTER")
    editPopup:SetMovable(true)
    editPopup:EnableMouse(true)
    editPopup:RegisterForDrag("LeftButton")
    editPopup:SetScript("OnDragStart", editPopup.StartMoving)
    editPopup:SetScript("OnDragStop", editPopup.StopMovingOrSizing)
    editPopup:SetFrameStrata("DIALOG")
    T.SetBackdrop(editPopup)

    -- Title
    local title = editPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(T.GOLD_LIGHT .. "Endre Award|r")

    -- Recipient label + input
    local recipLabel = editPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recipLabel:SetPoint("TOPLEFT", 16, -52)
    recipLabel:SetText(T.MUTED .. "Mottaker:|r")

    local recipInput = CreateFrame("EditBox", "NordavindLCEditRecip", editPopup, "InputBoxTemplate")
    recipInput:SetSize(200, 28)
    recipInput:SetPoint("TOPLEFT", 16, -68)
    recipInput:SetAutoFocus(false)
    editPopup.recipInput = recipInput

    -- Category label + dropdown
    local catLabel = editPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    catLabel:SetPoint("TOPLEFT", 16, -108)
    catLabel:SetText(T.MUTED .. "Kategori:|r")

    local catDropdown = CreateFrame("Frame", "NordavindLCEditCatDropdown", editPopup, "UIDropDownMenuTemplate")
    catDropdown:SetPoint("TOPLEFT", 4, -120)
    editPopup.catDropdown = catDropdown
    editPopup.selectedCategory = "upgrade"

    -- Lagre button
    local saveBtn = T.CreateButton(editPopup, 90, 32, T.GREEN .. "Lagre|r")
    saveBtn:SetPoint("BOTTOMLEFT", 16, 16)
    editPopup.saveBtn = saveBtn

    -- Avbryt button
    local cancelBtn = T.CreateButton(editPopup, 90, 32, T.MUTED .. "Avbryt|r")
    cancelBtn:SetPoint("BOTTOMLEFT", 116, 16)
    cancelBtn:SetScript("OnClick", function() editPopup:Hide() end)
  end

  -- Pre-fill values
  editPopup.recipInput:SetText(entry.awardedTo or "")
  editPopup.selectedCategory = entry.category or "upgrade"

  -- Build category dropdown
  UIDropDownMenu_SetWidth(editPopup.catDropdown, 150)
  UIDropDownMenu_SetText(editPopup.catDropdown, editPopup.selectedCategory)
  UIDropDownMenu_Initialize(editPopup.catDropdown, function(self, level)
    for _, cat in ipairs(CATEGORIES) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = cat
      info.value = cat
      info.func = function()
        editPopup.selectedCategory = cat
        UIDropDownMenu_SetText(editPopup.catDropdown, cat)
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  -- Wire save button with current onSave callback
  editPopup.saveBtn:SetScript("OnClick", function()
    local newRecipient = editPopup.recipInput:GetText():match("^%s*(.-)%s*$")
    local newCategory = editPopup.selectedCategory
    if newRecipient and newRecipient ~= "" then
      onSave(newRecipient, newCategory)
      editPopup:Hide()
    else
      NLC.Utils.Print("Skriv inn et spillernavn.")
    end
  end)

  editPopup:Show()
  editPopup.recipInput:SetFocus()
end
```

- [ ] **Step 3: Verify TOC loads without error**

Open WoW and type `/reload`. Check chat for any Lua errors. If `NordavindLC_NS` namespace errors appear, make sure `Utils.lua` initializes `NLC.History = {}` — add it there if needed.

- [ ] **Step 4: Commit**

```bash
git add NordavindLC/UI/HistoryFrame.lua NordavindLC/NordavindLC.toc
git commit -m "feat: add HistoryFrame.lua with shared edit popup"
```

---

### Task 4: History Frame — Award List with Edit/Delete

**Files:**
- Modify: `NordavindLC/UI/HistoryFrame.lua`

- [ ] **Step 1: Add the shared edit save logic as a helper**

At the top of `HistoryFrame.lua` (after the namespace line), add the helper that applies edits to all three stores:

```lua
-- Apply an award edit to lootHistory, pendingExport, and pendingTrades
local function ApplyAwardEdit(entry, newRecipient, newCategory)
  local oldRecipient = entry.awardedTo

  -- Update lootHistory
  for _, h in ipairs(NLC.db.lootHistory or {}) do
    if h.timestamp == entry.timestamp and h.item == entry.item then
      h.awardedTo = newRecipient
      h.category = newCategory
      break
    end
  end

  -- Update pendingExport
  for _, e in ipairs(NLC.db.pendingExport or {}) do
    if e.timestamp == entry.timestamp and e.item == entry.item then
      e.awardedTo = newRecipient
      e.category = newCategory
      break
    end
  end

  -- Update pendingTrades (matched by itemId + old recipient)
  for _, t in ipairs(NLC.db.pendingTrades or {}) do
    if t.itemId == entry.itemId and t.awardedTo == oldRecipient then
      t.awardedTo = newRecipient
      t.category = newCategory
      break
    end
  end
end
NLC.History.ApplyAwardEdit = ApplyAwardEdit
```

- [ ] **Step 2: Add `ShowHistoryFrame` to `HistoryFrame.lua`**

Append this function to the bottom of `HistoryFrame.lua`:

```lua
-- ============================================================
-- HISTORY FRAME
-- ============================================================

local function refreshHistoryFrame()
  if not historyFrame or not historyFrame:IsShown() then return end

  for _, child in ipairs({ historyFrame.content:GetChildren() }) do child:Hide() end
  for _, region in ipairs({ historyFrame.content:GetRegions() }) do region:Hide() end

  local history = NLC.db.lootHistory or {}
  local count = #history

  if count == 0 then
    historyFrame:SetHeight(120)
    local empty = historyFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetText(T.MUTED .. "Ingen awards registrert.|r")
    empty:Show()
    return
  end

  historyFrame:SetHeight(math.min(120 + count * HISTORY_ROW_HEIGHT, 500))
  historyFrame.content:SetHeight(count * HISTORY_ROW_HEIGHT)

  -- Show newest first
  for i = count, 1, -1 do
    local entry = history[i]
    local rowIdx = count - i + 1

    local rowBg = historyFrame.content:CreateTexture(nil, "BACKGROUND")
    rowBg:SetPoint("TOPLEFT", 0, -(rowIdx - 1) * HISTORY_ROW_HEIGHT)
    rowBg:SetSize(HISTORY_WIDTH - 40, HISTORY_ROW_HEIGHT)
    rowBg:SetColorTexture(1, 1, 1, rowIdx % 2 == 0 and 0.04 or 0)
    rowBg:Show()

    local row = CreateFrame("Frame", nil, historyFrame.content)
    row:SetSize(HISTORY_WIDTH - 40, HISTORY_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(rowIdx - 1) * HISTORY_ROW_HEIGHT)
    row:Show()

    -- Item link
    local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemText:SetPoint("LEFT", 12, 8)
    itemText:SetWidth(260)
    itemText:SetJustifyH("LEFT")
    itemText:SetText(entry.item or "?")
    itemText:Show()

    -- Recipient + category
    local toText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toText:SetPoint("LEFT", 12, -10)
    local dateStr = entry.timestamp and date("%d.%m %H:%M", entry.timestamp) or "?"
    toText:SetText(T.MUTED .. "Til:|r " .. (entry.awardedTo or "?") ..
      "  " .. T.MUTED .. "(" .. (entry.category or "?") .. ")  " .. dateStr .. "|r")
    toText:Show()

    -- Endre button
    local editBtn = T.CreateButton(row, 70, 26, T.GOLD .. "Endre|r")
    editBtn:SetPoint("RIGHT", -12, 0)
    local capturedEntry = entry
    editBtn:SetScript("OnClick", function()
      NLC.UI.ShowEditPopup(capturedEntry, function(newRecipient, newCategory)
        ApplyAwardEdit(capturedEntry, newRecipient, newCategory)
        capturedEntry.awardedTo = newRecipient
        capturedEntry.category = newCategory
        refreshHistoryFrame()
      end)
    end)

    -- Slett button
    local deleteBtn = T.CreateButton(row, 60, 26, "|cffff4444Slett|r")
    deleteBtn:SetPoint("RIGHT", -88, 0)
    deleteBtn:SetScript("OnClick", function()
      -- Remove from all three stores by timestamp + item
      for j = #NLC.db.lootHistory, 1, -1 do
        local h = NLC.db.lootHistory[j]
        if h.timestamp == entry.timestamp and h.item == entry.item then
          table.remove(NLC.db.lootHistory, j); break
        end
      end
      for j = #(NLC.db.pendingExport or {}), 1, -1 do
        local e = NLC.db.pendingExport[j]
        if e.timestamp == entry.timestamp and e.item == entry.item then
          table.remove(NLC.db.pendingExport, j); break
        end
      end
      for j = #(NLC.db.pendingTrades or {}), 1, -1 do
        local t = NLC.db.pendingTrades[j]
        if t.itemId == entry.itemId and t.awardedTo == entry.awardedTo then
          table.remove(NLC.db.pendingTrades, j); break
        end
      end
      refreshHistoryFrame()
    end)
  end
end

function NLC.UI.ShowHistoryFrame()
  if not NLC.isOfficer then return end

  if not historyFrame then
    historyFrame = CreateFrame("Frame", "NordavindLCHistoryFrame", UIParent, "BackdropTemplate")
    historyFrame:SetSize(HISTORY_WIDTH, 300)
    historyFrame:SetPoint("CENTER")
    historyFrame:SetMovable(true)
    historyFrame:EnableMouse(true)
    historyFrame:RegisterForDrag("LeftButton")
    historyFrame:SetScript("OnDragStart", historyFrame.StartMoving)
    historyFrame:SetScript("OnDragStop", historyFrame.StopMovingOrSizing)
    T.SetBackdrop(historyFrame)

    -- Title
    local title = historyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(T.GOLD_LIGHT .. "Award Historikk|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, historyFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() historyFrame:Hide() end)

    -- Scroll frame
    local scroll = CreateFrame("ScrollFrame", nil, historyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -44)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(HISTORY_WIDTH - 40, 1)
    scroll:SetScrollChild(content)
    historyFrame.content = content
  end

  historyFrame:Show()
  refreshHistoryFrame()
end
```

- [ ] **Step 3: Verify in-game**

Run `/nordlc testloot`, start council, award an item. Then run `/nordlc history` (won't work yet — added in Task 6, but you can call `NLC.UI.ShowHistoryFrame()` from the chat via a macro to test early). The history frame should show the awarded item with Endre and Slett buttons.

- [ ] **Step 4: Commit**

```bash
git add NordavindLC/UI/HistoryFrame.lua
git commit -m "feat: add award history frame with edit and delete"
```

---

### Task 5: Endre Button in TradeFrame

**Files:**
- Modify: `NordavindLC/UI/TradeFrame.lua`

- [ ] **Step 1: Add Endre button to each row in `refreshTradeFrame`**

In `TradeFrame.lua`, find the row-building loop (around line 168). After the Trade button block, add an Endre button. The Trade button is at `RIGHT -12`, Remove (X) at `RIGHT -96`. Add Endre at `RIGHT -124`:

Replace the existing button layout block:

```lua
-- Trade button
local tradeBtn = T.CreateButton(row, 80, 32, T.GREEN .. "Trade|r")
tradeBtn:SetPoint("RIGHT", -12, 0)
tradeBtn:SetScript("OnClick", function()
  InitiateTradeWith(entry.awardedTo, entry.itemId)
end)

-- Remove button (X) — manually mark as done
local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
removeBtn:SetSize(22, 22)
removeBtn:SetPoint("RIGHT", -96, 0)
removeBtn:SetScript("OnClick", function()
  NLC.Trade.Remove(i)
  refreshTradeFrame()
end)
```

With:

```lua
-- Trade button
local tradeBtn = T.CreateButton(row, 80, 32, T.GREEN .. "Trade|r")
tradeBtn:SetPoint("RIGHT", -12, 0)
tradeBtn:SetScript("OnClick", function()
  InitiateTradeWith(entry.awardedTo, entry.itemId)
end)

-- Endre button
local editBtn = T.CreateButton(row, 70, 26, T.GOLD .. "Endre|r")
editBtn:SetPoint("RIGHT", -98, 0)
local capturedEntry = entry
local capturedIdx = i
editBtn:SetScript("OnClick", function()
  NLC.UI.ShowEditPopup(capturedEntry, function(newRecipient, newCategory)
    NLC.History.ApplyAwardEdit(capturedEntry, newRecipient, newCategory)
    capturedEntry.awardedTo = newRecipient
    capturedEntry.category = newCategory
    refreshTradeFrame()
  end)
end)

-- Remove button (X) — manually mark as done
local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
removeBtn:SetSize(22, 22)
removeBtn:SetPoint("RIGHT", -174, 0)
removeBtn:SetScript("OnClick", function()
  NLC.Trade.Remove(capturedIdx)
  refreshTradeFrame()
end)
```

- [ ] **Step 2: Verify in-game**

Run `/nordlc testloot`, award an item, then open `/nordlc trade`. Each row should now have a gold "Endre" button. Click it — the edit popup should appear pre-filled with the recipient's name and category. Change the name, click Lagre — the row should update.

- [ ] **Step 3: Commit**

```bash
git add NordavindLC/UI/TradeFrame.lua
git commit -m "feat: add Endre button to TradeFrame rows"
```

---

### Task 6: Wire `/nordlc history` Slash Command

**Files:**
- Modify: `NordavindLC/Core.lua`

- [ ] **Step 1: Add `history` command to slash handler in `Core.lua`**

In the slash command handler (`SlashCmdList["NORDLC"]`), find the `elseif cmd == "trade" then` block and add history after it:

```lua
elseif cmd == "trade" then
  NLC.UI.ShowTradeFrame()

elseif cmd == "history" then
  NLC.UI.ShowHistoryFrame()
```

Also add it to the help text at the bottom of the handler:

```lua
NLC.Utils.Print("  /nordlc history — Vis og rediger award-historikk")
```

- [ ] **Step 2: Verify full flow in-game**

1. `/nordlc testloot` → award an item
2. `/nordlc history` → history frame opens, shows the award
3. Click Endre → popup pre-filled → change recipient → Lagre → row updates
4. Click Slett → row disappears
5. `/nordlc trade` → Endre button visible → works same way
6. `/reload` → `/nordlc history` → edits persisted

- [ ] **Step 3: Commit**

```bash
git add NordavindLC/Core.lua
git commit -m "feat: add /nordlc history slash command"
```

---

### Task 7: Database Sync — Edit Awards via Companion App and Web API

**Files:**
- Modify: `NordavindLC/Core.lua` (init `pendingEdits` in DB)
- Modify: `NordavindLC/UI/HistoryFrame.lua` (queue edits to `pendingEdits`)
- Modify: `nordavind-addon/companion/lib/watcher.js` (detect pendingEdits)
- Modify: `nordavind-addon/companion/lib/api-client.js` (add editAward method)
- Modify: `nordavind-addon/companion/index.js` (process edits on interval)
- Modify: `nordavind-web/app/api/loot/addon/route.ts` (add PATCH handler)

- [ ] **Step 1: Init `pendingEdits` in DB (`Core.lua`)**

In the `ADDON_LOADED` block, add `pendingEdits` to the DB init (same place as `pendingExport`):

```lua
NordavindLC_DB = NordavindLC_DB or {
  importData = { players = {} },
  lootHistory = {},
  config = { officers = {}, timer = 90 },
  pendingExport = {},
  pendingTrades = {},
  weeklyLoot = { resetTimestamp = 0, counts = {} },
  pendingEdits = {},
}
NordavindLC_DB.pendingEdits = NordavindLC_DB.pendingEdits or {}
```

- [ ] **Step 2: Queue edits to `pendingEdits` in `ApplyAwardEdit` (`HistoryFrame.lua`)**

Update the `ApplyAwardEdit` helper to also push to `pendingEdits`:

```lua
local function ApplyAwardEdit(entry, newRecipient, newCategory)
  local oldRecipient = entry.awardedTo

  -- Update lootHistory
  for _, h in ipairs(NLC.db.lootHistory or {}) do
    if h.timestamp == entry.timestamp and h.item == entry.item then
      h.awardedTo = newRecipient
      h.category = newCategory
      break
    end
  end

  -- Update pendingExport
  for _, e in ipairs(NLC.db.pendingExport or {}) do
    if e.timestamp == entry.timestamp and e.item == entry.item then
      e.awardedTo = newRecipient
      e.category = newCategory
      break
    end
  end

  -- Update pendingTrades
  for _, t in ipairs(NLC.db.pendingTrades or {}) do
    if t.itemId == entry.itemId and t.awardedTo == oldRecipient then
      t.awardedTo = newRecipient
      t.category = newCategory
      break
    end
  end

  -- Queue edit for companion app → database sync
  NLC.db.pendingEdits = NLC.db.pendingEdits or {}
  table.insert(NLC.db.pendingEdits, {
    originalTimestamp = entry.timestamp,
    item = entry.item,
    newAwardedTo = newRecipient,
    newCategory = newCategory,
  })
end
NLC.History.ApplyAwardEdit = ApplyAwardEdit
```

- [ ] **Step 3: Add `editAward()` to ApiClient (`companion/lib/api-client.js`)**

```js
async editAward({ originalTimestamp, item, newAwardedTo, newCategory }) {
  const res = await fetch(`${this.baseUrl}/api/loot/addon`, {
    method: "PATCH",
    headers: { "x-api-key": this.apiKey, "Content-Type": "application/json", "Host": "nordavind.cc" },
    body: JSON.stringify({ originalTimestamp, item, newAwardedTo, newCategory }),
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) throw new Error(`Edit failed: ${res.status} ${await res.text()}`);
  return res.json();
}
```

- [ ] **Step 4: Add `checkPendingEdits()` to watcher (`companion/lib/watcher.js`)**

Add alongside `checkPendingExports()`:

```js
checkPendingEdits() {
  const stat = fs.statSync(this.svPath, { throwIfNoEntry: false });
  if (!stat) return [];

  const mtime = stat.mtimeMs;
  if (mtime <= this.lastEditMtime) return [];
  this.lastEditMtime = mtime;

  const vars = this.read();
  const db = vars?.NordavindLC_DB;
  if (!db?.pendingEdits) return [];

  const edits = Array.isArray(db.pendingEdits) ? db.pendingEdits : Object.values(db.pendingEdits);
  if (edits.length <= this.lastEditCount) return [];

  const newEdits = edits.slice(this.lastEditCount);
  this.lastEditCount = edits.length;
  return newEdits;
}
```

Also add `this.lastEditMtime = 0` and `this.lastEditCount = 0` to the constructor.

- [ ] **Step 5: Process edits in `companion/index.js`**

Add a `processEdits` function and register it on the same 5s interval as `processExports`:

```js
async function processEdits() {
  try {
    const edits = watcher.checkPendingEdits();
    for (const edit of edits) {
      try {
        await api.editAward(edit);
        console.log(`[edit] Synced: ${edit.item} -> ${edit.newAwardedTo}`);
      } catch (err) {
        console.error(`[edit] Failed: ${edit.item} ->`, err.message);
      }
    }
  } catch { /* file not found yet */ }
}
```

Then in the startup block, add:
```js
setInterval(() => processEdits(), 5000);
```

- [ ] **Step 6: Add PATCH handler to web API (`nordavind-web/app/api/loot/addon/route.ts`)**

Append a `PATCH` export to the existing file:

```ts
export async function PATCH(req: NextRequest) {
  const apiKey = req.headers.get("x-api-key");
  if (!apiKey || apiKey !== process.env.ADDON_API_KEY) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: {
    originalTimestamp?: number;
    item?: string;
    newAwardedTo?: string;
    newCategory?: string;
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const { originalTimestamp, item, newAwardedTo } = body;
  if (!originalTimestamp || !item || !newAwardedTo) {
    return NextResponse.json(
      { error: "Missing required fields: originalTimestamp, item, newAwardedTo" },
      { status: 400 }
    );
  }

  // Look up new recipient's discordId by character name
  const recipientUser = await prisma.user.findFirst({
    where: {
      characters: {
        some: { name: { equals: newAwardedTo, mode: "insensitive" } },
      },
    },
  });
  if (!recipientUser) {
    return NextResponse.json(
      { error: `Character not found: ${newAwardedTo}` },
      { status: 404 }
    );
  }

  // Find existing LootDrop by timestamp (±5s tolerance)
  const createdAt = new Date(originalTimestamp * 1000);
  const lootDrop = await prisma.lootDrop.findFirst({
    where: {
      item,
      createdAt: {
        gte: new Date(createdAt.getTime() - 5000),
        lte: new Date(createdAt.getTime() + 5000),
      },
    },
  });

  if (!lootDrop) {
    return NextResponse.json({ error: "LootDrop not found" }, { status: 404 });
  }

  await prisma.lootDrop.update({
    where: { id: lootDrop.id },
    data: { givenTo: recipientUser.discordId },
  });

  return NextResponse.json({ ok: true, lootDropId: lootDrop.id });
}
```

- [ ] **Step 7: Verify full sync**

1. Award an item in WoW (`/nordlc testloot`)
2. Wait for companion to sync (5s)
3. Open `/nordlc history`, change recipient, click Lagre
4. Wait 5s — companion should log `[edit] Synced: ...`
5. Check nordavind.cc loot history — recipient should be updated

---

### Task 8: Wishlist Filter — Ekskluder spillere uten wishlist-item

Upgrade-kandidater som ikke har wishlistet itemet på WoWAudit vises ikke i rangeringen.

**Files:**
- Modify: `nordavind-web/lib/scoring.ts` (parse wishlist fra WoWAudit)
- Modify: `nordavind-web/app/api/loot/addon-export/route.ts` (eksporter wishlist per spiller)
- Modify: `NordavindLC/Council.lua` (filtrer upgrade-kandidater mot wishlist)

- [ ] **Step 1: Verifiser WoWAudit API-format for wishlist**

Logg WoWAudit-responsen midlertidig for å se eksakt format. I `nordavind-web/lib/scoring.ts`, legg til midlertidig logging i `fetchRoster()`:

```ts
export async function fetchRoster(): Promise<any[]> {
  const res = await fetch("https://wowaudit.com/v1/characters", {
    headers: { Authorization: WOWAUDIT_API_KEY, Accept: "application/json" },
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) throw new Error("WowAudit API error");
  const data = await res.json();
  // TEMP: log first character to see wishlist format
  if (data[0]) console.log("[wowaudit-debug] first char keys:", Object.keys(data[0]));
  if (data[0]?.wishlist) console.log("[wowaudit-debug] wishlist sample:", JSON.stringify(data[0].wishlist).slice(0, 500));
  return data;
}
```

Kjør `/api/scores/calculate` og se server-loggene. Noter eksakt format på wishlist-feltet. Fjern logging når formatet er bekreftet.

- [ ] **Step 2: Legg til `wishlist` i `PlayerScoreData` og scoring-eksport**

Etter at wishlist-formatet er bekreftet, oppdater `PlayerScoreData`-interfacet i `scoring.ts`:

```ts
export interface PlayerScoreData {
  // ... eksisterende felt ...
  wishlist: number[]; // item IDs
}
```

I `calculateAllScores`, hent wishlist-IDs fra WoWAudit-dataen per karakter. WoWAudit returnerer typisk:
```ts
// Tilpass basert på faktisk format funnet i Step 1
const wishlist: number[] = (char.wishlist || []).map((w: any) => w.item_id || w.id || w).filter(Number.isInteger);
```

Legg til `wishlist` i `results.push(...)` for begge modes (full og live).

- [ ] **Step 3: Inkluder wishlist i `saveScores` og Prisma-schema**

Legg til `wishlist` som `Int[]`-felt i Prisma-schema (`nordavind-web/prisma/schema.prisma`):

```prisma
model PlayerScore {
  // ... eksisterende felt ...
  wishlist      Int[]    @default([])
}
```

Kjør migrering:

```bash
cd nordavind-web
npx prisma migrate dev --name add_wishlist_to_player_score
```

Oppdater `saveScores()` i `scoring.ts` til å inkludere `wishlist` i upsert.

- [ ] **Step 4: Eksporter wishlist i addon-export API**

I `nordavind-web/app/api/loot/addon-export/route.ts`, legg til `wishlist` i player-objektet:

```ts
players[s.playerName] = {
  // ... eksisterende felt ...
  wishlist: s.wishlist || [],
};
```

- [ ] **Step 5: Filtrer upgrade-kandidater i addon (`Council.lua`)**

I `BuildRanking`, etter `GetImportedScore`, ekskluder upgrade-kandidater uten wishlist-match:

```lua
for name, interest in pairs(session.interests) do
  local imported = NLC.Scoring.GetImportedScore(name)

  -- For upgrade: skip if item not on wishlist
  if interest.category == "upgrade" then
    local wishlisted = false
    local wishlist = imported and imported.wishlist or {}
    for _, wid in ipairs(wishlist) do
      if wid == session.itemId then
        wishlisted = true
        break
      end
    end
    if not wishlisted then goto continue end
  end

  -- ... resten av kandidat-bygging ...
  ::continue::
end
```

- [ ] **Step 6: Verifiser i-game**

1. Kjør `/api/scores/calculate` på web for å oppdatere wishlist-data
2. Importer til addon via companion
3. Start `/nordlc test` — kun spillere som har det aktuelle itemet wishlisted skal dukke opp under Upgrade

- [ ] **Step 7: Commit**

```bash
# Web
cd nordavind-web
git add prisma/schema.prisma prisma/migrations/ lib/scoring.ts app/api/loot/addon-export/route.ts
git commit -m "feat: include WoWAudit wishlist in addon export"

# Addon
cd nordavind-addon
git add NordavindLC/Council.lua
git commit -m "feat: filter upgrade candidates by WoWAudit wishlist"
```

---

### Task 9: Equipped Item i Ranking Frame

Vis hva spilleren har utstyrt i det aktuelle slottet, direkte i ranking-raden.

**Files:**
- Modify: `NordavindLC/UI/RankingFrame.lua`
- Modify: `NordavindLC/Utils.lua` (legg til equipLoc → slotId mapping)

- [ ] **Step 1: Legg til `EQUIPLOC_TO_SLOT`-mapping i `Utils.lua`**

Legg til på slutten av Utils.lua (etter de eksisterende mappingene):

```lua
NLC.Utils.EQUIPLOC_TO_SLOT = {
  INVTYPE_HEAD         = 1,
  INVTYPE_NECK         = 2,
  INVTYPE_SHOULDER     = 3,
  INVTYPE_CHEST        = 5,
  INVTYPE_ROBE         = 5,
  INVTYPE_WAIST        = 6,
  INVTYPE_LEGS         = 7,
  INVTYPE_FEET         = 8,
  INVTYPE_WRIST        = 9,
  INVTYPE_HAND         = 10,
  INVTYPE_FINGER       = 11,  -- sjekker begge ring-slots
  INVTYPE_TRINKET      = 13,  -- sjekker begge trinket-slots
  INVTYPE_CLOAK        = 15,
  INVTYPE_WEAPON       = 16,
  INVTYPE_2HWEAPON     = 16,
  INVTYPE_WEAPONMAINHAND = 16,
  INVTYPE_WEAPONOFFHAND  = 17,
  INVTYPE_SHIELD       = 17,
  INVTYPE_HOLDABLE     = 17,
}

-- Returns equipped item link for a raid member in the relevant slot
-- Returns nil if not in raid or slot not found
function NLC.Utils.GetEquippedItemForSlot(playerName, equipLoc)
  local slotId = NLC.Utils.EQUIPLOC_TO_SLOT[equipLoc]
  if not slotId then return nil end

  -- Find unit token for playerName
  for i = 1, GetNumGroupMembers() do
    local unit = "raid" .. i
    if UnitName(unit) == playerName then
      local link = GetInventoryItemLink(unit, slotId)
      -- For rings and trinkets, check both slots
      if not link and (equipLoc == "INVTYPE_FINGER") then
        link = GetInventoryItemLink(unit, 12)
      elseif not link and (equipLoc == "INVTYPE_TRINKET") then
        link = GetInventoryItemLink(unit, 14)
      end
      return link
    end
  end
  return nil
end
```

- [ ] **Step 2: Show equipped item in ranking row (`RankingFrame.lua`)**

In the candidate row loop in `ShowRanking` (around the area where `c.name`, `c.score`, `c.ilvlDiff` are displayed), add an equipped item section below each row.

Find the section where the `equippedIlvl` is shown (column `COL.ilvl`). After it, add a hover frame that shows the equipped item link as a tooltip:

```lua
-- Equipped item tooltip hover
local equippedLink = NLC.Utils.GetEquippedItemForSlot(c.name, session.equipLoc)
if equippedLink then
  local ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ilvlText:SetPoint("TOPLEFT", COL.ilvl, -2)
  ilvlText:SetText(T.MUTED .. (c.equippedIlvl or "?") .. "|r")

  -- Hover for equipped item tooltip
  local eqHover = CreateFrame("Frame", nil, row)
  eqHover:SetSize(80, ROW_HEIGHT)
  eqHover:SetPoint("TOPLEFT", COL.ilvl, 0)
  eqHover:EnableMouse(true)
  eqHover:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(equippedLink)
    GameTooltip:Show()
  end)
  eqHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
else
  -- No equipped item found — just show ilvl number
  local ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ilvlText:SetPoint("TOPLEFT", COL.ilvl, -2)
  ilvlText:SetText(T.MUTED .. (c.equippedIlvl or "?") .. "|r")
end
```

- [ ] **Step 3: Verify in-game**

Run `/nordlc test` in WoW during a raid. In the ranking frame, hover over the ilvl column for a candidate — the tooltip should show their currently equipped item in that slot. If not in a raid (test mode), only the ilvl number should show.

- [ ] **Step 4: Commit**

```bash
git add NordavindLC/Utils.lua NordavindLC/UI/RankingFrame.lua
git commit -m "feat: show equipped item tooltip in ranking frame"
```

---

- [ ] **Step 8: Commit all**

```bash
# Addon
cd nordavind-addon
git add NordavindLC/Core.lua NordavindLC/UI/HistoryFrame.lua
git add companion/lib/watcher.js companion/lib/api-client.js companion/index.js
git commit -m "feat: sync award edits to database via companion app"

# Web
cd nordavind-web
git add app/api/loot/addon/route.ts
git commit -m "feat: add PATCH /api/loot/addon to update existing loot drop"
```
