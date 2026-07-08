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
      armorType = item.armorType,
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
      armorType = item.armorType,
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

  -- Live: if the wizard is open and this item is still in the ranking phase, rebuild the
  -- ranking and re-render (debounced ~1s to avoid flicker when many respond at once).
  if NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen() then
    NLC.Theme.Debounce("wizard-refresh", 1.0, function()
      local sessions = NLC.Council.GetActiveSessions()
      local idx = NLC.Council.GetWizardIndex()
      local cur = sessions[idx]
      if cur and cur.phase == "ranking" then
        cur.ranked = NLC.Council.BuildRanking(cur)
        NLC.UI.ShowWizard(sessions, idx)
      end
    end)
  end
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
      ilvl = session.ilvl, equipLoc = session.equipLoc, armorType = session.armorType,
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
      isTier = session.armorType ~= nil or (session.equipLoc and (
        session.equipLoc == "INVTYPE_HEAD" or
        session.equipLoc == "INVTYPE_SHOULDER" or
        session.equipLoc == "INVTYPE_CHEST" or
        session.equipLoc == "INVTYPE_ROBE" or
        session.equipLoc == "INVTYPE_HAND" or
        session.equipLoc == "INVTYPE_LEGS"
      )),
    }

    local score, breakdown = NLC.Scoring.Calculate(imported, live, name)
    local warnings = NLC.Scoring.GetWarnings(imported, name)

    -- Tier token filter: exclude candidates whose armor type doesn't match the token
    local skipCandidate = false
    if session.armorType then
      local classArmor = NLC.Utils.CLASS_ARMOR[interest.class]
      if classArmor ~= session.armorType then
        skipCandidate = true
      end
    end

    -- Wishlist safety filter: skip "upgrade" candidates if item not on their wishlist
    -- (front-end also hides the button, but this handles stale import data edge cases)
    if not skipCandidate and interest.category == "upgrade" and session.itemId then
      if imported and imported.wishlist and #imported.wishlist > 0 then
        local wishlisted = false
        for _, wid in ipairs(imported.wishlist) do
          if wid == session.itemId then wishlisted = true; break end
        end
        if not wishlisted then skipCandidate = true end
      end
    end

    if not skipCandidate then

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
    end -- if not skipCandidate
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
  -- Tmog does not count as real loot
  if category ~= "tmog" then
    NLC.db.weeklyLoot = NLC.db.weeklyLoot or { resetTimestamp = 0, counts = {} }
    NLC.db.weeklyLoot.counts[playerName] = (NLC.db.weeklyLoot.counts[playerName] or 0) + 1
  end

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
  NLC.Council.ClearRoll()
  NLC.Council.AdvanceWizard()
end

-- Award to a non-player target (disenchant/bank/free). Logged and tradeable, but does NOT
-- count as loot: no weekly counter, not exported to the website.
local SPECIAL_LABEL = { disenchant = "Disenchant", bank = "Guild Bank", free = "Free" }
function NLC.Council.AwardSpecial(target)
  if not NLC.isOfficer or not UnitIsGroupLeader("player") then return end
  local session = activeSessions[currentWizardIndex]
  if not session then return end
  local label = SPECIAL_LABEL[target] or target
  NLC.RecordAward(session.itemLink, label, UnitName("player"), session.boss, target, session.itemId, false)
  NLC.Utils.Print(session.itemLink .. " -> " .. label .. " (teller ikke som loot)")
  session.phase = "awarded"
  NLC.Council.ClearRoll()
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

-- Number of raiders who have responded on a given item (officer only — interests are
-- only populated on the officer's client).
function NLC.Council.GetResponseCount(sessionIdx)
  for _, s in ipairs(activeSessions) do
    if s.sessionIdx == sessionIdx then
      return NLC.Utils.TableCount(s.interests)
    end
  end
  return 0
end

-- Change a candidate's response category on the current wizard item, then rebuild + re-render.
function NLC.Council.ChangeCategory(name, newCategory)
  local session = activeSessions[currentWizardIndex]
  if not session or not session.interests[name] then return end
  session.interests[name].category = newCategory
  session.ranked = NLC.Council.BuildRanking(session)
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
end

-- Remove a candidate from the current wizard item's list, then rebuild + re-render.
function NLC.Council.RemoveCandidate(name)
  local session = activeSessions[currentWizardIndex]
  if not session or not session.interests[name] then return end
  session.interests[name] = nil
  session.ranked = NLC.Council.BuildRanking(session)
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
end

function NLC.Council.WhisperCandidate(name)
  ChatFrame_SendTell(name)
end

-- ============================================================
-- Roll-off between candidates (to break ties)
-- ============================================================
local _roll = { names = {}, results = {}, active = false }
local _rollFrame = CreateFrame("Frame")

-- Build a locale-independent pattern from RANDOM_ROLL_RESULT ("%s rolls %d (%d-%d)").
-- Escape ALL magic characters first (including the % in %s/%d and the literal parens),
-- then restore the placeholders as capture groups.
local _rollPattern = (_G.RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")
  :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  :gsub("%%%%s", "(.+)")
  :gsub("%%%%d", "(%%d+)")

function NLC.Council.GetRollState() return _roll end

function NLC.Council.ClearRoll()
  _roll = { names = {}, results = {}, active = false }
  _rollFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
end

function NLC.Council.AddToRoll(name)
  for _, n in ipairs(_roll.names) do if n == name then return end end
  table.insert(_roll.names, name)
  if NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen() then
    NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
  end
end

_rollFrame:SetScript("OnEvent", function(_, _, text)
  if not _roll.active or not text then return end
  local who, roll = text:match(_rollPattern)
  if not who then return end
  who = who:match("^([^-]+)") or who
  for _, n in ipairs(_roll.names) do
    if n == who and not _roll.results[who] then
      _roll.results[who] = tonumber(roll)
      if NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen() then
        NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      end
      break
    end
  end
end)

function NLC.Council.StartRoll()
  if #_roll.names < 2 then
    NLC.Utils.Print("Legg til minst 2 kandidater i roll-offen.")
    return
  end
  if _roll.timer then _roll.timer:Cancel() end
  _roll.results = {}
  _roll.active = true
  _rollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
  local session = activeSessions[currentWizardIndex]
  local itemLabel = (session and session.itemLink) or "item"
  local myName = UnitName("player")
  for _, n in ipairs(_roll.names) do
    if n == myName then
      RandomRoll(1, 100)
    else
      SendChatMessage("Roll-off for " .. itemLabel .. " — /roll 100 takk!", "WHISPER", nil, n)
    end
  end
  -- Close the capture window after 15s (cancellable so a re-started roll-off resets it).
  _roll.timer = C_Timer.NewTimer(15, function()
    _roll.timer = nil
    _roll.active = false
    _rollFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
  end)
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
  -- Raiders don't need the wizard — they receive award announcements via chat
end

function NLC.Council.OnRollCallAck(sender)
  local name = sender:match("^([^-]+)") or sender
  _rollCallAcks[name] = true
end

-- ============================================================
-- Distributed loot aggregation (officer only)
-- Each raider sends LOOT_REPORT after a boss; the officer collects reports over a
-- short window and feeds the merged list into the existing Loot Detected panel.
-- ============================================================
local _agg = {}          -- itemKey -> item
local _aggTimer = nil
local _aggBoss = nil

function NLC.Council.OnLootReport(sender, data)
  if not NLC.isOfficer then return end
  if not data or not data.items then return end
  _aggBoss = data.boss or _aggBoss
  for _, it in ipairs(data.items) do
    -- Dedup across senders (an item can only be looted once). Client already
    -- deduped by GUID, so itemId+looter is enough here.
    local key = (it.itemId or 0) .. ":" .. (it.looter or sender)
    if not _agg[key] then _agg[key] = it end
  end
  -- Open/extend a 5s collection window from the first report.
  if _aggTimer then _aggTimer:Cancel() end
  _aggTimer = C_Timer.NewTimer(5, function()
    _aggTimer = nil
    local items = {}
    for _, it in pairs(_agg) do table.insert(items, it) end
    _agg = {}
    if #items > 0 then
      NLC.LootDetection._setDetected(items)
      NLC.UI.ShowLootDetected(items)
    end
  end)
end
