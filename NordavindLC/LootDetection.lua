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
local collectingLoot = false
local seenChatItems = {}
local collectTimer = nil

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
    seenChatItems = {}
    collectingLoot = true
    if collectTimer then collectTimer:Cancel() end
    collectTimer = C_Timer.NewTimer(8, showIfAny)

  elseif event == "CHAT_MSG_LOOT" then
    if not collectingLoot or not NLC.isOfficer then return end
    local text = ...
    for link in text:gmatch("|c%x+|Hitem:[^|]+|h%[.-%]|h|r") do
      local itemID = C_Item.GetItemInfoInstant(link)
      if itemID and not seenChatItems[itemID] then
        seenChatItems[itemID] = true -- one council entry per itemID; duplicate token drops (multiple raiders receiving same token) are intentionally collapsed
        local tryTrackChat
        tryTrackChat = function(retries)
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
      RollOnLoot(rollID, 1) -- 1 = Need
    else
      if link then
        local _, _, _, _, _, itemType = C_Item.GetItemInfo(link)
        if itemType ~= "Miscellaneous" and itemType ~= "Companion Pets" then
          RollOnLoot(rollID, 0) -- 0 = Pass
        end
      else
        RollOnLoot(rollID, 0) -- 0 = Pass
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
