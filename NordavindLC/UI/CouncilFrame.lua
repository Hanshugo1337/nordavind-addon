-- UI/CouncilFrame.lua
-- Interest popup (all raiders) + loot detected panel (officer)

local NLC = NordavindLC_NS
local T = NLC.Theme

local interestFrame = nil

function NLC.UI.ShowInterestPopup(itemLink, ilvl, equipLoc, timer)
  if not interestFrame then
    interestFrame = CreateFrame("Frame", "NordavindLCInterest", UIParent, "BackdropTemplate")
    interestFrame:SetSize(400, 320)
    interestFrame:SetPoint("CENTER", 0, 100)
    interestFrame:SetMovable(true)
    interestFrame:EnableMouse(true)
    interestFrame:RegisterForDrag("LeftButton")
    interestFrame:SetScript("OnDragStart", interestFrame.StartMoving)
    interestFrame:SetScript("OnDragStop", interestFrame.StopMovingOrSizing)
    interestFrame:SetFrameStrata("DIALOG")
    T.ApplyBackdrop(interestFrame)

    T.CreateTitleBar(interestFrame, "Loot Council")

    -- Close button
    local closeX = CreateFrame("Button", nil, interestFrame, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -2, -2)

    -- Item name
    interestFrame.itemText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    interestFrame.itemText:SetPoint("TOP", 0, -44)
    interestFrame.itemText:SetWidth(360)
    interestFrame.itemText:SetJustifyH("CENTER")

    -- Equipped comparison
    interestFrame.equippedText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    interestFrame.equippedText:SetPoint("TOP", 0, -68)
    interestFrame.equippedText:SetWidth(360)
    interestFrame.equippedText:SetJustifyH("CENTER")

    -- Timer with gold accent
    interestFrame.timerText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    interestFrame.timerText:SetPoint("TOP", 0, -92)

    -- Separator
    T.CreateSeparator(interestFrame, -108)

    -- Note input (hidden by default)
    interestFrame.noteBox = CreateFrame("EditBox", nil, interestFrame, "InputBoxTemplate")
    interestFrame.noteBox:SetSize(320, 28)
    interestFrame.noteBox:SetPoint("TOP", 0, -130)
    interestFrame.noteBox:SetAutoFocus(false)
    interestFrame.noteBox:SetMaxLetters(60)
    interestFrame.noteBox:Hide()

    interestFrame.noteLabel = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    interestFrame.noteLabel:SetPoint("BOTTOM", interestFrame.noteBox, "TOP", 0, 4)
    interestFrame.noteLabel:SetText(T.MUTED .. "Note (valgfritt):|r")
    interestFrame.noteLabel:Hide()

    interestFrame.noteSendBtn = CreateFrame("Button", nil, interestFrame, "UIPanelButtonTemplate")
    interestFrame.noteSendBtn:SetSize(320, 34)
    interestFrame.noteSendBtn:SetPoint("TOP", interestFrame.noteBox, "BOTTOM", 0, -10)
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
    local upgradeBtn = CreateFrame("Button", nil, interestFrame, "UIPanelButtonTemplate")
    upgradeBtn:SetSize(360, 38)
    upgradeBtn:SetPoint("TOP", 0, -122)
    upgradeBtn:SetText(T.GOLD_LIGHT .. "Upgrade|r")
    upgradeBtn:SetNormalFontObject("GameFontHighlightLarge")
    upgradeBtn:SetScript("OnClick", function()
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
      local btn = CreateFrame("Button", nil, interestFrame, "UIPanelButtonTemplate")
      btn:SetSize(114, 34)
      btn:SetPoint("TOPLEFT", 22 + (i - 1) * 120, -172)
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

    -- Pass (full width, bottom, subtle)
    local passBtn = CreateFrame("Button", nil, interestFrame, "UIPanelButtonTemplate")
    passBtn:SetSize(360, 34)
    passBtn:SetPoint("BOTTOM", 0, 22)
    passBtn:SetText(T.MUTED .. "Pass|r")
    passBtn:SetScript("OnClick", function()
      interestFrame:Hide()
    end)
    interestFrame.passBtn = passBtn
  end

  interestFrame.title:SetText(T.GOLD .. "Loot Council|r")
  interestFrame.itemText:SetText((itemLink or "?") .. "  " .. T.MUTED .. "(ilvl " .. (ilvl or 0) .. ")|r")

  local eqLink, eqIlvl = NLC.Utils.GetEquippedInfo(equipLoc or "")
  if eqLink then
    local diff = (ilvl or 0) - eqIlvl
    local diffColor = diff > 0 and T.GREEN or T.RED
    interestFrame.equippedText:SetText(T.MUTED .. "Equipped: |r" .. eqLink .. "  " .. T.MUTED .. "(" .. eqIlvl .. ")|r  " .. diffColor .. (diff > 0 and "+" or "") .. diff .. " ilvl|r")
  else
    interestFrame.equippedText:SetText(T.MUTED .. "Ingen item i slot|r")
  end

  -- Reset to button view
  interestFrame.noteLabel:Hide()
  interestFrame.noteBox:Hide()
  interestFrame.noteBox:SetText("")
  interestFrame.noteSendBtn:Hide()
  interestFrame.buttons["upgrade"]:Show()
  interestFrame.buttons["catalyst"]:Show()
  interestFrame.buttons["offspec"]:Show()
  interestFrame.buttons["tmog"]:Show()
  interestFrame.passBtn:Show()

  interestFrame.timerText:SetText(T.GOLD .. (timer or 180) .. "s|r " .. T.MUTED .. "igjen|r")
  interestFrame:Show()

  local remaining = timer or 180
  C_Timer.NewTicker(1, function(ticker)
    remaining = remaining - 1
    if remaining <= 0 or not interestFrame:IsShown() then
      ticker:Cancel()
      if interestFrame:IsShown() then interestFrame:Hide() end
      return
    end
    if interestFrame.timerText then
      local color = remaining <= 5 and T.RED or remaining <= 10 and T.ORANGE or T.GOLD
      interestFrame.timerText:SetText(color .. remaining .. "s|r " .. T.MUTED .. "igjen|r")
    end
  end, timer or 180)
end

-- Loot Detected Panel (officer only)
local lootPanel = nil

function NLC.UI.ShowLootDetected(items)
  if not NLC.isOfficer then return end

  if not lootPanel then
    lootPanel = CreateFrame("Frame", "NordavindLCLootPanel", UIParent, "BackdropTemplate")
    lootPanel:SetSize(440, 60)
    lootPanel:SetPoint("TOP", 0, -50)
    lootPanel:SetMovable(true)
    lootPanel:EnableMouse(true)
    lootPanel:RegisterForDrag("LeftButton")
    lootPanel:SetScript("OnDragStart", lootPanel.StartMoving)
    lootPanel:SetScript("OnDragStop", lootPanel.StopMovingOrSizing)
    lootPanel:SetFrameStrata("HIGH")
    T.ApplyBackdrop(lootPanel)

    T.CreateTitleBar(lootPanel, "Loot Detected")

    local closeX = CreateFrame("Button", nil, lootPanel, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -2, -2)

    lootPanel.content = CreateFrame("Frame", nil, lootPanel)
    lootPanel.content:SetPoint("TOPLEFT", 15, -40)
    lootPanel.content:SetPoint("BOTTOMRIGHT", -15, 10)
  end

  for _, child in ipairs({ lootPanel.content:GetChildren() }) do
    child:Hide()
  end

  lootPanel:SetHeight(52 + #items * 40)

  for i, item in ipairs(items) do
    local row = CreateFrame("Button", nil, lootPanel.content)
    row:SetSize(400, 34)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 40)
    row:SetHighlightTexture("Interface/Buttons/UI-Listbox-Highlight")

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 10, 0)
    text:SetText((item.itemLink or "?") .. "  " .. T.MUTED .. "(ilvl " .. (item.ilvl or 0) .. ")|r")

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(90, 28)
    btn:SetPoint("RIGHT", -10, 0)
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
