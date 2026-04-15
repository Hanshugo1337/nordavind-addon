-- Utils.lua
-- Shared utility functions for NordavindLC

NordavindLC_NS = NordavindLC_NS or {}
local NLC = NordavindLC_NS
NLC.Utils = {}
NLC.UI = {}
NLC.Comms = {}
NLC.LootDetection = {}
NLC.Council = {}
NLC.Scoring = {}
NLC.Trade = {}

NLC.Utils.CLASS_COLORS = {
  DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
  DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
  DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
  EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
  HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
  MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
  MONK        = { r = 0.00, g = 1.00, b = 0.60 },
  PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
  PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
  ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
  SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
  WARLOCK     = { r = 0.53, g = 0.53, b = 0.93 },
  WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
}

function NLC.Utils.ClassColoredName(name, class)
  local c = NLC.Utils.CLASS_COLORS[class]
  if not c then return name end
  return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end

NLC.Utils.SLOT_MAP = {
  INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
  INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6,
  INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9,
  INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
  INVTYPE_TRINKET = 13,
  INVTYPE_CLOAK = 15, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPON = 16,
  INVTYPE_WEAPONMAINHAND = 16, INVTYPE_RANGED = 16,
  INVTYPE_WEAPONOFFHAND = 17, INVTYPE_HOLDABLE = 17, INVTYPE_SHIELD = 17,
}

function NLC.Utils.GetEquippedInfo(equipLoc)
  local slotId = NLC.Utils.SLOT_MAP[equipLoc]
  if not slotId then return nil, 0 end

  -- Rings and trinkets have two slots — return the lower ilvl one
  local altSlot = nil
  if equipLoc == "INVTYPE_FINGER" then altSlot = 12
  elseif equipLoc == "INVTYPE_TRINKET" then altSlot = 14
  end

  local link = GetInventoryItemLink("player", slotId)
  local ilvl = link and (GetDetailedItemLevelInfo(link) or 0) or 0

  if altSlot then
    local link2 = GetInventoryItemLink("player", altSlot)
    local ilvl2 = link2 and (GetDetailedItemLevelInfo(link2) or 0) or 0
    -- Only compare if both slots are occupied
    if link2 and link then
      if ilvl2 < ilvl then return link2, ilvl2 end
    elseif link2 and not link then
      return link2, ilvl2
    end
  end

  if not link then return nil, 0 end
  return link, ilvl
end

function NLC.Utils.GetTierCount()
  local tierSlots = { 1, 3, 5, 10, 7 } -- head, shoulder, chest, hands, legs
  local count = 0
  for _, slot in ipairs(tierSlots) do
    local tooltipData = C_TooltipInfo.GetInventoryItem("player", slot)
    if tooltipData and tooltipData.lines then
      for _, line in ipairs(tooltipData.lines) do
        local text = line.leftText or ""
        if text:find("%(%d/%d%)") or text:find("Set:") or text:find("Set Bonus") then
          count = count + 1
          break
        end
      end
    end
  end
  return count
end

function NLC.Utils.IsWarbound(itemLink)
  if not itemLink then return false end
  local tooltipData = C_TooltipInfo.GetItemByHyperlink(itemLink)
  if not tooltipData or not tooltipData.lines then return false end
  for _, line in ipairs(tooltipData.lines) do
    local text = line.leftText or ""
    if text:find("Warbound") or text:find("Account Bound") then
      return true
    end
  end
  return false
end

-- Armor type per class (for filtering council buttons)
NLC.Utils.CLASS_ARMOR = {
  WARRIOR = "Plate", PALADIN = "Plate", DEATHKNIGHT = "Plate",
  HUNTER = "Mail", SHAMAN = "Mail", EVOKER = "Mail",
  ROGUE = "Leather", MONK = "Leather", DRUID = "Leather", DEMONHUNTER = "Leather",
  MAGE = "Cloth", WARLOCK = "Cloth", PRIEST = "Cloth",
}

local ARMOR_SUBCLASS = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
local TIER_SLOTS = { INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_HAND = true, INVTYPE_LEGS = true }
local JEWELRY_SLOTS = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_NECK = true, INVTYPE_CLOAK = true }
local WEAPON_SLOTS = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true, INVTYPE_RANGED = true }

function NLC.Utils.GetAvailableCategories(itemLink, equipLoc, itemId)
  local result = { upgrade = false, catalyst = false, offspec = false, tmog = true }
  if not itemLink then return result end

  -- Recipes or items without equipLoc — show upgrade + tmog
  if not equipLoc or equipLoc == "" then
    result.upgrade = true
    return result
  end

  local _, playerClass = UnitClass("player")
  local myArmor = NLC.Utils.CLASS_ARMOR[playerClass]

  -- Jewelry/cloaks — universal, everyone can use
  if JEWELRY_SLOTS[equipLoc] then
    result.upgrade = true
    result.offspec = true
    return result
  end

  -- Weapons — check if player can equip this weapon type
  if WEAPON_SLOTS[equipLoc] then
    if IsEquippableItem(itemLink) then
      result.upgrade = true
      result.offspec = true
    end
    return result
  end

  -- Armor — check armor type via GetItemInfoInstant (synchronous)
  -- Returns: itemID, itemType(str), itemSubType(str), equipLoc, icon, classID(num), subclassID(num)
  local itemID, itemTypeStr, itemSubTypeStr, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemLink)

  -- Try numeric classID first (classID 4 = Armor)
  local isArmor = (classID == 4) or (itemTypeStr == "Armor")
  local armorSubType = ARMOR_SUBCLASS[subclassID] or itemSubTypeStr

  if isArmor then
    if armorSubType and armorSubType == myArmor then
      -- Primary armor type — full options
      result.upgrade = true
      result.offspec = true
      if TIER_SLOTS[equipLoc] then
        result.catalyst = true
        result.tmog = false  -- tier pieces should never be used for tmog
      end
    end
  elseif IsEquippableItem(itemLink) then
    -- Fallback: item is equippable but classID didn't match (e.g. API change, token items,
    -- or item not yet cached on raider's client when SESSION_START arrived)
    result.upgrade = true
    result.offspec = true
    if TIER_SLOTS[equipLoc] then
      result.catalyst = true
      result.tmog = false  -- tier slot — hide tmog even when armor type is unknown
    end
  end

  -- Wishlist filter: if upgrade would be available, check if this item is on the player's wishlist.
  -- If import data exists but the item is NOT wishlisted, disable upgrade.
  if result.upgrade and itemId then
    local playerName = UnitName("player")
    local imported = NLC.db and NLC.db.importData and NLC.db.importData.players and
                     NLC.db.importData.players[playerName]
    if imported and imported.wishlist and #imported.wishlist > 0 then
      local wishlisted = false
      for _, wid in ipairs(imported.wishlist) do
        if wid == itemId then wishlisted = true; break end
      end
      if not wishlisted then
        result.upgrade = false
      end
    end
  end

  return result
end

function NLC.Utils.DeepCopy(orig)
  if type(orig) ~= "table" then return orig end
  local copy = {}
  for k, v in pairs(orig) do
    copy[k] = NLC.Utils.DeepCopy(v)
  end
  return copy
end

function NLC.Utils.TableCount(t)
  local count = 0
  if t then for _ in pairs(t) do count = count + 1 end end
  return count
end

function NLC.Utils.Print(msg)
  print("|cff00ccff[NordavindLC]|r " .. msg)
end
