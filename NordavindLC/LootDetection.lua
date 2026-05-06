-- LootDetection.lua
-- Detect loot drops from boss kills.
-- Primary: CHAT_MSG_LOOT buffered continuously; flushed on ENCOUNTER_END (success).
-- START_LOOT_ROLL kept for auto-need only (fires in group loot mode).
-- ENCOUNTER_LOOT_RECEIVED kept for looter-name tracking only.
--
-- Why ENCOUNTER_END instead of BOSS_KILL: WoW fires CHAT_MSG_LOOT *before*
-- BOSS_KILL, so using BOSS_KILL as the gate causes all loot messages to be
-- missed. ENCOUNTER_END with success==1 fires after loot is distributed and
-- is reliably later than (or concurrent with) the chat messages.
-- The chatBuffer captures messages up to 30s before encounter end to handle
-- any remaining edge cases.

local NLC = NordavindLC_NS

local lootFrame = CreateFrame("Frame")
local isRegistered = false

function NLC.LootDetection.Register()
  if isRegistered then return end
  lootFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
  lootFrame:RegisterEvent("ENCOUNTER_END")
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
local chatBuffer = {} -- rolling buffer of { link, itemID, time } for pre-encounter messages
local BUFFER_WINDOW = 30 -- seconds to look back in buffer when encounter ends

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

local function flushBufferToDropped()
  local now = GetTime()
  for _, entry in ipairs(chatBuffer) do
    if (now - entry.time) <= BUFFER_WINDOW and not seenChatItems[entry.itemID] then
      seenChatItems[entry.itemID] = true -- one council entry per itemID
      local link, itemID = entry.link, entry.itemID
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
  chatBuffer = {}
end

lootFrame:SetScript("OnEvent", function(self, event, ...)
  if not NLC.active then return end

  if event == "ENCOUNTER_END" then
    local encounterID, name, difficultyID, groupSize, success = ...
    if success ~= 1 then return end
    currentBoss = name or "Unknown Boss"
    droppedItems = {}
    seenChatItems = {}
    collectingLoot = true
    if collectTimer then collectTimer:Cancel() end
    flushBufferToDropped()
    collectTimer = C_Timer.NewTimer(8, showIfAny)

  elseif event == "CHAT_MSG_LOOT" then
    if not NLC.isOfficer then return end
    local text = ...
    local now = GetTime()
    for link in text:gmatch("|c%x+|Hitem:[^|]+|h%[.-%]|h|r") do
      local itemID = C_Item.GetItemInfoInstant(link)
      if itemID then
        if collectingLoot then
          -- Encounter already started: process immediately
          if not seenChatItems[itemID] then
            seenChatItems[itemID] = true -- one council entry per itemID; duplicate token drops intentionally collapsed
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
        else
          -- Pre-encounter: buffer for later
          table.insert(chatBuffer, { link = link, itemID = itemID, time = now })
        end
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
