# Loot Detection via CHAT_MSG_LOOT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace broken `START_LOOT_ROLL` detection with `CHAT_MSG_LOOT` parsing so the pre-session loot window appears automatically after every boss kill.

**Architecture:** On `BOSS_KILL`, open an 8-second collection window and register interest in `CHAT_MSG_LOOT`. Every loot message during that window is parsed for item links, filtered through the existing `shouldTrackItem` logic, and deduplicated by itemID. After 8 seconds the existing `ShowLootDetected` panel appears with all collected items.

**Tech Stack:** WoW Lua 5.1, AceAddon-3.0, WoW C API (C_Item, C_Timer)

---

## File Map

| File | Change |
|---|---|
| `NordavindLC/LootDetection.lua` | Full rewrite — new detection logic |

No other files change.

---

### Task 1: Rewrite LootDetection.lua

**Files:**
- Modify: `NordavindLC/LootDetection.lua` (full replacement)

- [ ] **Step 1: Replace the file with the new implementation**

Overwrite `NordavindLC/LootDetection.lua` completely with:

```lua
-- LootDetection.lua
-- Detect loot drops from boss kills.
-- Primary: CHAT_MSG_LOOT parsing in an 8s window after BOSS_KILL.
-- START_LOOT_ROLL kept for auto-need only (fires in group loot mode).
-- ENCOUNTER_LOOT_RECEIVED kept for looter-name tracking only.

local NLC = NordavindLC_NS

local lootFrame = CreateFrame("Frame")
local isRegistered = false

function NLC.LootDetection.Register()
  if isRegistered then return end
  lootFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
  lootFrame:RegisterEvent("BOSS_KILL")
  lootFrame:RegisterEvent("START_LOOT_ROLL")
  lootFrame:RegisterEvent("CHAT_MSG_LOOT")
  isRegistered = true
end

function NLC.LootDetection.Unregister()
  lootFrame:UnregisterAllEvents()
  isRegistered = false
end

local currentBoss = nil
local droppedItems = {}
local seenRollItems = {}
local collectingLoot = false
local seenChatItems = {}

local EXCLUDED_TYPES = {
  ["Miscellaneous"] = true,
  ["Companion Pets"] = true,
  ["Consumable"] = true,
}

local function shouldTrackItem(itemLink, itemID)
  if not itemLink or not itemID then return false end

  local _, _, quality, ilvl, _, itemType, itemSubType, _, equipLoc = C_Item.GetItemInfo(itemLink)

  if not quality then return nil end
  if quality < 4 then return false end
  if itemType == "Recipe" then return true, ilvl or 0, equipLoc or "" end
  if EXCLUDED_TYPES[itemType] then return false end

  if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
    local tokenArmor = NLC.Utils.GetTierTokenArmorType(itemLink)
    if tokenArmor then
      return true, ilvl or 0, "", tokenArmor
    end
    return false
  end

  if equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return false end
  if NLC.Utils.IsWarbound(itemLink) then return false end

  return true, ilvl or 0, equipLoc or ""
end

local function showIfAny()
  collectingLoot = false
  if NLC.isOfficer and #droppedItems > 0 then
    NLC.UI.ShowLootDetected(droppedItems)
  end
end

lootFrame:SetScript("OnEvent", function(self, event, ...)
  if not NLC.active then return end

  if event == "BOSS_KILL" then
    local id, name = ...
    currentBoss = name or "Unknown Boss"
    droppedItems = {}
    seenRollItems = {}
    seenChatItems = {}
    collectingLoot = true
    C_Timer.After(8, showIfAny)

  elseif event == "CHAT_MSG_LOOT" then
    if not collectingLoot or not NLC.isOfficer then return end
    local text = ...
    for link in text:gmatch("|c%x+|Hitem:[^|]+|h%[.-%]|h|r") do
      local itemID = C_Item.GetItemInfoInstant(link)
      if itemID and not seenChatItems[itemID] then
        seenChatItems[itemID] = true
        local function tryTrackChat(retries)
          local track, ilvl, equipLoc, armorType = shouldTrackItem(link, itemID)
          if track == nil and retries > 0 then
            C_Timer.After(0.5, function() tryTrackChat(retries - 1) end)
            return
          end
          if track then
            table.insert(droppedItems, {
              itemLink = link,
              itemId = itemID,
              ilvl = ilvl or 0,
              equipLoc = equipLoc,
              armorType = armorType,
              boss = currentBoss,
              looter = nil,
            })
          end
        end
        tryTrackChat(5)
      end
    end

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

  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    local encounterID, itemID, itemLink, quantity, playerName, className = ...
    for _, item in ipairs(droppedItems) do
      if item.itemId == itemID and not item.looter then
        item.looter = playerName
        break
      end
    end
  end
end)

function NLC.LootDetection.GetDroppedItems()
  return droppedItems
end

function NLC.LootDetection.RemoveItem(index)
  table.remove(droppedItems, index)
end

function NLC.LootDetection.GetCurrentBoss()
  return currentBoss
end
```

- [ ] **Step 2: Verify the file looks correct**

Open `NordavindLC/LootDetection.lua` and confirm:
- `CHAT_MSG_LOOT` is registered in `Register()`
- `collectingLoot` and `seenChatItems` are declared at module level
- `BOSS_KILL` handler sets `collectingLoot = true` and calls `C_Timer.After(8, showIfAny)`
- `CHAT_MSG_LOOT` handler uses `gmatch` to extract item links
- `START_LOOT_ROLL` handler only contains auto-need/pass logic — no detection
- `ENCOUNTER_LOOT_RECEIVED` handler only updates `item.looter` — no detection

---

### Task 2: Test in-game

**Files:** None changed in this task — testing only.

- [ ] **Step 1: Load the addon in WoW**

Reload UI: `/reload`

Check for Lua errors in the error frame. If any error appears, fix before continuing.

- [ ] **Step 2: Test the loot panel still works manually**

Type: `/nordlc testloot`

Expected: The "Loot Detected" panel appears with 4 fake items, X-buttons work, "Start Council" button is present.

- [ ] **Step 3: Simulate the new detection flow**

Paste this in WoW chat to fake a BOSS_KILL + CHAT_MSG_LOOT sequence:

```lua
/script
local NLC = NordavindLC_NS
NLC.active = true
NLC.isOfficer = true
-- Simulate BOSS_KILL
local frame = NordavindLCLootFrame or CreateFrame("Frame")
NLC.LootDetection._testBoss = "Test Boss"
-- Manually trigger the same state BOSS_KILL sets:
NordavindLC_NS_LootFrame = frame
```

Since we can't fire events directly via `/script`, use this workaround instead — call the internal functions directly:

```lua
/script NordavindLC_NS.active=true; NordavindLC_NS.isOfficer=true
```

Then in a second line trigger a fake loot chat message by using the debug command:
```
/nordlc testloot
```

This verifies the panel renders correctly. The real CHAT_MSG_LOOT flow will only be testable in an actual raid.

- [ ] **Step 4: Verify activation prompt still works**

Type `/nordlc deactivate` then `/nordlc activate`.

Expected: Chat prints "Activated! (Officer mode)" (or Raider mode depending on rank).

---

### Task 3: Commit

- [ ] **Step 1: Stage and commit**

```bash
git add NordavindLC/LootDetection.lua
git commit -m "fix: replace START_LOOT_ROLL detection with CHAT_MSG_LOOT

Personal loot in WoW Midnight does not fire START_LOOT_ROLL.
Detect items by parsing CHAT_MSG_LOOT in an 8s window after
BOSS_KILL instead. Pre-session loot panel now appears automatically."
```

- [ ] **Step 2: Tag and push (v1.7.5)**

```bash
git push
git tag v1.7.5
git push --tags
```

Expected: CI publishes to CurseForge automatically.
