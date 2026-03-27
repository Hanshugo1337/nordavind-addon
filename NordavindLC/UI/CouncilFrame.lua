-- UI/CouncilFrame.lua
-- Interest popup (all raiders) + loot detected panel (officer)

local _, NLC = ...

local interestFrame = nil

function NLC.UI.ShowInterestPopup(itemLink, ilvl, equipLoc, timer)
  if not interestFrame then
    interestFrame = CreateFrame("Frame", "NordavindLCInterest", UIParent, "BasicFrameTemplateWithInset")
    interestFrame:SetSize(300, 220)
    interestFrame:SetPoint("CENTER", 0, 100)
    interestFrame:SetMovable(true)
    interestFrame:EnableMouse(true)
    interestFrame:RegisterForDrag("LeftButton")
    interestFrame:SetScript("OnDragStart", interestFrame.StartMoving)
    interestFrame:SetScript("OnDragStop", interestFrame.StopMovingOrSizing)
    interestFrame:SetFrameStrata("DIALOG")
    interestFrame.TitleBg:SetHeight(24)
    interestFrame.title = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    interestFrame.title:SetPoint("TOP", 0, -6)

    interestFrame.itemText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    interestFrame.itemText:SetPoint("TOP", 0, -35)

    interestFrame.equippedText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    interestFrame.equippedText:SetPoint("TOP", 0, -55)

    interestFrame.timerText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    interestFrame.timerText:SetPoint("TOP", 0, -75)

    local categories = {
      { id = "upgrade",  label = "Upgrade" },
      { id = "catalyst", label = "Catalyst" },
      { id = "offspec",  label = "Offspec" },
      { id = "tmog",     label = "Tmog" },
    }

    interestFrame.buttons = {}
    for i, cat in ipairs(categories) do
      local btn = CreateFrame("Button", nil, interestFrame, "GameMenuButtonTemplate")
      btn:SetSize(120, 26)
      btn:SetPoint("TOPLEFT", 20 + ((i - 1) % 2) * 135, -95 - math.floor((i - 1) / 2) * 32)
      btn:SetText(cat.label)
      btn:SetScript("OnClick", function()
        local session = NLC.Council.GetActiveSession()
        local itemId = session and session.itemId or 0
        NLC.Council.SendInterest(itemId, cat.id)
        interestFrame:Hide()
        NLC.Utils.Print("Interesse: " .. cat.label)
      end)
      interestFrame.buttons[cat.id] = btn
    end

    local passBtn = CreateFrame("Button", nil, interestFrame, "GameMenuButtonTemplate")
    passBtn:SetSize(260, 26)
    passBtn:SetPoint("BOTTOM", 0, 15)
    passBtn:SetText("Pass")
    passBtn:SetScript("OnClick", function()
      interestFrame:Hide()
    end)
  end

  interestFrame.title:SetText("Loot Council")
  interestFrame.itemText:SetText((itemLink or "?") .. " (ilvl " .. (ilvl or 0) .. ")")

  local eqLink, eqIlvl = NLC.Utils.GetEquippedInfo(equipLoc or "")
  if eqLink then
    local diff = (ilvl or 0) - eqIlvl
    local diffColor = diff > 0 and "|cff00ff00+" or "|cffff0000"
    interestFrame.equippedText:SetText("Equipped: " .. eqLink .. " (" .. eqIlvl .. ") " .. diffColor .. diff .. "|r")
  else
    interestFrame.equippedText:SetText("Ingen item i slot")
  end

  interestFrame.timerText:SetText((timer or 30) .. "s igjen")
  interestFrame:Show()

  local remaining = timer or 30
  C_Timer.NewTicker(1, function(ticker)
    remaining = remaining - 1
    if remaining <= 0 or not interestFrame:IsShown() then
      ticker:Cancel()
      if interestFrame:IsShown() then interestFrame:Hide() end
      return
    end
    if interestFrame.timerText then
      interestFrame.timerText:SetText(remaining .. "s igjen")
    end
  end, timer or 30)
end

-- Loot Detected Panel (officer only)
local lootPanel = nil

function NLC.UI.ShowLootDetected(items)
  if not NLC.isOfficer then return end

  if not lootPanel then
    lootPanel = CreateFrame("Frame", "NordavindLCLootPanel", UIParent, "BasicFrameTemplateWithInset")
    lootPanel:SetSize(350, 60)
    lootPanel:SetPoint("TOP", 0, -50)
    lootPanel:SetMovable(true)
    lootPanel:EnableMouse(true)
    lootPanel:RegisterForDrag("LeftButton")
    lootPanel:SetScript("OnDragStart", lootPanel.StartMoving)
    lootPanel:SetScript("OnDragStop", lootPanel.StopMovingOrSizing)
    lootPanel:SetFrameStrata("HIGH")
    lootPanel.TitleBg:SetHeight(24)
    lootPanel.title = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lootPanel.title:SetPoint("TOP", 0, -6)
    lootPanel.title:SetText("Loot Detected")
    lootPanel.content = CreateFrame("Frame", nil, lootPanel)
    lootPanel.content:SetPoint("TOPLEFT", 10, -30)
    lootPanel.content:SetPoint("BOTTOMRIGHT", -10, 5)
  end

  for _, child in ipairs({ lootPanel.content:GetChildren() }) do
    child:Hide()
  end

  lootPanel:SetHeight(40 + #items * 30)

  for i, item in ipairs(items) do
    local row = CreateFrame("Button", nil, lootPanel.content)
    row:SetSize(320, 26)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 30)
    row:SetHighlightTexture("Interface/Buttons/UI-Listbox-Highlight")

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 5, 0)
    text:SetText((item.itemLink or "?") .. " (ilvl " .. (item.ilvl or 0) .. ")")

    local btn = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
    btn:SetSize(80, 22)
    btn:SetPoint("RIGHT", -5, 0)
    btn:SetText("Council")
    btn:SetScript("OnClick", function()
      NLC.Council.StartSession(item.itemLink, item.itemId, item.ilvl, item.equipLoc, item.boss)
      lootPanel:Hide()
    end)
  end

  lootPanel:Show()
end

function NLC.UI.UpdateCouncilInterests(session)
  local count = 0
  for _ in pairs(session.interests) do count = count + 1 end
  NLC.Utils.Print(count .. " interesse(r) mottatt")
end
