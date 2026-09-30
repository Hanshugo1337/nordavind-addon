-- Hvilke knapper svarvinduet viser for et item.
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/kategorier_harness.lua',encoding='utf-8').read())"
--
-- 30.09.2026: Upgrade ble delt i BiS/Major/Stat, og Catalyst ble fjernet.
-- De tre skal vises paa noeyaktig de itemene Upgrade ble vist paa.

CreateFrame = function()
  return { RegisterEvent = function() end, UnregisterEvent = function() end,
           UnregisterAllEvents = function() end, SetScript = function() end }
end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function() return { Cancel = function() end } end }
GetTime = function() return 0 end
bit = { bxor = function(a, b) return a ~ b end }
UnitName = function() return "Bobletount" end
UnitClass = function() return "Paladin", "PALADIN" end   -- Plate
IsEquippableItem = function() return true end
local ARMOR = "Plate"
C_Item = { GetItemInfoInstant = function() return 1, "Armor", ARMOR, nil, nil, 4, nil end }

NordavindLC_NS = {}
dofile("NordavindLC/Utils.lua")
local NLC = NordavindLC_NS
NLC.db = { importData = { players = {} } }

local LENKE = "|cffa335ee|Hitem:270300::::::::90:::::|h[Ting]|h|r"

local function sjekk(r, forventet, hva)
  for _, k in ipairs({ "bis", "major", "stat", "offspec", "tmog" }) do
    assert(r[k] == forventet[k], hva .. ": " .. k .. " = " .. tostring(r[k]))
  end
  assert(r.upgrade == nil, hva .. ": upgrade skal ikke finnes lenger")
  assert(r.catalyst == nil, hva .. ": catalyst skal ikke finnes lenger")
end

sjekk(NLC.Utils.GetAvailableCategories(LENKE, "INVTYPE_FINGER", 270300),
  { bis = true, major = true, stat = true, offspec = true, tmog = true }, "ring")
sjekk(NLC.Utils.GetAvailableCategories(LENKE, "INVTYPE_CHEST", 270300),
  { bis = true, major = true, stat = true, offspec = true, tmog = true }, "tier-bryst, riktig rustning")
ARMOR = "Cloth"
sjekk(NLC.Utils.GetAvailableCategories(LENKE, "INVTYPE_CHEST", 270300),
  { bis = false, major = false, stat = false, offspec = false, tmog = true }, "tier-bryst, feil rustning")
print("knappene             : OK -> bis/major/stat der upgrade var, ingen catalyst")
