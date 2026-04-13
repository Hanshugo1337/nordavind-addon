-- Council.lua
-- Council session management — interest collection, timer, award flow

local NLC = NordavindLC_NS

local catOrder = { upgrade = 1, catalyst = 2, offspec = 3, tmog = 4 }
-- roleTier: dps always above tank/healer within same category
local roleTier = { dps = 1, tank = 2, healer = 2 }

local activeSessions = {}    -- list of session tables (one per item)
local currentWizardIndex = 0 -- which item officer is viewing in wizard
local respondents = {}       -- set of player names who have responded
local raidAddonUsers = 0     -- count of addon users in raid (for auto-close)
local collectingTimer = nil  -- C_Timer ticker reference
local _rollCallAcks = {}     -- tracks addon users who responded to roll call
local _rollCallComplete = false -- true after 3s roll call window
local _collectingClosed = false -- guard against double CloseCollecting

function NLC.Council.StartMultiSession(items, boss)
  if not NLC.isOfficer then
    NLC.Utils.Print("Only officers can start council.")
    return
  end

  activeSessions = {}
  respondents = {}
  raidAddonUsers = 0
  currentWizardIndex = 1
  _collectingClosed = false

  for idx, item in ipairs(items) do
    table.insert(activeSessions, {
      sessionIdx = idx,
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

  -- Ensure all raiders are activated before sending session
  NLC.Comms.Send("ACTIVATE", "")
  NLC.Comms.SendMultiSession(items, boss or items[1].boss or "Unknown")
  NLC.Utils.Print("Council started for " .. #items .. " items")

  -- Count addon users via roll call (3s collection window)
  _rollCallAcks = {}
  _rollCallComplete = false
  NLC.Comms.SendRollCall()
  C_Timer.After(3, function()
    local count = 0
    for _ in pairs(_rollCallAcks) do count = count + 1 end
    raidAddonUsers = count
    _rollCallComplete = true
    -- Check if enough responses already came in during the 3s window
    local respCount = 0
    for _ in pairs(respondents) do respCount = respCount + 1 end
    if raidAddonUsers > 0 and respCount >= raidAddonUsers then
      if collectingTimer then collectingTimer:Cancel(); collectingTimer = nil end
      NLC.Council.CloseCollecting()
    end
  end)
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
      sessionIdx = item.sessionIdx,
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
    local sel = selections[session.sessionIdx]
    if sel and sel.category ~= "pass" then
      local eqLink, eqIlvl = NLC.Utils.GetEquippedInfo(session.equipLoc or "")
      local tierCount = NLC.Utils.GetTierCount()
      table.insert(responses, {
        sessionIdx = session.sessionIdx,
        category = sel.category,
        eqIlvl = eqIlvl or 0,
        eqLink = eqLink or "",
        tierCount = tierCount,
        note = sel.note or "",
      })
    end
  end
  if #responses > 0 then
    NLC.Comms.SendMultiInterest(responses)
  end
  NLC.Comms.SendRespond()
  NLC.Utils.Print("Responses sent for " .. #responses .. " item(s)")
end

function NLC.Council.OnInterestReceived(sender, sessionIdx, category, eqIlvl, tierCount, note, eqLink)
  if not NLC.isOfficer then return end

  local session = nil
  for _, s in ipairs(activeSessions) do
    if s.sessionIdx == sessionIdx then session = s; break end
  end
  if not session then return end

  local name = sender:match("^([^-]+)") or sender
  local _, class = UnitClass(name)

  session.interests[name] = {
    category = category,
    equippedIlvl = eqIlvl,
    equippedLink = (eqLink and eqLink ~= "") and eqLink or nil,
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

  if _rollCallComplete then
    NLC.Utils.Print(count .. " / " .. raidAddonUsers .. " responded")
    if raidAddonUsers > 0 and count >= raidAddonUsers then
      if collectingTimer then
        collectingTimer:Cancel()
        collectingTimer = nil
      end
      NLC.Council.CloseCollecting()
    end
  else
    NLC.Utils.Print(count .. " responded (counting addon users...)")
  end
end

function NLC.Council.CloseCollecting()
  if _collectingClosed or #activeSessions == 0 then return end
  _collectingClosed = true

  for _, session in ipairs(activeSessions) do
    session.phase = "ranking"
  end

  NLC.UI.HideMultiItemPopup()
  NLC.Utils.Print("Collecting closed. Starting award wizard.")

  for _, session in ipairs(activeSessions) do
    session.ranked = NLC.Council.BuildRanking(session)
  end

  -- Broadcast ranking data so all raiders can see the wizard
  local broadcastData = {}
  for _, session in ipairs(activeSessions) do
    table.insert(broadcastData, {
      sessionIdx = session.sessionIdx, itemLink = session.itemLink, itemId = session.itemId,
      ilvl = session.ilvl, equipLoc = session.equipLoc,
      boss = session.boss, ranked = session.ranked, phase = session.phase,
    })
  end
  NLC.Comms.Send("SESSION_CLOSE", broadcastData)

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
        session.equipLoc == "INVTYPE_ROBE" or
        session.equipLoc == "INVTYPE_HAND" or
        session.equipLoc == "INVTYPE_LEGS"
      ),
    }

    local score, breakdown = NLC.Scoring.Calculate(imported, live)
    local warnings = NLC.Scoring.GetWarnings(imported, name)

    -- Tmog: random roll 0-100 (generated fresh each ranking)
    local roll = nil
    if interest.category == "tmog" then
      roll = math.random(0, 100)
    end

    local role = imported and imported.role or "dps"

    table.insert(candidates, {
      name = name,
      class = interest.class,
      category = interest.category,
      note = interest.note,
      score = roll or score,
      roll = roll,
      breakdown = (not roll) and breakdown or nil,
      warnings = warnings,
      rank = imported and imported.rank or "trial",
      role = role,
      equippedIlvl = interest.equippedIlvl,
      equippedLink = interest.equippedLink,
      tierCount = interest.tierCount,
      ilvlDiff = (session.ilvl or 0) - (interest.equippedIlvl or 0),
    })
  end

  table.sort(candidates, function(a, b)
    local ca, cb = catOrder[a.category] or 99, catOrder[b.category] or 99
    if ca ~= cb then return ca < cb end
    local ra, rb = roleTier[a.role] or 2, roleTier[b.role] or 2
    if ra ~= rb then return ra < rb end
    return a.score > b.score
  end)

  return candidates
end

function NLC.Council.Award(playerName)
  if not NLC.isOfficer or not UnitIsGroupLeader("player") or #activeSessions == 0 then return end

  local session = activeSessions[currentWizardIndex]
  if not session then return end

  -- Find the player's interest category from ranking
  local category = "upgrade"
  if session.ranked then
    for _, c in ipairs(session.ranked) do
      if c.name == playerName then
        category = c.category or "upgrade"
        break
      end
    end
  end

  NLC.Comms.Send("AWARD", { sessionIdx = session.sessionIdx, itemLink = session.itemLink, playerName = playerName, category = category })
  NLC.RecordAward(session.itemLink, playerName, UnitName("player"), session.boss, category, session.itemId)
  NLC.Utils.Print(session.itemLink .. " awarded to " .. playerName .. " (" .. category .. ")")

  -- Track weekly loot count in SavedVariables (resets each Wednesday)
  NLC.db.weeklyLoot = NLC.db.weeklyLoot or { resetTimestamp = 0, counts = {} }
  NLC.db.weeklyLoot.counts[playerName] = (NLC.db.weeklyLoot.counts[playerName] or 0) + 1

  if IsInRaid() then
    local chatType = (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and "RAID_WARNING" or "RAID"
    SendChatMessage(playerName .. " has been awarded " .. session.itemLink .. " for " .. category, chatType)
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
  -- Search forward first, then wrap around to beginning
  for i = currentWizardIndex + 1, #activeSessions do
    if activeSessions[i].phase == "ranking" then
      currentWizardIndex = i
      NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      return
    end
  end
  for i = 1, currentWizardIndex - 1 do
    if activeSessions[i].phase == "ranking" then
      currentWizardIndex = i
      NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      return
    end
  end
  NLC.Utils.Print("All items awarded!")
  NLC.UI.HideWizard()
  activeSessions = {}
end

function NLC.Council.ReopenWizard()
  -- Find the first ranking-phase session and reopen the wizard
  for i, s in ipairs(activeSessions) do
    if s.phase == "ranking" then
      currentWizardIndex = i
      NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      return true
    end
  end
  return false
end

function NLC.Council.AwardLaterCurrent()
  if #activeSessions == 0 then return end
  local session = activeSessions[currentWizardIndex]
  if not session then return end

  table.insert(NLC.pendingSessions, session)
  NLC.Utils.Print(session.itemLink .. " added to pending")
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
    NLC.Utils.Print("Ingen ufordelte items.")
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
  NLC.Utils.Print("Wizard opened with " .. #activeSessions .. " pending items.")
end

function NLC.Council.OnAward(sessionIdx, itemLink, playerName, sender, category)
  local catText = category and (" for " .. category) or ""
  NLC.Utils.Print(playerName .. " has been awarded " .. itemLink .. catText)

  -- Non-officers: update read-only wizard display
  if not NLC.isOfficer then
    for _, session in ipairs(activeSessions) do
      if session.sessionIdx == sessionIdx then
        session.phase = "awarded"
        break
      end
    end
    -- Advance to next unawarded item
    for i = 1, #activeSessions do
      if activeSessions[i].phase == "ranking" then
        currentWizardIndex = i
        NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
        return
      end
    end
    NLC.UI.HideWizard()
  end
end

function NLC.Council.OnSessionClose(data)
  activeSessions = data
  currentWizardIndex = 1
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
end

function NLC.Council.OnRollCallAck(sender)
  local name = sender:match("^([^-]+)") or sender
  _rollCallAcks[name] = true
end
