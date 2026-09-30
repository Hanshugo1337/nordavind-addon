-- Scoring.lua
-- Calculate loot council score from imported web data + live in-game data

local NLC = NordavindLC_NS

-- Trekk per item, per kategori. MÅ matche LOOT_PENALTY i
-- nordavind-web/lib/loot-penalty.ts — står de ulikt, straffes samme item ulikt
-- avhengig av om importen har rukket å oppdatere seg, og rekkefølgen i raidet
-- blir en annen enn nettsidens.
-- upgrade/catalyst er gamle rader fra før knappene ble delt (30.09.2026).
local LOOT_PENALTY = {
  bis      = { week = 10, season = 2 },
  major    = { week = 7,  season = 1.5 },
  stat     = { week = 5,  season = 1 },
  upgrade  = { week = 10, season = 2 },
  catalyst = { week = 10, season = 2 },
}
local INGEN_TREKK = { week = 0, season = 0 }

function NLC.Scoring.PenaltyFor(category)
  return (category and LOOT_PENALTY[category]) or INGEN_TREKK
end

-- Under hvor mye defensivbruk vi advarer. MÅ følge terskelen i
-- nordavind-web/app/api/loot/route.ts — står de på ulike tall, får samme
-- spiller advarsel på nettsida men ikke i addonet, eller omvendt.
--
-- Tallet er IKKE kast per fight. Det er andelen av knappene spilleren
-- faktisk har: nevneren er spec-normalisert i nordavind-web/lib/defensives.ts
-- (en Mage har én barriere, ikke tre; en Holy Priest har ingen Dispersion).
-- 1.0 betyr «brukte alle knappene sine hver fight».
--
-- Merk at web sender null for tanks — filteret der teller dem ikke i det hele
-- tatt — og da skal det ikke stå noen advarsel.
--
-- Senket fra 0.8 til 0.25 den 02.09.2026. 0.8 lå OVER det kodebasens egen
-- karakterskala kaller «good» (0.5), så for 31 av 33 specer utløste advarselen
-- på nettopp den bruken raidanalysen ga toppkarakter. Og siden tallet er en
-- andel av knappene, krevde 0.8 at en Ret paladin fyrte fire av fem knapper
-- hver fight — tre av dem har flere minutters cooldown. Uoppnåelig for specen,
-- uansett hvor godt hen spilte.
--
-- 0.25 er «okay»-grensa i lib/defensives.ts. Advarselen peker nå ut den som
-- ikke bruker knappene sine, ikke alle som ikke er i toppsjiktet.
local DEFENSIVE_WARN_BELOW = 0.25

-- Sim-poeng. MÅ følge SIM_MAX_POINTS og SIM_FULL_AT_PERCENT i
-- nordavind-web/app/api/loot/route.ts. Regelteksten gir sims 0-8, og full score
-- ved 5 % upgrade.
--
-- To ledd i nettsidas formel speiles IKKE her, fordi tallene ikke finnes i
-- importen:
--   * Rabatten når spilleren har et bedre item i SAMME SLOT fra en annen boss
--     (nettsida ganger da ned med forholdet mellom de to prosentene).
--   * Tier-gevinsten fra TIER_SIMS. Tier-deler får derfor ingen sim-poeng her —
--     addonet beholder sin flate tier-bonus i stedet, se TierAdjustment.
-- Begge gjør addonet mildere enn nettsida, aldri strengere.
local SIM_MAX_POINTS = 8
local SIM_FULL_AT_PERCENT = 5

--- Sim-poeng for en upgrade-prosent. Nil-prosent gir 0.
function NLC.Scoring.SimPoints(pct)
  if type(pct) ~= "number" or pct <= 0 then return 0 end
  local p = pct * (SIM_MAX_POINTS / SIM_FULL_AT_PERCENT)
  if p > SIM_MAX_POINTS then p = SIM_MAX_POINTS end
  return p
end

--- Sim-prosenten spilleren har for ett item.
---
--- Nøklene kommer fra JSON via companion, og der blir tall til STRENGER. Vi slår
--- derfor opp begge veier — ellers finner vi aldri noe, uten å feile synlig.
function NLC.Scoring.SimPctFor(imported, itemId)
  if not imported or not imported.simPct or not itemId then return nil end
  local v = imported.simPct[itemId]
  if v == nil then v = imported.simPct[tostring(itemId)] end
  return type(v) == "number" and v or nil
end

--- Er sim-dataene til å stole på? Feilet hentingen på nettsida, står hasSims
--- falskt for alle, og da skal INGEN utestenges på det grunnlaget.
function NLC.Scoring.SimDataOk()
  local d = NLC.db and NLC.db.importData
  return d ~= nil and d.kilder ~= nil and d.kilder.sims == "ok"
end

-- Hvilke kategorier som teller som loot: de som har trekk. MÅ følge
-- PENALISED_CATEGORIES i nordavind-web/lib/loot-penalty.ts. Offspec og tmog er
-- fritatt: teller addonet dem mens nettsiden ikke gjør det, henger det et
-- spøkelsestrekk på spilleren resten av uka.
function NLC.Scoring.CountsAsLoot(category)
  return LOOT_PENALTY[category or ""] ~= nil
end

-- Én utdeling (sign = 1) eller én angret utdeling (sign = -1) denne uka.
-- Antallet brukes ved uavgjort, trekket i poeng går i scoren.
function NLC.Scoring.AddWeeklyAward(playerName, category, sign)
  if not NLC.Scoring.CountsAsLoot(category) then return end
  NLC.db.weeklyLoot = NLC.db.weeklyLoot or { resetTimestamp = 0, counts = {} }
  local wl = NLC.db.weeklyLoot
  wl.counts = wl.counts or {}
  wl.penalty = wl.penalty or {}
  -- Oppgradert midt i uka: utdelinger fra forrige versjon finnes bare som
  -- antall. De kostet 10 hver den gang, og skal ikke forsvinne ved neste award.
  if wl.penalty[playerName] == nil then
    wl.penalty[playerName] = (wl.counts[playerName] or 0) * 10
  end
  local p = NLC.Scoring.PenaltyFor(category).week
  wl.counts[playerName] = math.max(0, (wl.counts[playerName] or 0) + sign)
  wl.penalty[playerName] = math.max(0, (wl.penalty[playerName] or 0) + sign * p)
end

-- Onsdagsresetten. Trekket MÅ nullstilles sammen med antallet — ellers
-- trekker forrige ukes loot hele neste uke, mens advarselen sier 0 loot.
function NLC.Scoring.ResetWeek(timestamp)
  NLC.db.weeklyLoot = NLC.db.weeklyLoot or {}
  NLC.db.weeklyLoot.counts = {}
  NLC.db.weeklyLoot.penalty = {}
  NLC.db.weeklyLoot.resetTimestamp = timestamp
end

-- Ukestrekket nettsida allerede har regnet med. Gammel eksport uten feltet
-- (nettsida ikke deployet ennå) faller tilbake til den gamle formelen.
function NLC.Scoring.ImportedWeekPenalty(imported)
  if not imported then return 0 end
  if type(imported.lootPenaltyWeek) == "number" then return imported.lootPenaltyWeek end
  return (imported.lootThisWeek or 0) * 10
end

-- Items denne uka. In-game-telleren gjelder naar en reset er registrert, ellers
-- importen. (Etter onsdagsresetten er counts[playerName] nil — uten vakten
-- faller Lua gjennom `or`-kjeden til forrige ukes import.)
function NLC.Scoring.WeeklyLootCount(imported, playerName)
  local wl = NLC.db.weeklyLoot
  if wl and wl.resetTimestamp and wl.resetTimestamp > 0 then
    return (wl.counts and wl.counts[playerName]) or 0
  end
  return (imported and imported.lootThisWeek) or 0
end

-- Items mottatt i sesongen. Skiller to som staar helt likt: reglene gir itemet
-- til den som har faatt faerrest. lootTotal fra nettsiden teller kun straffbare
-- kategorier, saa offspec og tmog paavirker heller ikke denne.
function NLC.Scoring.SeasonLootCount(imported, playerName)
  return NLC.Scoring.WeeklyLootCount(imported, playerName)
    + ((imported and imported.lootTotal) or 0)
end

function NLC.Scoring.GetImportedScore(playerName)
  local players = NLC.db.importData and NLC.db.importData.players
  if not players then return nil end
  local data = players[playerName]
  if not data then
    for name, d in pairs(players) do
      if name:lower() == playerName:lower() then
        data = d
        break
      end
    end
  end
  return data
end

function NLC.Scoring.TierAdjustment(tierCount)
  if tierCount == 1 or tierCount == 3 then return 3 end
  if tierCount == 0 or tierCount == 2 then return 1 end
  return 0
end

function NLC.Scoring.Calculate(imported, live, playerName)
  local score = 0
  local breakdown = {}

  if imported then
    score = imported.baseScore or 0
    table.insert(breakdown, { label = "Base (web)", value = imported.baseScore or 0 })

    -- Adjust for loot awarded during the current raid session that the server hasn't
    -- seen yet (i.e. since the last /nordlc import). weeklyLoot.penalty holds the
    -- penalty points for every award made by this officer this week; whatever
    -- exceeds what the import already counted is applied now.
    -- Gamle SavedVariables uten `penalty` har bare antall; de regnes x10.
    local wl = NLC.db.weeklyLoot
    if playerName and wl and wl.resetTimestamp and wl.resetTimestamp > 0 then
      local ingame = (wl.penalty and wl.penalty[playerName])
        or (((wl.counts and wl.counts[playerName]) or 0) * 10)
      local extra = ingame - NLC.Scoring.ImportedWeekPenalty(imported)
      if extra > 0 then
        score = score - extra
        table.insert(breakdown, { label = "Session loot", value = -extra })
      end
    end
  else
    table.insert(breakdown, { label = "Base (web)", value = 0 })
  end

  if live and live.isTier and imported and imported.tierGain then
    -- Tier-gevinsten fra nettsida, ikke den flate tabellen under.
    --
    -- Addonet regnet tier med `TierAdjustment` (+3 om du har 1 eller 3 brikker,
    -- +1 om du har 0 eller 2). Den er rolle- og spec-blind, og `GetTierCount`
    -- teller forrige tiers brikker som gjeldende. Resultatet var at nettsida og
    -- addonet rangerte tier nesten omvendt: maalt 26.08 sto Mohp foerst paa
    -- nettsida (3 gjeldende brikker, én unna 4-set) og NEST SIST i addonet,
    -- som saa fem brikker totalt og ga ham null.
    --
    -- Nettsida har baade riktig spec og riktig brikketall, saa den regner det
    -- ut og sender prosenten i importen. Samme formel som der: 5 % gir full
    -- pott, taket er 8.
    local poeng = math.min(8, imported.tierGain * (8 / 5))
    score = score + poeng
    table.insert(breakdown, { label = "Tier", value = math.floor(poeng * 10 + 0.5) / 10 })

  elseif live and live.isTier and live.tierCount then
    -- Fallback for gamle importer uten tierGain. Beholder den gamle
    -- oppfoerselen framfor aa gi null tier-vurdering.
    local tierAdj = NLC.Scoring.TierAdjustment(live.tierCount)
    score = score + tierAdj
    table.insert(breakdown, { label = "Tier bonus (gammel)", value = tierAdj })
  elseif live and live.simPct then
    -- Sim-poeng gis kun utenfor tier: der bruker nettsida tier-gevinsten i
    -- stedet, og den har vi ikke. Uten dette skillet ville en tier-del faatt
    -- baade flat bonus og sim-poeng, altsaa dobbelt opp.
    local simP = NLC.Scoring.SimPoints(live.simPct)
    if simP > 0 then
      score = score + simP
      table.insert(breakdown, { label = "Sim", value = math.floor(simP * 10 + 0.5) / 10 })
    end
  end

  return score, breakdown
end

function NLC.Scoring.GetWarnings(imported, playerName)
  local warnings = {}
  if not imported then
    table.insert(warnings, "No web data")
    return warnings
  end
  -- MÅ følge ATTENDANCE_REQUIREMENT i nordavind-web/lib/attendance.ts. Sto på
  -- 80 fra sesong 1; kravet er 90 i sesong 2, så en spiller på 85 % tapte poeng
  -- på nettsida uten at addonet sa fra.
  if imported.attendance and imported.attendance < 90 then
    table.insert(warnings, string.format("Low attendance: %d%%", imported.attendance))
  end
  if imported.wclParse and imported.wclParse < 25 then
    table.insert(warnings, string.format("Low parse: %d", imported.wclParse))
  end
  -- «/fight» var direkte feil: tallet er en andel av knappene, ikke et antall
  -- kast. 1.5 leses som «halvannet kast» men betyr 150 % av knappene sine.
  if imported.defensives and imported.defensives < DEFENSIVE_WARN_BELOW then
    table.insert(warnings, string.format("Low defensives: %d%% av knappene",
      math.floor(imported.defensives * 100 + 0.5)))
  end
  local weeklyCount = NLC.Scoring.WeeklyLootCount(imported, playerName)
  if weeklyCount > 0 then
    table.insert(warnings, string.format("%d loot denne uka", weeklyCount))
  end
  -- Nettsida avgjør hva som mangler (lib/datamangler.ts); addonet bare viser det.
  for _, m in ipairs(imported.mangler or {}) do
    table.insert(warnings, "Mangler: " .. m)
  end
  if imported.rank == "trial" then
    table.insert(warnings, "Trial")
  elseif imported.rank == "backup" then
    table.insert(warnings, "Backup")
  end
  return warnings
end
