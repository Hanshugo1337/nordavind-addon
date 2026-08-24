-- Testrigg for tier-token-gjenkjenning.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/tiertoken_harness.lua',encoding='utf-8').read())"
--
-- Bruker meldte 2026-08-19: «/nordlc addall funker, men legger ikke til alle
-- tiersets». To feil laa bak.
--
-- 1) Spillet klassifiserer et armor token som Miscellaneous/Junk — samme
--    itemklasse som pets og skrot. Bekreftet i RCLootCouncils kilde to steder
--    (VotingFrame.lua: `classID == Enum.ItemClass.Miscellaneous and
--    Enum.ItemMiscellaneousSubclass.Junk == subClassID and L["Armor Token"]`,
--    og tokenData.lua: `if typeID == 15 and subTypeID == 0`). «Miscellaneous»
--    sto i EXCLUDED_TYPES, saa tokenet ble kastet ut EN LINJE FOER
--    token-sjekken. Hele tier-grenen var doed kode.
--
-- 2) Et token har itemSubType «Junk» og ingen egen linje som bare sier «Plate»,
--    saa rustningstypen maa leses ut av «Classes:»-linja i tooltipen.

CreateFrame = function()
  return { RegisterEvent = function() end, UnregisterEvent = function() end,
           UnregisterAllEvents = function() end, SetScript = function() end }
end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
GetTime = function() return 0 end
UnitName = function() return "Bobletount" end
UnitIsGroupLeader = function() return false end
UnitClass = function() return "Paladin", "PALADIN" end
IsEquippableItem = function() return false end

_G = _G or {}
ITEM_CLASSES_ALLOWED = "Classes: %s"
LOCALIZED_CLASS_NAMES_MALE = {
  WARRIOR = "Warrior", PALADIN = "Paladin", DEATHKNIGHT = "Death Knight",
  HUNTER = "Hunter", SHAMAN = "Shaman", EVOKER = "Evoker",
  ROGUE = "Rogue", MONK = "Monk", DRUID = "Druid", DEMONHUNTER = "Demon Hunter",
  MAGE = "Mage", WARLOCK = "Warlock", PRIEST = "Priest",
}

-- --- Itemene ---
local TOKEN = "|cffa335ee|Hitem:268999::::::::90:::::|h[Zenith Chestguard of the Awakening]|h|r"
local PET   = "|cffa335ee|Hitem:111222::::::::90:::::|h[Coiled Serpent Hatchling]|h|r"
local BRYST = "|cffa335ee|Hitem:268235::::::::90:::::|h[Vestment of the Awakening]|h|r"

-- 1 name 2 link 3 quality 4 ilvl 5 minLevel 6 type 7 subType 8 stack 9 equipLoc
local itemInfo = {
  [TOKEN] = { "Zenith Chestguard", TOKEN, 4, 678, 80, "Miscellaneous", "Junk", 1, "" },
  [PET]   = { "Coiled Serpent",    PET,   4, 0,   80, "Miscellaneous", "Companion Pets", 1, "" },
  [BRYST] = { "Vestment",          BRYST, 4, 671, 80, "Armor", "Plate", 1, "INVTYPE_CHEST" },
}

local tooltips = {
  -- Ekte tier-token-tooltip: ingen linje som bare sier «Plate».
  [TOKEN] = { { leftText = "Zenith Chestguard of the Awakening" },
              { leftText = "Classes: Paladin, Warrior, Death Knight" },
              { leftText = "Use: Bind to a chest piece." } },
  [PET]   = { { leftText = "Coiled Serpent Hatchling" },
              { leftText = "Use: Teaches you this pet." } },
  [BRYST] = { { leftText = "Vestment of the Awakening" },
              { leftText = "Plate" } },
}

C_Item = {
  GetItemInfo = function(link)
    local d = itemInfo[link]
    if not d then return nil end
    return d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9]
  end,
  GetItemInfoInstant = function(link) return 268999 end,
  DoesItemExist = function() return true end,
  GetItemGUID = function(loc) return "GUID-" .. loc.slot end,
}
C_TooltipInfo = {
  GetHyperlink = function(link)
    local l = tooltips[link]
    return l and { lines = l } or nil
  end,
  GetBagItem = function() return nil end,
}

-- Bagg: token i slot 1, pet i slot 2, vanlig bryst i slot 3.
local baggen = { [1] = TOKEN, [2] = PET, [3] = BRYST }
C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and 3 or 0 end,
  GetContainerItemLink = function(b, s) return b == 0 and baggen[s] or nil end,
}
ItemLocation = { CreateFromBagAndSlot = function(self, b, s) return { bag = b, slot = s } end }

NordavindLC_NS = { active = true, LootDetection = {},
  Comms = { IsRestricted = function() return false end, Send = function() end } }
dofile("NordavindLC/Utils.lua")
NordavindLC_NS.active = true
NordavindLC_NS.LootDetection = {}
NordavindLC_NS.Comms = { IsRestricted = function() return false end, Send = function() end }
NordavindLC_NS.Utils.IsTradeableBagItem = function(b, s) return b == 0 and baggen[s] ~= nil end
dofile("NordavindLC/LootDetection.lua")

local U = NordavindLC_NS.Utils
local LD = NordavindLC_NS.LootDetection
LD.Register()

-- --- 1: rustningstypen leses ut av klasselista ---
local rustning = U.GetTierTokenArmorType(TOKEN)
assert(rustning == "Plate",
       "forventet Plate fra «Classes: Paladin, ...», fikk " .. tostring(rustning))
print("token -> rustningstype : OK -> Plate, utledet fra klasselista")

-- Pets har ingen klasseliste og skal ikke se ut som et token.
assert(U.GetTierTokenArmorType(PET) == nil, "pet ble tatt for aa vaere et token")
print("pet   -> rustningstype : OK -> nil")

-- --- 2: tokenet overlever filteret og havner i panelet ---
local funnet = LD.ScanBagsForPanel()
local navn = {}
for _, it in ipairs(funnet) do navn[#navn + 1] = it.itemLink end

local harToken, harPet, harBryst = false, false, false
for _, it in ipairs(funnet) do
  if it.itemLink == TOKEN then harToken = true; assert(it.armorType == "Plate",
      "tokenet mistet armorType: " .. tostring(it.armorType)) end
  if it.itemLink == PET then harPet = true end
  if it.itemLink == BRYST then harBryst = true end
end

assert(harToken, "tier-tokenet ble filtrert bort — dette ER feilen brukeren meldte")
assert(harBryst, "vanlig tier-bryst forsvant")
assert(not harPet, "pet skal fortsatt filtreres bort")
assert(#funnet == 2, "forventet 2 items, fikk " .. #funnet)
print("filter                 : OK -> token + bryst med, pet ute")

print("\nALLE PAASTANDER HOLDT")
