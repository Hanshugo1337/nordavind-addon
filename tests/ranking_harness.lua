-- Testrigg for at rangeringsvinduet ikke ender tomt.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/ranking_harness.lua',encoding='utf-8').read())"
--
-- Bruker 2026-08-19: «rangeringsvinduet er tomt». To filtre i BuildRanking kunne
-- toemme lista, og begge slaar til i et cross-realm raid — som er nettopp det
-- Nordavind kjoerer (Draenor, Stormscale, TarrenMill, Darksorrow samme kveld).
--
-- 1) UnitClass tar en unit-id. Et spillernavn duger for folk i gruppa di, men
--    cross-realm MAA realmen vaere med. Offiseren strippet den og falt tilbake
--    paa «WARRIOR» for alle. Paa et tier-token sammenlignet rustningsfilteret da
--    Plate mot alle: var tokenet Cloth, ble HVER kandidat kastet ut.
--
-- 2) Front-end fritar tier-slots fra wishlist-filteret, rangeringen gjorde ikke.
--    Raideren kunne trykke «Upgrade» paa en tier-del og likevel forsvinne.

CreateFrame = function()
  return { RegisterEvent = function() end, UnregisterEvent = function() end,
           UnregisterAllEvents = function() end, SetScript = function() end }
end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function() return { Cancel = function() end } end }
GetTime = function() return 0 end
IsInRaid = function() return true end
UnitIsGroupLeader = function() return true end
UnitName = function() return "Bobletount" end
date = date or function() return "2026-08-19" end
bit = { bxor = function(a, b) return a ~ b end }

-- Cross-realm raid. UnitClass svarer KUN paa fullt navn med realm, slik spillet
-- oppfoerer seg. Rosteret kjenner alle.
local roster = {
  { navn = "Bobletount-Draenor",  klasse = "PALADIN" },  -- Plate
  { navn = "Moggin-TarrenMill",   klasse = "WARLOCK" },  -- Cloth
  { navn = "Areniir-Darksorrow",  klasse = "PRIEST"  },  -- Cloth
  { navn = "Shotgrogg-Stormscale",klasse = "WARRIOR" },  -- Plate
}
UnitClass = function(id)
  for _, r in ipairs(roster) do
    if r.navn == id then return "visningsnavn", r.klasse end
  end
  return nil
end
GetNumGroupMembers = function() return #roster end
GetRaidRosterInfo = function(i)
  local r = roster[i]
  if not r then return nil end
  return r.navn, 0, 1, 80, "Klasse", r.klasse
end

NordavindLC_NS = {}
dofile("NordavindLC/Utils.lua")
local NLC = NordavindLC_NS
NLC.isOfficer = true
NLC.db = { config = { timer = 90 }, importData = { players = {} }, weeklyLoot = { counts = {} } }

local wishlister = {}
NLC.Scoring = {
  GetImportedScore = function(navn)
    return { rank = "raider", role = "dps", baseScore = 40, wishlist = wishlister[navn] or {} }
  end,
  Calculate = function() return 40, {} end,
  GetWarnings = function() return {} end,
  SeasonLootCount = function() return 0 end,
}
NLC.Comms = { Send = function() end, SendMultiSession = function() end,
              SendRollCall = function() end, IsRestricted = function() return false end }
NLC.UI = { ShowMultiItemPopup = function() end, ShowWizard = function() end,
           HideMultiItemPopup = function() end, IsWizardOpen = function() return false end }
NLC.Theme = { Debounce = function(_, _, fn) fn() end }
NLC.LootDetection = { GetCurrentBoss = function() return "Nek'zali" end }
NLC.Trade = { Add = function() end }
dofile("NordavindLC/Council.lua")

local function navnene(rangert)
  local t = {}
  for _, c in ipairs(rangert) do t[#t + 1] = c.name end
  table.sort(t)
  return table.concat(t, ", ")
end

-- --- 1: klassen loeses opp cross-realm ---
assert(NLC.Utils.ClassForPlayer("Moggin-TarrenMill") == "WARLOCK",
       "fullt navn med realm ga ikke klassen")
assert(NLC.Utils.ClassForPlayer("Moggin") == "WARLOCK",
       "kortformen fant ikke klassen via rosteret")
assert(NLC.Utils.ClassForPlayer("Ukjentfyr-Annen") == nil,
       "en som ikke er i raidet skal gi nil, ikke en gjetning")
print("klasseoppslag        : OK -> cross-realm loest, ukjent gir nil")

-- --- 2: Cloth-token i et cross-realm raid ---
local token = {
  sessionIdx = 1, itemLink = "|cffa335ee|Hitem:268999::::::::90:::::|h[Token]|h|r",
  itemId = 268999, ilvl = 678, equipLoc = "", armorType = "Cloth",
  interests = {}, phase = "ranking",
}
for _, r in ipairs(roster) do
  local kort = r.navn:match("^([^-]+)")
  token.interests[kort] = {
    category = "upgrade", equippedIlvl = 660, tierCount = 2,
    class = NLC.Utils.ClassForPlayer(r.navn),
  }
end

local rangert = NLC.Council.BuildRanking(token)
assert(#rangert > 0, "TOMT rangeringsvindu paa et Cloth-token — dette ER feilen")
assert(#rangert == 2, "forventet de to cloth-klassene, fikk " .. #rangert .. ": " .. navnene(rangert))
assert(navnene(rangert) == "Areniir, Moggin",
       "feil kandidater: " .. navnene(rangert))
print("Cloth-token          : OK -> " .. navnene(rangert) .. " (plate filtrert bort)")

-- Med den gamle «WARRIOR»-gjettinga ville CLASS_ARMOR gitt Plate for alle fire,
-- og Plate ~= Cloth hadde kastet ut samtlige.

-- --- 3: ukjent klasse skal vises, ikke forsvinne ---
token.interests["Nykommer"] = { category = "upgrade", equippedIlvl = 650, tierCount = 0, class = nil }
local medUkjent = NLC.Council.BuildRanking(token)
local fantUkjent = false
for _, c in ipairs(medUkjent) do if c.name == "Nykommer" then fantUkjent = true end end
assert(fantUkjent, "ukjent klasse ble filtrert bort i stillhet")
print("ukjent klasse        : OK -> vises for offiseren i stedet for aa forsvinne")

-- --- 4: tier-slot uten wishlist skal IKKE filtreres ---
wishlister["Moggin"] = { 999999 }  -- har wishlist, men ikke dette itemet
local tierDel = {
  sessionIdx = 2, itemLink = "|cffa335ee|Hitem:268235::::::::90:::::|h[Tier-bryst]|h|r",
  itemId = 268235, ilvl = 671, equipLoc = "INVTYPE_CHEST",
  interests = { Moggin = { category = "upgrade", equippedIlvl = 660, tierCount = 2, class = "WARLOCK" } },
  phase = "ranking",
}
local tierRangert = NLC.Council.BuildRanking(tierDel)
assert(#tierRangert == 1,
       "tier-slot ble filtrert bort av wishlist-filteret — front-end fritar den, rangeringen maa ogsaa")
print("tier-slot + wishlist : OK -> beholdt, som i knappefilteret")

-- --- 5: vanlig slot uten wishlist skal fortsatt filtreres ---
local vanlig = {
  sessionIdx = 3, itemLink = "|cffa335ee|Hitem:270162::::::::90:::::|h[Ring]|h|r",
  itemId = 270162, ilvl = 671, equipLoc = "INVTYPE_FINGER",
  interests = { Moggin = { category = "upgrade", equippedIlvl = 660, tierCount = 2, class = "WARLOCK" } },
  phase = "ranking",
}
assert(#NLC.Council.BuildRanking(vanlig) == 0,
       "wishlist-filteret skal fortsatt gjelde utenfor tier-slots")
print("vanlig slot          : OK -> wishlist-filteret gjelder fortsatt")

print("\nALLE PAASTANDER HOLDT")
