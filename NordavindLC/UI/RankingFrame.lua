-- UI/RankingFrame.lua
-- Ranked candidate list with award buttons (officer) and display (all)

local NLC = NordavindLC_NS
local T = NLC.Theme

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

function NLC.UI.ShowRanking(session, candidates)
  if not rankFrame then
    rankFrame = CreateFrame("Frame", "NordavindLCRanking", UIParent, "BackdropTemplate")
    rankFrame:SetSize(640, 520)
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

    -- Column headers
    local hdrY = -40
    local headers = {
      { text = "RANK",  x = 10 },
      { text = "NAVN",  x = 78 },
      { text = "SCORE", x = 220 },
      { text = "ILVL",  x = 290 },
      { text = "TIER",  x = 360 },
      { text = "INFO",  x = 420 },
    }
    for _, h in ipairs(headers) do
      local ht = rankFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      ht:SetPoint("TOPLEFT", h.x, hdrY)
      ht:SetText(T.GOLD_DIM .. h.text .. "|r")
    end

    -- Header separator
    local hdrSep = rankFrame:CreateTexture(nil, "ARTWORK")
    hdrSep:SetPoint("TOPLEFT", 10, hdrY - 14)
    hdrSep:SetPoint("TOPRIGHT", -30, hdrY - 14)
    hdrSep:SetHeight(1)
    hdrSep:SetColorTexture(0.788, 0.659, 0.298, 0.25)

    rankFrame.scrollFrame = CreateFrame("ScrollFrame", nil, rankFrame, "UIPanelScrollFrameTemplate")
    rankFrame.scrollFrame:SetPoint("TOPLEFT", 10, hdrY - 18)
    rankFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -32, 58)

    rankFrame.scrollChild = CreateFrame("Frame")
    rankFrame.scrollFrame:SetScrollChild(rankFrame.scrollChild)
    rankFrame.scrollChild:SetSize(570, 1)

    rankFrame.laterBtn = CreateFrame("Button", nil, rankFrame, "UIPanelButtonTemplate")
    rankFrame.laterBtn:SetSize(150, 32)
    rankFrame.laterBtn:SetPoint("BOTTOMLEFT", 20, 18)
    rankFrame.laterBtn:SetText("Award Later")
    rankFrame.laterBtn:SetScript("OnClick", function()
      NLC.Council.AwardLater()
      rankFrame:Hide()
    end)

    rankFrame.closeBtn = CreateFrame("Button", nil, rankFrame, "UIPanelButtonTemplate")
    rankFrame.closeBtn:SetSize(110, 32)
    rankFrame.closeBtn:SetPoint("BOTTOMRIGHT", -20, 18)
    rankFrame.closeBtn:SetText("Lukk")
    rankFrame.closeBtn:SetScript("OnClick", function()
      rankFrame:Hide()
    end)
  end

  rankFrame.title:SetText(T.GOLD .. "Loot Council|r  " .. T.MUTED .. "—|r  " .. (session.itemLink or "?"))
  rankFrame.laterBtn:SetShown(NLC.isOfficer)

  -- Clear previous rows
  for _, child in ipairs({ rankFrame.scrollChild:GetChildren() }) do
    child:Hide()
  end
  -- Also hide fontstrings/textures from previous render
  for _, region in ipairs({ rankFrame.scrollChild:GetRegions() }) do
    region:Hide()
  end

  local yOffset = 0
  local currentCat = nil

  for i, c in ipairs(candidates) do
    -- Category header
    if c.category ~= currentCat then
      currentCat = c.category
      if yOffset > 0 then yOffset = yOffset + 12 end

      local header = rankFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      header:SetPoint("TOPLEFT", 8, -yOffset)
      header:SetText(CATEGORY_LABELS[currentCat] or currentCat)
      header:Show()
      yOffset = yOffset + 22

      local sep = rankFrame.scrollChild:CreateTexture(nil, "ARTWORK")
      sep:SetPoint("TOPLEFT", 8, -yOffset)
      sep:SetWidth(555)
      sep:SetHeight(1)
      sep:SetColorTexture(0.3, 0.3, 0.3, 0.4)
      sep:Show()
      yOffset = yOffset + 8
    end

    -- Alternating row bg
    local rowBg = rankFrame.scrollChild:CreateTexture(nil, "BACKGROUND")
    rowBg:SetPoint("TOPLEFT", 0, -yOffset)
    rowBg:SetSize(570, 36)
    rowBg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
    rowBg:Show()

    local row = CreateFrame("Frame", nil, rankFrame.scrollChild)
    row:SetSize(570, 36)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:Show()

    -- Rank badge
    local rc = RANK_COLORS[c.rank] or RANK_COLORS.trial
    local rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankText:SetPoint("LEFT", 10, 0)
    rankText:SetText(string.format("|cff%02x%02x%02x%s|r", rc.r * 255, rc.g * 255, rc.b * 255, (c.rank or "?"):upper()))

    -- Name (class colored)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", 78, 0)
    nameText:SetText(NLC.Utils.ClassColoredName(c.name, c.class))

    -- Score (gold, prominent)
    local scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    scoreText:SetPoint("LEFT", 220, 0)
    scoreText:SetText(T.GOLD_LIGHT .. string.format("%.1f", c.score) .. "|r")

    -- ilvl diff
    local ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ilvlText:SetPoint("LEFT", 290, 0)
    local diffColor = (c.ilvlDiff or 0) > 0 and T.GREEN or T.RED
    ilvlText:SetText(diffColor .. ((c.ilvlDiff or 0) > 0 and "+" or "") .. (c.ilvlDiff or 0) .. " ilvl|r")

    -- Tier
    local tierText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tierText:SetPoint("LEFT", 360, 0)
    local tierColor = (c.tierCount == 1 or c.tierCount == 3) and T.GREEN or T.WHITE
    tierText:SetText(tierColor .. (c.tierCount or 0) .. "pc|r")

    -- Warnings
    if c.warnings and #c.warnings > 0 then
      local warnText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      warnText:SetPoint("LEFT", 420, 0)
      warnText:SetWidth(80)
      warnText:SetJustifyH("LEFT")
      warnText:SetText(T.ORANGE .. table.concat(c.warnings, " ") .. "|r")
    end

    -- Award button (officer only)
    if NLC.isOfficer then
      local awardBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      awardBtn:SetSize(75, 28)
      awardBtn:SetPoint("RIGHT", -8, 0)
      awardBtn:SetText("Tildel")
      awardBtn:SetScript("OnClick", function()
        NLC.Council.Award(c.name)
        rankFrame:Hide()
      end)
    end

    yOffset = yOffset + 38

    -- Note
    if c.note then
      local noteRow = CreateFrame("Frame", nil, rankFrame.scrollChild)
      noteRow:SetSize(570, 18)
      noteRow:SetPoint("TOPLEFT", 0, -yOffset)
      noteRow:Show()
      local noteText = noteRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      noteText:SetPoint("LEFT", 83, 0)
      noteText:SetText(T.MUTED .. ">> " .. c.note .. "|r")
      yOffset = yOffset + 20
    end
  end

  rankFrame.scrollChild:SetHeight(yOffset + 30)
  rankFrame:Show()
end
