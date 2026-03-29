-- UI/CouncilFrame.lua
-- Interest popup (all raiders) + loot detected panel (officer)

local NLC = NordavindLC_NS
local T = NLC.Theme

local interestFrame = nil

function NLC.UI.ShowInterestPopup(itemLink, ilvl, equipLoc, timer)
  if not interestFrame then
    interestFrame = CreateFrame("Frame", "NordavindLCInterest", UIParent, "BackdropTemplate")
    interestFrame:SetSize(440, 380)
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

    -- Item name (large, centered)
    interestFrame.itemText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    interestFrame.itemText:SetPoint("TOP", 0, -48)
    interestFrame.itemText:SetWidth(400)
    interestFrame.itemText:SetJustifyH("CENTER")

    -- Equipped comparison
    interestFrame.equippedText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    interestFrame.equippedText:SetPoint("TOP", 0, -76)
    interestFrame.equippedText:SetWidth(400)
    interestFrame.equippedText:SetJustifyH("CENTER")

    -- Separator
    T.CreateSeparator(interestFrame, -100)

    -- Timer (centered, with more space)
    interestFrame.timerText = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    interestFrame.timerText:SetPoint("TOP", 0, -112)

    -- Note input (hidden by default)
    interestFrame.noteBox = CreateFrame("EditBox", nil, interestFrame, "InputBoxTemplate")
    interestFrame.noteBox:SetSize(380, 32)
    interestFrame.noteBox:SetPoint("TOP", 0, -155)
    interestFrame.noteBox:SetAutoFocus(false)
    interestFrame.noteBox:SetMaxLetters(60)
    interestFrame.noteBox:Hide()

    interestFrame.noteLabel = interestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    interestFrame.noteLabel:SetPoint("BOTTOM", interestFrame.noteBox, "TOP", 0, 6)
    interestFrame.noteLabel:SetText(T.MUTED .. "Note (valgfritt):|r")
    interestFrame.noteLabel:Hide()

    interestFrame.noteSendBtn = CreateFrame("Button", nil, interestFrame, "UIPanelButtonTemplate")
    interestFrame.noteSendBtn:SetSize(380, 40)
    interestFrame.noteSendBtn:SetPoint("TOP", interestFrame.noteBox, "BOTTOM", 0, -12)
    interestFrame.noteSendBtn:SetText(T.GREEN .. "Send Upgrade|r")
    interestFrame.noteSendBtn:SetNormalFontObject("GameFontHighlightLarge")
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

    -- Upgrade (full width, prominent, gold styled)
    local upgradeBtn = CreateFrame("Button", nil, interestFrame, "UIPanelButtonTemplate")
    upgradeBtn:SetSize(390, 46)
    upgradeBtn:SetPoint("TOP", 0, -142)
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

    -- Second row: Catalyst, Offspec, Tmog — evenly spaced
    local secondRow = {
      { id = "catalyst", label = "|cff9933ffCatalyst|r" },
      { id = "offspec",  label = "|cff3399ffOffspec|r" },
      { id = "tmog",     label = T.GOLD .. "Tmog|r" },
    }
    local btnWidth = 122
    local btnSpacing = 6
    local totalWidth = btnWidth * 3 + btnSpacing * 2
    local startX = -totalWidth / 2 + btnWidth / 2

    for i, cat in ipairs(secondRow) do
      local btn = CreateFrame("Button", nil, interestFrame, "UIPanelButtonTemplate")
      btn:SetSize(btnWidth, 40)
      btn:SetPoint("TOP", startX + (i - 1) * (btnWidth + btnSpacing), -198)
      btn:SetText(cat.label)
      btn:SetScript("OnClick", function()
        local session = NLC.Council.GetActiveSession()
        local itemId = session and session.itemId or 0
        NLC.Council.SendInterest(itemId, cat.id)
        interestFrame:Hide()
        NLC.Utils.Print("Interesse: " .. cat.id)
      end)
      interestFrame.buttons[cat.id] = btn
    end

    -- Separator before pass
    T.CreateSeparator(interestFrame, -252)

    -- Pass (full width, bottom, subtle)
    local passBtn = CreateFrame("Button", nil, interestFrame, "UIPanelButtonTemplate")
    passBtn:SetSize(390, 40)
    passBtn:SetPoint("TOP", 0, -264)
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
-- Shows all dropped items with remove buttons, then "Start Council" queues them all
local lootPanel = nil

local function refreshLootPanel(items)
  if not lootPanel then return end

  -- Clear previous rows
  for _, child in ipairs({ lootPanel.content:GetChildren() }) do
    child:Hide()
  end
  for _, region in ipairs({ lootPanel.content:GetRegions() }) do
    region:Hide()
  end

  local count = #items
  local ROW_H = 42
  lootPanel:SetHeight(110 + count * ROW_H)

  if count == 0 then
    local empty = lootPanel.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetText(T.MUTED .. "Ingen items igjen|r")
    empty:Show()
    lootPanel.startBtn:Disable()
    lootPanel.countText:SetText("")
    return
  end

  lootPanel.countText:SetText(T.MUTED .. count .. " item" .. (count > 1 and "s" or "") .. "|r")
  lootPanel.startBtn:Enable()
  lootPanel.startBtn:SetText(T.GREEN .. "Start Council (" .. count .. ")|r")

  for i, item in ipairs(items) do
    -- Alternating row bg
    local rowBg = lootPanel.content:CreateTexture(nil, "BACKGROUND")
    rowBg:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    rowBg:SetSize(460, ROW_H)
    rowBg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
    rowBg:Show()

    local row = CreateFrame("Frame", nil, lootPanel.content)
    row:SetSize(460, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:Show()

    -- Item text
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 12, 0)
    text:SetWidth(360)
    text:SetJustifyH("LEFT")
    text:SetText((item.itemLink or "?") .. "  " .. T.MUTED .. "(ilvl " .. (item.ilvl or 0) .. ")|r")

    -- Remove button (X)
    local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
    removeBtn:SetSize(24, 24)
    removeBtn:SetPoint("RIGHT", -8, 0)
    removeBtn:SetScript("OnClick", function()
      NLC.LootDetection.RemoveItem(i)
      local remaining = NLC.LootDetection.GetDroppedItems()
      refreshLootPanel(remaining)
      NLC.Utils.Print("Fjernet: " .. (item.itemLink or "?"))
    end)
  end
end

function NLC.UI.ShowLootDetected(items)
  if not NLC.isOfficer then return end

  if not lootPanel then
    lootPanel = CreateFrame("Frame", "NordavindLCLootPanel", UIParent, "BackdropTemplate")
    lootPanel:SetSize(500, 200)
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

    -- Item count subtitle
    lootPanel.countText = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lootPanel.countText:SetPoint("TOP", 0, -34)

    -- Content area for item rows
    lootPanel.content = CreateFrame("Frame", nil, lootPanel)
    lootPanel.content:SetPoint("TOPLEFT", 15, -52)
    lootPanel.content:SetPoint("RIGHT", -15, 0)
    lootPanel.content:SetHeight(200)

    -- Start Council button (bottom, prominent)
    lootPanel.startBtn = CreateFrame("Button", nil, lootPanel, "UIPanelButtonTemplate")
    lootPanel.startBtn:SetSize(460, 42)
    lootPanel.startBtn:SetPoint("BOTTOM", 0, 16)
    lootPanel.startBtn:SetNormalFontObject("GameFontHighlightLarge")
    lootPanel.startBtn:SetScript("OnClick", function()
      local remaining = NLC.LootDetection.GetDroppedItems()
      if #remaining == 0 then return end

      -- Start first item, queue the rest
      local first = remaining[1]
      NLC.Council.StartSession(first.itemLink, first.itemId, first.ilvl, first.equipLoc, first.boss)

      -- Queue remaining items as pending sessions
      for i = 2, #remaining do
        local item = remaining[i]
        table.insert(NLC.pendingSessions, {
          itemLink = item.itemLink,
          itemId = item.itemId,
          ilvl = item.ilvl,
          equipLoc = item.equipLoc,
          boss = item.boss,
          timer = NLC.db.config.timer or 30,
          interests = {},
          phase = "collecting",
        })
      end

      if #remaining > 1 then
        NLC.Utils.Print((#remaining - 1) .. " item(s) lagt i ko.")
        NLC.UpdateMinimapCount()
      end

      lootPanel:Hide()
    end)
  end

  refreshLootPanel(items)
  lootPanel:Show()
end

function NLC.UI.UpdateCouncilInterests(session)
  local count = 0
  for _ in pairs(session.interests) do count = count + 1 end
  NLC.Utils.Print(count .. " interesse(r) mottatt")
end
