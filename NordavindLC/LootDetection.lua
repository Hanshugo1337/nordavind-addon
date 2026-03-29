-- LootDetection.lua
-- Detect loot drops from boss kills, build item list for officer

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

-- Item types to exclude from council
local EXCLUDED_TYPES = {
  ["Miscellaneous"] = true,
  ["Companion Pets"] = true,
  ["Consumable"] = true,
}

local function shouldTrackItem(itemLink, itemID)
  if not itemLink or not itemID then return false end

  local _, _, quality, ilvl, _, itemType, itemSubType, _, equipLoc = C_Item.GetItemInfo(itemLink)

  -- Must be epic+
  if not quality or quality < 4 then return false end

  -- Recipes always pass through (leader decides)
  if itemType == "Recipe" then return true, ilvl or 0, equipLoc or "" end

  -- Must be equippable (has a slot)
  if not equipLoc or equipLoc == "" then return false end

  -- Skip toys, pets, consumables
  if EXCLUDED_TYPES[itemType] then return false end

  -- Skip cosmetic/decor slots
  if equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return false end

  -- Skip warbound (account-bound) items
  if C_Item.IsBoundToAccountUntilEquip and C_Item.IsBoundToAccountUntilEquip(itemID) then return false end

  return true, ilvl, equipLoc
end

lootFrame:SetScript("OnEvent", function(self, event, ...)
  if not NLC.active then return end

  if event == "BOSS_KILL" then
    local id, name = ...
    currentBoss = name or "Unknown Boss"
    droppedItems = {}

  elseif event == "START_LOOT_ROLL" then
    -- Auto-pass on gear for non-officers (council handles distribution)
    if not NLC.isOfficer then
      local rollID = ...
      if rollID then
        local link = GetLootRollItemLink(rollID)
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
      end
    end

  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    local encounterID, itemID, itemLink, quantity, playerName, className = ...
    local track, ilvl, equipLoc = shouldTrackItem(itemLink, itemID)
    if track then
      table.insert(droppedItems, {
        itemLink = itemLink,
        itemId = itemID,
        ilvl = ilvl or 0,
        equipLoc = equipLoc,
        boss = currentBoss,
        looter = playerName,
      })

      if NLC.isOfficer then
        NLC.UI.ShowLootDetected(droppedItems)
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
