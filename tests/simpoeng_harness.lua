-- Testrigg for sim-poengene i addonet.
--
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/simpoeng_harness.lua',encoding='utf-8').read())"
--
-- Sims er 0-8 poeng etter de vedtatte vektene, med full score ved 5 % upgrade.
-- Tallene MAA treffe nettsida: SIM_MAX_POINTS = 8 og SIM_FULL_AT_PERCENT = 5 i
-- nordavind-web/app/api/loot/route.ts, formel
-- `min(8, pct * (8/5))`.
--
-- Fram til 25.08 hadde addonet null av disse poengene, og rangerte derfor
-- annerledes enn nettsida paa hvert eneste item.

NordavindLC_NS = {
  Scoring = {},
  db = {
    weeklyLoot = { counts = {}, resetTimestamp = 0 },
    importData = nil,
  },
  Utils = { Print = function() end },
}

dofile("NordavindLC/Scoring.lua")
local NLC = NordavindLC_NS

local function omtrent(a, b)
  return math.abs(a - b) < 0.0001
end

-- --- Formelen, mot nettsidas tall ---
assert(omtrent(NLC.Scoring.SimPoints(5), 8), "5 % skal gi full score: " .. NLC.Scoring.SimPoints(5))
assert(omtrent(NLC.Scoring.SimPoints(2.5), 4), "2,5 % skal gi halv score")
assert(omtrent(NLC.Scoring.SimPoints(1), 1.6), "1 % skal gi 1,6")
assert(omtrent(NLC.Scoring.SimPoints(12), 8), "over 5 % skal takes paa 8")
assert(NLC.Scoring.SimPoints(0) == 0, "0 % gir 0")
assert(NLC.Scoring.SimPoints(nil) == 0, "manglende sim gir 0, ikke feil")
assert(NLC.Scoring.SimPoints("2.5") == 0, "streng er ikke et tall")
print("formelen             : OK -> min(8, pct * 1,6), som nettsida")

-- --- Oppslaget taaler at JSON gjorde tall om til strenger ---
local medTall    = { simPct = { [268263] = 3.1 } }
local medStreng  = { simPct = { ["268263"] = 3.1 } }
assert(NLC.Scoring.SimPctFor(medTall, 268263) == 3.1, "numerisk noekkel")
assert(NLC.Scoring.SimPctFor(medStreng, 268263) == 3.1,
       "strengnoekkel — companion skriver JSON, og der blir tall til strenger")
assert(NLC.Scoring.SimPctFor(medTall, 999) == nil, "ukjent item gir nil")
assert(NLC.Scoring.SimPctFor(nil, 268263) == nil, "ingen import gir nil")
assert(NLC.Scoring.SimPctFor({}, 268263) == nil, "import uten simPct gir nil")
print("noekkeloppslag       : OK -> tall og streng gir samme svar")

-- --- Poengene havner i totalen ---
local imported = { baseScore = 40 }

local utenSim = NLC.Scoring.Calculate(imported, { isTier = false }, "Revo")
assert(utenSim == 40, "uten sim-data skal scoren staa uroert: " .. utenSim)

local medSim = NLC.Scoring.Calculate(imported, { isTier = false, simPct = 2.5 }, "Revo")
assert(omtrent(medSim, 44), "2,5 % skal legge 4 poeng til 40, fikk " .. medSim)
print("legges til totalen   : OK -> 40 + 4 = 44")

-- --- Tier faar IKKE sim-poeng, den har sin egen bonus ---
--
-- Nettsida bytter ut sim-verdien med tier-gevinsten paa tier-deler. Den tabellen
-- finnes ikke i importen, saa addonet beholder sin flate bonus. Uten dette
-- skillet ville en tier-del faatt begge deler.
local tier = NLC.Scoring.Calculate(imported, { isTier = true, tierCount = 1, simPct = 5 }, "Revo")
assert(omtrent(tier, 43), "tier skal gi flat +3, ikke sim-poeng, fikk " .. tier)
print("tier dobbelttelles ei: OK -> flat bonus, ingen sim-poeng")

-- --- Er sim-dataene til aa stole paa? ---
assert(NLC.Scoring.SimDataOk() == false, "ingen import = ikke stolbar")
NLC.db.importData = { players = {} }
assert(NLC.Scoring.SimDataOk() == false, "import uten kilder = ikke stolbar")
NLC.db.importData = { players = {}, kilder = { sims = "feilet" } }
assert(NLC.Scoring.SimDataOk() == false, "feilet henting = ikke stolbar")
NLC.db.importData = { players = {}, kilder = { sims = "ok" } }
assert(NLC.Scoring.SimDataOk() == true, "ok = stolbar")
print("kildesjekken         : OK -> kun \"ok\" aapner for sim-porten")


-- ============================================================
-- Tier-gevinst fra nettsida (lagt til 26.08 etter audit)
-- ============================================================
--
-- Addonet regnet tier med en flat tabell mens nettsida brukte sim-gevinst.
-- Maalt mot ekte data samme dag rangerte de to nesten omvendt: Mohp sto foerst
-- paa nettsida og nest sist i addonet. Naa sender importen prosenten.

local function poeng(imported, live)
  local s = NLC.Scoring.Calculate(imported, live, "Test")
  return s
end

-- Mohp: 3 gjeldende brikker, én unna 4-set. Nettsida gir 10.9 % -> taket paa 8.
local medGevinst = poeng({ baseScore = 0, tierGain = 10.9 }, { isTier = true, tierCount = 5 })
assert(math.abs(medGevinst - 8) < 0.01,
       "tier-gevinst ble ikke 8 poeng ved 10.9 %, fikk " .. tostring(medGevinst))

-- Lav gevinst skal gi lave poeng, ikke flat bonus.
local lav = poeng({ baseScore = 0, tierGain = 1.05 }, { isTier = true, tierCount = 1 })
assert(math.abs(lav - 1.68) < 0.05, "1.05 % skulle gitt 1.68 poeng, fikk " .. tostring(lav))

-- Uten tierGain (gammel import) skal den flate tabellen fortsatt virke, slik at
-- en klient med utdatert import ikke mister tier-vurderingen helt.
local gammel = poeng({ baseScore = 0 }, { isTier = true, tierCount = 1 })
assert(math.abs(gammel - 3) < 0.01, "fallback ga ikke +3 ved 1 brikke, fikk " .. tostring(gammel))

-- tierCount fra spillet skal IKKE lenger paavirke resultatet naar nettsida har
-- sendt en gevinst. Det var hele feilen: addonet talte forrige tiers brikker.
local a = poeng({ baseScore = 0, tierGain = 4.0 }, { isTier = true, tierCount = 0 })
local b = poeng({ baseScore = 0, tierGain = 4.0 }, { isTier = true, tierCount = 4 })
assert(math.abs(a - b) < 0.01, "spillets brikketall paavirket fortsatt tier-poengene")

print("tier-gevinst fra web  : OK -> 8 ved taket, 1.68 ved 1.05 %, fallback +3")

print("\nALLE PAASTANDER HOLDT")
