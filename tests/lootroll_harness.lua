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
C_Item = { GetItemInfo = function() return nil, nil, nil, nil, nil, "Armor" end }

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

print("\nALLE PAASTANDER HOLDT")
