# Multi-Item Council Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-item-at-a-time council flow with a multi-item popup (raiders) and award wizard (officers), cutting boss loot time from 12-18 minutes to ~2 minutes.

**Architecture:** Council.lua manages a list of active sessions instead of a single session. Comms.lua sends/receives multi-item payloads. CouncilFrame.lua shows all items in one scrollable popup. RankingFrame.lua adds wizard navigation with auto-advance on award.

**Tech Stack:** WoW Lua API, AceComm addon messaging, existing NordavindLC theme system

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `NordavindLC/Comms.lua` | Modify | New SESSION_START, RESPOND message types; multi-item INTEREST parsing |
| `NordavindLC/Council.lua` | Modify | `StartMultiSession()`, `activeSessions[]`, auto-close tracking, wizard-aware `Award()` |
| `NordavindLC/UI/CouncilFrame.lua` | Rewrite | Multi-item popup replaces single-item popup; loot panel calls `StartMultiSession` |
| `NordavindLC/UI/RankingFrame.lua` | Modify | Wizard navigation (prev/next/progress), auto-advance on award, skip for no-interest |
| `NordavindLC/Core.lua` | Modify | Timer default to 90, test commands updated for multi-item, loot panel wiring |

Files NOT changing: `Utils.lua`, `Scoring.lua`, `LootDetection.lua`, `UI/Theme.lua`, `UI/ActivationPrompt.lua`

---

### Task 1: Update Comms Protocol

**Files:**
- Modify: `NordavindLC/Comms.lua`

This task adds the new message types needed for multi-item flow. No UI changes yet.

- [ ] **Step 1: Add SESSION_START message handler**

In `Comms.lua`, add a new message type `SESSION_START` that carries multiple items separated by `|`. Each item is `itemLink;itemId;ilvl;equipLoc` separated by `;`. The handler in `OnMessage` parses the payload into a list of item tables and calls `NLC.Council.OnMultiSessionStart()`.

```lua
-- In NLC.Comms.OnMessage, add this elseif block after the COUNCIL_CLOSE handler:

  elseif msgType == "SESSION_START" then
    local items = {}
    for itemData in data:gmatch("[^|]+") do
      local itemLink, itemId, ilvl, equipLoc, boss = itemData:match("^(.*);(%d+);(%d+);([^;]*);(.*)$")
      if itemLink then
        table.insert(items, {
          itemLink = itemLink,
          itemId = tonumber(itemId),
          ilvl = tonumber(ilvl),
          equipLoc = equipLoc,
          boss = boss,
        })
      end
    end
    local timer = 90
    if NLC.Council.OnMultiSessionStart then
      NLC.Council.OnMultiSessionStart(items, timer, sender)
    end
```

- [ ] **Step 2: Add RESPOND message handler**

This is a simple ping from raiders to signal they've submitted responses. Officer uses this for auto-close counting.

```lua
  elseif msgType == "RESPOND" then
    if NLC.Council.OnRespond then
      NLC.Council.OnRespond(sender)
    end
```

- [ ] **Step 3: Update INTEREST handler for multi-item format**

The new INTEREST payload is comma-separated entries: `itemId1:cat1:eqIlvl1:tier1:note1,itemId2:cat2:...`. Only items the raider selected (not Pass) are included.

Replace the existing INTEREST handler:

```lua
  elseif msgType == "INTEREST" then
    for entry in data:gmatch("[^,]+") do
      local itemId, category, eqIlvl, tierCount, note = entry:match("^(%d+):(%w+):(%d+):(%d+):?(.*)$")
      if itemId and NLC.Council.OnInterestReceived then
        NLC.Council.OnInterestReceived(sender, tonumber(itemId), category, tonumber(eqIlvl), tonumber(tierCount), note)
      end
    end
```

- [ ] **Step 4: Add SendMultiSession helper**

Add a new function that builds and sends the SESSION_START payload from a list of item tables:

```lua
function NLC.Comms.SendMultiSession(items, boss)
  if not IsInRaid() then return end
  local parts = {}
  for _, item in ipairs(items) do
    table.insert(parts, string.format("%s;%d;%d;%s;%s",
      item.itemLink, item.itemId or 0, item.ilvl or 0, item.equipLoc or "", boss or ""))
  end
  local payload = "SESSION_START:" .. table.concat(parts, "|")
  C_ChatInfo.SendAddonMessage(PREFIX, payload, "RAID")
end
```

- [ ] **Step 5: Add SendMultiInterest helper**

Add a function that sends all raider responses in one message:

```lua
function NLC.Comms.SendMultiInterest(responses)
  -- responses = { { itemId=123, category="upgrade", eqIlvl=626, tierCount=3, note="" }, ... }
  local parts = {}
  for _, r in ipairs(responses) do
    table.insert(parts, string.format("%d:%s:%d:%d:%s",
      r.itemId or 0, r.category, r.eqIlvl or 0, r.tierCount or 0, r.note or ""))
  end
  NLC.Comms.Send("INTEREST", table.concat(parts, ","))
end

function NLC.Comms.SendRespond()
  NLC.Comms.Send("RESPOND", "1")
end
```

- [ ] **Step 6: Commit**

```bash
git add NordavindLC/Comms.lua
git commit -m "feat: multi-item comms protocol (SESSION_START, RESPOND, multi-INTEREST)"
```

---

### Task 2: Update Council.lua for Multi-Session Logic

**Files:**
- Modify: `NordavindLC/Council.lua`

Replace single `activeSession` with `activeSessions` list. Add `StartMultiSession()`, auto-close tracking, and wizard-aware award.

- [ ] **Step 1: Replace activeSession with activeSessions and add state variables**

At the top of Council.lua, replace `local activeSession = nil` with:

```lua
local activeSessions = {}    -- list of session tables (one per item)
local currentWizardIndex = 0 -- which item officer is viewing in wizard
local respondents = {}       -- set of player names who have responded
local raidAddonUsers = 0     -- count of addon users in raid (for auto-close)
local collectingTimer = nil  -- C_Timer ticker reference
```

- [ ] **Step 2: Add StartMultiSession function**

This is the new entry point for boss loot. Creates a session per item and starts the shared timer.

```lua
function NLC.Council.StartMultiSession(items, boss)
  if not NLC.isOfficer then
    NLC.Utils.Print("Kun officers kan starte council.")
    return
  end

  activeSessions = {}
  respondents = {}
  raidAddonUsers = 0
  currentWizardIndex = 1

  for _, item in ipairs(items) do
    table.insert(activeSessions, {
      itemLink = item.itemLink,
      itemId = item.itemId,
      ilvl = item.ilvl,
      equipLoc = item.equipLoc,
      boss = boss or item.boss or "Unknown",
      timer = NLC.db.config.timer or 90,
      interests = {},
      phase = "collecting",
    })
  end

  -- Count addon users in raid (self counts)
  raidAddonUsers = GetNumGroupMembers()

  -- Send session start to raid
  NLC.Comms.SendMultiSession(items, boss or items[1].boss or "Unknown")
  NLC.Utils.Print("Council startet for " .. #items .. " items")

  -- Show multi-item popup for officer too
  NLC.UI.ShowMultiItemPopup(activeSessions, NLC.db.config.timer or 90)

  -- Start shared timer
  local remaining = NLC.db.config.timer or 90
  collectingTimer = C_Timer.NewTicker(1, function(ticker)
    remaining = remaining - 1
    if remaining <= 0 then
      ticker:Cancel()
      collectingTimer = nil
      NLC.Council.CloseCollecting()
    end
  end, remaining)
end
```

- [ ] **Step 3: Add OnMultiSessionStart (raider-side handler)**

Called on non-officer clients when they receive SESSION_START:

```lua
function NLC.Council.OnMultiSessionStart(items, timer, sender)
  activeSessions = {}
  for _, item in ipairs(items) do
    table.insert(activeSessions, {
      itemLink = item.itemLink,
      itemId = item.itemId,
      ilvl = item.ilvl,
      equipLoc = item.equipLoc,
      boss = item.boss or "Unknown",
      timer = timer,
      interests = {},
      phase = "collecting",
    })
  end
  NLC.UI.ShowMultiItemPopup(activeSessions, timer)
end
```

- [ ] **Step 4: Add SubmitResponses (raider sends all choices)**

Called by the multi-item popup's "Send" button:

```lua
function NLC.Council.SubmitResponses(selections)
  -- selections = { [itemId] = { category="upgrade", note="bis" }, ... }
  local responses = {}
  for _, session in ipairs(activeSessions) do
    local sel = selections[session.itemId]
    if sel and sel.category ~= "pass" then
      local eqLink, eqIlvl = NLC.Utils.GetEquippedInfo(session.equipLoc or "")
      local tierCount = NLC.Utils.GetTierCount()
      table.insert(responses, {
        itemId = session.itemId,
        category = sel.category,
        eqIlvl = eqIlvl or 0,
        tierCount = tierCount,
        note = sel.note or "",
      })
    end
  end
  if #responses > 0 then
    NLC.Comms.SendMultiInterest(responses)
  end
  NLC.Comms.SendRespond()
  NLC.Utils.Print("Svar sendt for " .. #responses .. " item(s)")
end
```

- [ ] **Step 5: Update OnInterestReceived to find correct session**

Replace the existing function. It now looks up the session by itemId:

```lua
function NLC.Council.OnInterestReceived(sender, itemId, category, eqIlvl, tierCount, note)
  if not NLC.isOfficer then return end

  local session = nil
  for _, s in ipairs(activeSessions) do
    if s.itemId == itemId then session = s; break end
  end
  if not session then return end

  local name = sender:match("^([^-]+)") or sender
  local _, class = UnitClass(name)

  session.interests[name] = {
    category = category,
    equippedIlvl = eqIlvl,
    tierCount = tierCount,
    class = class or "WARRIOR",
    note = (note and note ~= "") and note or nil,
  }
end
```

- [ ] **Step 6: Add OnRespond for auto-close tracking**

```lua
function NLC.Council.OnRespond(sender)
  if not NLC.isOfficer then return end
  local name = sender:match("^([^-]+)") or sender
  respondents[name] = true

  local count = 0
  for _ in pairs(respondents) do count = count + 1 end

  NLC.Utils.Print(count .. " / " .. raidAddonUsers .. " har svart")

  -- Auto-close if everyone has responded
  if count >= raidAddonUsers then
    if collectingTimer then
      collectingTimer:Cancel()
      collectingTimer = nil
    end
    NLC.Council.CloseCollecting()
  end
end
```

- [ ] **Step 7: Update CloseCollecting for multi-session**

Replace the existing function:

```lua
function NLC.Council.CloseCollecting()
  if #activeSessions == 0 then return end

  for _, session in ipairs(activeSessions) do
    session.phase = "ranking"
  end

  NLC.Comms.Send("SESSION_CLOSE", "")
  NLC.Utils.Print("Collecting lukket. Starter award wizard.")

  -- Build rankings for all items
  for _, session in ipairs(activeSessions) do
    session.ranked = NLC.Council.BuildRanking(session)
  end

  currentWizardIndex = 1
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
end
```

- [ ] **Step 8: Update Award for wizard flow**

Replace the existing function:

```lua
function NLC.Council.Award(playerName)
  if not NLC.isOfficer or #activeSessions == 0 then return end

  local session = activeSessions[currentWizardIndex]
  if not session then return end

  NLC.Comms.Send("AWARD", session.itemLink .. ":" .. playerName)
  NLC.RecordAward(session.itemLink, playerName, UnitName("player"), session.boss)
  NLC.Utils.Print(session.itemLink .. " tildelt " .. playerName)

  -- Live score update
  local imported = NLC.Scoring.GetImportedScore(playerName)
  if imported then
    imported.lootThisWeek = (imported.lootThisWeek or 0) + 1
    imported.baseScore = (imported.baseScore or 0) - 15
  end

  -- Announce to raid
  if IsInRaid() then
    SendChatMessage(session.itemLink .. " -> " .. playerName, "RAID_WARNING")
  end

  -- Re-rank remaining items (score changed)
  for i, s in ipairs(activeSessions) do
    if i ~= currentWizardIndex and s.phase == "ranking" then
      s.ranked = NLC.Council.BuildRanking(s)
    end
  end

  -- Mark this session done and advance wizard
  session.phase = "awarded"
  NLC.Council.AdvanceWizard()
end
```

- [ ] **Step 9: Add AdvanceWizard, AwardLaterCurrent, GetActiveSessions, GetWizardIndex**

```lua
function NLC.Council.AdvanceWizard()
  -- Find next un-awarded session
  for i = currentWizardIndex + 1, #activeSessions do
    if activeSessions[i].phase == "ranking" then
      currentWizardIndex = i
      NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      return
    end
  end
  -- No more items — wizard done
  NLC.Utils.Print("Alle items tildelt!")
  NLC.UI.HideWizard()
  activeSessions = {}
end

function NLC.Council.AwardLaterCurrent()
  if #activeSessions == 0 then return end
  local session = activeSessions[currentWizardIndex]
  if not session then return end

  table.insert(NLC.pendingSessions, session)
  NLC.Utils.Print(session.itemLink .. " lagt til ventende")
  NLC.UpdateMinimapCount()

  session.phase = "deferred"
  NLC.Council.AdvanceWizard()
end

function NLC.Council.SkipCurrent()
  if #activeSessions == 0 then return end
  activeSessions[currentWizardIndex].phase = "skipped"
  NLC.Council.AdvanceWizard()
end

function NLC.Council.GetActiveSessions()
  return activeSessions
end

function NLC.Council.GetWizardIndex()
  return currentWizardIndex
end

function NLC.Council.SetWizardIndex(idx)
  if idx >= 1 and idx <= #activeSessions and activeSessions[idx].phase == "ranking" then
    currentWizardIndex = idx
    NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
  end
end
```

- [ ] **Step 10: Keep StartSession for /nordlc add (single item)**

The existing `StartSession()` function should wrap the new multi-session logic so single items still work:

```lua
function NLC.Council.StartSession(itemLink, itemId, ilvl, equipLoc, boss)
  NLC.Council.StartMultiSession({
    { itemLink = itemLink, itemId = itemId, ilvl = ilvl, equipLoc = equipLoc, boss = boss },
  }, boss)
end
```

Remove the old `StartSession` body, `OnCouncilStart`, `AwardLater`, `GetActiveSession`, and `SendInterest` functions — they are replaced by the new multi-session equivalents.

- [ ] **Step 11: Commit**

```bash
git add NordavindLC/Council.lua
git commit -m "feat: multi-session council logic with wizard flow and auto-close"
```

---

### Task 3: Rewrite CouncilFrame.lua (Multi-Item Popup)

**Files:**
- Rewrite: `NordavindLC/UI/CouncilFrame.lua`

Replace the single-item interest popup with a scrollable multi-item frame. Keep the loot detected panel but wire it to `StartMultiSession`.

- [ ] **Step 1: Write the new multi-item popup**

Replace the entire `ShowInterestPopup` function and related code with `ShowMultiItemPopup`. The frame structure:

```lua
-- UI/CouncilFrame.lua
-- Multi-item interest popup (all raiders) + loot detected panel (officer)

local NLC = NordavindLC_NS
local T = NLC.Theme

-- ============================================================
-- MULTI-ITEM INTEREST POPUP
-- ============================================================
local multiFrame = nil
local itemRows = {}      -- { [itemId] = { buttons={}, noteBox=nil, selection=nil } }
local ITEM_ROW_HEIGHT = 100
local ITEM_ROW_WIDTH = 460

local function createItemRow(parent, index, item)
  local yOffset = -(index - 1) * ITEM_ROW_HEIGHT

  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(ITEM_ROW_WIDTH, ITEM_ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, yOffset)

  -- Alternating bg
  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)

  -- Item name + ilvl
  local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  itemText:SetPoint("TOPLEFT", 12, -8)
  itemText:SetWidth(ITEM_ROW_WIDTH - 24)
  itemText:SetJustifyH("LEFT")
  itemText:SetText((item.itemLink or "?") .. "  " .. T.MUTED .. "ilvl " .. (item.ilvl or 0) .. "|r")

  -- Equipped comparison
  local eqLink, eqIlvl = NLC.Utils.GetEquippedInfo(item.equipLoc or "")
  local eqText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  eqText:SetPoint("TOPLEFT", 12, -26)
  eqText:SetWidth(ITEM_ROW_WIDTH - 24)
  eqText:SetJustifyH("LEFT")
  if eqLink then
    local diff = (item.ilvl or 0) - eqIlvl
    local diffColor = diff > 0 and T.GREEN or T.RED
    eqText:SetText(T.MUTED .. "Equipped: |r" .. eqLink .. " " .. T.MUTED .. "(" .. eqIlvl .. ")|r  " .. diffColor .. (diff > 0 and "+" or "") .. diff .. "|r")
  else
    eqText:SetText(T.MUTED .. "Ingen item i slot|r")
  end

  -- Category buttons
  local categories = {
    { id = "upgrade",  label = T.GOLD_LIGHT .. "Upgrade|r", width = 110 },
    { id = "catalyst", label = "|cff9933ffCatalyst|r",      width = 95 },
    { id = "offspec",  label = "|cff3399ffOffspec|r",       width = 95 },
    { id = "tmog",     label = T.GOLD .. "Tmog|r",          width = 80 },
  }

  local rowData = { buttons = {}, noteBox = nil, selection = nil, noteText = "" }
  local btnX = 12

  for _, cat in ipairs(categories) do
    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(cat.width, 28)
    btn:SetPoint("TOPLEFT", btnX, -46)
    btn:SetText(cat.label)

    btn:SetScript("OnClick", function()
      if rowData.selection == cat.id then
        -- Deselect
        rowData.selection = nil
        btn:SetAlpha(1.0)
        if cat.id == "upgrade" and rowData.noteBox then
          rowData.noteBox:Hide()
        end
      else
        -- Deselect previous
        for _, b in pairs(rowData.buttons) do b:SetAlpha(1.0) end
        -- Select this one
        rowData.selection = cat.id
        for id, b in pairs(rowData.buttons) do
          b:SetAlpha(id == cat.id and 1.0 or 0.4)
        end
        -- Show note field for upgrade
        if cat.id == "upgrade" and rowData.noteBox then
          rowData.noteBox:Show()
          rowData.noteBox:SetFocus()
        elseif rowData.noteBox then
          rowData.noteBox:Hide()
        end
      end
    end)

    rowData.buttons[cat.id] = btn
    btnX = btnX + cat.width + 6
  end

  -- Note field (only visible when Upgrade selected)
  local noteBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
  noteBox:SetSize(ITEM_ROW_WIDTH - 24, 22)
  noteBox:SetPoint("TOPLEFT", 12, -78)
  noteBox:SetAutoFocus(false)
  noteBox:SetMaxLetters(60)
  noteBox:Hide()
  noteBox:SetScript("OnTextChanged", function(self)
    rowData.noteText = self:GetText():trim()
  end)
  noteBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  rowData.noteBox = noteBox

  itemRows[item.itemId] = rowData
  return row
end

function NLC.UI.ShowMultiItemPopup(sessions, timer)
  itemRows = {}

  if multiFrame then multiFrame:Hide() end

  local itemCount = #sessions
  local contentHeight = itemCount * ITEM_ROW_HEIGHT
  local frameHeight = math.min(120 + contentHeight, 600)

  if not multiFrame then
    multiFrame = CreateFrame("Frame", "NordavindLCMultiItem", UIParent, "BackdropTemplate")
    multiFrame:SetPoint("CENTER", 0, 50)
    multiFrame:SetMovable(true)
    multiFrame:EnableMouse(true)
    multiFrame:RegisterForDrag("LeftButton")
    multiFrame:SetScript("OnDragStart", multiFrame.StartMoving)
    multiFrame:SetScript("OnDragStop", multiFrame.StopMovingOrSizing)
    multiFrame:SetFrameStrata("DIALOG")
    T.ApplyBackdrop(multiFrame)

    local closeX = CreateFrame("Button", nil, multiFrame, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -2, -2)
  end

  multiFrame:SetSize(ITEM_ROW_WIDTH + 40, frameHeight)

  -- Clear old children
  if multiFrame.scrollChild then
    for _, child in ipairs({ multiFrame.scrollChild:GetChildren() }) do child:Hide() end
  end

  -- Title with boss name
  if multiFrame.title then multiFrame.title:Hide() end
  T.CreateTitleBar(multiFrame, "Loot Council")
  local bossName = sessions[1] and sessions[1].boss or "Unknown"
  multiFrame.title:SetText(T.GOLD .. "Loot Council|r  " .. T.MUTED .. "— " .. bossName .. "|r")

  -- Timer
  if not multiFrame.timerText then
    multiFrame.timerText = multiFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    multiFrame.timerText:SetPoint("TOPRIGHT", -40, -10)
  end
  multiFrame.timerText:SetText(T.GOLD .. timer .. "s|r")
  multiFrame.timerText:Show()

  -- Scroll frame for items
  if not multiFrame.scrollFrame then
    multiFrame.scrollFrame = CreateFrame("ScrollFrame", nil, multiFrame, "UIPanelScrollFrameTemplate")
    multiFrame.scrollFrame:SetPoint("TOPLEFT", 12, -40)
    multiFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -32, 56)

    multiFrame.scrollChild = CreateFrame("Frame")
    multiFrame.scrollFrame:SetScrollChild(multiFrame.scrollChild)
  end
  multiFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -32, 56)
  multiFrame.scrollChild:SetSize(ITEM_ROW_WIDTH, contentHeight)

  -- Create item rows
  for i, session in ipairs(sessions) do
    local row = createItemRow(multiFrame.scrollChild, i, session)
    row:Show()
  end

  -- Send button
  if not multiFrame.sendBtn then
    multiFrame.sendBtn = CreateFrame("Button", nil, multiFrame, "UIPanelButtonTemplate")
    multiFrame.sendBtn:SetSize(ITEM_ROW_WIDTH, 40)
    multiFrame.sendBtn:SetPoint("BOTTOM", 0, 12)
    multiFrame.sendBtn:SetText(T.GREEN .. "Send Responses|r")
    multiFrame.sendBtn:SetNormalFontObject("GameFontHighlightLarge")
  end
  multiFrame.sendBtn:SetScript("OnClick", function()
    local selections = {}
    for _, session in ipairs(sessions) do
      local rowData = itemRows[session.itemId]
      if rowData and rowData.selection then
        selections[session.itemId] = {
          category = rowData.selection,
          note = rowData.selection == "upgrade" and rowData.noteText or "",
        }
      end
    end
    NLC.Council.SubmitResponses(selections)
    multiFrame:Hide()
  end)
  multiFrame.sendBtn:Show()

  multiFrame:Show()

  -- Timer countdown
  local remaining = timer
  if multiFrame._ticker then multiFrame._ticker:Cancel() end
  multiFrame._ticker = C_Timer.NewTicker(1, function(ticker)
    remaining = remaining - 1
    if remaining <= 0 or not multiFrame:IsShown() then
      ticker:Cancel()
      if multiFrame:IsShown() then
        -- Auto-submit on timeout
        multiFrame.sendBtn:GetScript("OnClick")()
      end
      return
    end
    local color = remaining <= 10 and T.RED or remaining <= 30 and T.ORANGE or T.GOLD
    multiFrame.timerText:SetText(color .. remaining .. "s|r")
  end, timer)
end
```

- [ ] **Step 2: Keep the loot detected panel, wire to StartMultiSession**

The loot detected panel (officer sees boss drops, can remove items, clicks "Start Council") stays mostly the same. Only change the "Start Council" button to call `StartMultiSession` instead of `StartSession` + queue:

```lua
-- ============================================================
-- LOOT DETECTED PANEL (officer only)
-- ============================================================
-- Keep the existing lootPanel code (refreshLootPanel, ShowLootDetected)
-- exactly as-is, EXCEPT change the startBtn OnClick handler:

    lootPanel.startBtn:SetScript("OnClick", function()
      local remaining = NLC.LootDetection.GetDroppedItems()
      if #remaining == 0 then return end

      NLC.Council.StartMultiSession(remaining, remaining[1].boss)
      lootPanel:Hide()
    end)
```

Copy the existing `refreshLootPanel` and `ShowLootDetected` functions unchanged. Only the `OnClick` handler above changes.

- [ ] **Step 3: Remove old ShowInterestPopup and UpdateCouncilInterests**

Delete the old `ShowInterestPopup` function and `UpdateCouncilInterests` function — they're replaced by `ShowMultiItemPopup`.

- [ ] **Step 4: Commit**

```bash
git add NordavindLC/UI/CouncilFrame.lua
git commit -m "feat: multi-item interest popup replaces single-item popup"
```

---

### Task 4: Update RankingFrame.lua (Award Wizard)

**Files:**
- Modify: `NordavindLC/UI/RankingFrame.lua`

Add wizard navigation to the existing ranking frame: prev/next arrows, progress indicator, auto-advance on award, skip button for no-interest items.

- [ ] **Step 1: Add ShowWizard and HideWizard entry points**

Add these functions at the bottom of the file. `ShowWizard` wraps the existing `ShowRanking` with wizard chrome:

```lua
function NLC.UI.ShowWizard(sessions, index)
  local session = sessions[index]
  if not session then return end

  local ranked = session.ranked or {}
  local total = #sessions

  -- Use existing ShowRanking to render the candidates
  NLC.UI.ShowRanking(session, ranked)

  -- Update title with progress
  rankFrame.title:SetText(T.GOLD .. "Loot Council|r  " .. T.MUTED .. "— Item " .. index .. " / " .. total .. "|r")

  -- Show item info below title
  if not rankFrame.itemInfo then
    rankFrame.itemInfo = rankFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankFrame.itemInfo:SetPoint("TOP", 0, -34)
  end
  rankFrame.itemInfo:SetText((session.itemLink or "?") .. "  " .. T.MUTED .. "ilvl " .. (session.ilvl or 0) .. "|r")
  rankFrame.itemInfo:Show()

  -- Navigation arrows
  if not rankFrame.prevBtn then
    rankFrame.prevBtn = T.CreateButton(rankFrame, 40, 34, "<")
    rankFrame.prevBtn:SetPoint("TOPLEFT", 20, -6)
  end
  if not rankFrame.nextBtn then
    rankFrame.nextBtn = T.CreateButton(rankFrame, 40, 34, ">")
    rankFrame.nextBtn:SetPoint("TOPRIGHT", -40, -6)
  end

  rankFrame.prevBtn:SetScript("OnClick", function()
    for i = index - 1, 1, -1 do
      if sessions[i].phase == "ranking" then
        NLC.Council.SetWizardIndex(i)
        return
      end
    end
  end)
  rankFrame.nextBtn:SetScript("OnClick", function()
    for i = index + 1, #sessions do
      if sessions[i].phase == "ranking" then
        NLC.Council.SetWizardIndex(i)
        return
      end
    end
  end)

  -- Enable/disable based on available items
  local hasPrev = false
  for i = index - 1, 1, -1 do
    if sessions[i].phase == "ranking" then hasPrev = true; break end
  end
  local hasNext = false
  for i = index + 1, #sessions do
    if sessions[i].phase == "ranking" then hasNext = true; break end
  end
  rankFrame.prevBtn:SetEnabled(hasPrev)
  rankFrame.nextBtn:SetEnabled(hasNext)
  rankFrame.prevBtn:Show()
  rankFrame.nextBtn:Show()

  -- "No interest" skip button if no candidates
  if #ranked == 0 then
    if not rankFrame.skipBtn then
      rankFrame.skipBtn = T.CreateButton(rankFrame, 200, 40, T.MUTED .. "Ingen interesse — Skip|r")
      rankFrame.skipBtn:SetPoint("CENTER", 0, 0)
    end
    rankFrame.skipBtn:SetScript("OnClick", function()
      NLC.Council.SkipCurrent()
    end)
    rankFrame.skipBtn:Show()
  elseif rankFrame.skipBtn then
    rankFrame.skipBtn:Hide()
  end

  -- Update Award Later button for wizard
  rankFrame.laterBtn:SetScript("OnClick", function()
    NLC.Council.AwardLaterCurrent()
  end)
end

function NLC.UI.HideWizard()
  if rankFrame then
    rankFrame:Hide()
    if rankFrame.itemInfo then rankFrame.itemInfo:Hide() end
    if rankFrame.prevBtn then rankFrame.prevBtn:Hide() end
    if rankFrame.nextBtn then rankFrame.nextBtn:Hide() end
    if rankFrame.skipBtn then rankFrame.skipBtn:Hide() end
  end
end
```

- [ ] **Step 2: Update ShowRanking award button to use wizard-aware Award**

In the existing `ShowRanking` function, the award button's OnClick currently calls `NLC.Council.Award(c.name)` and hides `rankFrame`. Remove the `rankFrame:Hide()` — the wizard's `AdvanceWizard()` handles frame updates now:

Change this in the award button OnClick:
```lua
      awardBtn:SetScript("OnClick", function()
        NLC.Council.Award(c.name)
        -- Don't hide rankFrame here — wizard AdvanceWizard handles it
      end)
```

- [ ] **Step 3: Commit**

```bash
git add NordavindLC/UI/RankingFrame.lua
git commit -m "feat: award wizard with navigation, progress, auto-advance"
```

---

### Task 5: Update Core.lua (Timer Default, Test Commands, Wiring)

**Files:**
- Modify: `NordavindLC/Core.lua`

- [ ] **Step 1: Change default timer from 30 to 90**

In the `ADDON_LOADED` handler, change:

```lua
      config = { officers = {}, timer = 90 },
```

- [ ] **Step 2: Update test command for multi-item flow**

Replace the `elseif cmd == "test"` block. The test now creates multiple items and uses `StartMultiSession`:

```lua
  elseif cmd == "test" then
    NLC.isOfficer = true
    NLC.active = true

    -- Mock imported scoring data
    NLC.db.importData = NLC.db.importData or {}
    NLC.db.importData.players = NLC.db.importData.players or {}

    if not NLC._testSeeded then
      local testPlayers = {
        { name = "Testwarrior",  class = "WARRIOR",  rank = "raider", attendance = 95, wclParse = 92, defensives = 1.8, baseScore = 38.5 },
        { name = "Testshaman",   class = "SHAMAN",   rank = "raider", attendance = 90, wclParse = 88, defensives = 2.1, baseScore = 36.2 },
        { name = "Testpaladin",  class = "PALADIN",  rank = "raider", attendance = 85, wclParse = 95, defensives = 0.6, baseScore = 32.0 },
        { name = "Testmage",     class = "MAGE",     rank = "trial",  attendance = 70, wclParse = 97, defensives = 0.3, baseScore = 25.8 },
        { name = "Testrogue",    class = "ROGUE",    rank = "backup", attendance = 80, wclParse = 90, defensives = 1.2, baseScore = 30.5 },
      }
      for _, p in ipairs(testPlayers) do
        NLC.db.importData.players[p.name] = {
          attendance = p.attendance, wclParse = p.wclParse, defensives = p.defensives,
          baseScore = p.baseScore, rank = p.rank, lootThisWeek = 0, lootTotal = 2,
          mplusEffort = 10, role = "dps", deathPenalty = 0,
        }
      end
      NLC._testSeeded = true
      NLC.Utils.Print("Mock-data opprettet (5 test-spillere)")
    end

    -- Build multiple fake sessions (simulating wizard)
    local fakeItems = {
      { itemLink = "|cffa335ee|Hitem:111111::::::::80:::::|h[Void-Touched Chestplate]|h|r", itemId = 111111, ilvl = 639, equipLoc = "INVTYPE_CHEST", boss = "Test Boss" },
      { itemLink = "|cffa335ee|Hitem:222222::::::::80:::::|h[Dreamrift Shoulders]|h|r", itemId = 222222, ilvl = 639, equipLoc = "INVTYPE_SHOULDER", boss = "Test Boss" },
      { itemLink = "|cffa335ee|Hitem:333333::::::::80:::::|h[Quel'Danas Legguards]|h|r", itemId = 333333, ilvl = 636, equipLoc = "INVTYPE_LEGS", boss = "Test Boss" },
    }

    local fakeSessions = {}
    local testInterests = {
      { name = "Testwarrior",  class = "WARRIOR",  cat = "upgrade",  tier = 3 },
      { name = "Testshaman",   class = "SHAMAN",   cat = "upgrade",  tier = 3 },
      { name = "Testpaladin",  class = "PALADIN",  cat = "catalyst", tier = 1 },
      { name = "Testmage",     class = "MAGE",     cat = "catalyst", tier = 1 },
      { name = "Testrogue",    class = "ROGUE",    cat = "upgrade",  tier = 2 },
    }

    for _, item in ipairs(fakeItems) do
      local session = {
        itemLink = item.itemLink, itemId = item.itemId, ilvl = item.ilvl,
        equipLoc = item.equipLoc, boss = item.boss,
        timer = 999, interests = {}, phase = "ranking",
      }
      -- Add varied interests per item
      for _, p in ipairs(testInterests) do
        session.interests[p.name] = {
          category = p.cat, equippedIlvl = 626, tierCount = p.tier, class = p.class,
        }
      end
      session.ranked = NLC.Council.BuildRanking(session)
      table.insert(fakeSessions, session)
    end

    -- Show wizard directly
    NLC.UI.ShowWizard(fakeSessions, 1)
    NLC.Utils.Print("Test wizard vist med " .. #fakeSessions .. " items. Klikk Tildel for a teste auto-advance.")
```

- [ ] **Step 3: Update testpopup to use multi-item popup**

```lua
  elseif cmd == "testpopup" then
    local fakeItems = {
      { itemLink = "|cffa335ee|Hitem:111111::::::::80:::::|h[Void-Touched Chestplate]|h|r", itemId = 111111, ilvl = 639, equipLoc = "INVTYPE_CHEST", boss = "Test Boss" },
      { itemLink = "|cffa335ee|Hitem:222222::::::::80:::::|h[Dreamrift Shoulders]|h|r", itemId = 222222, ilvl = 639, equipLoc = "INVTYPE_SHOULDER", boss = "Test Boss" },
    }
    NLC.UI.ShowMultiItemPopup(fakeItems, 30)
    NLC.Utils.Print("Test multi-item popup vist.")
```

- [ ] **Step 4: Update testloot wiring**

The `testloot` command stays the same — it shows the loot detected panel which now calls `StartMultiSession` via the updated button handler.

No code changes needed here, but verify the loot panel's "Start Council" button calls `StartMultiSession`.

- [ ] **Step 5: Commit**

```bash
git add NordavindLC/Core.lua
git commit -m "feat: update test commands and timer default for multi-item council"
```

---

### Task 6: Integration Testing and Cleanup

**Files:**
- All modified files

- [ ] **Step 1: Test multi-item popup in-game**

Log in to WoW, run:
1. `/nordlc testpopup` — verify multi-item popup shows 2 items with buttons, timer, send button
2. Click Upgrade on first item — verify highlight and note field
3. Click Catalyst on second item — verify highlight
4. Click "Send Responses" — verify it closes and prints confirmation

- [ ] **Step 2: Test award wizard in-game**

Run `/nordlc test` — verify:
1. Wizard shows "Item 1 / 3" with candidates
2. Click "Tildel" on a candidate — verify it auto-advances to "Item 2 / 3"
3. Score updates visible on next item
4. Navigate with `<` `>` arrows
5. "Award Later" puts item in pending
6. Last item Tildel closes wizard

- [ ] **Step 3: Test loot panel flow**

Run `/nordlc testloot` — verify:
1. Loot panel shows 4 items with X buttons
2. Remove one item — count updates
3. Click "Start Council" — multi-item popup appears (not single-item)

- [ ] **Step 4: Remove dead code**

Remove any leftover references to the old single-item flow:
- `ShowInterestPopup` references in other files
- `UpdateCouncilInterests` references
- Old `COUNCIL_START` handler in Comms.lua (replaced by `SESSION_START`)
- Old `GetActiveSession` references

- [ ] **Step 5: Version bump**

In `NordavindLC.toc`, change:
```
## Version: 1.2.0
```

- [ ] **Step 6: Final commit and deploy**

```bash
git add -A
git commit -m "feat: multi-item council v1.2.0 — batch popup, award wizard, auto-close"
git push
cp -r NordavindLC/* "/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/NordavindLC/"
```
