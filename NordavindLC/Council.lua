-- Council.lua
-- Council session management — interest collection, timer, award flow

local NLC = NordavindLC_NS

local activeSessions = {}    -- list of session tables (one per item)
local currentWizardIndex = 0 -- which item officer is viewing in wizard
local respondents = {}       -- set of player names who have responded
local raidAddonUsers = 0     -- count of addon users in raid (for auto-close)
local collectingTimer = nil  -- C_Timer ticker reference

function NLC.Council.StartMultiSession(items, boss)
  if not NLC.isOfficer then
    NLC.Utils.Print("Kun officers kan starte council.")
    return
  end

  activeSessions = {}
  respondents = {}
  raidAddonUsers = 0
  currentWizardIndex = 1

  for _, item in ipairs(items) do
    table.insert(activeSessions, {
      itemLink = item.itemLink,
      itemId = item.itemId,
      ilvl = item.ilvl,
      equipLoc = item.equipLoc,
      boss = boss or item.boss or "Unknown",
      timer = NLC.db.config.timer or 90,
      interests = {},
      phase = "collecting",
    })
  end

  raidAddonUsers = GetNumGroupMembers()
  NLC.Comms.SendMultiSession(items, boss or items[1].boss or "Unknown")
  NLC.Utils.Print("Council startet for " .. #items .. " items")
  NLC.UI.ShowMultiItemPopup(activeSessions, NLC.db.config.timer or 90)

  local remaining = NLC.db.config.timer or 90
  collectingTimer = C_Timer.NewTicker(1, function(ticker)
    remaining = remaining - 1
    if remaining <= 0 then
      ticker:Cancel()
      collectingTimer = nil
      NLC.Council.CloseCollecting()
    end
  end, remaining)
end

function NLC.Council.StartSession(itemLink, itemId, ilvl, equipLoc, boss)
  NLC.Council.StartMultiSession({
    { itemLink = itemLink, itemId = itemId, ilvl = ilvl, equipLoc = equipLoc, boss = boss },
  }, boss)
end

function NLC.Council.OnMultiSessionStart(items, timer, sender)
  activeSessions = {}
  for _, item in ipairs(items) do
    table.insert(activeSessions, {
      itemLink = item.itemLink,
      itemId = item.itemId,
      ilvl = item.ilvl,
      equipLoc = item.equipLoc,
      boss = item.boss or "Unknown",
      timer = timer,
      interests = {},
      phase = "collecting",
    })
  end
  NLC.UI.ShowMultiItemPopup(activeSessions, timer)
end

function NLC.Council.SubmitResponses(selections)
  local responses = {}
  for _, session in ipairs(activeSessions) do
    local sel = selections[session.itemId]
    if sel and sel.category ~= "pass" then
      local eqLink, eqIlvl = NLC.Utils.GetEquippedInfo(session.equipLoc or "")
      local tierCount = NLC.Utils.GetTierCount()
      table.insert(responses, {
        itemId = session.itemId,
        category = sel.category,
        eqIlvl = eqIlvl or 0,
        tierCount = tierCount,
        note = sel.note or "",
      })
    end
  end
  if #responses > 0 then
    NLC.Comms.SendMultiInterest(responses)
  end
  NLC.Comms.SendRespond()
  NLC.Utils.Print("Svar sendt for " .. #responses .. " item(s)")
end

function NLC.Council.OnInterestReceived(sender, itemId, category, eqIlvl, tierCount, note)
  if not NLC.isOfficer then return end

  local session = nil
  for _, s in ipairs(activeSessions) do
    if s.itemId == itemId then session = s; break end
  end
  if not session then return end

  local name = sender:match("^([^-]+)") or sender
  local _, class = UnitClass(name)

  session.interests[name] = {
    category = category,
    equippedIlvl = eqIlvl,
    tierCount = tierCount,
    class = class or "WARRIOR",
    note = (note and note ~= "") and note or nil,
  }
end

function NLC.Council.OnRespond(sender)
  if not NLC.isOfficer then return end
  local name = sender:match("^([^-]+)") or sender
  respondents[name] = true

  local count = 0
  for _ in pairs(respondents) do count = count + 1 end

  NLC.Utils.Print(count .. " / " .. raidAddonUsers .. " har svart")

  if count >= raidAddonUsers then
    if collectingTimer then
      collectingTimer:Cancel()
      collectingTimer = nil
    end
    NLC.Council.CloseCollecting()
  end
end

function NLC.Council.CloseCollecting()
  if #activeSessions == 0 then return end

  for _, session in ipairs(activeSessions) do
    session.phase = "ranking"
  end

  NLC.Comms.Send("SESSION_CLOSE", "")
  NLC.Utils.Print("Collecting lukket. Starter award wizard.")

  for _, session in ipairs(activeSessions) do
    session.ranked = NLC.Council.BuildRanking(session)
  end

  currentWizardIndex = 1
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
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
  if not NLC.isOfficer or #activeSessions == 0 then return end

  local session = activeSessions[currentWizardIndex]
  if not session then return end

  NLC.Comms.Send("AWARD", session.itemLink .. ":" .. playerName)
  NLC.RecordAward(session.itemLink, playerName, UnitName("player"), session.boss)
  NLC.Utils.Print(session.itemLink .. " tildelt " .. playerName)

  local imported = NLC.Scoring.GetImportedScore(playerName)
  if imported then
    imported.lootThisWeek = (imported.lootThisWeek or 0) + 1
    imported.baseScore = (imported.baseScore or 0) - 15
  end

  if IsInRaid() then
    SendChatMessage(session.itemLink .. " -> " .. playerName, "RAID_WARNING")
  end

  for i, s in ipairs(activeSessions) do
    if i ~= currentWizardIndex and s.phase == "ranking" then
      s.ranked = NLC.Council.BuildRanking(s)
    end
  end

  session.phase = "awarded"
  NLC.Council.AdvanceWizard()
end

function NLC.Council.AdvanceWizard()
  for i = currentWizardIndex + 1, #activeSessions do
    if activeSessions[i].phase == "ranking" then
      currentWizardIndex = i
      NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      return
    end
  end
  NLC.Utils.Print("Alle items tildelt!")
  NLC.UI.HideWizard()
  activeSessions = {}
end

function NLC.Council.AwardLaterCurrent()
  if #activeSessions == 0 then return end
  local session = activeSessions[currentWizardIndex]
  if not session then return end

  table.insert(NLC.pendingSessions, session)
  NLC.Utils.Print(session.itemLink .. " lagt til ventende")
  NLC.UpdateMinimapCount()

  session.phase = "deferred"
  NLC.Council.AdvanceWizard()
end

function NLC.Council.SkipCurrent()
  if #activeSessions == 0 then return end
  activeSessions[currentWizardIndex].phase = "skipped"
  NLC.Council.AdvanceWizard()
end

function NLC.Council.GetActiveSessions()
  return activeSessions
end

function NLC.Council.GetWizardIndex()
  return currentWizardIndex
end

function NLC.Council.SetWizardIndex(idx)
  if idx >= 1 and idx <= #activeSessions and activeSessions[idx].phase == "ranking" then
    currentWizardIndex = idx
    NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
  end
end

function NLC.Council.ResumePending(index)
  local session = table.remove(NLC.pendingSessions, index)
  if not session then return end
  activeSessions = { session }
  currentWizardIndex = 1
  session.phase = "ranking"
  session.ranked = NLC.Council.BuildRanking(session)
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
  NLC.UpdateMinimapCount()
end

function NLC.Council.ResumeAll()
  if #NLC.pendingSessions == 0 then
    NLC.Utils.Print("Ingen ventende items.")
    return
  end

  activeSessions = {}
  for _, session in ipairs(NLC.pendingSessions) do
    session.phase = "ranking"
    session.ranked = NLC.Council.BuildRanking(session)
    table.insert(activeSessions, session)
  end
  NLC.pendingSessions = {}
  NLC.UpdateMinimapCount()

  currentWizardIndex = 1
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
  NLC.Utils.Print("Wizard apnet med " .. #activeSessions .. " ventende items.")
end

function NLC.Council.OnAward(itemLink, playerName, sender)
  NLC.Utils.Print(itemLink .. " tildelt " .. playerName .. " (av " .. sender .. ")")
end
