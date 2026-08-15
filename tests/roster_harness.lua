-- Testrigg for Roster.lua — kjoerer logikken uten WoW ved aa stubbe API-et.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/roster_harness.lua',encoding='utf-8').read())"
--
-- Dekker de to fellene som ikke krever spillet:
--   * rankIndex er 0-basert i API-et, men 1-basert i Guild Control
--   * navn kommer som «Revo-TwistingNether» og maa strippes for realm
-- I tillegg: at et avkuttet roster advarer og IKKE ber om /reload.
--
-- Den tredje fella (SavedVariables skrives foerst ved /reload) kan bare
-- verifiseres in-game.

local utskrift = {}

-- --- WoW-API-stubber ---
IsInGuild = function() return true end
time = function() return 1755280000 end

local ROSTER  -- settes per scenario

GetNumGuildMembers = function() return #ROSTER end
GetGuildRosterInfo = function(i)
  local r = ROSTER[i]
  if not r then return nil end
  -- navn, rangNavn, rankIndex(0-basert!), niva, klasse, sone, publicNote
  return r.navn, r.rang, r.rankIndex0, 80, "Warrior", "Valdrakken", r.note
end
GetGuildRosterLastOnline = function(i)
  local r = ROSTER[i]
  return 0, 0, r.dager or 0, 0
end

C_GuildInfo = {
  SetGuildRosterShowOffline = function(v) _G.__visteOffline = v end,
  GuildRoster = function() _G.__baOmRoster = true end,
}

CreateFrame = function()
  local f = {}
  function f:RegisterEvent() end
  function f:UnregisterAllEvents() end
  function f:SetScript(navn, fn)
    -- Fyr GUILD_ROSTER_UPDATE med en gang OnEvent settes.
    if navn == "OnEvent" and fn then self._onEvent = fn; fn(self) end
  end
  return f
end

NordavindLC_DB = {}

local NLC = { Utils = { Print = function(m) table.insert(utskrift, m) end } }

-- --- Last Roster.lua med samme vararg som WoW gir ---
local chunk = assert(loadfile("NordavindLC/Roster.lua"))
chunk("NordavindLC", NLC)

-- --- Scenario 1: fullt roster ---
ROSTER = {}
for i = 1, 120 do
  table.insert(ROSTER, {
    navn = "Char" .. i .. "-TwistingNether",
    rang = "Sosial / M+",
    rankIndex0 = 8,             -- 0-basert => Guild Control viser «Rank 9»
    note = "Rolf - Revo - Main",
    dager = 3,
  })
end
-- Én raider for aa sjekke rangforskyvning presist
ROSTER[1].rankIndex0 = 4        -- 0-basert => «Rank 5: Raider»
ROSTER[1].navn = "Revo-TwistingNether"

utskrift = {}
NLC.Roster.Capture()

local lagret = NordavindLC_DB.pendingRosterImport
assert(lagret, "ingenting lagret i SavedVariables")
assert(#lagret.characters == 120, "feil antall: " .. #lagret.characters)

-- FELLE 3: 0-basert API maa bli 1-basert som i Guild Control
assert(lagret.characters[1].rankIndex == 5,
  "rankIndex ble " .. lagret.characters[1].rankIndex .. ", forventet 5 (Raider)")
assert(lagret.characters[2].rankIndex == 9,
  "rankIndex ble " .. lagret.characters[2].rankIndex .. ", forventet 9 (Sosial / M+)")

-- Realm maa strippes for aa kunne matche mot Discord
assert(lagret.characters[1].name == "Revo",
  "navn ble '" .. tostring(lagret.characters[1].name) .. "', forventet 'Revo'")

assert(_G.__visteOffline == true, "SetGuildRosterShowOffline ble ikke kalt med true")
assert(_G.__baOmRoster == true, "GuildRoster() ble aldri kalt")

local saReload = false
for _, m in ipairs(utskrift) do if m:find("/reload") then saReload = true end end
assert(saReload, "sa ikke fra om /reload")

print("scenario 1 (fullt roster, 120): OK")
print("  rankIndex 4 -> " .. lagret.characters[1].rankIndex .. "  (Raider)")
print("  navn 'Revo-TwistingNether' -> '" .. lagret.characters[1].name .. "'")

-- --- Scenario 2: avkuttet roster (offline-fella) ---
ROSTER = {}
for i = 1, 10 do
  table.insert(ROSTER, {
    navn = "Paalogget" .. i .. "-TwistingNether", rang = "Raider",
    rankIndex0 = 4, note = "", dager = 0,
  })
end

utskrift = {}
NLC.Roster.Capture()

local advarte = false
for _, m in ipairs(utskrift) do if m:find("ADVARSEL") then advarte = true end end
assert(advarte, "advarte IKKE om avkuttet roster")

local saReload2 = false
for _, m in ipairs(utskrift) do if m:find("/reload") then saReload2 = true end end
assert(not saReload2, "sa 'klart, kjoer /reload' selv om rosteret var avkuttet")

print("scenario 2 (avkuttet, 10): OK — advarte og ba IKKE om /reload")
print("")
print("ALLE PAASTANDER HOLDT")
