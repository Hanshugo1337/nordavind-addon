-- UI/CouncilFrame.lua
-- Multi-item interest popup (all raiders) + loot detected panel (officer)

local NLC = NordavindLC_NS
local T = NLC.Theme

-- ============================================================
-- TOOLTIP HELPERS
-- ============================================================
local CATEGORY_TIPS = {
  upgrade  = "Du trenger dette itemet som en direkte oppgradering\nfor din main spec.",
  catalyst = "Du vil bruke Catalyst for å gjøre dette\ntil tier-set piece.",
  offspec  = "Du trenger dette for off spec\n(annen rolle enn main).",
  tmog     = "Du vil ha dette itemet for transmog\n(utseende).",
  pass     = "Du trenger ikke dette itemet.",
}

local function AddItemTooltip(frame, itemLink)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(itemLink)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function AddTextTooltip(frame, title, lines)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 0.82, 0)
    if type(lines) == "string" then
      GameTooltip:AddLine(lines, 1, 1, 1, true)
    elseif type(lines) == "table" then
      for _, line in ipairs(lines) do
        if line.left and line.right then
          GameTooltip:AddDoubleLine(line.left, line.right, line.lr or 0.6, line.lg or 0.6, line.lb or 0.6, line.rr or 1, line.rg or 1, line.rb or 1)
        else
          GameTooltip:AddLine(line.text or line, line.r or 1, line.g or 1, line.b or 1, true)
        end
      end
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ============================================================
-- MULTI-ITEM INTEREST POPUP
-- ============================================================
local multiFrame = nil
local itemRows = {}
local ITEM_ROW_HEIGHT = 100
local ITEM_ROW_WIDTH = 460

local function createItemRow(parent, index, item)
  local yOffset = -(index - 1) * ITEM_ROW_HEIGHT

  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(ITEM_ROW_WIDTH, ITEM_ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, yOffset)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)

  -- Invisible overlay for item tooltip on hover
  local itemHover = CreateFrame("Frame", nil, row)
  itemHover:SetSize(ITEM_ROW_WIDTH - 24, 18)
  itemHover:SetPoint("TOPLEFT", 12, -6)
  if item.itemLink then AddItemTooltip(itemHover, item.itemLink) end

  local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  itemText:SetPoint("TOPLEFT", 12, -8)
  itemText:SetWidth(ITEM_ROW_WIDTH - 24)
  itemText:SetJustifyH("LEFT")
  itemText:SetText((item.itemLink or "?") .. "  " .. T.MUTED .. "ilvl " .. (item.ilvl or 0) .. "|r")

  local eqLink, eqIlvl = NLC.Utils.GetEquippedInfo(item.equipLoc or "")
  local eqText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  eqText:SetPoint("TOPLEFT", 12, -26)
  eqText:SetWidth(ITEM_ROW_WIDTH - 24)
  eqText:SetJustifyH("LEFT")
  if eqLink then
    local diff = (item.ilvl or 0) - eqIlvl
    local diffColor = diff > 0 and T.GREEN or T.RED
    eqText:SetText(T.MUTED .. "Equipped: |r" .. eqLink .. " " .. T.MUTED .. "(" .. eqIlvl .. ")|r  " .. diffColor .. (diff > 0 and "+" or "") .. diff .. "|r")
  else
    eqText:SetText(T.MUTED .. "Ingen item i slot|r")
  end

  local available = NLC.Utils.GetAvailableCategories(item.itemLink, item.equipLoc)
  local allCategories = {
    { id = "upgrade",  label = T.GOLD_LIGHT .. "Upgrade|r", width = 100 },
    { id = "catalyst", label = "|cff9933ffCatalyst|r",      width = 90 },
    { id = "offspec",  label = "|cff3399ffOffspec|r",       width = 85 },
    { id = "tmog",     label = T.GOLD .. "Tmog|r",          width = 70 },
  }
  local categories = {}
  for _, cat in ipairs(allCategories) do
    if available[cat.id] then table.insert(categories, cat) end
  end
  -- Always add Pass button at the end
  table.insert(categories, { id = "pass", label = T.RED .. "Pass|r", width = 65 })

  local rowData = { buttons = {}, noteBox = nil, selection = nil, noteText = "" }

  if #categories == 0 then
    local noUse = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noUse:SetPoint("TOPLEFT", 12, -52)
    noUse:SetText(T.MUTED .. "Not usable by your class|r")
    itemRows[item.sessionIdx] = rowData
    return row
  end

  local btnX = 12

  for _, cat in ipairs(categories) do
    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(cat.width, 28)
    btn:SetPoint("TOPLEFT", btnX, -46)
    btn:SetText(cat.label)

    btn:SetScript("OnClick", function()
      if cat.id == "pass" then
        -- Pass: deselect everything
        rowData.selection = nil
        for _, b in pairs(rowData.buttons) do b:SetAlpha(1.0) end
        btn:SetAlpha(1.0)
        if rowData.noteBox then rowData.noteBox:Hide() end
      elseif rowData.selection == cat.id then
        -- Clicking same button: deselect (back to no selection)
        rowData.selection = nil
        for _, b in pairs(rowData.buttons) do b:SetAlpha(1.0) end
        if cat.id == "upgrade" and rowData.noteBox then
          rowData.noteBox:Hide()
        end
      else
        -- Select this category
        rowData.selection = cat.id
        for id, b in pairs(rowData.buttons) do
          b:SetAlpha(id == cat.id and 1.0 or 0.4)
        end
        -- Dim the pass button too
        if rowData.buttons["pass"] then rowData.buttons["pass"]:SetAlpha(0.4) end
        if cat.id == "upgrade" and rowData.noteBox then
          rowData.noteBox:Show()
          rowData.noteBox:SetFocus()
        elseif rowData.noteBox then
          rowData.noteBox:Hide()
        end
      end
    end)

    -- Category tooltip
    if CATEGORY_TIPS[cat.id] then
      btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(cat.id:sub(1,1):upper() .. cat.id:sub(2), 1, 0.82, 0)
        GameTooltip:AddLine(CATEGORY_TIPS[cat.id], 1, 1, 1, true)
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    rowData.buttons[cat.id] = btn
    btnX = btnX + cat.width + 6
  end

  local noteBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
  noteBox:SetSize(ITEM_ROW_WIDTH - 24, 22)
  noteBox:SetPoint("TOPLEFT", 12, -78)
  noteBox:SetAutoFocus(false)
  noteBox:SetMaxLetters(60)
  noteBox:Hide()
  noteBox:SetScript("OnTextChanged", function(self)
    rowData.noteText = self:GetText():trim()
  end)
  noteBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  rowData.noteBox = noteBox

  itemRows[item.sessionIdx] = rowData
  return row
end

function NLC.UI.ShowMultiItemPopup(sessions, timer)
  itemRows = {}

  if multiFrame then multiFrame:Hide() end

  local itemCount = #sessions
  local contentHeight = itemCount * ITEM_ROW_HEIGHT
  local frameHeight = math.min(120 + contentHeight, 600)

  if not multiFrame then
    multiFrame = CreateFrame("Frame", "NordavindLCMultiItem", UIParent, "BackdropTemplate")
    multiFrame:SetPoint("CENTER", 0, 50)
    multiFrame:SetMovable(true)
    multiFrame:EnableMouse(true)
    multiFrame:RegisterForDrag("LeftButton")
    multiFrame:SetScript("OnDragStart", multiFrame.StartMoving)
    multiFrame:SetScript("OnDragStop", multiFrame.StopMovingOrSizing)
    multiFrame:SetFrameStrata("DIALOG")
    T.ApplyBackdrop(multiFrame)

    local closeX = CreateFrame("Button", nil, multiFrame, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -2, -2)
  end

  multiFrame:SetSize(ITEM_ROW_WIDTH + 40, frameHeight)

  if multiFrame.scrollChild then
    for _, child in ipairs({ multiFrame.scrollChild:GetChildren() }) do child:Hide() end
  end

  if multiFrame.title then multiFrame.title:Hide() end
  T.CreateTitleBar(multiFrame, "Loot Council")
  local bossName = sessions[1] and sessions[1].boss or "Unknown"
  multiFrame.title:SetText(T.GOLD .. "Loot Council|r  " .. T.MUTED .. "— " .. bossName .. "|r")

  if not multiFrame.timerText then
    multiFrame.timerText = multiFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    multiFrame.timerText:SetPoint("TOPRIGHT", -40, -10)
  end
  multiFrame.timerText:SetText(T.GOLD .. timer .. "s|r")
  multiFrame.timerText:Show()

  if not multiFrame.scrollFrame then
    multiFrame.scrollFrame = CreateFrame("ScrollFrame", nil, multiFrame, "UIPanelScrollFrameTemplate")
    multiFrame.scrollFrame:SetPoint("TOPLEFT", 12, -40)
    multiFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -32, 56)

    multiFrame.scrollChild = CreateFrame("Frame")
    multiFrame.scrollFrame:SetScrollChild(multiFrame.scrollChild)
  end
  multiFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -32, 56)
  multiFrame.scrollChild:SetSize(ITEM_ROW_WIDTH, contentHeight)

  for i, session in ipairs(sessions) do
    local row = createItemRow(multiFrame.scrollChild, i, session)
    row:Show()
  end

  if not multiFrame.sendBtn then
    multiFrame.sendBtn = CreateFrame("Button", nil, multiFrame, "UIPanelButtonTemplate")
    multiFrame.sendBtn:SetSize(ITEM_ROW_WIDTH, 40)
    multiFrame.sendBtn:SetPoint("BOTTOM", 0, 12)
    multiFrame.sendBtn:SetText(T.GREEN .. "Send Responses|r")
    multiFrame.sendBtn:SetNormalFontObject("GameFontHighlightLarge")
  end
  multiFrame.sendBtn:SetScript("OnClick", function()
    local selections = {}
    for _, session in ipairs(sessions) do
      local rowData = itemRows[session.sessionIdx]
      if rowData and rowData.selection then
        selections[session.sessionIdx] = {
          category = rowData.selection,
          note = rowData.selection == "upgrade" and rowData.noteText or "",
        }
      end
    end
    NLC.Council.SubmitResponses(selections)
    multiFrame:Hide()
  end)
  multiFrame.sendBtn:Show()

  multiFrame:Show()

  local remaining = timer
  if multiFrame._ticker then multiFrame._ticker:Cancel() end
  multiFrame._ticker = C_Timer.NewTicker(1, function(ticker)
    remaining = remaining - 1
    if remaining <= 0 or not multiFrame:IsShown() then
      ticker:Cancel()
      if multiFrame:IsShown() then
        multiFrame.sendBtn:GetScript("OnClick")()
      end
      return
    end
    local color = remaining <= 10 and T.RED or remaining <= 30 and T.ORANGE or T.GOLD
    multiFrame.timerText:SetText(color .. remaining .. "s|r")
  end, timer)
end

function NLC.UI.HideMultiItemPopup()
  if multiFrame and multiFrame:IsShown() then
    if multiFrame._ticker then multiFrame._ticker:Cancel() end
    multiFrame:Hide()
  end
end

-- ============================================================
-- LOOT DETECTED PANEL (officer only)
-- Shows all dropped items with remove buttons, then "Start Council" queues them all
-- ============================================================
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
    empty:SetText(T.MUTED .. "No items remaining|r")
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
      NLC.Utils.Print("Removed: " .. (item.itemLink or "?"))
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

      NLC.Council.StartMultiSession(remaining, remaining[1].boss)
      lootPanel:Hide()
    end)
  end

  refreshLootPanel(items)
  lootPanel:Show()
end
