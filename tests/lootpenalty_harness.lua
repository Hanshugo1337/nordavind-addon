-- Trekk per kategori. Tallene MAA treffe nordavind-web/lib/loot-penalty.ts.
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/lootpenalty_harness.lua',encoding='utf-8').read())"
--
-- Vedtatt 30.09.2026: BiS/Major/Stat erstatter Upgrade/Catalyst, og trekket
-- avhenger av knappen. Gamle upgrade/catalyst-rader beholder 10/2.

NordavindLC_NS = {
  Scoring = {},
  db = { weeklyLoot = { counts = {}, penalty = {}, resetTimestamp = 1 }, importData = nil },
  Utils = { Print = function() end },
}
dofile("NordavindLC/Scoring.lua")
local NLC = NordavindLC_NS
local S = NLC.Scoring

local function lik(p, uke, sesong, hva)
  assert(p.week == uke and p.season == sesong,
    hva .. ": fikk " .. tostring(p.week) .. "/" .. tostring(p.season))
end
lik(S.PenaltyFor("bis"), 10, 2, "bis")
lik(S.PenaltyFor("major"), 7, 1.5, "major")
lik(S.PenaltyFor("stat"), 5, 1, "stat")
lik(S.PenaltyFor("upgrade"), 10, 2, "gammel upgrade")
lik(S.PenaltyFor("catalyst"), 10, 2, "gammel catalyst")
lik(S.PenaltyFor("offspec"), 0, 0, "offspec")
lik(S.PenaltyFor("tmog"), 0, 0, "tmog")
lik(S.PenaltyFor(nil), 0, 0, "nil")
lik(S.PenaltyFor("disenchant"), 0, 0, "disenchant")
assert(S.CountsAsLoot("stat") and not S.CountsAsLoot("offspec"), "CountsAsLoot")
print("tabellen             : OK -> 10/2, 7/1.5, 5/1, som nettsida")

-- To utdelinger samme kveld summeres per kategori, ikke antall x 10.
S.AddWeeklyAward("Mohp", "bis", 1)
S.AddWeeklyAward("Mohp", "stat", 1)
assert(NLC.db.weeklyLoot.counts["Mohp"] == 2, "antall")
assert(NLC.db.weeklyLoot.penalty["Mohp"] == 15, "trekk: " .. tostring(NLC.db.weeklyLoot.penalty["Mohp"]))
local score = S.Calculate({ baseScore = 50, lootThisWeek = 0, lootPenaltyWeek = 0 }, nil, "Mohp")
assert(score == 35, "50 - 15 skal gi 35, fikk " .. score)
-- Importen har allerede sett bis-en: bare stat-en kommer i tillegg.
score = S.Calculate({ baseScore = 40, lootThisWeek = 1, lootPenaltyWeek = 10 }, nil, "Mohp")
assert(score == 35, "40 - (15-10) skal gi 35, fikk " .. score)
print("session-trekk        : OK -> summeres i poeng")

-- Gammel eksport uten lootPenaltyWeek (nettsida ikke deployet ennaa).
assert(S.ImportedWeekPenalty({ lootThisWeek = 2 }) == 20, "fallback 2 x 10")
assert(S.ImportedWeekPenalty({ lootThisWeek = 1, lootPenaltyWeek = 5 }) == 5, "nytt felt vinner")
print("gammel eksport       : OK -> faller tilbake til antall x 10")

-- Gamle SavedVariables uten `penalty`: antallet regnes x10, som foer.
NLC.db.weeklyLoot = { counts = { Gammel = 1 }, resetTimestamp = 1 }
score = S.Calculate({ baseScore = 50, lootThisWeek = 0 }, nil, "Gammel")
assert(score == 40, "gammel SV: 50 - 10 skal gi 40, fikk " .. score)
print("gamle SavedVariables : OK")

-- Retting trekker fra igjen.
NLC.db.weeklyLoot = { counts = {}, penalty = {}, resetTimestamp = 1 }
S.AddWeeklyAward("Mohp", "bis", 1)
S.AddWeeklyAward("Mohp", "stat", 1)
S.AddWeeklyAward("Mohp", "bis", -1)
assert(NLC.db.weeklyLoot.penalty["Mohp"] == 5 and NLC.db.weeklyLoot.counts["Mohp"] == 1, "angre")
S.AddWeeklyAward("Mohp", "offspec", 1)
assert(NLC.db.weeklyLoot.counts["Mohp"] == 1, "offspec teller ikke")
print("angre/offspec        : OK")

-- Mangler-lista fra nettsida blir advarsler.
local w = S.GetWarnings({ rank = "raider", mangler = { "ingen parse", "ingen sim (Mythic)" } }, "Mohp")
local funnet = 0
for _, x in ipairs(w) do if x:find("^Mangler: ") then funnet = funnet + 1 end end
assert(funnet == 2, "to mangler-advarsler, fikk " .. funnet)
print("mangler              : OK -> vises som advarsel")

-- Retting i historikken: BiS -> Stat flytter 10 ut og 5 inn (HistoryFrame).
NLC.db.weeklyLoot = { counts = {}, penalty = {}, resetTimestamp = 1 }
S.AddWeeklyAward("Sondi", "bis", 1)
S.AddWeeklyAward("Sondi", "bis", -1)
S.AddWeeklyAward("Sondi", "stat", 1)
assert(NLC.db.weeklyLoot.penalty["Sondi"] == 5 and NLC.db.weeklyLoot.counts["Sondi"] == 1, "bis->stat")
print("historikk-retting    : OK -> trekket flyttes med")
