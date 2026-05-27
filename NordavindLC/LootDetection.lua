-- LootDetection.lua
-- Detect loot drops from boss kills.
--
-- Detection flow:
--   ENCOUNTER_END (success) fires when the boss dies — BEFORE loot is distributed.
--   ENCOUNTER_LOOT_RECEIVED and CHAT_MSG_LOOT fire 1-3s later as items land in bags.
--
-- So we must NOT flush on ENCOUNTER_END. Instead, we set waitingForLoot=true and
-- let incoming ELR/chat events add items directly to droppedItems while the timer runs.
-- After 8s we show whatever arrived.
--
-- waitingForLoot:  true from ENCOUNTER_END success until showIfAny fires.
-- collectingLoot:  true during an active encounter (ENCOUNTER_START → ENCOUNTER_END),
--                  used only to guard against chat messages from before the pull.

local NLC = NordavindLC_NS

local lootFrame = CreateFrame("Frame")
local isRegistered = false

function NLC.LootDetection.Register()
  if isRegistered then return end
  lootFrame:RegisterEvent("ENCOUNTER_START")
  lootFrame:RegisterEvent("ENCOUNTER_END")
  lootFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
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
local collectingLoot = false  -- true during pull (ENCOUNTER_START → ENCOUNTER_END)
local waitingForLoot = false  -- true after ENCOUNTER_END success, until showIfAny
local seenItems = {}          -- dedup by itemID
local collectTimer = nil

local debugMode = false

local EXCLUDED_TYPES = {
  ["Miscellaneous"] = true,
  ["Companion Pets"] = true,
  ["Consumable"] = true,
}

local function dbg(msg)
  if debugMode then
    NLC.Utils.Print("|cff00bbff[LootDebug]|r " .. msg)
  end
end

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
  waitingForLoot = false
  collectTimer = nil
  if NLC.isOfficer and #droppedItems > 0 then
    NLC.UI.ShowLootDetected(droppedItems)
  end
end

local function tryAddItem(link, itemID, boss, looter, retries)
  local track, ilvl, equipLoc, armorType = shouldTrackItem(link, itemID)
  if track == nil and retries > 0 then
    C_Timer.After(0.5, function() tryAddItem(link, itemID, boss, looter, retries - 1) end)
    return
  end
  if track then
    table.insert(droppedItems, {
      itemLink = link,
      itemId = itemID,
      ilvl = ilvl or 0,
      equipLoc = equipLoc,
      armorType = armorType,
      boss = boss,
      looter = looter,
    })
    dbg("Added: " .. link .. " (looter: " .. (looter or "?") .. ")")
  end
end

local function resetState()
  droppedItems = {}
  seenItems = {}
  collectingLoot = false
  waitingForLoot = false
  if collectTimer then collectTimer:Cancel(); collectTimer = nil end
end

lootFrame:SetScript("OnEvent", function(self, event, ...)
  if not NLC.active then return end

  if event == "ENCOUNTER_START" then
    local encounterID, name = ...
    currentBoss = name or "Unknown Boss"
    resetState()
    collectingLoot = true
    dbg("ENCOUNTER_START: " .. currentBoss)

  elseif event == "ENCOUNTER_END" then
    local encounterID, name, difficultyID, groupSize, success = ...
    dbg(string.format("ENCOUNTER_END: %s | success=%s (%s)", tostring(name), tostring(success), type(success)))
    if not (success == 1 or success == true) then
      resetState()
      dbg("Encounter failed, resetting.")
      return
    end
    if name then currentBoss = name end
    collectingLoot = false
    -- NOTE: do NOT flush here — loot arrives AFTER ENCOUNTER_END.
    -- Set waitingForLoot so incoming ELR/chat events add directly to droppedItems.
    waitingForLoot = true
    if collectTimer then collectTimer:Cancel() end
    collectTimer = C_Timer.NewTimer(8, showIfAny)
    dbg("Encounter success, waiting 8s for loot events.")

  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    local encounterID, itemID, itemLink, quantity, playerName, className = ...
    dbg(string.format("ENCOUNTER_LOOT_RECEIVED: id=%s player=%s link=%s", tostring(itemID), tostring(playerName), tostring(itemLink)))
    if not itemID or not itemLink then return end
    if waitingForLoot and not seenItems[itemID] then
      seenItems[itemID] = true
      tryAddItem(itemLink, itemID, currentBoss, playerName, 5)
    end
    -- Update looter on already-added items
    for _, item in ipairs(droppedItems) do
      if item.itemId == itemID and not item.looter then
        item.looter = playerName
        break
      end
    end

  elseif event == "CHAT_MSG_LOOT" then
    if not NLC.isOfficer then return end
    local text = ...
    dbg("CHAT_MSG_LOOT: " .. (text or "nil"))
    -- Only process during the post-ENCOUNTER_END loot window
    if not waitingForLoot then return end
    for link in text:gmatch("|c%x+|Hitem:[^|]+|h%[.-%]|h|r") do
      local itemID = C_Item.GetItemInfoInstant(link)
      if itemID and not seenItems[itemID] then
        seenItems[itemID] = true
        tryAddItem(link, itemID, currentBoss, nil, 5)
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

function NLC.LootDetection.ToggleDebug()
  debugMode = not debugMode
  NLC.Utils.Print("Loot debug: " .. (debugMode and "|cff00ff00PÅ|r" or "|cffff0000AV|r"))
  if debugMode then
    NLC.Utils.Print("  collectingLoot=" .. tostring(collectingLoot))
    NLC.Utils.Print("  waitingForLoot=" .. tostring(waitingForLoot))
    NLC.Utils.Print("  currentBoss=" .. tostring(currentBoss))
    NLC.Utils.Print("  droppedItems=" .. #droppedItems)
  end
end
