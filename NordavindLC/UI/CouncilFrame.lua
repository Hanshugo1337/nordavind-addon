-- UI/CouncilFrame.lua
-- Interest popup (all raiders) + loot detected panel (officer)

local NLC = NordavindLC_NS

local interestFrame = nil

function NLC.UI.ShowInterestPopup(itemLink, ilvl, equipLoc, timer)
  if not interestFrame then
    interestFrame = CreateFrame("Frame", "NordavindLCInterest", UIParent, "BasicFrameTemplateWithInset")
    interestFrame:SetSize(380, 310)
    interestFrame:SetPoint("CENTER", 0, 100)
    interestFrame:SetMovable(true)
    interestFrame:EnableMouse(true)
    interestFrame:RegisterForDrag("LeftButton")
    interestFrame:SetScript("OnDragStart", interestFrame.StartMoving)
    interestFrame:SetScript("OnDragStop", interestFrame.StopMovingOrSizing)
    interestFrame:SetFrameStrata("DIALOG")
    interestFrame.TitleBg:SetHeight(30)
    interestFrame.title = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    interestFrame.title:SetPoint("TOP", 0, -8)

    -- Item name (large)
    interestFrame.itemText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    interestFrame.itemText:SetPoint("TOP", 0, -42)
    interestFrame.itemText:SetWidth(340)
    interestFrame.itemText:SetJustifyH("CENTER")

    -- Equipped comparison
    interestFrame.equippedText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    interestFrame.equippedText:SetPoint("TOP", 0, -65)
    interestFrame.equippedText:SetWidth(340)
    interestFrame.equippedText:SetJustifyH("CENTER")

    -- Separator line
    local sep = interestFrame:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 20, -88)
    sep:SetPoint("TOPRIGHT", -20, -88)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.5)

    -- Timer
    interestFrame.timerText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    interestFrame.timerText:SetPoint("TOP", 0, -98)

    -- Note input (hidden by default, shown when Upgrade is clicked)
    interestFrame.noteBox = CreateFrame("EditBox", nil, interestFrame, "InputBoxTemplate")
    interestFrame.noteBox:SetSize(300, 26)
    interestFrame.noteBox:SetPoint("TOP", 0, -125)
    interestFrame.noteBox:SetAutoFocus(false)
    interestFrame.noteBox:SetMaxLetters(60)
    interestFrame.noteBox:Hide()

    interestFrame.noteLabel = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    interestFrame.noteLabel:SetPoint("BOTTOM", interestFrame.noteBox, "TOP", 0, 4)
    interestFrame.noteLabel:SetText("|cffaaaaaaNote (valgfritt):|r")
    interestFrame.noteLabel:Hide()

    interestFrame.noteSendBtn = CreateFrame("Button", nil, interestFrame, "GameMenuButtonTemplate")
    interestFrame.noteSendBtn:SetSize(300, 32)
    interestFrame.noteSendBtn:SetPoint("TOP", interestFrame.noteBox, "BOTTOM", 0, -8)
    interestFrame.noteSendBtn:SetText("Send Upgrade")
    interestFrame.noteSendBtn:Hide()
    interestFrame.noteSendBtn:SetScript("OnClick", function()
      local session = NLC.Council.GetActiveSession()
      local itemId = session and session.itemId or 0
      local note = interestFrame.noteBox:GetText():trim()
      NLC.Council.SendInterest(itemId, "upgrade", note ~= "" and note or nil)
      interestFrame:Hide()
      NLC.Utils.Print("Interesse: Upgrade" .. (note ~= "" and (" — " .. note) or ""))
    end)

    interestFrame.noteBox:SetScript("OnEnterPressed", function()
      interestFrame.noteSendBtn:GetScript("OnClick")()
    end)

    -- Category buttons
    interestFrame.buttons = {}

    -- Upgrade (full width, prominent)
    local upgradeBtn = CreateFrame("Button", nil, interestFrame, "GameMenuButtonTemplate")
    upgradeBtn:SetSize(340, 36)
    upgradeBtn:SetPoint("TOP", 0, -120)
    upgradeBtn:SetText("Upgrade")
    upgradeBtn:SetNormalFontObject("GameFontHighlightLarge")
    upgradeBtn:SetScript("OnClick", function()
      -- Show note input, hide category buttons
      upgradeBtn:Hide()
      interestFrame.buttons["catalyst"]:Hide()
      interestFrame.buttons["offspec"]:Hide()
      interestFrame.buttons["tmog"]:Hide()
      interestFrame.passBtn:Hide()
      interestFrame.noteLabel:Show()
      interestFrame.noteBox:Show()
      interestFrame.noteBox:SetText("")
      interestFrame.noteBox:SetFocus()
      interestFrame.noteSendBtn:Show()
    end)
    interestFrame.buttons["upgrade"] = upgradeBtn

    -- Second row: Catalyst, Offspec, Tmog
    local secondRow = {
      { id = "catalyst", label = "Catalyst" },
      { id = "offspec",  label = "Offspec" },
      { id = "tmog",     label = "Tmog" },
    }
    for i, cat in ipairs(secondRow) do
      local btn = CreateFrame("Button", nil, interestFrame, "GameMenuButtonTemplate")
      btn:SetSize(108, 32)
      btn:SetPoint("TOPLEFT", 20 + (i - 1) * 114, -168)
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

    -- Pass (full width, bottom)
    local passBtn = CreateFrame("Button", nil, interestFrame, "GameMenuButtonTemplate")
    passBtn:SetSize(340, 32)
    passBtn:SetPoint("BOTTOM", 0, 20)
    passBtn:SetText("Pass")
    passBtn:SetScript("OnClick", function()
      interestFrame:Hide()
    end)
    interestFrame.passBtn = passBtn
  end

  interestFrame.title:SetText("Loot Council")
  interestFrame.itemText:SetText((itemLink or "?") .. "  |cffaaaaaa(ilvl " .. (ilvl or 0) .. ")|r")

  local eqLink, eqIlvl = NLC.Utils.GetEquippedInfo(equipLoc or "")
  if eqLink then
    local diff = (ilvl or 0) - eqIlvl
    local diffColor = diff > 0 and "|cff00ff00+" or "|cffff0000"
    interestFrame.equippedText:SetText("Equipped: " .. eqLink .. "  |cffaaaaaa(" .. eqIlvl .. ")|r  " .. diffColor .. diff .. " ilvl|r")
  else
    interestFrame.equippedText:SetText("|cff888888Ingen item i slot|r")
  end

  -- Reset to button view (hide note input)
  interestFrame.noteLabel:Hide()
  interestFrame.noteBox:Hide()
  interestFrame.noteBox:SetText("")
  interestFrame.noteSendBtn:Hide()
  interestFrame.buttons["upgrade"]:Show()
  interestFrame.buttons["catalyst"]:Show()
  interestFrame.buttons["offspec"]:Show()
  interestFrame.buttons["tmog"]:Show()
  interestFrame.passBtn:Show()

  interestFrame.timerText:SetText("|cffffff00" .. (timer or 30) .. "s|r igjen")
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
      local color = remaining <= 5 and "|cffff3333" or remaining <= 10 and "|cffff8800" or "|cffffff00"
      interestFrame.timerText:SetText(color .. remaining .. "s|r igjen")
    end
  end, timer or 30)
end

-- Loot Detected Panel (officer only)
local lootPanel = nil

function NLC.UI.ShowLootDetected(items)
  if not NLC.isOfficer then return end

  if not lootPanel then
    lootPanel = CreateFrame("Frame", "NordavindLCLootPanel", UIParent, "BasicFrameTemplateWithInset")
    lootPanel:SetSize(420, 60)
    lootPanel:SetPoint("TOP", 0, -50)
    lootPanel:SetMovable(true)
    lootPanel:EnableMouse(true)
    lootPanel:RegisterForDrag("LeftButton")
    lootPanel:SetScript("OnDragStart", lootPanel.StartMoving)
    lootPanel:SetScript("OnDragStop", lootPanel.StopMovingOrSizing)
    lootPanel:SetFrameStrata("HIGH")
    lootPanel.TitleBg:SetHeight(30)
    lootPanel.title = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    lootPanel.title:SetPoint("TOP", 0, -8)
    lootPanel.title:SetText("Loot Detected")
    lootPanel.content = CreateFrame("Frame", nil, lootPanel)
    lootPanel.content:SetPoint("TOPLEFT", 15, -38)
    lootPanel.content:SetPoint("BOTTOMRIGHT", -15, 10)
  end

  for _, child in ipairs({ lootPanel.content:GetChildren() }) do
    child:Hide()
  end

  lootPanel:SetHeight(50 + #items * 38)

  for i, item in ipairs(items) do
    local row = CreateFrame("Button", nil, lootPanel.content)
    row:SetSize(380, 32)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 38)
    row:SetHighlightTexture("Interface/Buttons/UI-Listbox-Highlight")

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 8, 0)
    text:SetText((item.itemLink or "?") .. "  |cffaaaaaa(ilvl " .. (item.ilvl or 0) .. ")|r")

    local btn = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
    btn:SetSize(90, 26)
    btn:SetPoint("RIGHT", -8, 0)
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
