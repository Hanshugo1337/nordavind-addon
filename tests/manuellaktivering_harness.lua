-- Testrigg for /nordlc activate og hoeyreklikk paa addon-ikonet.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/manuellaktivering_harness.lua',encoding='utf-8').read())"
--
-- Lederporten i Comms stengte fjernaktiveringen 26.08, men den manuelle veien
-- sto fortsatt aapen: hvem som helst kunne skrive /nordlc activate og dermed
-- auto-passe paa alt i en pug. Ingen andre enn lederen TRENGER aa aktivere —
-- resten tas av lederens ACTIVATE — saa kommandoen skal si nei til dem.
--
-- Hoeyreklikk paa ikonet maa gjennom samme port. Ellers er den bare et
-- omvei rundt kommandoen, og det er den veien folk faktisk bruker.

local hendelser = {}
CreateFrame = function()
  return {
    RegisterEvent = function(_, e) hendelser[e] = true end,
    UnregisterEvent = function() end,
    UnregisterAllEvents = function() end,
    SetScript = function() end,
  }
end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end,
            NewTicker = function() return { Cancel = function() end } end }
C_AddOns = { GetAddOnMetadata = function() return "1.9.2" end }
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 100 end }
GetTime = function() return 0 end
UnitName = function() return "Bobletount" end
GetGuildInfo = function() return nil end
GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end,
                Hide = function() end }
UIParent = {}
time = time or os.time
SlashCmdList = {}
-- WoW utvider string med trim; standard Lua har den ikke.
getmetatable("").__index.trim = function(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local iRaid, erLeder = true, false
IsInRaid = function() return iRaid end
UnitIsGroupLeader = function() return erLeder end

local utskrift = {}
NordavindLC_NS = {
  Utils = {
    Print = function(m) table.insert(utskrift, m) end,
    Diag = function() end,
    TableCount = function() return 0 end,
    DeepCopy = function(t) return t end,
  },
  Comms = { Register = function() end, Send = function() end },
  Council = {}, UI = {}, LootDetection = { Register = function() end, Unregister = function() end },
  Trade = {}, Scoring = {}, Roster = {},
  pendingSessions = {},
}

dofile("NordavindLC/Core.lua")
local NLC = NordavindLC_NS
-- Core.lua:13 setter NLC.db = {} ved innlasting, saa stubben maa komme etter.
NLC.db = { config = {}, importData = { players = {} }, pendingTrades = {}, pendingExport = {} }

local function kjoer(cmd)
  utskrift = {}
  SlashCmdList["NORDLC"](cmd)
end

local function sa(bit)
  for _, m in ipairs(utskrift) do if m:find(bit, 1, true) then return true end end
  return false
end

-- --- 1: menig i raid faar nei ---
NLC.active, iRaid, erLeder = false, true, false
kjoer("activate")
assert(not NLC.active, "en menig aktiverte seg selv i et raid — da auto-passer hun i pug")
assert(sa("raidleder"), "avviste uten aa si hvorfor: " .. table.concat(utskrift, " | "))
print("menig i raid          : OK -> avvist med forklaring")

-- --- 2: lederen faar lov ---
NLC.active, iRaid, erLeder = false, true, true
kjoer("activate")
assert(NLC.active, "lederen fikk ikke aktivere — da virker addonet ikke i det hele tatt")
print("leder i raid          : OK -> aktiverte")

-- --- 3: utenfor raid faar lov ---
-- Offiseren maa kunne aapne addonet og sjekke importen foer folk er invitert.
-- Utenfor raid finnes det ingen rull aa passe paa, saa det koster ingenting.
NLC.active, iRaid, erLeder = false, false, false
kjoer("activate")
assert(NLC.active, "kunne ikke aktivere solo — da kan ingen sjekke importen foer raid")
print("solo, utenfor raid    : OK -> aktiverte")

-- --- 4: deactivate skal alltid virke ---
-- Porten gaar én vei. Aa skru AV maa alle kunne, ellers sitter den som ble
-- aktivert av lederen fast med auto-passet naar hun forlater raidet.
NLC.active, iRaid, erLeder = true, true, false
kjoer("deactivate")
assert(not NLC.active, "en menig kunne ikke skru av — da sitter hun fast med auto-passet")
print("deactivate som menig  : OK -> slo av")

-- --- 5: hoeyreklikk paa ikonet gaar gjennom samme port ---
NLC.active, iRaid, erLeder = false, true, false
utskrift = {}
NordavindLC_OnAddonCompartmentClick(nil, "RightButton")
assert(not NLC.active, "hoeyreklikk omgikk porten — da er kommandosjekken bare pynt")
print("hoeyreklikk som menig : OK -> avvist")

-- --- 6: hoeyreklikk hos lederen aktiverer ---
NLC.active, iRaid, erLeder = false, true, true
NordavindLC_OnAddonCompartmentClick(nil, "RightButton")
assert(NLC.active, "lederen fikk ikke aktivere med hoeyreklikk")
print("hoeyreklikk som leder : OK -> aktiverte")

print("\nALLE PAASTANDER HOLDT")
