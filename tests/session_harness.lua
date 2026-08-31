-- Testrigg for at et council faktisk naar raidet.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/session_harness.lua',encoding='utf-8').read())"
--
-- Bruker meldte 2026-08-19 at raiderne ikke fikk noe. StartMultiSession kaller
-- flere ting FOER SESSION_START gaar ut. Er en eneste av dem nil, kaster
-- funksjonen og meldinga blir aldri sendt — offiseren ser «Council started»
-- aldri, og raidet merker ingenting. Denne riggen kjoerer hele veien og krever
-- at SESSION_START faktisk forlater klienten.

local planlagte = {}
C_Timer = {
  After = function(sek, fn) table.insert(planlagte, fn) end,
  NewTicker = function(sek, fn, n) return { Cancel = function() end } end,
  NewTimer = function(sek, fn) return { Cancel = function() end } end,
}
CreateFrame = function()
  return { RegisterEvent = function() end, UnregisterEvent = function() end,
           UnregisterAllEvents = function() end, SetScript = function() end }
end
GetTime = function() return 0 end
IsInRaid = function() return true end
UnitIsGroupLeader = function() return true end
UnitName = function() return "Bobletount" end
UnitClass = function(n) return "Paladin", "PALADIN" end
GetNumGroupMembers = function() return 28 end
GetRaidRosterInfo = function(i) return "Raider" .. i end
date = date or function() return "2026-08-19" end
bit = { bxor = function(a, b) return a ~ b end }

local sendt = {}
local popupVist = 0

-- Hvem klienten er styres per scenario, saa leder-porten kan proeves.
-- Standard: en ekte officer som ogsaa har lead — den lovlige kombinasjonen.
_G.ER_EKTE_OFFICER = true
_G.ER_LOOT_LEADER = true

NordavindLC_NS = {
  active = true,
  isOfficer = true,
  ErEkteOfficer = function() return _G.ER_EKTE_OFFICER end,
  IsLootLeader = function() return _G.ER_LOOT_LEADER end,
  db = { config = { timer = 90, officers = {} }, importData = { players = {} },
         lootHistory = {}, pendingExport = {}, pendingTrades = {}, weeklyLoot = { counts = {} } },
  pendingSessions = {},
  Utils = {
    Print = function() end,
    AddonVersion = function() return "1.9.0" end,
    Diag = function() end,
    TableCount = function(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end,
    GetEquippedInfo = function() return nil, 0 end,
    GetTierCount = function() return 0 end,
    ClassColoredName = function(n) return n end,
    CLASS_ARMOR = {},
  },
  Comms = {
    IsRestricted = function() return false end,
    Send = function(t, d) table.insert(sendt, t) end,
    SendMultiSession = function(items, boss) table.insert(sendt, "SESSION_START") end,
    SendRollCall = function() table.insert(sendt, "ROLL_CALL") end,
  },
  UI = {
    ShowMultiItemPopup = function() popupVist = popupVist + 1 end,
    ShowWizard = function() end,
    HideMultiItemPopup = function() end,
    IsWizardOpen = function() return false end,
  },
  Theme = { Debounce = function(_, _, fn) fn() end },
  Scoring = { Calculate = function() return 0, {} end },
  LootDetection = { GetCurrentBoss = function() return "Testboss" end },
  Trade = { Add = function() end },
  -- Utils.lua oppretter normalt namespacene; her stubber vi dem selv.
  Council = {},
}

dofile("NordavindLC/Council.lua")
local NLC = NordavindLC_NS

local function harSendt(t)
  for _, v in ipairs(sendt) do if v == t then return true end end
  return false
end

-- --- Selve testen: start et council med to items ---
local items = {
  { itemLink = "|cffa335ee|Hitem:270162::::::::90:::::|h[Soulcoiler Ritual Vessel]|h|r",
    itemId = 270162, ilvl = 671, equipLoc = "INVTYPE_CHEST", boss = "Nek'zali" },
  { itemLink = "|cffa335ee|Hitem:268235::::::::90:::::|h[Vestment of the Awakening]|h|r",
    itemId = 268235, ilvl = 671, equipLoc = "INVTYPE_LEGS", boss = "Nek'zali" },
}

local ok, feil = pcall(NLC.Council.StartMultiSession, items, "Nek'zali")
assert(ok, "StartMultiSession kastet — da naar SESSION_START aldri raidet: " .. tostring(feil))
print("StartMultiSession        : OK -> kastet ikke")

assert(harSendt("SESSION_START"), "SESSION_START ble ALDRI sendt — raidet faar ingenting")
print("SESSION_START            : OK -> sendt til raidet")

assert(harSendt("ACTIVATE"), "ACTIVATE ble ikke sendt — uaktiverte raidere vaakner aldri")
assert(harSendt("ROLL_CALL"), "ROLL_CALL ble ikke sendt")
print("ACTIVATE + ROLL_CALL     : OK -> sendt")

assert(popupVist == 1, "offiserens egen popup ble ikke vist (" .. popupVist .. ")")
print("popup                    : OK -> vist")

assert(#NLC.Council.GetActiveSessions() == 2,
       "forventet 2 aktive sessions, fikk " .. #NLC.Council.GetActiveSessions())
print("aktive sessions          : OK -> 2")

-- Den nye ClearLootAggregation kalles midt i StartMultiSession. Er den nil,
-- kaster hele funksjonen. Sjekk at den finnes og at den taaler aa kalles alene.
assert(type(NLC.Council.ClearLootAggregation) == "function",
       "ClearLootAggregation mangler — StartMultiSession ville kastet")
assert(pcall(NLC.Council.ClearLootAggregation), "ClearLootAggregation kastet")
print("ClearLootAggregation     : OK -> finnes og kjoerer")

-- --- Raidersiden: mottar de session-en? ---
sendt = {}
popupVist = 0
local payload = {}
for idx, it in ipairs(items) do
  table.insert(payload, { sessionIdx = idx, itemLink = it.itemLink, itemId = it.itemId,
                          ilvl = it.ilvl, equipLoc = it.equipLoc, boss = it.boss })
end
local ok2, feil2 = pcall(NLC.Council.OnMultiSessionStart, payload, 90, "Officer-Draenor")
assert(ok2, "OnMultiSessionStart kastet hos raideren: " .. tostring(feil2))
assert(popupVist == 1, "raideren fikk ingen popup")
print("raidersiden              : OK -> popup vist")

-- --- Kun officer OG raidleder kan starte council ---
-- To ulike hull, begge ekte:
--   * en raider med midlertidig lead er `isOfficer` (Core.lua gir gruppelederen
--     officer-tilgang), og kunne dratt i gang councilet for hele raidet
--   * en officer UTEN lead drev interesse-popupen hos alle 27 den 26.08
-- Derfor kreves begge, og porten proeves fra begge sider.
local function proevStart()
  popupVist = 0   -- StartMultiSession nullstiller activeSessions selv
  NLC.Council.StartMultiSession(items, "Test Boss")
  return popupVist
end

_G.ER_EKTE_OFFICER, _G.ER_LOOT_LEADER = false, true
assert(proevStart() == 0, "en raider med lead fikk starte council")
print("raider med lead          : OK -> nektet")

_G.ER_EKTE_OFFICER, _G.ER_LOOT_LEADER = true, false
assert(proevStart() == 0, "en officer uten lead fikk starte council")
print("officer uten lead        : OK -> nektet")

_G.ER_EKTE_OFFICER, _G.ER_LOOT_LEADER = true, true
assert(proevStart() == 1, "officer med lead ble nektet — porten er for stram")
print("officer med lead         : OK -> slipper gjennom")

print("\nALLE PAASTANDER HOLDT")

-- --- Gjenopptak etter reload ---
--
-- Sesjonen ligger kun i minnet. Reloader en raider mens innsamlingen paagaar,
-- er popupen borte for godt: han svarer aldri, og offiseren maa vente ut hele
-- timeren paa et svar som ikke kan komme. Det var den siste kjente maaten aa
-- falle ut av et council paa.
--
-- Lederen maa derfor kunne svare paa «hva er det som paagaar?». To krav:
-- han maa vite AT noe paagaar, og han maa kunne pakke det slik at mottakeren
-- kan lese det med akkurat den samme funksjonen som en vanlig sesjonsstart.
assert(NLC.Council.HasOpenCollecting(),
       "innsamlingen paagaar, men HasOpenCollecting sier nei")
print("aapen innsamling         : OK -> lederen vet at noe paagaar")

local snap = NLC.Council.CollectingSnapshot()
assert(snap and snap.items, "CollectingSnapshot ga ingenting")
assert(#snap.items == 2, "snapshotet hadde " .. #snap.items .. " items, ventet 2")
assert(snap.timer and snap.timer > 0,
       "snapshotet manglet gjenstaaende tid (" .. tostring(snap.timer) .. ")")
assert(snap.items[1].itemLink and snap.items[1].itemId,
       "snapshotet manglet itemLink/itemId - mottakeren faar en tom rad")
print("snapshot                 : OK -> 2 items og tid igjen")

-- Rundturen er selve kontrakten: det lederen pakker MAA kunne leses av den
-- samme funksjonen som tar imot en helt vanlig sesjonsstart. Ellers oppdager vi
-- forskjellen foerst midt i et raid, hos den ene som reloadet.
popupVist = 0
local ok3, feil3 = pcall(NLC.Council.OnMultiSessionStart, snap.items, snap.timer, "Officer-Draenor")
assert(ok3, "snapshotet kunne ikke leses av OnMultiSessionStart: " .. tostring(feil3))
assert(popupVist == 1, "den som reloadet fikk ingen popup tilbake")
assert(#NLC.Council.GetActiveSessions() == 2,
       "gjenopptaket ga " .. #NLC.Council.GetActiveSessions() .. " sessions, ventet 2")
print("rundtur snapshot         : OK -> popupen kom tilbake med begge items")

-- Er innsamlingen stengt, skal lederen tie. En som reloader etter stenging skal
-- ikke faa en popup for noe som allerede er rangert og delt ut.
NLC.Council.CloseCollecting()
assert(not NLC.Council.HasOpenCollecting(),
       "innsamlingen er stengt, men lederen ville fortsatt svart med en popup")
print("stengt innsamling        : OK -> lederen tier")
