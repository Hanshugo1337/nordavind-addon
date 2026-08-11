-- Scoring.lua
-- Calculate loot council score from imported web data + live in-game data

local NLC = NordavindLC_NS

-- Straff per item en spiller har fått denne uka. MÅ følge ukesstraffen i
-- app/api/loot/route.ts (lootPenalty i nordavind-web/lib/scoring.ts) — ligger
-- de to på ulike tall, straffes samme item ulikt avhengig av om importen har
-- rukket å oppdatere seg, og rekkefølgen i raidet blir en annen enn nettsidens.
local WEEKLY_LOOT_PENALTY = 10

-- Hvilke kategorier som teller som loot. MÅ følge PENALISED i
-- nordavind-web/lib/scoring.ts og app/api/loot/route.ts. Offspec og tmog er
-- fritatt: teller addonet dem mens nettsiden ikke gjør det, henger det et
-- spøkelses-10 på spilleren resten av uka.
local PENALISED_CATEGORIES = { upgrade = true, catalyst = true }

function NLC.Scoring.CountsAsLoot(category)
  return PENALISED_CATEGORIES[category or "upgrade"] == true
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
    -- seen yet (i.e. since the last /nordlc import). weeklyLoot.counts tracks every
    -- award made by this officer this week; if that count exceeds what the import
    -- knew about, apply the extra weekly penalty per item now.
    local wl = NLC.db.weeklyLoot
    if playerName and wl and wl.resetTimestamp and wl.resetTimestamp > 0 then
      local sessionLoot = (wl.counts and wl.counts[playerName]) or 0
      local importedThisWeek = imported.lootThisWeek or 0
      if sessionLoot > importedThisWeek then
        local extraPenalty = (sessionLoot - importedThisWeek) * WEEKLY_LOOT_PENALTY
        score = score - extraPenalty
        table.insert(breakdown, { label = "Session loot", value = -extraPenalty })
      end
    end
  else
    table.insert(breakdown, { label = "Base (web)", value = 0 })
  end

  if live and live.isTier and live.tierCount then
    local tierAdj = NLC.Scoring.TierAdjustment(live.tierCount)
    score = score + tierAdj
    table.insert(breakdown, { label = "Tier bonus", value = tierAdj })
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
  if imported.defensives and imported.defensives < 0.8 then
    table.insert(warnings, string.format("Low defensives: %.1f/fight", imported.defensives))
  end
  local weeklyCount = NLC.Scoring.WeeklyLootCount(imported, playerName)
  if weeklyCount > 0 then
    table.insert(warnings, string.format("%d loot denne uka", weeklyCount))
  end
  if imported.rank == "trial" then
    table.insert(warnings, "Trial")
  elseif imported.rank == "backup" then
    table.insert(warnings, "Backup")
  end
  return warnings
end
