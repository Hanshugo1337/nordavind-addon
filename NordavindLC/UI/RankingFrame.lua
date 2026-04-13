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
  rankFrame.laterBtn:SetShown(NLC.isOfficer and UnitIsGroupLeader("player"))

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

    -- Score or Roll (gold, prominent)
    local scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    scoreText:SetPoint("LEFT", COL.score, 0)
    if c.roll then
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
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Item Level", 1, 0.82, 0)
      GameTooltip:AddDoubleLine("Equipped", tostring(c.equippedIlvl or "?"), 0.6, 0.6, 0.6, 1, 1, 1)
      GameTooltip:AddDoubleLine("This item", tostring(session.ilvl or "?"), 0.6, 0.6, 0.6, 1, 1, 1)
      GameTooltip:AddDoubleLine("Difference", (c.ilvlDiff and c.ilvlDiff > 0 and "+" or "") .. tostring(c.ilvlDiff or 0), 0.6, 0.6, 0.6, c.ilvlDiff and c.ilvlDiff > 0 and 0.2 or 1, c.ilvlDiff and c.ilvlDiff > 0 and 1 or 0.3, c.ilvlDiff and c.ilvlDiff > 0 and 0.2 or 0.3)
      GameTooltip:Show()
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
    if NLC.isOfficer and UnitIsGroupLeader("player") then
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
