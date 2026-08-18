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
GetNormalizedRealmName = function() return "TwistingNether" end

local ROSTER  -- settes per scenario

GetNumGuildMembers = function() return #ROSTER end
GetGuildRosterInfo = function(i)
  local r = ROSTER[i]
  if not r then return nil end
  -- navn, rangNavn, rankIndex(0-basert!), niva, klasse, sone, publicNote, officerNote
  return r.navn, r.rang, r.rankIndex0, 80, "Warrior", "Valdrakken", r.note, r.onote
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
SlashCmdList = {}   -- Roster.lua registrerer sin egen /nordroster

-- Namespacet er GLOBALT i dette addonet, akkurat som Utils.lua setter det opp.
-- Riggen MAA etterligne det. Tidligere matet den inn sin egen NLC-tabell som
-- chunk-argument, og da kunne den umulig fange at Roster.lua brukte feil
-- namespace — som var nettopp feilen som slo til in-game.
NordavindLC_NS = { Utils = { Print = function(m) table.insert(utskrift, m) end } }
local NLC = NordavindLC_NS

-- --- Last Roster.lua slik WoW gjoer: kun addon-navnet som vararg ---
local chunk = assert(loadfile("NordavindLC/Roster.lua"))
chunk("NordavindLC")

assert(NLC.Roster, "Roster.lua festet seg ikke paa det globale namespacet")

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
ROSTER[2].onote = "disc: bjango"   -- officer note skal ogsaa fanges
ROSTER[3].navn = "Utenrealm"       -- ingen suffiks => hjemrealm

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
assert(lagret.characters[1].realm == "TwistingNether",
  "realm fra suffiks ble " .. tostring(lagret.characters[1].realm))

assert(lagret.characters[1].class == "Warrior",
  "klassen ble ikke fanget: " .. tostring(lagret.characters[1].class))

assert(lagret.characters[1].name == "Revo",
  "navn ble '" .. tostring(lagret.characters[1].name) .. "', forventet 'Revo'")

-- Officer note maa vaere med — identitet staar ofte der i stedet for i den
-- offentlige noten.
assert(lagret.characters[2].officerNote == "disc: bjango",
  "officerNote ble '" .. tostring(lagret.characters[2].officerNote) .. "'")
assert(lagret.characters[1].officerNote == "",
  "manglende officer note skal bli tom streng, ble " .. tostring(lagret.characters[1].officerNote))

assert(lagret.characters[3].realm == "TwistingNether",
  "navn uten suffiks skal faa hjemrealm, ble " .. tostring(lagret.characters[3].realm))
assert(lagret.characters[3].name == "Utenrealm",
  "navn uten suffiks ble " .. tostring(lagret.characters[3].name))

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
