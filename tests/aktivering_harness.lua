-- Testrigg for HVEM som har lov til aa skru addonet paa hos andre.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/aktivering_harness.lua',encoding='utf-8').read())"
--
-- Bruker 2026-08-26: «Vi pugga tidligere, da passa den for flere av oss...»
--
-- Regelen har hele tiden vaert at LEDEREN faar popupen og sier ja, og at resten
-- foelger etter. Chatlinja lovte det ogsaa («Activated by raid leader.»), men
-- avsenderen ble aldri sjekket. Dermed kunne hvem som helst med et hengende
-- active-flagg — typisk etter /nordlc test — svare paa ACTIVATE_CHECK og skru
-- paa auto-passet hos hele pugen. Ingen leder ble spurt om noe.
--
-- Cross-realm og norske navn er ikke en detalj her: avsenderen kommer som
-- «Navn-Realm», rosteret kan svare «Navn», og UnitIsUnit sammenligner ikke
-- «Æver» og «æver» likt. Bommer navnematchen, slipper ingen leder gjennom og
-- addonet er dødt i stedet for utrygt.

CreateFrame = function()
  return { RegisterEvent = function() end, UnregisterEvent = function() end,
           UnregisterAllEvents = function() end, SetScript = function() end }
end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end,
            NewTicker = function() return { Cancel = function() end } end }
IsInRaid = function() return true end
UnitName = function() return "Braxina" end
GetTime = function() return 0 end
Enum = { AddOnRestrictionType = {}, AddOnRestrictionState = {} }

-- Spillets egen realm-stripper.
Ambiguate = function(navn, _) return (navn:match("^([^-]+)")) or navn end
-- UnitIsUnit duger ikke som eneste kilde (se toppen), saa riggen lar den bomme
-- paa alt. Klarer koden testene likevel, hviler den ikke paa den.
UnitIsUnit = function() return false end

-- Rosteret. rang 2 = leder, jf. GetRaidRosterInfo.
local roster = {
  { navn = "Bobletount-Draenor", rang = 0 },
  { navn = "Revohunt-TwistingNether", rang = 2 },
  { navn = "Braxina", rang = 0 },
}
GetNumGroupMembers = function() return #roster end
GetRaidRosterInfo = function(i)
  local r = roster[i]
  if not r then return nil end
  return r.navn, r.rang
end

local jegErLeder = false
UnitIsGroupLeader = function() return jegErLeder end

local sendt = {}

LibStub = function()
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

dofile("NordavindLC/Utils.lua")
local NLC = NordavindLC_NS
NLC.Utils.Print = function() end
NLC.Utils.Diag = function() end
NLC.Utils.AddonVersion = function() return "1.9.2" end
NLC.Utils.TableCount = function() return 0 end
NLC.active = false
NLC.isOfficer = false
NLC.version = "1.9.2"
NLC.db = { config = { timer = 90 }, importData = { players = {} } }
NLC.Council = {}
NLC.UI = {}
NLC.LootDetection = {}

local aktiveringer = 0
NLC.Activate = function()
  NLC.active = true
  aktiveringer = aktiveringer + 1
end

dofile("NordavindLC/Comms.lua")

local LEDER, MENIG = "Revohunt-TwistingNether", "Bobletount-Draenor"

local function motta(msgType, avsender, data)
  sendt = {}
  aktiveringer = 0
  NLC.Comms.OnMessage("NordLC", { msgType, data }, "RAID", avsender)
end

local function harSendt(t)
  for _, v in ipairs(sendt) do if v == t then return true end end
  return false
end

-- --- 1: ACTIVATE fra en menig skal IKKE aktivere ---
-- Selve pug-feilen. En med hengende active-flagg kringkastet, og alle fulgte.
NLC.active = false
motta("ACTIVATE", MENIG)
assert(not NLC.active, "ACTIVATE fra en menig aktiverte addonet — dette er pug-feilen")
assert(aktiveringer == 0, "aktiverte paa melding fra en som ikke er leder")
print("ACTIVATE fra menig    : OK -> ignorert")

-- --- 2: ACTIVATE fra lederen skal aktivere ---
NLC.active = false
motta("ACTIVATE", LEDER)
assert(NLC.active, "ACTIVATE fra lederen aktiverte ikke — da virker ikke addonet i raid")
print("ACTIVATE fra leder    : OK -> aktiverte")

-- --- 3: norsk navn, annen kasus, realm paa den ene siden ---
-- Rosteret svarer «Æver-TarrenMill», avsenderen kommer som «æver».
roster[2] = { navn = "Æver-TarrenMill", rang = 2 }
NLC.active = false
motta("ACTIVATE", "æver")
assert(NLC.active, "leder med norsk navn i annen kasus ble ikke gjenkjent")
print("norsk navn/kasus      : OK -> gjenkjent som leder")
roster[2] = { navn = LEDER, rang = 2 }

-- --- 4: en aktiv menig skal ikke svare paa ACTIVATE_CHECK ---
-- Svaret ER en aktivering hos mottakeren. Bare lederen faar gi det.
NLC.active = true
jegErLeder = false
motta("ACTIVATE_CHECK", MENIG)
assert(not harSendt("ACTIVATE"),
       "en aktiv menig svarte paa ACTIVATE_CHECK — én hengende klient smitter hele raidet")
print("CHECK -> aktiv menig  : OK -> svarer ikke")

-- --- 5: en aktiv leder skal svare ---
NLC.active = true
jegErLeder = true
motta("ACTIVATE_CHECK", MENIG)
assert(harSendt("ACTIVATE"), "lederen svarte ikke — raidere som logger inn sent blir staaende av")
print("CHECK -> aktiv leder  : OK -> svarer")
jegErLeder = false

-- --- 6: SESSION_START fra en menig skal ikke aktivere ---
NLC.active = false
motta("SESSION_START", MENIG, { items = {}, timer = 90 })
assert(not NLC.active, "SESSION_START fra en menig aktiverte")
print("SESSION_START menig   : OK -> ignorert")

-- --- 7: ROLL_CALL fra en menig: svar, men IKKE aktiver ---
-- Braxina-kravet fra 19.08 staar: en installert men uaktivert klient maa vaere
-- synlig i opptellingen. Aa svare er noe annet enn aa skru paa auto-passet.
NLC.active = false
motta("ROLL_CALL", MENIG)
assert(harSendt("ROLL_CALL_ACK"), "sluttet aa svare paa ROLL_CALL — usynlig i opptellingen")
assert(not NLC.active, "ROLL_CALL fra en menig aktiverte auto-passet")
print("ROLL_CALL menig       : OK -> svarer, aktiverer ikke")

-- --- 8: VERSION_CHECK likedan ---
NLC.active = false
motta("VERSION_CHECK", MENIG)
assert(harSendt("VERSION_REPLY"), "sluttet aa svare paa VERSION_CHECK")
assert(not NLC.active, "VERSION_CHECK fra en menig aktiverte auto-passet")
print("VERSION_CHECK menig   : OK -> svarer, aktiverer ikke")

-- --- 9: ROLL_CALL fra lederen aktiverer ---
NLC.active = false
motta("ROLL_CALL", LEDER)
assert(NLC.active, "ROLL_CALL fra lederen aktiverte ikke")
assert(harSendt("ROLL_CALL_ACK"), "svarte ikke lederen")
print("ROLL_CALL leder       : OK -> aktiverte og svarte")

-- --- 10: uten leder i rosteret slipper ingen gjennom ---
-- Solo, eller et roster som ikke er lest inn enda. Da skal svaret vaere nei,
-- ikke «vet ikke, saa ja».
roster[2] = { navn = LEDER, rang = 0 }
NLC.active = false
motta("ACTIVATE", LEDER)
assert(not NLC.active, "aktiverte selv om ingen i rosteret var leder")
print("ingen leder i roster  : OK -> ignorert")
roster[2] = { navn = LEDER, rang = 2 }

print("\nALLE PAASTANDER HOLDT")
