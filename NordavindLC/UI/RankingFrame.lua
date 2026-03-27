-- UI/RankingFrame.lua
-- Ranked candidate list with award buttons (officer) and display (all)

local NLC = NordavindLC_NS

local rankFrame = nil
local RANK_COLORS = {
  raider = { r = 0.2, g = 0.8, b = 0.2 },
  backup = { r = 0.9, g = 0.7, b = 0.2 },
  trial  = { r = 0.9, g = 0.5, b = 0.2 },
}

local CATEGORY_LABELS = {
  upgrade = "|cff33cc33Upgrade|r",
  catalyst = "|cff9933ffCatalyst|r",
  offspec = "|cff3399ffOffspec|r",
  tmog = "|cffffff66Tmog|r",
}

function NLC.UI.ShowRanking(session, candidates)
  if not rankFrame then
    rankFrame = CreateFrame("Frame", "NordavindLCRanking", UIParent, "BasicFrameTemplateWithInset")
    rankFrame:SetSize(620, 500)
    rankFrame:SetPoint("CENTER")
    rankFrame:SetMovable(true)
    rankFrame:EnableMouse(true)
    rankFrame:RegisterForDrag("LeftButton")
    rankFrame:SetScript("OnDragStart", rankFrame.StartMoving)
    rankFrame:SetScript("OnDragStop", rankFrame.StopMovingOrSizing)
    rankFrame:SetFrameStrata("DIALOG")
    rankFrame.TitleBg:SetHeight(30)
    rankFrame.title = rankFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    rankFrame.title:SetPoint("TOP", 0, -8)

    rankFrame.scrollFrame = CreateFrame("ScrollFrame", nil, rankFrame, "UIPanelScrollFrameTemplate")
    rankFrame.scrollFrame:SetPoint("TOPLEFT", 15, -40)
    rankFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -35, 55)

    rankFrame.scrollChild = CreateFrame("Frame")
    rankFrame.scrollFrame:SetScrollChild(rankFrame.scrollChild)
    rankFrame.scrollChild:SetSize(550, 1)

    -- Column headers
    local headerFrame = CreateFrame("Frame", nil, rankFrame)
    headerFrame:SetSize(550, 20)
    headerFrame:SetPoint("TOPLEFT", rankFrame.scrollFrame, "TOPLEFT", 0, 18)

    local headers = {
      { text = "Rank",  x = 5 },
      { text = "Navn",  x = 70 },
      { text = "Score", x = 210 },
      { text = "ilvl",  x = 270 },
      { text = "Tier",  x = 340 },
      { text = "Info",  x = 400 },
    }
    for _, h in ipairs(headers) do
      local ht = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      ht:SetPoint("LEFT", h.x, 0)
      ht:SetText("|cff888888" .. h.text .. "|r")
    end

    rankFrame.laterBtn = CreateFrame("Button", nil, rankFrame, "GameMenuButtonTemplate")
    rankFrame.laterBtn:SetSize(140, 30)
    rankFrame.laterBtn:SetPoint("BOTTOMLEFT", 20, 15)
    rankFrame.laterBtn:SetText("Award Later")
    rankFrame.laterBtn:SetScript("OnClick", function()
      NLC.Council.AwardLater()
      rankFrame:Hide()
    end)

    rankFrame.closeBtn = CreateFrame("Button", nil, rankFrame, "GameMenuButtonTemplate")
    rankFrame.closeBtn:SetSize(100, 30)
    rankFrame.closeBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    rankFrame.closeBtn:SetText("Lukk")
    rankFrame.closeBtn:SetScript("OnClick", function()
      rankFrame:Hide()
    end)
  end

  rankFrame.title:SetText("Loot Council  —  " .. (session.itemLink or "?"))
  rankFrame.laterBtn:SetShown(NLC.isOfficer)

  -- Clear previous rows
  for _, child in ipairs({ rankFrame.scrollChild:GetChildren() }) do
    child:Hide()
  end

  local yOffset = 0
  local currentCat = nil

  for i, c in ipairs(candidates) do
    -- Category header
    if c.category ~= currentCat then
      currentCat = c.category
      if yOffset > 0 then yOffset = yOffset + 8 end -- extra gap between categories
      local header = rankFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      header:SetPoint("TOPLEFT", 5, -yOffset)
      header:SetText(CATEGORY_LABELS[currentCat] or currentCat)
      header:Show()
      yOffset = yOffset + 24

      -- Separator under header
      local sep = rankFrame.scrollChild:CreateTexture(nil, "ARTWORK")
      sep:SetHeight(1)
      sep:SetPoint("TOPLEFT", 5, -yOffset)
      sep:SetWidth(540)
      sep:SetColorTexture(0.3, 0.3, 0.3, 0.6)
      sep:Show()
      yOffset = yOffset + 6
    end

    -- Alternating row background
    local rowBg = rankFrame.scrollChild:CreateTexture(nil, "BACKGROUND")
    rowBg:SetPoint("TOPLEFT", 0, -yOffset)
    rowBg:SetSize(550, 34)
    if i % 2 == 0 then
      rowBg:SetColorTexture(1, 1, 1, 0.03)
    else
      rowBg:SetColorTexture(0, 0, 0, 0)
    end
    rowBg:Show()

    local row = CreateFrame("Frame", nil, rankFrame.scrollChild)
    row:SetSize(550, 34)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:Show()

    -- Rank badge
    local rc = RANK_COLORS[c.rank] or RANK_COLORS.trial
    local rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankText:SetPoint("LEFT", 8, 0)
    rankText:SetText(string.format("|cff%02x%02x%02x%s|r", rc.r * 255, rc.g * 255, rc.b * 255, (c.rank or "?"):upper()))

    -- Name (class colored)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", 70, 0)
    nameText:SetText(NLC.Utils.ClassColoredName(c.name, c.class))

    -- Score (bigger, highlighted)
    local scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    scoreText:SetPoint("LEFT", 210, 0)
    scoreText:SetText(string.format("|cffffff00%.1f|r", c.score))

    -- ilvl diff
    local ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ilvlText:SetPoint("LEFT", 270, 0)
    local diffColor = (c.ilvlDiff or 0) > 0 and "|cff00ff00+" or "|cffff0000"
    ilvlText:SetText(diffColor .. (c.ilvlDiff or 0) .. " ilvl|r")

    -- Tier
    local tierText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tierText:SetPoint("LEFT", 340, 0)
    local tierColor = (c.tierCount == 1 or c.tierCount == 3) and "|cff00ff00" or "|cffffffff"
    tierText:SetText(tierColor .. (c.tierCount or 0) .. "pc|r")

    -- Warnings
    if c.warnings and #c.warnings > 0 then
      local warnText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      warnText:SetPoint("LEFT", 400, 0)
      warnText:SetWidth(80)
      warnText:SetJustifyH("LEFT")
      warnText:SetText("|cffff8800" .. table.concat(c.warnings, " ") .. "|r")
    end

    -- Award button (officer only)
    if NLC.isOfficer then
      local awardBtn = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
      awardBtn:SetSize(70, 26)
      awardBtn:SetPoint("RIGHT", -8, 0)
      awardBtn:SetText("Tildel")
      awardBtn:SetScript("OnClick", function()
        NLC.Council.Award(c.name)
        rankFrame:Hide()
      end)
    end

    yOffset = yOffset + 36

    -- Note (shown below the row if present)
    if c.note then
      local noteRow = CreateFrame("Frame", nil, rankFrame.scrollChild)
      noteRow:SetSize(550, 18)
      noteRow:SetPoint("TOPLEFT", 0, -yOffset)
      noteRow:Show()
      local noteText = noteRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      noteText:SetPoint("LEFT", 75, 0)
      noteText:SetText("|cffaaaaaa>> " .. c.note .. "|r")
      yOffset = yOffset + 20
    end
  end

  rankFrame.scrollChild:SetHeight(yOffset + 30)
  rankFrame:Show()
end
