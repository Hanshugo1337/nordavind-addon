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

lootFrame:SetScript("OnEvent", function(self, event, ...)
  if not NLC.active then return end

  if event == "BOSS_KILL" then
    local id, name = ...
    currentBoss = name or "Unknown Boss"
    droppedItems = {}

  elseif event == "START_LOOT_ROLL" then
    -- Auto-pass for non-officers when addon is active
    if not NLC.isOfficer then
      local rollID, rollTime, lootHandle = ...
      if rollID then
        RollOnLoot(rollID, 0) -- 0 = Pass
        NLC.Utils.Print("Auto-pass (loot council aktiv)")
      end
    end

  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    local encounterID, itemID, itemLink, quantity, playerName, className = ...
    if itemLink and itemID then
      local _, _, quality, ilvl, _, _, _, _, equipLoc = C_Item.GetItemInfo(itemLink)
      if quality and quality >= 4 and equipLoc and equipLoc ~= "" then
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
  end
end)

function NLC.LootDetection.GetDroppedItems()
  return droppedItems
end

function NLC.LootDetection.GetCurrentBoss()
  return currentBoss
end
