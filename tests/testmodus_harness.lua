-- Testrigg for at testmodus ikke foelger med inn i et raid.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/testmodus_harness.lua',encoding='utf-8').read())"
--
-- /nordlc test og /nordlc testloot setter active for at utdelingsknappene skal
-- kunne oeves solo. Flagget ble aldri ryddet, saa det fulgte med inn i neste
-- raid — og aktiv addon betyr auto-pass paa alt. Det var én av kildene til at
-- folk passet i en pug 26.08 uten aa ha startet noe.
--
-- Riggen finnes fordi ryddTestmodus ble lagt inn UTEN test, og fordi den er
-- den ene endringen som kan oedelegge noe som virket: sletter den for ivrig,
-- daar /nordlc test solo, og da kan ingen oeve paa utdelingen offline.

local hendelser = {}
local hovedHandler = nil

CreateFrame = function()
  local f = {}
  f.RegisterEvent = function(_, e)
    hendelser[e] = true
    -- Hovedramma er den som lytter paa GROUP_ROSTER_UPDATE. Feilramma
    -- (ADDON_ACTION_BLOCKED m.fl.) skal ikke fanges opp her.
    if e == "GROUP_ROSTER_UPDATE" then f._erHoved = true end
  end
  f.UnregisterEvent = function() end
  f.UnregisterAllEvents = function() end
  f.SetScript = function(sj, _, fn) if sj._erHoved then hovedHandler = fn end end
  return f
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
getmetatable("").__index.trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local iRaid = false
IsInRaid = function() return iRaid end
UnitIsGroupLeader = function() return false end

local utskrift = {}
local avslag = 0
NordavindLC_NS = {
  Utils = {
    Print = function(m) table.insert(utskrift, m) end,
    Diag = function() end,
    TableCount = function() return 0 end,
    DeepCopy = function(t) return t end,
  },
  Comms = { Register = function() end, Send = function() end },
  Council = {}, UI = {},
  LootDetection = { Register = function() end, Unregister = function() end },
  Trade = {}, Scoring = {}, Roster = {},
  pendingSessions = {},
}

dofile("NordavindLC/Core.lua")
local NLC = NordavindLC_NS
-- Core.lua:13 setter NLC.db = {} ved innlasting, saa stubben maa komme etter.
NLC.db = { config = {}, importData = { players = {} }, pendingTrades = {},
           pendingExport = {}, weeklyLoot = { resetTimestamp = math.huge, counts = {} } }

-- Deactivate teller: vi vil vite AT den ble kalt, ikke bare at flagget falt.
local deaktiveringer = 0
local ekteDeactivate = NLC.Deactivate
NLC.Deactivate = function() deaktiveringer = deaktiveringer + 1; ekteDeactivate() end

assert(hovedHandler, "fikk aldri tak i hovedramma sin OnEvent")

local function fyr(event)
  utskrift = {}
  deaktiveringer = 0
  hovedHandler(nil, event)
end

local function sa(bit)
  for _, m in ipairs(utskrift) do if m:find(bit, 1, true) then return true end end
  return false
end

-- --- 1: testmodus + raid = ryddes ---
NLC.testMode, NLC.active, iRaid = true, true, true
fyr("PLAYER_ENTERING_WORLD")
assert(deaktiveringer == 1, "testmodus ble ikke ryddet da vi kom i raid")
assert(not NLC.active, "active sto igjen etter opprydding")
assert(not NLC.testMode, "testMode sto igjen etter opprydding")
assert(sa("Testmodus"), "ryddet uten aa si fra: " .. table.concat(utskrift, " | "))
print("testmodus i raid      : OK -> ryddet og forklart")

-- --- 2: rydderen skal ikke vaere den som tar deg SOLO ---
--
-- Riggen avdekket at solo blir addonet deaktivert uansett — men av en helt
-- annen og eldre regel, «Deaktivert (forlot raid)» (Core.lua:111 og :127), som
-- slaar til paa alt som ikke er et raid. Den er ikke ny og ikke min.
--
-- Konsekvensen er verdt aa vite om: /nordlc test overlever ikke et
-- soneskifte eller en /reload naar du staar alene. Wizarden virker med én
-- gang du skriver kommandoen, for da fyrer ingen event — men gaar du gjennom
-- en portal, er den borte.
--
-- Det denne paastanden vokter er kun min egen endring: rydderen skal holde
-- fingrene fra folk som ikke er i et raid.
NLC.testMode, NLC.active, iRaid = true, true, false
fyr("PLAYER_ENTERING_WORLD")
assert(not sa("Testmodus avsluttet"),
       "ryddTestmodus slo til utenfor raid — den skal kun gjelde i raid")
assert(sa("forlot raid"),
       "forventet den eldre «forlot raid»-regelen her: " .. table.concat(utskrift, " | "))
print("solo                  : OK -> rydderen holdt seg unna (eldre regel tok den)")

-- --- 3: ekte aktivering i raid skal staa i fred ---
-- Den som ble aktivert av lederen har testMode = false. Rydderen skal ikke
-- kunne ta henne — det ville slaatt av addonet midt i raidet.
NLC.testMode, NLC.active, iRaid = false, true, true
fyr("GROUP_ROSTER_UPDATE")
assert(deaktiveringer == 0, "slo av en ekte aktivering i raid")
assert(NLC.active, "raider mistet aktiveringen sin")
print("ekte aktivering       : OK -> roert ikke")

-- --- 4: rydderen henger paa BEGGE eventene ---
-- Blir du invitert mens du staar i byen, fyrer ikke PLAYER_ENTERING_WORLD.
-- Da er GROUP_ROSTER_UPDATE eneste sjanse.
NLC.testMode, NLC.active, iRaid = true, true, true
fyr("GROUP_ROSTER_UPDATE")
assert(deaktiveringer == 1, "ryddet ikke ved GROUP_ROSTER_UPDATE — invitasjon i byen slipper unna")
print("invitert i byen       : OK -> ryddet")

print("\nALLE PAASTANDER HOLDT")
