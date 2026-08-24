-- Testrigg for «kjoerte addonet i det hele tatt?»-spoersmaalet.
--
-- Kjoeres fra repo-rot:
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/inaktivlogg_harness.lua',encoding='utf-8').read())"
--
-- Bakgrunn: 22.08 hadde brukeren kjoert en hel raidkveld med addonet lastet, og
-- diagloggen var helt tom. Grunnen var at ENCOUNTER_END ble registrert inne i
-- Register(), som kun kalles fra Activate() — saa grenen «addon er IKKE aktiv»
-- kunne aldri naas. Det sikkerhetsnettet var doed kode.
--
-- Auto-rullen (START_LOOT_ROLL) skal IKKE flyttes med. Den maa bli liggende bak
-- Activate(), ellers ruller addonet Need/Pass for deg i tilfeldige pug-raid.

local registrerte = {}
local handler
GetTime = function() return 0 end
C_Timer = {
  After = function() end,
  NewTimer = function() return { Cancel = function() end } end,
}
CreateFrame = function()
  return {
    RegisterEvent = function(self, e) registrerte[e] = true end,
    UnregisterEvent = function(self, e) registrerte[e] = nil end,
    UnregisterAllEvents = function(self)
      for k in pairs(registrerte) do registrerte[k] = nil end
    end,
    SetScript = function(self, _, fn) handler = fn end,
  }
end
C_Container = { GetContainerNumSlots = function() return 0 end,
                GetContainerItemLink = function() return nil end }
ItemLocation = { CreateFromBagAndSlot = function(self) return {} end }
C_Item = { DoesItemExist = function() return false end, GetItemInfoInstant = function() return nil end }
UnitName = function() return "Bobletount" end
UnitIsGroupLeader = function() return false end

local diagLinjer = {}
NordavindLC_NS = {
  active = false,
  db = { diagLog = diagLinjer },
  LootDetection = {},
  Comms = { IsRestricted = function() return false end, Send = function() end },
  Utils = {
    Print = function() end,
    Diag = function(msg) table.insert(diagLinjer, msg) end,
    IsTradeableBagItem = function() return false end,
    IsWarbound = function() return false end,
    GetTierTokenArmorType = function() return nil end,
  },
}

dofile("NordavindLC/LootDetection.lua")
local LD = NordavindLC_NS.LootDetection

-- --- Scenario 1: ENCOUNTER_END lyttes paa uten at noen har aktivert ---
assert(registrerte["ENCOUNTER_END"],
  "ENCOUNTER_END maa vaere registrert ved innlasting, ellers kan loggen aldri svare")
print("scenario 1 (lytter ved load):  OK -> ENCOUNTER_END registrert")

-- --- Scenario 2: auto-rullen blir liggende bak Activate ---
assert(not registrerte["START_LOOT_ROLL"],
  "START_LOOT_ROLL maa IKKE registreres ved innlasting - det gjeninnfoerer pug-fella")
print("scenario 2 (rull bak aktiv):   OK -> START_LOOT_ROLL ikke registrert")

-- --- Scenario 3: en boss som doer mens addonet er av setter spor i loggen ---
handler(nil, "ENCOUNTER_END", 3009, "Ula'tek", 14, 20, 1)
local funnet = false
for _, linje in ipairs(diagLinjer) do
  if linje:find("IKKE aktiv", 1, true) then funnet = true end
end
assert(funnet, "ENCOUNTER_END mens inaktiv maa logge en linje, fikk " .. #diagLinjer .. " linjer")
assert(#LD.GetReport() == 0, "inaktivt addon skal ikke samle inn noe")
assert(not registrerte["BAG_UPDATE_DELAYED"], "inaktivt addon skal ikke aapne innsamlingsvindu")
print("scenario 3 (spor i loggen):    OK -> " .. diagLinjer[#diagLinjer])

-- --- Scenario 4: nettet overlever en Activate/Deactivate-runde ---
-- Unregister() kaller UnregisterAllEvents(), som river alt. Uten en ny
-- registrering etterpaa gaar ENCOUNTER_END moerk igjen ved foerste deaktivering.
LD.Register()
assert(registrerte["START_LOOT_ROLL"], "Register() skal slaa paa auto-rullen")
LD.Unregister()
assert(registrerte["ENCOUNTER_END"],
  "ENCOUNTER_END maa overleve Unregister(), ellers virker nettet kun frem til foerste Deactivate")
assert(not registrerte["START_LOOT_ROLL"],
  "START_LOOT_ROLL skal vaere av igjen etter Unregister()")
print("scenario 4 (overlever av/paa):  OK -> ENCOUNTER_END staar, rullen er av")

print("\nalle scenarier OK")
