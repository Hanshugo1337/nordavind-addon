-- Scoring.lua
-- Calculate loot council score from imported web data + live in-game data

local NLC = NordavindLC_NS

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

function NLC.Scoring.Calculate(imported, live)
  local score = 0
  local breakdown = {}

  if imported then
    score = imported.baseScore or 0
    table.insert(breakdown, { label = "Base (web)", points = imported.baseScore or 0 })
  else
    table.insert(breakdown, { label = "Base (web)", points = 0 })
  end

  if live and live.isTier and live.tierCount then
    local tierAdj = NLC.Scoring.TierAdjustment(live.tierCount)
    score = score + tierAdj
    table.insert(breakdown, { label = "Tier bonus", points = tierAdj })
  end

  return score, breakdown
end

function NLC.Scoring.GetWarnings(imported, playerName)
  local warnings = {}
  if not imported then
    table.insert(warnings, "No web data")
    return warnings
  end
  if imported.attendance and imported.attendance < 80 then
    table.insert(warnings, string.format("Low attendance: %d%%", imported.attendance))
  end
  if imported.wclParse and imported.wclParse < 25 then
    table.insert(warnings, string.format("Low parse: %d", imported.wclParse))
  end
  if imported.defensives and imported.defensives < 0.8 then
    table.insert(warnings, string.format("Low defensives: %.1f/fight", imported.defensives))
  end
  -- Use persisted weekly count instead of ephemeral importData field
  local weeklyCount = NLC.db.weeklyLoot and NLC.db.weeklyLoot.counts and
    NLC.db.weeklyLoot.counts[playerName] or imported.lootThisWeek or 0
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
