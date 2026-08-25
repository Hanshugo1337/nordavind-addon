-- Testrigg for aggregeringa av LOOT_REPORT paa officer-sida.
--
-- Kjoeres fra repo-rot:
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/aggregering_harness.lua',encoding='utf-8').read())"
--
-- Raidkvelden 2026-08-24, fra Braxinas diagnoselogg:
--
--     22:34:33  Sendte LOOT_REPORT: 5 items
--     22:34:33  LOOT_REPORT mottatt fra Braxina | 5 items
--     22:34:43  Aggregering ferdig | 4 items totalt -> panel
--
-- Fem inn, fire ut. Dedup-noekkelen var `itemId:looter`, saa to eksemplarer av
-- samme item lootet av samme person kollapset til ett. Det andre eksemplaret
-- forsvant fra panelet uten et ord. Bekreftet i dataene hennes: Frostscale's
-- Mystic Frond (268263) ble delt ut til BAADE Braxina og Joedemannen.
--
-- Dedupen skal fortsatt virke paa tvers av AVSENDERE: samme item rapportert av
-- to klienter er ett item, ikke to.

local timerFn = nil
C_Timer = {
  After = function(sek, fn) end,
  NewTicker = function() return { Cancel = function() end } end,
  NewTimer = function(sek, fn)
    timerFn = fn
    return { Cancel = function() timerFn = nil end }
  end,
}
local function fyrTimer()
  local fn = timerFn
  timerFn = nil
  if fn then fn() end
end

CreateFrame = function()
  return { RegisterEvent = function() end, UnregisterEvent = function() end,
           UnregisterAllEvents = function() end, SetScript = function() end }
end
GetTime = function() return 0 end
IsInRaid = function() return true end
UnitIsGroupLeader = function() return true end
UnitName = function() return "Bobletount" end
UnitClass = function() return "Paladin", "PALADIN" end
GetNumGroupMembers = function() return 28 end
GetRaidRosterInfo = function(i) return "Raider" .. i end
date = date or function() return "2026-08-24" end
bit = { bxor = function(a, b) return a ~ b end }

local vistIPanel = nil
local diagLinjer = {}

NordavindLC_NS = {
  active = true,
  isOfficer = true,
  db = { config = { timer = 90, officers = {} }, importData = { players = {} },
         lootHistory = {}, pendingExport = {}, pendingTrades = {}, weeklyLoot = { counts = {} } },
  pendingSessions = {},
  Utils = {
    Print = function() end,
    AddonVersion = function() return "1.9.2-test1" end,
    Diag = function(m) table.insert(diagLinjer, m) end,
    TableCount = function(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end,
    GetEquippedInfo = function() return nil, 0 end,
    GetTierCount = function() return 0 end,
    ClassColoredName = function(n) return n end,
    CLASS_ARMOR = {},
  },
  Comms = {
    IsRestricted = function() return false end,
    Send = function() end,
    SendMultiSession = function() end,
    SendRollCall = function() end,
  },
  UI = {
    ShowLootDetected = function(items) vistIPanel = items end,
    ShowMultiItemPopup = function() end,
    ShowWizard = function() end,
    HideMultiItemPopup = function() end,
    IsWizardOpen = function() return false end,
  },
  Theme = { Debounce = function(_, _, fn) fn() end },
  Scoring = { Calculate = function() return 0, {} end },
  LootDetection = {
    GetCurrentBoss = function() return "Sszorak" end,
    _setDetected = function() end,
  },
  Trade = { Add = function() end },
  Council = {},
}

dofile("NordavindLC/Council.lua")
local NLC = NordavindLC_NS

local function item(id, navn, looter)
  return { itemId = id, itemLink = "|cffa335ee|Hitem:" .. id .. "::::::::90:::::|h[" .. navn .. "]|h|r",
           ilvl = 90, equipLoc = "INVTYPE_CLOAK", boss = "Sszorak", looter = looter }
end

local function antallIPanel()
  return vistIPanel and #vistIPanel or 0
end

-- --- Mandagens tilfelle: to eksemplarer av samme item, samme looter ---
NLC.Council.ClearLootAggregation()
vistIPanel = nil

NLC.Council.OnLootReport("Braxina", { boss = "Sszorak", items = {
  item(268263, "Frostscale's Mystic Frond", "Braxina"),
  item(268263, "Frostscale's Mystic Frond", "Braxina"),   -- eksemplar to
  item(268253, "Silken Voodoo Drape", "Braxina"),
  item(270169, "Hex Lord's Dooming Idol", "Braxina"),
  item(268222, "Reckless Spirit Breastplate", "Braxina"),
} })
fyrTimer()

assert(antallIPanel() == 5,
  "to like items kollapset: forventet 5 i panelet, fikk " .. antallIPanel())
print("duplikater beholdes  : OK -> begge eksemplarene naadde panelet")

-- --- Dedupen skal fortsatt virke paa tvers av avsendere ---
NLC.Council.ClearLootAggregation()
vistIPanel = nil

local samme = item(268253, "Silken Voodoo Drape", "Braxina")
NLC.Council.OnLootReport("Braxina", { boss = "Sszorak", items = { samme } })
NLC.Council.OnLootReport("Lakrisgutten", { boss = "Sszorak", items = { samme } })
fyrTimer()

assert(antallIPanel() == 1,
  "samme item fra to avsendere skal telle én gang, fikk " .. antallIPanel())
print("dedup paa tvers      : OK -> to rapporter om samme item gir én rad")

-- --- Ny boss nullstiller ---
NLC.Council.ClearLootAggregation()
vistIPanel = nil

NLC.Council.OnLootReport("Braxina", { boss = "Nymrissa", items = { item(1, "A", "Braxina") } })
NLC.Council.OnLootReport("Braxina", { boss = "Sszorak", items = { item(2, "B", "Braxina") } })
fyrTimer()

assert(antallIPanel() == 1,
  "ny boss skal toemme forrige runde, fikk " .. antallIPanel())
print("ny boss nullstiller  : OK -> kun den nye bossens items")

print("\nALLE PAASTANDER HOLDT")
