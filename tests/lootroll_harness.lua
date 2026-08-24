-- Testrigg for auto-rull-logikken i LootDetection.lua.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/lootroll_harness.lua',encoding='utf-8').read())"
--
-- Dekker fella som kostet oss et helt item: Need er bare tilbudt paa det egen
-- spec kan bruke, saa et ubetinget Need-rull blir forkastet i stillhet. Siden
-- alle andre auto-passer, ender itemet da uten et eneste gyldig rull.
--
-- Selve utsettelsen (C_Timer.After) kan bare bekreftes in-game.

-- --- WoW-API-stubber ---
local planlagte = {}
C_Timer = { After = function(sek, fn) table.insert(planlagte, { sek = sek, fn = fn }) end }
CreateFrame = function()
  return { RegisterEvent = function() end, UnregisterEvent = function() end,
           UnregisterAllEvents = function() end, SetScript = function() end }
end
UnitIsGroupLeader = function() return true end
GetLootRollItemLink = function() return "[Testitem]" end
-- 1 id 2 type 3 subType 4 equipLoc 5 icon 6 classID 7 subclassID
local vareKlasse, vareUnderklasse = 4, 0
C_Item = {
  GetItemInfo = function() return nil, nil, nil, nil, nil, "Armor" end,
  GetItemInfoInstant = function() return 1, nil, nil, nil, nil, vareKlasse, vareUnderklasse end,
}
Enum = { ItemMiscellaneousSubclass = { Junk = 0, Reagent = 1, CompanionPet = 2, Holiday = 3, Other = 4, Mount = 5 } }

-- Toy-boksen svarer med navn kun for ekte toys.
erToy = false
C_ToyBox = {
  GetToyInfo = function(itemID)
    if not erToy then return nil end
    return itemID, "Et leketoey", "ikon", false, false, 3
  end,
}

-- Settes per scenario. Rekkefoelgen foelger GetLootRollItemInfo:
-- 1 texture, 2 name, 3 count, 4 quality, 5 bindOnPickUp, 6 canNeed, ... 13 canTransmog
local kanNeed, kanTransmog
GetLootRollItemInfo = function()
  return nil, nil, nil, 4, nil, kanNeed, nil, nil, nil, nil, nil, nil, kanTransmog
end

NordavindLC_NS = { LootDetection = {}, Comms = { IsRestricted = function() return false end } }

dofile("NordavindLC/LootDetection.lua")

local NLC = NordavindLC_NS
local rulletype = NLC.LootDetection._leaderRollType
assert(rulletype, "_leaderRollType ble ikke eksponert")

local PASS, NEED, GREED, TMOG = 0, 1, 2, 4

-- Scenario 1: Need er lov (egen rustningstype) -> Need
kanNeed, kanTransmog = true, true
assert(rulletype(1) == NEED, "Need var lov, men fikk " .. tostring(rulletype(1)))
print("scenario 1 (Need lov): OK -> Need")

-- Scenario 2: Need ikke lov, men Transmog er -> Transmog, ikke Need
kanNeed, kanTransmog = false, true
assert(rulletype(1) == TMOG, "forventet Transmog, fikk " .. tostring(rulletype(1)))
print("scenario 2 (feil rustningstype, tmog lov): OK -> Transmog")

-- Scenario 3: verken Need eller Transmog -> Greed. Aldri Disenchant: det er
-- councilets avgjoerelse, ikke auto-rullerens.
kanNeed, kanTransmog = false, false
assert(rulletype(1) == GREED, "forventet Greed, fikk " .. tostring(rulletype(1)))
assert(rulletype(1) ~= 3, "Disenchant skal aldri velges automatisk")
print("scenario 3 (verken need eller tmog): OK -> Greed")

-- Det gamle ubetingede Need-rullet ville returnert 1 i alle tre. At scenario 2
-- og 3 gir noe annet, ER rettelsen.
kanNeed, kanTransmog = false, false
assert(rulletype(1) ~= NEED, "regresjon: ruller fortsatt Need naar det ikke er lov")

-- Auto-pass hos alle andre enn lederen.
--
-- Regelen fra raidlederen: pets, toys og mounts ruller folk fritt paa, alt annet
-- passer de. Tier-tokens ligger i itemklasse Miscellaneous (15) med underklasse
-- Junk (0) — samme klasse som pets og mounts. Den gamle sjekken var «itemType ~=
-- Miscellaneous», saa raiderne passet ALDRI paa et token: rullen gikk full tid,
-- og hvem som helst kunne Neede itemet lederen skulle dele ut.
local erRaadsloot = NLC.LootDetection._erCouncilLoot
assert(erRaadsloot, "_erCouncilLoot ble ikke eksponert")

vareKlasse, vareUnderklasse = 4, 1          -- vanlig rustning
assert(erRaadsloot("[Bryst]") == true, "vanlig utstyr skal auto-passes")

vareKlasse, vareUnderklasse = 15, 0         -- Miscellaneous / Junk = tier-token
assert(erRaadsloot("[Token]") == true,
       "tier-token ble IKKE auto-passet — det er feilen fra 19.08")

vareKlasse, vareUnderklasse = 15, 2         -- Companion Pet
assert(erRaadsloot("[Pet]") == false, "pets skal folk faa rulle paa")

vareKlasse, vareUnderklasse = 15, 5         -- Mount
assert(erRaadsloot("[Mount]") == false, "mounts skal folk faa rulle paa")

-- Toys ligger ikke i én bestemt itemklasse, saa de spoerres om for seg.
-- Her er itemet en helt vanlig Miscellaneous/Other som toy-boksen kjenner igjen.
vareKlasse, vareUnderklasse = 15, 4
erToy = true
assert(erRaadsloot("[Toy]") == false, "toys skal folk faa rulle paa")
erToy = false
assert(erRaadsloot("[Ikke-toy]") == true,
       "samme itemklasse UTEN toy-treff skal fortsatt auto-passes")

assert(erRaadsloot(nil) == true, "uten lenke passer vi, framfor aa staa stille")
print("scenario 4 (auto-pass): OK -> pets, toys og mounts fritatt, resten passes")

print("\nALLE PAASTANDER HOLDT")
