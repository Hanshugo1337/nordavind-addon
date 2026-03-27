-- UI/RankingFrame.lua
-- Ranked candidate list with award buttons (officer) and display (all)

local _, NLC = ...

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
    rankFrame:SetSize(500, 400)
    rankFrame:SetPoint("CENTER")
    rankFrame:SetMovable(true)
    rankFrame:EnableMouse(true)
    rankFrame:RegisterForDrag("LeftButton")
    rankFrame:SetScript("OnDragStart", rankFrame.StartMoving)
    rankFrame:SetScript("OnDragStop", rankFrame.StopMovingOrSizing)
    rankFrame:SetFrameStrata("DIALOG")
    rankFrame.TitleBg:SetHeight(24)
    rankFrame.title = rankFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rankFrame.title:SetPoint("TOP", 0, -6)

    rankFrame.scrollFrame = CreateFrame("ScrollFrame", nil, rankFrame, "UIPanelScrollFrameTemplate")
    rankFrame.scrollFrame:SetPoint("TOPLEFT", 10, -30)
    rankFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -30, 45)

    rankFrame.scrollChild = CreateFrame("Frame")
    rankFrame.scrollFrame:SetScrollChild(rankFrame.scrollChild)
    rankFrame.scrollChild:SetSize(440, 1)

    rankFrame.laterBtn = CreateFrame("Button", nil, rankFrame, "GameMenuButtonTemplate")
    rankFrame.laterBtn:SetSize(120, 26)
    rankFrame.laterBtn:SetPoint("BOTTOMLEFT", 15, 12)
    rankFrame.laterBtn:SetText("Award Later")
    rankFrame.laterBtn:SetScript("OnClick", function()
      NLC.Council.AwardLater()
      rankFrame:Hide()
    end)

    rankFrame.closeBtn = CreateFrame("Button", nil, rankFrame, "GameMenuButtonTemplate")
    rankFrame.closeBtn:SetSize(80, 26)
    rankFrame.closeBtn:SetPoint("BOTTOMRIGHT", -15, 12)
    rankFrame.closeBtn:SetText("Lukk")
    rankFrame.closeBtn:SetScript("OnClick", function()
      rankFrame:Hide()
    end)
  end

  rankFrame.title:SetText("Loot Council — " .. (session.itemLink or "?"))
  rankFrame.laterBtn:SetShown(NLC.isOfficer)

  -- Clear previous rows
  for _, child in ipairs({ rankFrame.scrollChild:GetChildren() }) do
    child:Hide()
  end

  local yOffset = 0
  local currentCat = nil

  for i, c in ipairs(candidates) do
    if c.category ~= currentCat then
      currentCat = c.category
      local header = rankFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      header:SetPoint("TOPLEFT", 5, -yOffset)
      header:SetText(CATEGORY_LABELS[currentCat] or currentCat)
      header:Show()
      yOffset = yOffset + 20
    end

    local row = CreateFrame("Frame", nil, rankFrame.scrollChild)
    row:SetSize(440, 28)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:Show()

    -- Rank badge
    local rc = RANK_COLORS[c.rank] or RANK_COLORS.trial
    local rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankText:SetPoint("LEFT", 5, 0)
    rankText:SetText(string.format("|cff%02x%02x%02x%s|r", rc.r * 255, rc.g * 255, rc.b * 255, (c.rank or "?"):upper()))

    -- Name (class colored)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", 60, 0)
    nameText:SetText(NLC.Utils.ClassColoredName(c.name, c.class))

    -- Score
    local scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scoreText:SetPoint("LEFT", 180, 0)
    scoreText:SetText(string.format("%.1f", c.score))

    -- ilvl diff
    local ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlText:SetPoint("LEFT", 230, 0)
    local diffColor = (c.ilvlDiff or 0) > 0 and "|cff00ff00+" or "|cffff0000"
    ilvlText:SetText(diffColor .. (c.ilvlDiff or 0) .. " ilvl|r")

    -- Tier
    local tierText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tierText:SetPoint("LEFT", 290, 0)
    local tierColor = (c.tierCount == 1 or c.tierCount == 3) and "|cff00ff00" or "|cffffffff"
    tierText:SetText(tierColor .. (c.tierCount or 0) .. "pc|r")

    -- Warnings
    if c.warnings and #c.warnings > 0 then
      local warnText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      warnText:SetPoint("LEFT", 330, 0)
      warnText:SetText("|cffff8800" .. table.concat(c.warnings, " | ") .. "|r")
    end

    -- Award button (officer only)
    if NLC.isOfficer then
      local awardBtn = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
      awardBtn:SetSize(60, 22)
      awardBtn:SetPoint("RIGHT", -5, 0)
      awardBtn:SetText("Tildel")
      awardBtn:SetScript("OnClick", function()
        NLC.Council.Award(c.name)
        rankFrame:Hide()
      end)
    end

    yOffset = yOffset + 30
  end

  rankFrame.scrollChild:SetHeight(yOffset + 20)
  rankFrame:Show()
end
