-- UI/RankingFrame.lua
-- Ranked candidate list with award buttons (officer) and display (all)

local NLC = NordavindLC_NS
local T = NLC.Theme

StaticPopupDialogs["NORDLC_CONFIRM_AWARD"] = {
  text = "Tildel %s til %s?",
  button1 = "Ja",
  button2 = "Nei",
  OnAccept = function(self)
    if self.data and self.data.name then
      NLC.Council.Award(self.data.name)
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local rankFrame = nil
local RANK_COLORS = {
  raider = { r = 0.2, g = 0.8, b = 0.2 },
  backup = { r = 0.9, g = 0.7, b = 0.2 },
  trial  = { r = 0.9, g = 0.5, b = 0.2 },
}

local CATEGORY_LABELS = {
  upgrade  = T.GREEN .. "Upgrade|r",
  catalyst = "|cff9933ffCatalyst|r",
  offspec  = "|cff3399ffOffspec|r",
  tmog     = T.GOLD .. "Tmog|r",
}

-- Column positions (x offsets)
local COL = {
  rank  = 14,
  name  = 100,
  score = 270,
  ilvl  = 360,
  tier  = 440,
  info  = 500,
  award = -14,
}

local ROW_HEIGHT = 44
local NOTE_HEIGHT = 20
local CAT_HEADER_HEIGHT = 32
local FRAME_WIDTH = 820
local FRAME_HEIGHT = 560

function NLC.UI.ShowRanking(session, candidates)
  if not rankFrame then
    rankFrame = CreateFrame("Frame", "NordavindLCRanking", UIParent, "BackdropTemplate")
    rankFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    rankFrame:SetPoint("CENTER")
    rankFrame:SetMovable(true)
    rankFrame:EnableMouse(true)
    rankFrame:RegisterForDrag("LeftButton")
    rankFrame:SetScript("OnDragStart", rankFrame.StartMoving)
    rankFrame:SetScript("OnDragStop", rankFrame.StopMovingOrSizing)
    rankFrame:SetFrameStrata("DIALOG")
    T.ApplyBackdrop(rankFrame)

    T.CreateTitleBar(rankFrame, "Loot Council")

    local closeX = CreateFrame("Button", nil, rankFrame, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -2, -2)

    -- Column headers (pushed down to make room for item info in wizard mode)
    local hdrY = -62
    rankFrame.headerTexts = {}
    local headers = {
      { text = "RANK",  x = COL.rank },
      { text = "NAME",  x = COL.name },
      { text = "SCORE", x = COL.score },
      { text = "ILVL",  x = COL.ilvl },
      { text = "TIER",  x = COL.tier },
      { text = "INFO",  x = COL.info },
    }
    for _, h in ipairs(headers) do
      local ht = rankFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      ht:SetPoint("TOPLEFT", h.x, hdrY)
      ht:SetText(T.GOLD_DIM .. h.text .. "|r")
      table.insert(rankFrame.headerTexts, ht)
    end

    -- Header separator
    local hdrSep = rankFrame:CreateTexture(nil, "ARTWORK")
    hdrSep:SetPoint("TOPLEFT", 12, hdrY - 16)
    hdrSep:SetPoint("TOPRIGHT", -30, hdrY - 16)
    hdrSep:SetHeight(1)
    hdrSep:SetColorTexture(0.788, 0.659, 0.298, 0.3)

    -- Scroll area
    rankFrame.scrollFrame = CreateFrame("ScrollFrame", nil, rankFrame, "UIPanelScrollFrameTemplate")
    rankFrame.scrollFrame:SetPoint("TOPLEFT", 12, hdrY - 20)
    rankFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -32, 60)

    rankFrame.scrollChild = CreateFrame("Frame")
    rankFrame.scrollFrame:SetScrollChild(rankFrame.scrollChild)
    rankFrame.scrollChild:SetSize(FRAME_WIDTH - 50, 1)

    -- Bottom buttons
    rankFrame.laterBtn = T.CreateButton(rankFrame, 160, 34, "Award Later")
    rankFrame.laterBtn:SetPoint("BOTTOMLEFT", 20, 16)
    rankFrame.laterBtn:SetScript("OnClick", function()
      NLC.Council.AwardLaterCurrent()
      rankFrame:Hide()
    end)

    -- "Annet" — send item to a non-player target (Disenchant/Bank/Free), does not count as loot.
    rankFrame.specialBtn = T.CreateButton(rankFrame, 120, 34, "Annet")
    rankFrame.specialBtn:SetPoint("BOTTOMLEFT", 190, 16)
    rankFrame.specialBtn:SetScript("OnClick", function(self)
      T.ShowMenu(self, {
        { title = true, text = "Send item til" },
        { text = "Disenchant", func = function() NLC.Council.AwardSpecial("disenchant") end },
        { text = "Guild Bank", func = function() NLC.Council.AwardSpecial("bank") end },
        { text = "Free (gratis)", func = function() NLC.Council.AwardSpecial("free") end },
      })
    end)

    -- Officer-avstemming — kun lederen, og kun når det finnes noen å stemme over.
    rankFrame.voteBtn = T.CreateButton(rankFrame, 200, 34, "Be om officer-avstemming")
    rankFrame.voteBtn:SetPoint("BOTTOMLEFT", 320, 16)
    rankFrame.voteBtn:SetScript("OnClick", function()
      local sessions = NLC.Council.GetActiveSessions()
      local session = sessions[NLC.Council.GetWizardIndex()]
      if session then NLC.UI.ShowBallotBuilder(session) end
    end)

    rankFrame.closeBtn = T.CreateButton(rankFrame, 120, 34, "Close")
    rankFrame.closeBtn:SetPoint("BOTTOMRIGHT", -20, 16)
    rankFrame.closeBtn:SetScript("OnClick", function()
      rankFrame:Hide()
    end)
  end

  -- Item tooltip hover on item info line
  if not rankFrame.itemHover then
    rankFrame.itemHover = CreateFrame("Frame", nil, rankFrame)
    rankFrame.itemHover:SetSize(FRAME_WIDTH - 100, 20)
    rankFrame.itemHover:SetPoint("TOP", 0, -36)
    rankFrame.itemHover:EnableMouse(true)
  end
  if session.itemLink then
    rankFrame.itemHover:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetHyperlink(session.itemLink)
      GameTooltip:Show()
    end)
    rankFrame.itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  rankFrame.itemHover:Show()

  -- Update title with item link
  rankFrame.title:SetText(T.GOLD .. "Loot Council|r  " .. T.MUTED .. "—|r  " .. (session.itemLink or "?"))
  rankFrame.laterBtn:SetShown(NLC.isOfficer and NLC.IsLootLeader())
  if rankFrame.specialBtn then
    rankFrame.specialBtn:SetShown(NLC.isOfficer and NLC.IsLootLeader())
  end

  -- Clear previous rows
  for _, child in ipairs({ rankFrame.scrollChild:GetChildren() }) do
    child:Hide()
  end
  for _, region in ipairs({ rankFrame.scrollChild:GetRegions() }) do
    region:Hide()
  end

  local yOffset = 0
  local currentCat = nil

  for i, c in ipairs(candidates) do
    -- Category header
    if c.category ~= currentCat then
      currentCat = c.category
      if yOffset > 0 then yOffset = yOffset + 8 end

      local catBg = rankFrame.scrollChild:CreateTexture(nil, "BACKGROUND")
      catBg:SetPoint("TOPLEFT", 0, -yOffset)
      catBg:SetSize(FRAME_WIDTH - 50, CAT_HEADER_HEIGHT)
      catBg:SetColorTexture(0.788, 0.659, 0.298, 0.06)
      catBg:Show()

      local header = rankFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      header:SetPoint("TOPLEFT", COL.rank, -yOffset - 8)
      header:SetText(CATEGORY_LABELS[currentCat] or currentCat)
      header:Show()

      local sep = rankFrame.scrollChild:CreateTexture(nil, "ARTWORK")
      sep:SetPoint("TOPLEFT", 4, -yOffset - CAT_HEADER_HEIGHT)
      sep:SetWidth(FRAME_WIDTH - 60)
      sep:SetHeight(1)
      sep:SetColorTexture(0.3, 0.3, 0.3, 0.3)
      sep:Show()

      yOffset = yOffset + CAT_HEADER_HEIGHT + 2
    end

    -- Alternating row background
    local rowBg = rankFrame.scrollChild:CreateTexture(nil, "BACKGROUND")
    rowBg:SetPoint("TOPLEFT", 0, -yOffset)
    rowBg:SetSize(FRAME_WIDTH - 50, ROW_HEIGHT)
    rowBg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
    rowBg:Show()

    local row = CreateFrame("Frame", nil, rankFrame.scrollChild)
    row:SetSize(FRAME_WIDTH - 50, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:Show()

    -- Rank badge
    local rc = RANK_COLORS[c.rank] or RANK_COLORS.trial
    local rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankText:SetPoint("LEFT", COL.rank, 0)
    rankText:SetWidth(80)
    rankText:SetJustifyH("LEFT")
    rankText:SetText(string.format("|cff%02x%02x%02x%s|r", rc.r * 255, rc.g * 255, rc.b * 255, (c.rank or "?"):upper()))

    -- Name (class colored, larger font) with player tooltip
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", COL.name, 0)
    nameText:SetText(NLC.Utils.ClassColoredName(c.name, c.class))

    -- Role label (small, color-coded)
    local roleColors = { dps = "|cffff4444", tank = "|cff4488ff", healer = "|cff44ff88" }
    local roleLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleLabel:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
    roleLabel:SetText((roleColors[c.role] or "|cffffffff") .. (c.role or "dps") .. "|r")

    -- Player tooltip hover area
    local nameHover = CreateFrame("Frame", nil, row)
    nameHover:SetSize(160, ROW_HEIGHT)
    nameHover:SetPoint("LEFT", COL.name, 0)
    nameHover:EnableMouse(true)
    nameHover:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(c.name, 1, 0.82, 0)
      GameTooltip:AddLine(" ")
      if c.breakdown then
        for _, line in ipairs(c.breakdown) do
          GameTooltip:AddDoubleLine(line.label or "", string.format("%.1f", line.value or 0), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
      end
      GameTooltip:AddDoubleLine("Total Score", string.format("%.1f", c.score or 0), 1, 0.82, 0, 0.2, 1, 0.2)
      GameTooltip:AddDoubleLine("Equipped ilvl", tostring(c.equippedIlvl or "?"), 0.6, 0.6, 0.6, 1, 1, 1)
      GameTooltip:AddDoubleLine("ilvl diff", (c.ilvlDiff and c.ilvlDiff > 0 and "+" or "") .. tostring(c.ilvlDiff or 0), 0.6, 0.6, 0.6, 1, 1, 1)
      GameTooltip:AddDoubleLine("Tier pieces", tostring(c.tierCount or 0) .. "pc", 0.6, 0.6, 0.6, 1, 1, 1)
      GameTooltip:AddDoubleLine("Rank", (c.rank or "?"):upper(), 0.6, 0.6, 0.6, 1, 1, 1)
      if c.note then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Note: " .. c.note, 0.8, 0.8, 0.8, true)
      end
      if c.warnings and #c.warnings > 0 then
        GameTooltip:AddLine(" ")
        for _, w in ipairs(c.warnings) do
          GameTooltip:AddLine(w, 1, 0.5, 0, true)
        end
      end
      GameTooltip:Show()
    end)
    nameHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Officer: click the name (left or right) to open the candidate menu. A visible "▾"
    -- after the name signals it's interactive. Uses our own dropdown (MenuUtil was unreliable).
    if NLC.isOfficer then
      nameText:SetText((nameText:GetText() or "") .. "  " .. T.GOLD_DIM .. "▾|r")
      nameHover:SetScript("OnMouseUp", function(self)
        local roll = NLC.Council.GetRollState()
        local items = {
          { title = true, text = c.name },
          { text = "Legg til i roll", func = function() NLC.Council.AddToRoll(c.name) end },
        }
        if #roll.names >= 2 then
          table.insert(items, { text = "Start roll (" .. #roll.names .. ")", color = T.GOLD_LIGHT,
            func = function() NLC.Council.StartRoll() end })
        end
        table.insert(items, { divider = true })
        table.insert(items, { title = true, text = "Bytt kategori" })
        for _, cat in ipairs({ "upgrade", "catalyst", "offspec", "tmog" }) do
          table.insert(items, { text = "   " .. cat, func = function() NLC.Council.ChangeCategory(c.name, cat) end })
        end
        table.insert(items, { divider = true })
        table.insert(items, { text = "Omfordel award…", func = function()
          local session = NLC.Council.GetActiveSessions()[NLC.Council.GetWizardIndex()]
          if not session then return end
          local entry = { item = session.itemLink, itemId = session.itemId,
            awardedTo = c.name, category = c.category, timestamp = time() }
          NLC.UI.ShowEditPopup(entry, function(newRecipient, newCategory)
            NLC.History.ApplyAwardEdit(entry, newRecipient, newCategory)
          end)
        end })
        table.insert(items, { text = "Fjern fra listen", color = T.RED,
          func = function() NLC.Council.RemoveCandidate(c.name) end })
        table.insert(items, { divider = true })
        table.insert(items, { text = "Hvisk " .. c.name, func = function() NLC.Council.WhisperCandidate(c.name) end })
        table.insert(items, { text = "Kopier navn", func = function()
          local eb = ChatEdit_ChooseBoxForSend()
          ChatEdit_ActivateChat(eb)
          eb:SetText(c.name)
        end })
        T.ShowMenu(self, items)
      end)
    end

    -- Score or Roll (gold, prominent)
    local scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    scoreText:SetPoint("LEFT", COL.score, 0)
    local rollState = NLC.Council.GetRollState and NLC.Council.GetRollState() or { names = {}, results = {} }
    local inRoll = false
    for _, n in ipairs(rollState.names) do if n == c.name then inRoll = true; break end end
    if inRoll then
      local rollVal = rollState.results[c.name]
      -- Mark the current highest roll as the winner.
      local best, bestName = -1, nil
      for n, v in pairs(rollState.results) do if v > best then best, bestName = v, n end end
      local won = (c.name == bestName)
      scoreText:SetText((won and T.GREEN or T.GOLD_LIGHT) ..
        "Roll " .. (rollVal and tostring(rollVal) or "…") .. (won and " *" or "") .. "|r")
    elseif c.roll then
      scoreText:SetText(T.GOLD_LIGHT .. "Roll: " .. c.roll .. "|r")
    else
      scoreText:SetText(T.GOLD_LIGHT .. string.format("%.1f", c.score) .. "|r")
    end

    local scoreHover = CreateFrame("Frame", nil, row)
    scoreHover:SetSize(80, ROW_HEIGHT)
    scoreHover:SetPoint("LEFT", COL.score, 0)
    scoreHover:EnableMouse(true)
    scoreHover:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if c.roll then
        GameTooltip:AddLine("Tmog Roll", 1, 0.82, 0)
        GameTooltip:AddDoubleLine("Roll", tostring(c.roll), 0.6, 0.6, 0.6, 1, 1, 1)
      else
        GameTooltip:AddLine("Score Breakdown", 1, 0.82, 0)
        if c.breakdown then
          for _, line in ipairs(c.breakdown) do
            GameTooltip:AddDoubleLine(line.label or "", string.format("%.1f", line.value or 0), 0.6, 0.6, 0.6, 1, 1, 1)
          end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Total", string.format("%.1f", c.score or 0), 1, 0.82, 0, 0.2, 1, 0.2)
      end
      GameTooltip:Show()
    end)
    scoreHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ilvl diff
    local ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ilvlText:SetPoint("LEFT", COL.ilvl, 0)
    local diffColor = (c.ilvlDiff or 0) > 0 and T.GREEN or T.RED
    ilvlText:SetText(diffColor .. ((c.ilvlDiff or 0) > 0 and "+" or "") .. (c.ilvlDiff or 0) .. " ilvl|r")

    local ilvlHover = CreateFrame("Frame", nil, row)
    ilvlHover:SetSize(70, ROW_HEIGHT)
    ilvlHover:SetPoint("LEFT", COL.ilvl, 0)
    ilvlHover:EnableMouse(true)
    ilvlHover:SetScript("OnEnter", function(self)
      if c.equippedLink then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(c.equippedLink)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("This item", tostring(session.ilvl or "?"), 0.6, 0.6, 0.6, 1, 1, 1)
        local diff = c.ilvlDiff or 0
        local dr, dg = diff > 0 and 0.2 or 1, diff > 0 and 1 or 0.3
        GameTooltip:AddDoubleLine("Difference", (diff > 0 and "+" or "") .. diff, 0.6, 0.6, 0.6, dr, dg, 0.2)
        GameTooltip:Show()
      else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Item Level", 1, 0.82, 0)
        GameTooltip:AddDoubleLine("Equipped", tostring(c.equippedIlvl or "?"), 0.6, 0.6, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("This item", tostring(session.ilvl or "?"), 0.6, 0.6, 0.6, 1, 1, 1)
        local diff = c.ilvlDiff or 0
        local dr, dg = diff > 0 and 0.2 or 1, diff > 0 and 1 or 0.3
        GameTooltip:AddDoubleLine("Difference", (diff > 0 and "+" or "") .. diff, 0.6, 0.6, 0.6, dr, dg, 0.2)
        GameTooltip:Show()
      end
    end)
    ilvlHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Tier count
    local tierText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tierText:SetPoint("LEFT", COL.tier, 0)
    local tierColor = (c.tierCount == 1 or c.tierCount == 3) and T.GREEN or T.WHITE
    tierText:SetText(tierColor .. (c.tierCount or 0) .. "pc|r")

    local tierHover = CreateFrame("Frame", nil, row)
    tierHover:SetSize(50, ROW_HEIGHT)
    tierHover:SetPoint("LEFT", COL.tier, 0)
    tierHover:EnableMouse(true)
    tierHover:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Tier Pieces", 1, 0.82, 0)
      GameTooltip:AddLine(c.name .. " har " .. (c.tierCount or 0) .. " tier pieces equipped.", 1, 1, 1, true)
      if c.tierCount == 1 or c.tierCount == 3 then
        GameTooltip:AddLine("Neste tier-bonus ved " .. ((c.tierCount or 0) + 1) .. "pc!", 0.2, 1, 0.2)
      end
      GameTooltip:Show()
    end)
    tierHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Warnings
    if c.warnings and #c.warnings > 0 then
      local warnText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      warnText:SetPoint("LEFT", COL.info, 0)
      warnText:SetWidth(200)
      warnText:SetJustifyH("LEFT")
      warnText:SetText(T.ORANGE .. table.concat(c.warnings, "\n") .. "|r")
    end

    -- Award button (raid leader only) with confirmation dialog
    if NLC.isOfficer and NLC.IsLootLeader() then
      local awardBtn = T.CreateButton(row, 80, 30, "Tildel")
      awardBtn:SetPoint("RIGHT", COL.award, 0)
      awardBtn:SetScript("OnClick", function()
        local dialog = StaticPopup_Show("NORDLC_CONFIRM_AWARD", session.itemLink or "?", c.name)
        if dialog then
          dialog.data = { name = c.name }
        end
      end)
    end

    yOffset = yOffset + ROW_HEIGHT

    -- Note (if any)
    if c.note then
      local noteRow = CreateFrame("Frame", nil, rankFrame.scrollChild)
      noteRow:SetSize(FRAME_WIDTH - 50, NOTE_HEIGHT)
      noteRow:SetPoint("TOPLEFT", 0, -yOffset)
      noteRow:Show()
      local noteText = noteRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      noteText:SetPoint("LEFT", COL.name + 4, 0)
      noteText:SetText(T.MUTED .. ">> " .. c.note .. "|r")
      yOffset = yOffset + NOTE_HEIGHT
    end
  end

  rankFrame.scrollChild:SetHeight(yOffset + 40)
  rankFrame:Show()
end

function NLC.UI.ShowWizard(sessions, index)
  local session = sessions[index]
  if not session then return end

  local ranked = session.ranked or {}
  local total = #sessions

  -- Use existing ShowRanking to render the candidates
  NLC.UI.ShowRanking(session, ranked)

  -- Update title with progress
  rankFrame.title:SetText(T.GOLD .. "Loot Council|r  " .. T.MUTED .. "— Item " .. index .. " / " .. total .. "|r")

  -- Show item info below title
  if not rankFrame.itemInfo then
    rankFrame.itemInfo = rankFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankFrame.itemInfo:SetPoint("TOP", 0, -38)
  end
  rankFrame.itemInfo:SetText((session.itemLink or "?") .. "  " .. T.MUTED .. "ilvl " .. (session.ilvl or 0) .. "|r")
  rankFrame.itemInfo:Show()

  -- Navigation arrows
  if not rankFrame.prevBtn then
    rankFrame.prevBtn = T.CreateButton(rankFrame, 40, 34, "<")
    rankFrame.prevBtn:SetPoint("TOPLEFT", 20, -6)
  end
  if not rankFrame.nextBtn then
    rankFrame.nextBtn = T.CreateButton(rankFrame, 40, 34, ">")
    rankFrame.nextBtn:SetPoint("TOPRIGHT", -40, -6)
  end

  rankFrame.prevBtn:SetScript("OnClick", function()
    for i = index - 1, 1, -1 do
      if sessions[i].phase == "ranking" then
        NLC.Council.SetWizardIndex(i)
        return
      end
    end
  end)
  rankFrame.nextBtn:SetScript("OnClick", function()
    for i = index + 1, #sessions do
      if sessions[i].phase == "ranking" then
        NLC.Council.SetWizardIndex(i)
        return
      end
    end
  end)

  -- Enable/disable based on available items
  local hasPrev = false
  for i = index - 1, 1, -1 do
    if sessions[i].phase == "ranking" then hasPrev = true; break end
  end
  local hasNext = false
  for i = index + 1, #sessions do
    if sessions[i].phase == "ranking" then hasNext = true; break end
  end
  rankFrame.prevBtn:SetEnabled(hasPrev)
  rankFrame.nextBtn:SetEnabled(hasNext)
  rankFrame.prevBtn:Show()
  rankFrame.nextBtn:Show()

  -- "No interest" skip button if no candidates
  if #ranked == 0 then
    if not rankFrame.skipBtn then
      rankFrame.skipBtn = T.CreateButton(rankFrame, 200, 40, T.MUTED .. "Ingen interesse — Hopp over|r")
      rankFrame.skipBtn:SetPoint("CENTER", 0, 0)
    end
    rankFrame.skipBtn:SetScript("OnClick", function()
      NLC.Council.SkipCurrent()
    end)
    rankFrame.skipBtn:Show()
  elseif rankFrame.skipBtn then
    rankFrame.skipBtn:Hide()
  end

  -- Update Award Later button for wizard
  rankFrame.laterBtn:SetScript("OnClick", function()
    NLC.Council.AwardLaterCurrent()
  end)

  -- Avstemmingsknappen er lederens — samme gate som Award, ellers kunne to
  -- officers startet hver sin avstemming på samme item.
  if rankFrame.voteBtn then
    if NLC.IsLootLeader() and #ranked > 0 then
      rankFrame.voteBtn:Show()
    else
      rankFrame.voteBtn:Hide()
    end
  end

  -- Opptelling — kun for itemet det faktisk stemmes over.
  if not rankFrame.voteText then
    rankFrame.voteText = rankFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankFrame.voteText:SetPoint("BOTTOMLEFT", 20, 58)
    rankFrame.voteText:SetJustifyH("LEFT")
  end
  local tally = NLC.Council.GetVoteTally()
  local vs = NLC.Council.GetVoteState()
  if tally and vs.sessionIdx == session.sessionIdx then
    local lines = { T.GOLD .. "Officer-avstemming|r" }
    for _, row in ipairs(tally.rows) do
      table.insert(lines, string.format("  %s  %d  %s%s|r",
        row.name, row.count, T.MUTED, table.concat(row.voters, ", ")))
    end
    table.insert(lines, string.format("%s%d av %d officers har stemt|r",
      T.MUTED, tally.cast, tally.officers))
    rankFrame.voteText:SetText(table.concat(lines, "\n"))
    rankFrame.voteText:Show()
  else
    rankFrame.voteText:Hide()
  end
end

function NLC.UI.HideWizard()
  if rankFrame then
    rankFrame:Hide()
    if rankFrame.itemInfo then rankFrame.itemInfo:Hide() end
    if rankFrame.prevBtn then rankFrame.prevBtn:Hide() end
    if rankFrame.nextBtn then rankFrame.nextBtn:Hide() end
    if rankFrame.skipBtn then rankFrame.skipBtn:Hide() end
  end
end

-- True if the award wizard/ranking frame is currently visible.
function NLC.UI.IsWizardOpen()
  return rankFrame ~= nil and rankFrame:IsShown()
end

-- ============================================================
-- Officer-avstemming: stemmeseddel, stemmevindu og begrunnelse
-- ============================================================

-- Lederens stemmeseddel: alle kandidater er avkrysset som utgangspunkt, så man
-- fjerner de uaktuelle i stedet for å bygge lista fra bunnen midt i et raid.
local ballotFrame
function NLC.UI.ShowBallotBuilder(session)
  if not ballotFrame then
    ballotFrame = CreateFrame("Frame", "NordavindLCBallot", UIParent, "BackdropTemplate")
    ballotFrame:SetSize(340, 420)
    ballotFrame:SetPoint("CENTER")
    ballotFrame:SetFrameStrata("DIALOG")
    ballotFrame:SetMovable(true)
    ballotFrame:EnableMouse(true)
    ballotFrame:RegisterForDrag("LeftButton")
    ballotFrame:SetScript("OnDragStart", ballotFrame.StartMoving)
    ballotFrame:SetScript("OnDragStop", ballotFrame.StopMovingOrSizing)
    T.ApplyBackdrop(ballotFrame)
    T.CreateTitleBar(ballotFrame, "Officer-avstemming")
    ballotFrame.rows = {}
    ballotFrame.extra = {}
  end

  ballotFrame.session = session
  ballotFrame.checked = {}

  for _, r in ipairs(ballotFrame.rows) do
    r:Hide()
    if r.txt then r.txt:Hide() end
  end
  wipe(ballotFrame.rows)

  local y = -44
  local function addRow(name, label)
    local row = CreateFrame("CheckButton", nil, ballotFrame, "UICheckButtonTemplate")
    row:SetSize(24, 24)
    row:SetPoint("TOPLEFT", 16, y)
    row:SetChecked(true)
    ballotFrame.checked[name] = true
    row:SetScript("OnClick", function(self)
      ballotFrame.checked[name] = self:GetChecked() and true or nil
    end)
    local txt = ballotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("LEFT", row, "RIGHT", 6, 0)
    txt:SetText(label)
    -- Navnet lagres på raden. Å parse det ut av etiketten igjen ville brukket
    -- første gang noen får et mellomrom eller en fargekode i visningsteksten.
    row.playerName = name
    row.txt = txt
    table.insert(ballotFrame.rows, row)
    y = y - 28
  end

  for _, c in ipairs(session.ranked or {}) do
    addRow(c.name, string.format("%s  %s(%s, %.1fp)|r",
      c.name, T.MUTED, c.category or "?", c.score or 0))
  end
  for _, name in ipairs(ballotFrame.extra) do
    addRow(name, name .. "  " .. T.MUTED .. "(lagt til)|r")
  end

  if not ballotFrame.addBtn then
    ballotFrame.addInput = CreateFrame("EditBox", nil, ballotFrame, "InputBoxTemplate")
    ballotFrame.addInput:SetSize(140, 24)
    ballotFrame.addInput:SetPoint("BOTTOMRIGHT", -16, 56)
    ballotFrame.addInput:SetAutoFocus(false)

    ballotFrame.addBtn = T.CreateButton(ballotFrame, 150, 28, "+ Legg til spiller")
    ballotFrame.addBtn:SetPoint("BOTTOMLEFT", 16, 54)
    ballotFrame.addBtn:SetScript("OnClick", function()
      local n = ballotFrame.addInput:GetText():match("^%s*(.-)%s*$")
      if n and n ~= "" then
        table.insert(ballotFrame.extra, n)
        ballotFrame.addInput:SetText("")
        NLC.UI.ShowBallotBuilder(ballotFrame.session)
      end
    end)

    ballotFrame.startBtn = T.CreateButton(ballotFrame, 150, 30, "Start avstemming")
    ballotFrame.startBtn:SetPoint("BOTTOMLEFT", 16, 16)
    ballotFrame.startBtn:SetScript("OnClick", function()
      local ballot = {}
      for _, r in ipairs(ballotFrame.rows) do
        if ballotFrame.checked[r.playerName] then table.insert(ballot, r.playerName) end
      end
      NLC.Council.StartVote(ballotFrame.session.sessionIdx, ballot)
      wipe(ballotFrame.extra)
      ballotFrame:Hide()
    end)

    ballotFrame.cancelBtn = T.CreateButton(ballotFrame, 100, 30, "Avbryt")
    ballotFrame.cancelBtn:SetPoint("BOTTOMRIGHT", -16, 16)
    ballotFrame.cancelBtn:SetScript("OnClick", function()
      wipe(ballotFrame.extra)
      ballotFrame:Hide()
    end)
  end

  ballotFrame:Show()
end

-- Officers får dette når lederen starter. Ett klikk per navn; ny stemme
-- overskriver forrige, så feilklikk kan rettes uten å spørre lederen.
local votePopup
function NLC.UI.ShowVotePopup(sessionIdx, ballot)
  if not votePopup then
    votePopup = CreateFrame("Frame", "NordavindLCVote", UIParent, "BackdropTemplate")
    votePopup:SetSize(280, 360)
    votePopup:SetPoint("CENTER", 320, 0)
    votePopup:SetFrameStrata("DIALOG")
    votePopup:SetMovable(true)
    votePopup:EnableMouse(true)
    votePopup:RegisterForDrag("LeftButton")
    votePopup:SetScript("OnDragStart", votePopup.StartMoving)
    votePopup:SetScript("OnDragStop", votePopup.StopMovingOrSizing)
    T.ApplyBackdrop(votePopup)
    T.CreateTitleBar(votePopup, "Hvem skal ha itemet?")
    votePopup.btns = {}
  end

  for _, b in ipairs(votePopup.btns) do b:Hide() end
  wipe(votePopup.btns)

  local y = -44
  for _, name in ipairs(ballot or {}) do
    local b = T.CreateButton(votePopup, 240, 28, name)
    b:SetPoint("TOPLEFT", 20, y)
    b:SetScript("OnClick", function()
      NLC.Council.CastVote(sessionIdx, name)
      NLC.Utils.Print("Stemte på " .. name .. ".")
      votePopup:Hide()
    end)
    table.insert(votePopup.btns, b)
    y = y - 32
  end

  votePopup:Show()
end

-- Begrunnelsen er påkrevd: regelteksten lover at unntaket logges *med* grunn.
-- Uten den er "logges" bare en RW-melding som ruller vekk.
local reasonPopup
function NLC.UI.ShowReasonPopup(playerName, onConfirm)
  if not reasonPopup then
    reasonPopup = CreateFrame("Frame", "NordavindLCReason", UIParent, "BackdropTemplate")
    reasonPopup:SetSize(400, 170)
    reasonPopup:SetPoint("CENTER")
    reasonPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    reasonPopup:EnableMouse(true)
    T.ApplyBackdrop(reasonPopup)
    T.CreateTitleBar(reasonPopup, "Begrunnelse for unntaket")

    reasonPopup.label = reasonPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reasonPopup.label:SetPoint("TOPLEFT", 20, -44)

    reasonPopup.input = CreateFrame("EditBox", nil, reasonPopup, "InputBoxTemplate")
    reasonPopup.input:SetSize(356, 26)
    reasonPopup.input:SetPoint("TOPLEFT", 22, -72)
    reasonPopup.input:SetAutoFocus(true)

    reasonPopup.hint = reasonPopup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    reasonPopup.hint:SetPoint("TOPLEFT", 20, -102)
    reasonPopup.hint:SetText("Kort og konkret — dette havner i loot-historikken.")

    reasonPopup.okBtn = T.CreateButton(reasonPopup, 120, 30, "Tildel")
    reasonPopup.okBtn:SetPoint("BOTTOMRIGHT", -20, 16)
    reasonPopup.okBtn:SetScript("OnClick", function()
      local txt = reasonPopup.input:GetText():match("^%s*(.-)%s*$")
      if not txt or txt == "" then
        NLC.Utils.Print("Begrunnelse er påkrevd når itemet gis utenom lista.")
        return
      end
      reasonPopup:Hide()
      if reasonPopup.cb then reasonPopup.cb(txt) end
    end)

    reasonPopup.cancelBtn = T.CreateButton(reasonPopup, 100, 30, "Avbryt")
    reasonPopup.cancelBtn:SetPoint("BOTTOMLEFT", 20, 16)
    reasonPopup.cancelBtn:SetScript("OnClick", function() reasonPopup:Hide() end)
  end

  reasonPopup.label:SetText("Itemet gis til " .. T.GOLD .. playerName .. "|r utenom lista.")
  reasonPopup.input:SetText("")
  reasonPopup.cb = onConfirm
  reasonPopup:Show()
end
