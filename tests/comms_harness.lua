-- Testrigg for hvem som svarer paa council-oppkall.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/comms_harness.lua',encoding='utf-8').read())"
--
-- Bruker 2026-08-19: «Har en person som har addonet installert, men min addon
-- reagerer ikke at hun har den.» (Braxina.)
--
-- Comms registreres ved ADDON_LOADED, saa hun MOTTOK meldinga. Men baade
-- ROLL_CALL og VERSION_CHECK laa under «if not NLC.active then return end», saa
-- en uaktivert klient svarte aldri. Hun var usynlig for /nordlc version og for
-- opptellingen ved council-start — og siden en uaktivert klient heller ikke har
-- registrert noen events, auto-passet hun ikke og rapporterte ingen loot.

CreateFrame = function()
  return { RegisterEvent = function() end, UnregisterEvent = function() end,
           UnregisterAllEvents = function() end, SetScript = function() end }
end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end,
            NewTicker = function() return { Cancel = function() end } end }
IsInRaid = function() return true end
UnitName = function() return "Braxina" end
UnitIsGroupLeader = function() return false end
GetTime = function() return 0 end
Ambiguate = function(navn) return (navn:match("^([^-]+)")) or navn end
Enum = { AddOnRestrictionType = {}, AddOnRestrictionState = {} }

local sendt = {}

-- AceComm/AceSerializer stubbes: vi tester dispatchen, ikke biblioteket.
LibStub = function(navn)
  return {
    Embed = function(_, maal)
      maal.Serialize = function(_, ...) return { ... } end
      maal.Deserialize = function(_, m) return true, m[1], m[2] end
      maal.SendCommMessage = function(_, _, payload) table.insert(sendt, payload[1]) end
      maal.RegisterComm = function() end
      return maal
    end,
  }
end

local aktivertAv = nil
NordavindLC_NS = {
  active = false,
  isOfficer = false,
  version = "1.9.1",
  db = { config = { timer = 90 }, importData = { players = {} } },
  Utils = {
    Print = function(m) if m:find("Aktivert") or m:find("Activated") then aktivertAv = m end end,
    Diag = function() end,
    AddonVersion = function() return "1.9.1" end,
    TableCount = function() return 0 end,
    -- Hvem som er leder styres per scenario. Selve navnematchen har sin egen
    -- rigg (aktivering_harness); her testes dispatchen, ikke matchen.
    ErGruppeleder = function(avsender) return avsender == _G.LEDER_NAVN end,
  },
  Council = {}, UI = {}, LootDetection = {}, Comms = {},
}
local NLC = NordavindLC_NS

-- NLC.Activate finnes i Core.lua; her holder det aa vite at den ble kalt.
local aktiveringer = 0
NLC.Activate = function()
  NLC.active = true
  aktiveringer = aktiveringer + 1
end

dofile("NordavindLC/Comms.lua")

-- Avsenderen er en menig med mindre scenariet sier noe annet.
_G.LEDER_NAVN = "Revohunt-TwistingNether"

local function motta(msgType, data, avsender)
  sendt = {}
  NLC.Comms.OnMessage("NordLC", { msgType, data }, "RAID", avsender or "Bobletount-Draenor")
end

local function harSendt(t)
  for _, v in ipairs(sendt) do if v == t then return true end end
  return false
end

-- --- 1: uaktivert klient svarer paa ROLL_CALL ---
--
-- Aa SVARE og aa AKTIVERE er to ting, og de ble skilt 26.08. Svaret gaar
-- uansett hvem som spoer — ellers er hun usynlig i opptellingen, som var hele
-- poenget over. Aktiveringen krever lederen, se test 6.
NLC.active = false
aktiveringer = 0
motta("ROLL_CALL", "")
assert(harSendt("ROLL_CALL_ACK"),
       "svarte ikke paa ROLL_CALL — hun forblir usynlig i opptellingen")
assert(not NLC.active, "ROLL_CALL fra en menig skrudde paa auto-passet")
print("ROLL_CALL uaktivert   : OK -> svarer, aktiverer ikke")

-- --- 2: uaktivert klient svarer paa VERSION_CHECK ---
NLC.active = false
motta("VERSION_CHECK", "")
assert(harSendt("VERSION_REPLY"),
       "svarte ikke paa VERSION_CHECK — /nordlc version viser henne som «uten addon»")
assert(not NLC.active, "VERSION_CHECK fra en menig skrudde paa auto-passet")
print("VERSION_CHECK uaktiv. : OK -> svarer, aktiverer ikke")

-- --- 3: allerede aktiv skal fortsatt svare, uten aa aktivere paa nytt ---
NLC.active = true
aktiveringer = 0
motta("ROLL_CALL", "")
assert(harSendt("ROLL_CALL_ACK"), "aktiv klient sluttet aa svare")
assert(aktiveringer == 0, "aktiverte paa nytt selv om den allerede var aktiv")
print("allerede aktiv        : OK -> svarer, aktiverer ikke paa nytt")

-- --- 4: ACTIVATE_CHECK skal IKKE aktivere ---
-- Den er et spoersmaal, ikke bevis paa at noen holder paa. Ville den aktivert,
-- kunne to uaktiverte klienter vekket hverandre uten at en offiser var i gang.
NLC.active = false
aktiveringer = 0
motta("ACTIVATE_CHECK", "")
assert(not NLC.active, "ACTIVATE_CHECK skal ikke aktivere av seg selv")
assert(aktiveringer == 0, "aktiverte paa et spoersmaal")
print("ACTIVATE_CHECK        : OK -> aktiverer ikke")

-- --- 5: ACTIVATE fra lederen aktiverer, som foer ---
NLC.active = false
motta("ACTIVATE", "", _G.LEDER_NAVN)
assert(NLC.active, "ACTIVATE fra lederen sluttet aa aktivere")
print("ACTIVATE fra leder    : OK -> aktiverer fortsatt")

-- --- 6: ROLL_CALL fra lederen aktiverer OG svarer ---
NLC.active = false
motta("ROLL_CALL", "", _G.LEDER_NAVN)
assert(NLC.active, "ROLL_CALL fra lederen aktiverte ikke")
assert(harSendt("ROLL_CALL_ACK"), "svarte ikke lederen")
print("ROLL_CALL fra leder   : OK -> aktiverte og svarte")

print("\nALLE PAASTANDER HOLDT")
