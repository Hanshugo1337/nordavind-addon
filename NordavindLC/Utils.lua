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
  local link = GetInventoryItemLink("player", slotId)
  if not link then return nil, 0 end
  local ilvl = GetDetailedItemLevelInfo(link) or 0
  return link, ilvl
end

function NLC.Utils.GetTierCount()
  local tierSlots = { 1, 3, 5, 10, 7 } -- head, shoulder, chest, hands, legs
  local count = 0
  for _, slot in ipairs(tierSlots) do
    local link = GetInventoryItemLink("player", slot)
    if link then
      local itemId = C_Item.GetItemInfoInstant(link)
      if itemId then
        local setInfo = C_Item.GetItemSetInfo(itemId)
        if setInfo then
          count = count + 1
        end
      end
    end
  end
  return count
end

function NLC.Utils.TableCount(t)
  local count = 0
  if t then for _ in pairs(t) do count = count + 1 end end
  return count
end

function NLC.Utils.Print(msg)
  print("|cff00ccff[NordavindLC]|r " .. msg)
end
