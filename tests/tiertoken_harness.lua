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

-- Sett-ID-en ligger paa plass 16 i GetItemInfo. Det er den nettsida filtrerer
-- paa (`lib/tier-sims.ts`), og den NorthernSkyRaidTools bruker til samme sjekk.
local settId = {}

C_Item = {
  GetItemInfo = function(link)
    local d = itemInfo[link]
    if not d then return nil end
    return d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9],
           nil, nil, nil, nil, nil, nil, settId[link]
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

-- --- 3: tier telles fra GJELDENDE sett, ikke forrige ---
--
-- `GetTierCount` leste tooltipen etter «Set:» eller «(2/5)». Forrige sesongs
-- tier har noeyaktig de samme linjene — bonusen er slaatt av, men teksten staar.
-- Da talte vi fjoraarets brikker som om de var aarets, og siden gevinsten faller
-- til null ved fire brikker kunne en spiller med ETT stykke gjeldende tier bli
-- vist som ferdig utstyrt for councilet.
--
-- Sett-ID-en skiller dem. Maalt mot Blizzard-API-et 26.08.2026: 1931-1990 er
-- forrige tier, 2056-2066 er Venomous Abyss. Nettsida bruker vinduet 2000-2099
-- (`TIER_SETT_MIN`/`MAX` i lib/tier-sims.ts) — addonet MAA bruke det samme,
-- ellers rangerer de to ulikt igjen.
local HODE    = "|cffa335ee|Hitem:300001::::::::90:::::|h[Aarets hjelm]|h|r"
local SKULDRE = "|cffa335ee|Hitem:300002::::::::90:::::|h[Aarets skuldre]|h|r"
local BRYSTET = "|cffa335ee|Hitem:300003::::::::90:::::|h[Aarets bryst]|h|r"
local HENDER  = "|cffa335ee|Hitem:300004::::::::90:::::|h[Fjoraarets hansker]|h|r"
local BEINA   = "|cffa335ee|Hitem:300005::::::::90:::::|h[Vanlige bukser]|h|r"

for _, l in ipairs({ HODE, SKULDRE, BRYSTET, HENDER, BEINA }) do
  itemInfo[l] = { "Utstyr", l, 4, 300, 80, "Armor", "Plate", 1, "INVTYPE_CHEST" }
end
settId[HODE], settId[SKULDRE], settId[BRYSTET] = 2058, 2058, 2058  -- gjeldende
settId[HENDER] = 1955                                              -- forrige tier
settId[BEINA]  = nil                                               -- ikke i noe sett

-- head 1, shoulder 3, chest 5, legs 7, hands 10
local utstyr = { [1] = HODE, [3] = SKULDRE, [5] = BRYSTET, [7] = BEINA, [10] = HENDER }
GetInventoryItemLink = function(enhet, slot)
  if enhet ~= "player" then return nil end
  return utstyr[slot]
end

-- Tooltip-veien den GAMLE koden gikk. Fire av fem har sett-linjer, saa den
-- gamle tellingen gir 4 der den nye gir 3. Uten denne stubben ville testen
-- feilet paa nil i stedet for paa selve feilen.
C_TooltipInfo.GetInventoryItem = function(enhet, slot)
  local link = utstyr[slot]
  if not link or not settId[link] then return nil end
  return { lines = { { leftText = "Sett (2/5)" }, { leftText = "Set: noe bra" } } }
end

local antall = U.GetTierCount()
assert(antall == 3,
       "ventet 3 brikker fra gjeldende tier, fikk " .. tostring(antall)
       .. " (forrige tier eller sett-loese items ble talt med)")
print("tier-telling           : OK -> 3 av aarets, fjoraarets ikke talt")

-- --- 4: sett-vinduet skal ligge ett sted, og stemme med nettsida ---
assert(U.TIER_SETT_MIN == 2000 and U.TIER_SETT_MAX == 2099,
       "sett-vinduet stemmer ikke med lib/tier-sims.ts (2000-2099): "
       .. tostring(U.TIER_SETT_MIN) .. "-" .. tostring(U.TIER_SETT_MAX))
print("sett-vindu             : OK -> 2000-2099, samme som nettsida")
