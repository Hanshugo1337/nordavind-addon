-- Council.lua
-- Council session management — interest collection, timer, award flow

local NLC = NordavindLC_NS

local activeSession = nil

function NLC.Council.StartSession(itemLink, itemId, ilvl, equipLoc, boss)
  if not NLC.isOfficer then
    NLC.Utils.Print("Kun officers kan starte council.")
    return
  end

  activeSession = {
    itemLink = itemLink,
    itemId = itemId,
    ilvl = ilvl,
    equipLoc = equipLoc,
    boss = boss or "Unknown",
    timer = NLC.db.config.timer or 180,
    interests = {},
    phase = "collecting",
  }

  NLC.Comms.Send("COUNCIL_START", itemLink .. ":" .. activeSession.timer)
  NLC.Utils.Print("Council startet for " .. itemLink)

  -- Also show interest popup for the officer themselves
  NLC.UI.ShowInterestPopup(itemLink, ilvl, equipLoc, activeSession.timer)

  C_Timer.After(activeSession.timer, function()
    if activeSession and activeSession.phase == "collecting" then
      NLC.Council.CloseCollecting()
    end
  end)
end

function NLC.Council.OnCouncilStart(itemLink, timer, sender)
  local _, _, _, ilvl, _, _, _, _, equipLoc = C_Item.GetItemInfo(itemLink)
  NLC.UI.ShowInterestPopup(itemLink, ilvl or 0, equipLoc or "", timer)
end

function NLC.Council.SendInterest(itemId, category, note)
  local equipLoc = activeSession and activeSession.equipLoc or ""
  local _, eqIlvl = NLC.Utils.GetEquippedInfo(equipLoc)
  local tierCount = NLC.Utils.GetTierCount()
  local noteStr = note and note:gsub(":", "") or ""
  NLC.Comms.Send("INTEREST", string.format("%d:%s:%d:%d:%s", itemId or 0, category, eqIlvl, tierCount, noteStr))
end

function NLC.Council.OnInterestReceived(sender, itemId, category, eqIlvl, tierCount, note)
  if not activeSession or not NLC.isOfficer then return end

  local name = sender:match("^([^-]+)") or sender
  local _, class = UnitClass(name)

  activeSession.interests[name] = {
    category = category,
    equippedIlvl = eqIlvl,
    tierCount = tierCount,
    class = class or "WARRIOR",
    note = (note and note ~= "") and note or nil,
  }

  if NLC.UI.UpdateCouncilInterests then
    NLC.UI.UpdateCouncilInterests(activeSession)
  end
end

function NLC.Council.CloseCollecting()
  if not activeSession then return end
  activeSession.phase = "ranking"
  NLC.Comms.Send("COUNCIL_CLOSE", tostring(activeSession.itemId or 0))

  local ranked = NLC.Council.BuildRanking(activeSession)
  NLC.UI.ShowRanking(activeSession, ranked)
end

function NLC.Council.BuildRanking(session)
  local candidates = {}

  for name, interest in pairs(session.interests) do
    local imported = NLC.Scoring.GetImportedScore(name)
    local live = {
      equippedIlvl = interest.equippedIlvl,
      tierCount = interest.tierCount,
      isTier = session.equipLoc and (
        session.equipLoc == "INVTYPE_HEAD" or
        session.equipLoc == "INVTYPE_SHOULDER" or
        session.equipLoc == "INVTYPE_CHEST" or
        session.equipLoc == "INVTYPE_HAND" or
        session.equipLoc == "INVTYPE_LEGS"
      ),
    }

    local score, breakdown = NLC.Scoring.Calculate(imported, live)
    local warnings = NLC.Scoring.GetWarnings(imported)

    table.insert(candidates, {
      name = name,
      class = interest.class,
      category = interest.category,
      note = interest.note,
      score = score,
      breakdown = breakdown,
      warnings = warnings,
      rank = imported and imported.rank or "trial",
      equippedIlvl = interest.equippedIlvl,
      tierCount = interest.tierCount,
      ilvlDiff = (session.ilvl or 0) - (interest.equippedIlvl or 0),
    })
  end

  local catOrder = { upgrade = 1, catalyst = 2, offspec = 3, tmog = 4 }
  table.sort(candidates, function(a, b)
    local ca, cb = catOrder[a.category] or 99, catOrder[b.category] or 99
    if ca ~= cb then return ca < cb end
    return a.score > b.score
  end)

  return candidates
end

function NLC.Council.Award(playerName)
  if not activeSession or not NLC.isOfficer then return end

  NLC.Comms.Send("AWARD", activeSession.itemLink .. ":" .. playerName)
  NLC.RecordAward(activeSession.itemLink, playerName, UnitName("player"), activeSession.boss)
  NLC.Utils.Print(activeSession.itemLink .. " tildelt " .. playerName)

  -- Live recalculate: bump lootThisWeek so next item scores reflect this award
  local imported = NLC.Scoring.GetImportedScore(playerName)
  if imported then
    imported.lootThisWeek = (imported.lootThisWeek or 0) + 1
    imported.baseScore = (imported.baseScore or 0) - 15
  end

  -- Announce to raid chat
  if IsInRaid() then
    SendChatMessage(activeSession.itemLink .. " -> " .. playerName, "RAID_WARNING")
  end

  activeSession = nil
end

function NLC.Council.AwardLater()
  if not activeSession then return end
  table.insert(NLC.pendingSessions, activeSession)
  NLC.Utils.Print(activeSession.itemLink .. " lagt til ventende (" .. #NLC.pendingSessions .. " totalt)")
  activeSession = nil
  NLC.UpdateMinimapCount()
end

function NLC.Council.ResumePending(index)
  local session = table.remove(NLC.pendingSessions, index)
  if not session then return end
  activeSession = session
  activeSession.phase = "ranking"
  local ranked = NLC.Council.BuildRanking(activeSession)
  NLC.UI.ShowRanking(activeSession, ranked)
end

function NLC.Council.OnAward(itemLink, playerName, sender)
  NLC.Utils.Print(itemLink .. " tildelt " .. playerName .. " (av " .. sender .. ")")
end

function NLC.Council.GetActiveSession()
  return activeSession
end
