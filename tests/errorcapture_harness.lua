-- Testrigg for egen feilfangst i Core.lua.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/errorcapture_harness.lua',encoding='utf-8').read())"
--
-- 2026-08-19 var vi avhengige av at brukeren hadde BugGrabber og at noen leste
-- den for aa i det hele tatt se at noe var galt. Trade-vinduet hadde vaert doedt
-- i maanedsvis fordi CheckInteractDistance er protected: kallet blokkeres, gir
-- nil, og det eneste sporet var en ADDON_ACTION_BLOCKED ingen saa etter.
--
-- Kravet: vi fanger de tre eventene selv, logger kun det som gjelder oss, og
-- hver melding én gang — ellers spiser ett blokkert kall i en OnUpdate hele
-- diagnoseloggen.

local hendelser = {}
local handler = nil

CreateFrame = function()
  return {
    RegisterEvent = function(_, e) hendelser[e] = true end,
    UnregisterEvent = function() end,
    UnregisterAllEvents = function() end,
    SetScript = function(_, _, fn) handler = fn end,
  }
end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end,
            NewTicker = function() return { Cancel = function() end } end }
C_AddOns = { GetAddOnMetadata = function() return "1.9.1" end }
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 100 end }
GetTime = function() return 0 end
IsInRaid = function() return false end
UnitIsGroupLeader = function() return false end
UnitName = function() return "Bobletount" end
GetGuildInfo = function() return nil end
GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end,
                Hide = function() end }
UIParent = {}
time = time or os.time
SlashCmdList = {}
SLASH_NORDLC1 = nil

local logg = {}
NordavindLC_NS = {
  Utils = {
    Print = function() end,
    Diag = function(m) table.insert(logg, m) end,
    TableCount = function() return 0 end,
    DeepCopy = function(t) return t end,
  },
  Comms = { Register = function() end, Send = function() end },
  Council = {}, UI = {}, LootDetection = { Register = function() end, Unregister = function() end },
  Trade = {}, Scoring = {}, Roster = {},
}

dofile("NordavindLC/Core.lua")

assert(handler, "feilrammen fikk aldri en OnEvent-handler")
for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "LUA_WARNING" }) do
  assert(hendelser[e], e .. " ble ikke registrert")
end
print("registrering        : OK -> alle tre eventene")

-- --- 1: vaar egen blokkerte funksjon skal fanges ---
-- Ordrett den BugGrabber fanget 2026-05-06.
logg = {}
handler(nil, "ADDON_ACTION_BLOCKED",
        "AddOn 'NordavindLC' tried to call the protected function 'CheckInteractDistance()'.")
assert(#logg == 1, "vaar egen blokkerte funksjon ble ikke logget")
assert(logg[1]:find("CheckInteractDistance", 1, true), "feil innhold: " .. logg[1])
print("egen feil           : OK -> fanget og logget")

-- --- 2: andre addons sitt stoey skal IKKE fanges ---
logg = {}
handler(nil, "ADDON_ACTION_BLOCKED",
        "AddOn 'RaiderIO' tried to call the protected function 'SetGuildRosterOrder()'.")
handler(nil, "LUA_WARNING", "Interface/AddOns/BigWigs/Something.lua:1: noe helt annet")
assert(#logg == 0, "logget andre addons sine feil (" .. #logg .. ")")
print("andres stoey        : OK -> ignorert")

-- --- 3: samme melding skal kun logges én gang ---
logg = {}
for _ = 1, 50 do
  handler(nil, "ADDON_ACTION_BLOCKED",
          "AddOn 'NordavindLC' tried to call the protected function 'Gjentatt()'.")
end
assert(#logg == 1, "samme melding logget " .. #logg .. " ganger — ville spist loggen")
print("dedup               : OK -> 50 like meldinger ga 1 linje")

print("\nALLE PAASTANDER HOLDT")
