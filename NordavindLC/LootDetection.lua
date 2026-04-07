-- LootDetection.lua
-- Detect loot drops from boss kills using START_LOOT_ROLL (primary)
-- and ENCOUNTER_LOOT_RECEIVED (tracks who received each item).

local NLC = NordavindLC_NS

local lootFrame = CreateFrame("Frame")
local isRegistered = false

function NLC.LootDetection.Register()
  if isRegistered then return end
  lootFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
  lootFrame:RegisterEvent("BOSS_KILL")
  lootFrame:RegisterEvent("START_LOOT_ROLL")
  isRegistered = true
end

function NLC.LootDetection.Unregister()
  lootFrame:UnregisterAllEvents()
  isRegistered = false
end

local currentBoss = nil
local droppedItems = {}
local seenRollItems = {} -- track itemId from rolls to avoid duplicates

-- Item types to exclude from council
local EXCLUDED_TYPES = {
  ["Miscellaneous"] = true,
  ["Companion Pets"] = true,
  ["Consumable"] = true,
}

local function shouldTrackItem(itemLink, itemID)
  if not itemLink or not itemID then return false end

  local _, _, quality, ilvl, _, itemType, itemSubType, _, equipLoc = C_Item.GetItemInfo(itemLink)

  -- Item not cached yet — return nil to signal retry
  if not quality then return nil end

  -- Must be epic+
  if quality < 4 then return false end

  -- Recipes always pass through (leader decides)
  if itemType == "Recipe" then return true, ilvl or 0, equipLoc or "" end

  -- Must be equippable (has a slot)
  if not equipLoc or equipLoc == "" then return false end

  -- Skip toys, pets, consumables
  if EXCLUDED_TYPES[itemType] then return false end

  -- Skip cosmetic/decor slots
  if equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return false end

  return true, ilvl or 0, equipLoc or ""
end

lootFrame:SetScript("OnEvent", function(self, event, ...)
  if not NLC.active then return end

  if event == "BOSS_KILL" then
    local id, name = ...
    currentBoss = name or "Unknown Boss"
    droppedItems = {}
    seenRollItems = {}

  elseif event == "START_LOOT_ROLL" then
    local rollID = ...
    if not rollID then return end

    local link = GetLootRollItemLink(rollID)

    -- Auto-pass for non-officers (council handles distribution)
    if not NLC.isOfficer then
      local shouldPass = true
      if link then
        local _, _, _, _, _, itemType = C_Item.GetItemInfo(link)
        if itemType == "Miscellaneous" or itemType == "Companion Pets" then
          shouldPass = false
        end
      end
      if shouldPass then
        RollOnLoot(rollID, 0) -- 0 = Pass
      end
      return
    end

    -- Officer: detect item for loot panel
    if not link then return end
    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then return end

    -- Deduplicate (same item can fire multiple times)
    local rollKey = tostring(rollID)
    if seenRollItems[rollKey] then return end
    seenRollItems[rollKey] = true

    local function tryTrackRoll(retries)
      local track, ilvl, equipLoc = shouldTrackItem(link, itemID)
      if track == nil and retries > 0 then
        C_Timer.After(0.5, function() tryTrackRoll(retries - 1) end)
        return
      end
      if track then
        table.insert(droppedItems, {
          itemLink = link,
          itemId = itemID,
          ilvl = ilvl or 0,
          equipLoc = equipLoc,
          boss = currentBoss,
          looter = nil, -- filled in by ENCOUNTER_LOOT_RECEIVED
          rollID = rollID,
        })
        NLC.UI.ShowLootDetected(droppedItems)
      end
    end
    tryTrackRoll(5)

  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    local encounterID, itemID, itemLink, quantity, playerName, className = ...
    -- Update looter info on already-detected items
    for _, item in ipairs(droppedItems) do
      if item.itemId == itemID and not item.looter then
        item.looter = playerName
        break
      end
    end

    -- Fallback: if START_LOOT_ROLL missed this item, add it
    if NLC.isOfficer then
      local found = false
      for _, item in ipairs(droppedItems) do
        if item.itemId == itemID then found = true; break end
      end
      if not found then
        local function tryTrack(retries)
          local track, ilvl, equipLoc = shouldTrackItem(itemLink, itemID)
          if track == nil and retries > 0 then
            C_Timer.After(0.5, function() tryTrack(retries - 1) end)
            return
          end
          if track then
            table.insert(droppedItems, {
              itemLink = itemLink,
              itemId = itemID,
              ilvl = ilvl or 0,
              equipLoc = equipLoc,
              boss = currentBoss,
              looter = playerName,
            })
            NLC.UI.ShowLootDetected(droppedItems)
          end
        end
        tryTrack(5)
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
