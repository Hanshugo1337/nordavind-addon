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
      -- Kanal og mottaker maa med: en gjenopptatt sesjon skal HVISKES til den
      -- ene som spurte, ikke kringkastes til raidet. Kringkastet ville den
      -- revet opp igjen popupen hos alle som allerede hadde svart.
      maal.SendCommMessage = function(_, _, payload, kanal, mottaker)
        table.insert(sendt, { typ = payload[1], data = payload[2],
                              kanal = kanal, mottaker = mottaker })
      end
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
  Council = {},
  -- SESSION_CLOSE-grenen ble aldri kjoert her foer leder-porten kom,
  -- saa denne stubben manglet.
  UI = { HideMultiItemPopup = function() end },
  LootDetection = {}, Comms = {},
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
  for _, v in ipairs(sendt) do if v.typ == t then return true end end
  return false
end

local function sendtSom(t)
  for _, v in ipairs(sendt) do if v.typ == t then return v end end
  return nil
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

-- --- 7: SESSION_START fra en MENIG officer skal ignoreres ---
-- Kun raidlederen starter council. Uten denne porten kunne en officer paa
-- gammel build, eller med hengende tilstand, drive interesse-popupen hos hele
-- raidet — samme felle som ACTIVATE hadde: meldinga het «fra raid leader»,
-- men avsenderen ble aldri sjekket.
NLC.active = true
_G.__startet, _G.__lukket = 0, 0
NLC.Council.OnMultiSessionStart = function() _G.__startet = _G.__startet + 1 end
NLC.Council.OnSessionClose = function() _G.__lukket = _G.__lukket + 1 end

motta("SESSION_START", { items = {}, timer = 90 }, "Prectus-Kazzak")
assert(_G.__startet == 0,
       "SESSION_START fra en ikke-leder startet councilet likevel")
print("SESSION_START menig   : OK -> ignorert")

-- --- 8: SESSION_START fra lederen skal gaa gjennom ---
_G.__startet = 0
motta("SESSION_START", { items = {}, timer = 90 }, _G.LEDER_NAVN)
assert(_G.__startet == 1, "SESSION_START fra lederen naadde ikke fram")
print("SESSION_START leder   : OK -> gaar gjennom")

-- --- 9: SESSION_CLOSE foelger samme regel ---
-- Den baerer rangeringsdataene alle andre faar. Stoler vi ikke paa hvem som
-- startet, kan vi ikke stole paa hvem som lukker.
_G.__lukket = 0
motta("SESSION_CLOSE", {}, "Prectus-Kazzak")
assert(_G.__lukket == 0, "SESSION_CLOSE fra en ikke-leder ble godtatt")
motta("SESSION_CLOSE", {}, _G.LEDER_NAVN)
assert(_G.__lukket == 1, "SESSION_CLOSE fra lederen naadde ikke fram")
print("SESSION_CLOSE         : OK -> kun fra lederen")

print("\nALLE PAASTANDER HOLDT")

-- --- 10: en klient som nettopp er aktivert ber om sesjonen paa nytt ---
--
-- Reloader en raider midt i et council, ligger sesjonen kun i minnet og er
-- borte for godt. Popupen kommer ikke tilbake, han svarer aldri, og offiseren
-- venter paa et svar som aldri kan komme — 90-sekunderstimeren maa loepe ut.
-- Dette var den siste kjente maaten aa falle ut av et council paa.
--
-- Spoersmaalet henges paa aktiveringen fordi det er noeyaktig det oeyeblikket
-- en gjeninnlastet klient melder seg igjen. Da fyrer det én gang, ikke i loekke.
NLC.active = false
motta("ACTIVATE", "", _G.LEDER_NAVN)
assert(NLC.active, "ACTIVATE fra lederen aktiverte ikke")
assert(harSendt("SESSION_RESUME_REQ"),
       "spurte ikke om en paagaaende sesjon etter aktivering")
print("ber om gjenopptak     : OK -> spoer én gang ved aktivering")

-- --- 11: lederen hvisker sesjonen tilbake til den som spurte ---
NLC.active = true
UnitIsGroupLeader = function() return true end
NLC.Council.HasOpenCollecting = function() return true end
NLC.Council.CollectingSnapshot = function()
  return { items = { { sessionIdx = 1, itemLink = "|h[Ting]|h", itemId = 7 } }, timer = 42 }
end

motta("SESSION_RESUME_REQ", "", "Bobletount-Draenor")
local svar = sendtSom("SESSION_RESUME")
assert(svar, "lederen svarte ikke paa SESSION_RESUME_REQ")
assert(svar.kanal == "WHISPER",
       "sesjonen ble sendt paa " .. tostring(svar.kanal) .. ", ikke hvisket")
assert(svar.mottaker == "Bobletount-Draenor",
       "hvisket til " .. tostring(svar.mottaker) .. " i stedet for den som spurte")
assert(svar.data and svar.data.timer == 42, "gjenstaaende tid fulgte ikke med")
print("leder svarer          : OK -> hvisket til den ene, med tid igjen")

-- --- 12: ingen aapen innsamling betyr stillhet ---
-- Uten dette ville hver eneste reload i raidet utloese en runde meldinger.
NLC.Council.HasOpenCollecting = function() return false end
motta("SESSION_RESUME_REQ", "", "Bobletount-Draenor")
assert(not harSendt("SESSION_RESUME"),
       "svarte med en sesjon som ikke finnes")
print("ingen sesjon aapen    : OK -> stille")

-- --- 13: kun lederen svarer ---
-- Samme regel som SESSION_START. Svarte enhver officer, kunne en klient med
-- hengende tilstand dyttet en gammel sesjon inn hos en som nettopp reloadet.
NLC.Council.HasOpenCollecting = function() return true end
UnitIsGroupLeader = function() return false end
motta("SESSION_RESUME_REQ", "", "Bobletount-Draenor")
assert(not harSendt("SESSION_RESUME"), "en ikke-leder svarte med sesjonen sin")
UnitIsGroupLeader = function() return true end
print("kun lederen svarer    : OK")

-- --- 14: den gjenopptatte sesjonen godtas kun fra lederen ---
NLC.active = true
_G.__startet = 0
NLC.Council.OnMultiSessionStart = function() _G.__startet = _G.__startet + 1 end

motta("SESSION_RESUME", { items = {}, timer = 42 }, "Prectus-Kazzak")
assert(_G.__startet == 0, "SESSION_RESUME fra en ikke-leder ble godtatt")
motta("SESSION_RESUME", { items = {}, timer = 42 }, _G.LEDER_NAVN)
assert(_G.__startet == 1, "SESSION_RESUME fra lederen naadde ikke fram")
print("gjenopptak fra leder  : OK -> kun fra lederen")
