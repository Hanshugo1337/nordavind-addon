-- LootDetection.lua
-- Distributed loot capture for Midnight (patch 12.0).
--
-- Why distributed: in 12.0 the officer's single client no longer sees all loot
-- (START_LOOT_ROLL only fires for items the officer can roll on; ENCOUNTER_LOOT_RECEIVED
-- is unreliable; loot lands after combat; addon comms are blocked during encounters).
-- So each raider captures their OWN tradeable looted items locally and reports them to
-- the officer after the fight.
--
-- Capture model: after ENCOUNTER_END (success) we open a short collection window and scan
-- the player's bags for items that still carry a trade timer (BoP looted within the trade
-- window) and pass shouldTrackItem. Items are deduped by item GUID so each physical item is
-- reported once per session. BAG_UPDATE_DELAYED re-scans while the window is open so late
-- loot is caught without a fixed guess.
--
-- Send model: reports go out via NLC.Comms only when addon comms are NOT restricted
-- (ADDON_RESTRICTION_STATE_CHANGED / C_RestrictedActions). If comms are blocked when the
-- window closes, the report is held and flushed the moment the restriction lifts.
--
-- Officer aggregation of LOOT_REPORT lives in Comms.lua; it feeds detectedItems here via
-- _setDetected so the existing "Loot Detected" panel (GetDroppedItems/RemoveItem) is unchanged.
--
-- Technique reference only (RCLootCouncil): which WoW APIs exist in 12.0. No RC code,
-- names, structure or text. Read again at 3.23.1 (2026-08-18) for two behaviours we
-- were missing: that Need must be checked before it is rolled, and that auto-rolls
-- want a short delay. Both are reimplemented here from the API, not from their source.

local NLC = NordavindLC_NS

local lootFrame = CreateFrame("Frame")
local isRegistered = false

local currentBoss = nil
local reportItems = {}       -- tradeable items THIS client looted, awaiting send
local reportedGUIDs = {}     -- session-wide dedup: itemGUID -> true
local detectedItems = {}     -- aggregated list on the officer (shown in the panel)
local collecting = false     -- true while the post-combat collection window is open
local collectTimer = nil
local commsRestricted = false -- true when addon comms are blocked (encounter/challenge)
local pendingSend = false    -- true if a report is waiting for the restriction to lift
local debugMode = false

function NLC.LootDetection.Register()
  if isRegistered then return end
  lootFrame:RegisterEvent("ENCOUNTER_START")
  lootFrame:RegisterEvent("ENCOUNTER_END")
  lootFrame:RegisterEvent("START_LOOT_ROLL") -- auto-roll only
  -- New 12.0 event; guard so an older client can't error on RegisterEvent.
  pcall(function() lootFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED") end)
  isRegistered = true
  -- Fresh session state
  reportItems = {}
  reportedGUIDs = {}
  pendingSend = false
end

function NLC.LootDetection.Unregister()
  lootFrame:UnregisterAllEvents()
  isRegistered = false
  collecting = false
  pendingSend = false
  if collectTimer then collectTimer:Cancel(); collectTimer = nil end
end

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

-- True if addon comms are currently blocked.
--
-- Var en egen kopi av logikken i Comms.lua. To kopier av samme regel drev fra
-- hverandre i det øyeblikket den ene lærte noe den andre ikke gjorde: Comms
-- leser nå «Activating» fra event-payloaden, denne pollet API-et og så bare
-- «Active». Nå spør vi den ene kilden. Degraderer fortsatt til false hvis
-- 12.0-API-et mangler — den vakten ligger i Comms.
local function commsAreRestricted()
  return NLC.Comms and NLC.Comms.IsRestricted and NLC.Comms.IsRestricted() or false
end

-- Blizzard's roll types for RollOnLoot. Disenchant (3) is deliberately absent:
-- the council decides what gets sharded, never the auto-roller.
local ROLL_PASS, ROLL_NEED, ROLL_GREED, ROLL_TRANSMOG = 0, 1, 2, 4

-- Auto-rolls are deferred a frame or two. Landing inside the event handler means
-- racing any other addon that rebuilds the roll frame, and a call that arrives
-- mid-rebuild is dropped with no error to show for it.
local function rollLater(rollID, rollType)
  C_Timer.After(0.05, function() RollOnLoot(rollID, rollType) end)
end

-- The leader needs the item in their bags for the council to hand out, so we roll
-- Need on their behalf. But Need is only offered for what the leader's own spec can
-- equip — a plate leader cannot Need a leather drop. That call is refused silently,
-- and since every other raider auto-passes, the item would end the roll with no
-- valid entry at all and be lost. Transmog and Greed are always available, so we
-- step down to those rather than gamble on Need being allowed.
local function leaderRollType(rollID)
  local _, _, _, _, _, canNeed, _, _, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
  if canNeed then return ROLL_NEED end
  if canTransmog then return ROLL_TRANSMOG end
  return ROLL_GREED
end

-- Exposed for tests/lootroll_harness.lua only; nothing in the addon calls this.
-- Same underscore convention as _setDetected below.
NLC.LootDetection._leaderRollType = leaderRollType

-- Scan all bags for newly-looted tradeable items and add them to reportItems.
function NLC.LootDetection.ScanBags()
  for bag = 0, 4 do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link and NLC.Utils.IsTradeableBagItem(bag, slot) then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local guid = C_Item.DoesItemExist(loc) and C_Item.GetItemGUID(loc)
        if guid and not reportedGUIDs[guid] then
          local itemID = C_Item.GetItemInfoInstant(link)
          local track, ilvl, equipLoc, armorType = shouldTrackItem(link, itemID)
          if track then
            reportedGUIDs[guid] = true
            table.insert(reportItems, {
              itemLink = link,
              itemId = itemID,
              ilvl = ilvl or 0,
              equipLoc = equipLoc,
              armorType = armorType,
              boss = currentBoss,
              looter = UnitName("player"),
            })
            dbg("Rapport +: " .. link)
          end
        end
      end
    end
  end
end

-- Send the collected report if comms allow; otherwise hold and flush when the restriction lifts.
function NLC.LootDetection.TrySendReport()
  if #reportItems == 0 then
    pendingSend = false
    dbg("Ingen tradeable items å rapportere.")
    return
  end
  if commsRestricted then
    pendingSend = true
    dbg("Comms blokkert — venter på at restriksjon løftes (" .. #reportItems .. " items).")
    return
  end
  NLC.Comms.Send("LOOT_REPORT", { boss = currentBoss, items = reportItems })
  dbg("Sendte LOOT_REPORT: " .. #reportItems .. " items")
  reportItems = {}
  pendingSend = false
end

lootFrame:SetScript("OnEvent", function(self, event, ...)
  -- ADDON_RESTRICTION_STATE_CHANGED must be handled even outside active councils so a held
  -- report can flush; but reportItems is only ever populated while active, so gating the
  -- rest on NLC.active is fine.
  if event == "ADDON_RESTRICTION_STATE_CHANGED" then
    commsRestricted = commsAreRestricted()
    dbg("Comms-restriksjon: " .. tostring(commsRestricted))
    if not commsRestricted and pendingSend then
      NLC.LootDetection.TrySendReport()
    end
    return
  end

  if not NLC.active then return end

  if event == "ENCOUNTER_START" then
    local encounterID, name = ...
    currentBoss = name or "Unknown Boss"
    dbg("ENCOUNTER_START: " .. currentBoss)

  elseif event == "ENCOUNTER_END" then
    local encounterID, name, difficultyID, groupSize, success = ...
    dbg(string.format("ENCOUNTER_END: %s | success=%s", tostring(name), tostring(success)))
    if name then currentBoss = name end
    if not (success == 1 or success == true) then
      dbg("Encounter feilet, ingen innsamling.")
      return
    end
    -- Open the collection window: scan now, scan again on each BAG_UPDATE_DELAYED,
    -- close after 12s and attempt to send.
    commsRestricted = commsAreRestricted()
    collecting = true
    NLC.LootDetection.ScanBags()
    lootFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    if collectTimer then collectTimer:Cancel() end
    collectTimer = C_Timer.NewTimer(12, function()
      collectTimer = nil
      collecting = false
      lootFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
      NLC.LootDetection.TrySendReport()
    end)
    dbg("ENCOUNTER_END success, samler loot (maks 12s).")

  elseif event == "BAG_UPDATE_DELAYED" then
    if collecting then NLC.LootDetection.ScanBags() end

  elseif event == "START_LOOT_ROLL" then
    -- Auto-roll behaviour only; capture happens via ScanBags now.
    local rollID = ...
    if not rollID then return end
    local link = GetLootRollItemLink(rollID)
    local isLeader = UnitIsGroupLeader("player")
    if isLeader then
      local rollType = leaderRollType(rollID)
      if rollType ~= ROLL_NEED then
        dbg("Need not offered on " .. tostring(link) .. ", rolling " .. rollType .. " instead.")
      end
      rollLater(rollID, rollType)
    else
      if link then
        local _, _, _, _, _, itemType = C_Item.GetItemInfo(link)
        if itemType ~= "Miscellaneous" and itemType ~= "Companion Pets" then
          rollLater(rollID, ROLL_PASS)
        end
      else
        rollLater(rollID, ROLL_PASS)
      end
    end
  end
end)

-- ============================================================
-- Client report (this player's captured loot)
-- ============================================================
function NLC.LootDetection.GetReport()
  return reportItems
end

-- ============================================================
-- Officer panel (aggregated list, set by Comms.OnLootReport)
-- ============================================================
function NLC.LootDetection._setDetected(items)
  detectedItems = items
end

function NLC.LootDetection.GetDroppedItems()
  return detectedItems
end

function NLC.LootDetection.RemoveItem(index)
  table.remove(detectedItems, index)
end

function NLC.LootDetection.GetCurrentBoss()
  return currentBoss
end

function NLC.LootDetection.ToggleDebug()
  debugMode = not debugMode
  NLC.Utils.Print("Loot debug: " .. (debugMode and "|cff00ff00PÅ|r" or "|cffff0000AV|r"))
  if debugMode then
    NLC.Utils.Print("  currentBoss=" .. tostring(currentBoss))
    NLC.Utils.Print("  reportItems=" .. #reportItems)
    NLC.Utils.Print("  commsRestricted=" .. tostring(commsRestricted))
    NLC.Utils.Print("  collecting=" .. tostring(collecting))
  end
end
