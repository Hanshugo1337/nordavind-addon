-- UI/HistoryFrame.lua
-- Award history browser + shared edit popup used by both HistoryFrame and TradeFrame.

local NLC = NordavindLC_NS
local T = NLC.Theme

NLC.History = NLC.History or {}

local CATEGORIES = { "upgrade", "catalyst", "offspec", "tmog" }
local editPopup = nil
local historyFrame = nil
local HISTORY_ROW_HEIGHT = 44
local HISTORY_WIDTH = 580

-- ============================================================
-- EDIT HELPERS
-- ============================================================

-- Apply an award edit to lootHistory, pendingExport, and pendingTrades.
-- Also queues a pendingEdit for database sync via companion app.
local function ApplyAwardEdit(entry, newRecipient, newCategory)
  local oldRecipient = entry.awardedTo

  -- Update lootHistory
  for _, h in ipairs(NLC.db.lootHistory or {}) do
    if h.timestamp == entry.timestamp and h.item == entry.item then
      h.awardedTo = newRecipient
      h.category  = newCategory
      break
    end
  end

  -- Update pendingExport
  for _, e in ipairs(NLC.db.pendingExport or {}) do
    if e.timestamp == entry.timestamp and e.item == entry.item then
      e.awardedTo = newRecipient
      e.category  = newCategory
      break
    end
  end

  -- Update pendingTrades (matched by itemId + old recipient)
  for _, t in ipairs(NLC.db.pendingTrades or {}) do
    if t.itemId == entry.itemId and t.awardedTo == oldRecipient then
      t.awardedTo = newRecipient
      t.category  = newCategory
      break
    end
  end

  -- Queue for companion → database sync
  NLC.db.pendingEdits = NLC.db.pendingEdits or {}
  table.insert(NLC.db.pendingEdits, {
    originalTimestamp = entry.timestamp,
    item              = entry.item,
    newAwardedTo      = newRecipient,
    newCategory       = newCategory,
  })
end

NLC.History.ApplyAwardEdit = ApplyAwardEdit

-- ============================================================
-- SHARED EDIT POPUP
-- ============================================================

-- NLC.UI.ShowEditPopup(entry, onSave)
-- entry  : { item, itemId, awardedTo, category, timestamp, ... }
-- onSave : function(newRecipient, newCategory) called on Lagre
function NLC.UI.ShowEditPopup(entry, onSave)
  if not editPopup then
    editPopup = CreateFrame("Frame", "NordavindLCEditPopup", UIParent, "BackdropTemplate")
    editPopup:SetSize(360, 180)
    editPopup:SetPoint("CENTER")
    editPopup:SetMovable(true)
    editPopup:EnableMouse(true)
    editPopup:RegisterForDrag("LeftButton")
    editPopup:SetScript("OnDragStart", editPopup.StartMoving)
    editPopup:SetScript("OnDragStop", editPopup.StopMovingOrSizing)
    editPopup:SetFrameStrata("DIALOG")
    T.ApplyBackdrop(editPopup)

    local title = editPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(T.GOLD_LIGHT .. "Endre Award|r")

    local recipLabel = editPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recipLabel:SetPoint("TOPLEFT", 16, -48)
    recipLabel:SetText(T.MUTED .. "Mottaker:|r")

    local recipInput = CreateFrame("EditBox", "NordavindLCEditRecip", editPopup, "InputBoxTemplate")
    recipInput:SetSize(200, 28)
    recipInput:SetPoint("TOPLEFT", 16, -64)
    recipInput:SetAutoFocus(false)
    editPopup.recipInput = recipInput

    local catLabel = editPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    catLabel:SetPoint("TOPLEFT", 230, -48)
    catLabel:SetText(T.MUTED .. "Kategori:|r")

    local catDropdown = CreateFrame("Frame", "NordavindLCEditCatDropdown", editPopup, "UIDropDownMenuTemplate")
    catDropdown:SetPoint("TOPLEFT", 218, -60)
    UIDropDownMenu_SetWidth(catDropdown, 110)
    editPopup.catDropdown = catDropdown
    editPopup.selectedCategory = "upgrade"

    UIDropDownMenu_Initialize(catDropdown, function(_, _)
      for _, cat in ipairs(CATEGORIES) do
        local info = UIDropDownMenu_CreateInfo()
        info.text  = cat
        info.value = cat
        info.func  = function()
          editPopup.selectedCategory = cat
          UIDropDownMenu_SetText(editPopup.catDropdown, cat)
        end
        UIDropDownMenu_AddButton(info)
      end
    end)

    local saveBtn = T.CreateButton(editPopup, 90, 32, T.GREEN .. "Lagre|r")
    saveBtn:SetPoint("BOTTOMLEFT", 16, 14)
    editPopup.saveBtn = saveBtn

    local cancelBtn = T.CreateButton(editPopup, 90, 32, T.MUTED .. "Avbryt|r")
    cancelBtn:SetPoint("BOTTOMLEFT", 116, 14)
    cancelBtn:SetScript("OnClick", function() editPopup:Hide() end)
  end

  -- Pre-fill
  editPopup.recipInput:SetText(entry.awardedTo or "")
  editPopup.selectedCategory = entry.category or "upgrade"
  UIDropDownMenu_SetText(editPopup.catDropdown, editPopup.selectedCategory)

  -- Wire save for this invocation
  editPopup.saveBtn:SetScript("OnClick", function()
    local newRecipient = editPopup.recipInput:GetText():match("^%s*(.-)%s*$")
    local newCategory  = editPopup.selectedCategory
    if newRecipient and newRecipient ~= "" then
      onSave(newRecipient, newCategory)
      editPopup:Hide()
    else
      NLC.Utils.Print("Skriv inn et spillernavn.")
    end
  end)

  editPopup:Show()
  editPopup.recipInput:SetFocus()
end

-- ============================================================
-- HISTORY FRAME
-- ============================================================

local function refreshHistoryFrame()
  if not historyFrame or not historyFrame:IsShown() then return end

  for _, child in ipairs({ historyFrame.content:GetChildren() }) do child:Hide() end
  for _, region in ipairs({ historyFrame.content:GetRegions() }) do region:Hide() end

  local history = NLC.db.lootHistory or {}
  local count   = #history

  if count == 0 then
    historyFrame:SetHeight(120)
    local empty = historyFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetText(T.MUTED .. "Ingen awards registrert.|r")
    empty:Show()
    return
  end

  historyFrame:SetHeight(math.min(120 + count * HISTORY_ROW_HEIGHT, 500))
  historyFrame.content:SetHeight(count * HISTORY_ROW_HEIGHT)

  -- Newest first
  for i = count, 1, -1 do
    local entry  = history[i]
    local rowIdx = count - i + 1

    local rowBg = historyFrame.content:CreateTexture(nil, "BACKGROUND")
    rowBg:SetPoint("TOPLEFT", 0, -(rowIdx - 1) * HISTORY_ROW_HEIGHT)
    rowBg:SetSize(HISTORY_WIDTH - 40, HISTORY_ROW_HEIGHT)
    rowBg:SetColorTexture(1, 1, 1, rowIdx % 2 == 0 and 0.04 or 0)
    rowBg:Show()

    local row = CreateFrame("Frame", nil, historyFrame.content)
    row:SetSize(HISTORY_WIDTH - 40, HISTORY_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(rowIdx - 1) * HISTORY_ROW_HEIGHT)
    row:Show()

    local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemText:SetPoint("LEFT", 12, 8)
    itemText:SetWidth(260)
    itemText:SetJustifyH("LEFT")
    itemText:SetText(entry.item or "?")
    itemText:Show()

    local dateStr = entry.timestamp and date("%d.%m %H:%M", entry.timestamp) or "?"
    local toText  = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toText:SetPoint("LEFT", 12, -10)
    toText:SetText(T.MUTED .. "Til:|r " .. (entry.awardedTo or "?") ..
      "  " .. T.MUTED .. "(" .. (entry.category or "?") .. ")  " .. dateStr .. "|r")
    toText:Show()

    -- Slett button
    local deleteBtn = T.CreateButton(row, 60, 26, T.RED .. "Slett|r")
    deleteBtn:SetPoint("RIGHT", -12, 0)
    local capturedEntry = entry
    local capturedIdx   = i
    deleteBtn:SetScript("OnClick", function()
      for j = #(NLC.db.lootHistory or {}), 1, -1 do
        local h = NLC.db.lootHistory[j]
        if h.timestamp == capturedEntry.timestamp and h.item == capturedEntry.item then
          table.remove(NLC.db.lootHistory, j); break
        end
      end
      for j = #(NLC.db.pendingExport or {}), 1, -1 do
        local e = NLC.db.pendingExport[j]
        if e.timestamp == capturedEntry.timestamp and e.item == capturedEntry.item then
          table.remove(NLC.db.pendingExport, j); break
        end
      end
      for j = #(NLC.db.pendingTrades or {}), 1, -1 do
        local t = NLC.db.pendingTrades[j]
        if t.itemId == capturedEntry.itemId and t.awardedTo == capturedEntry.awardedTo then
          table.remove(NLC.db.pendingTrades, j); break
        end
      end
      refreshHistoryFrame()
    end)

    -- Endre button
    local editBtn = T.CreateButton(row, 70, 26, T.GOLD .. "Endre|r")
    editBtn:SetPoint("RIGHT", -80, 0)
    editBtn:SetScript("OnClick", function()
      NLC.UI.ShowEditPopup(capturedEntry, function(newRecipient, newCategory)
        ApplyAwardEdit(capturedEntry, newRecipient, newCategory)
        capturedEntry.awardedTo = newRecipient
        capturedEntry.category  = newCategory
        refreshHistoryFrame()
      end)
    end)
  end
end

function NLC.UI.ShowHistoryFrame()
  if not NLC.isOfficer then return end

  if not historyFrame then
    historyFrame = CreateFrame("Frame", "NordavindLCHistoryFrame", UIParent, "BackdropTemplate")
    historyFrame:SetSize(HISTORY_WIDTH, 300)
    historyFrame:SetPoint("CENTER")
    historyFrame:SetMovable(true)
    historyFrame:EnableMouse(true)
    historyFrame:RegisterForDrag("LeftButton")
    historyFrame:SetScript("OnDragStart", historyFrame.StartMoving)
    historyFrame:SetScript("OnDragStop", historyFrame.StopMovingOrSizing)
    T.ApplyBackdrop(historyFrame)

    T.CreateTitleBar(historyFrame, "Award Historikk")

    local closeBtn = CreateFrame("Button", nil, historyFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() historyFrame:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, historyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -44)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(HISTORY_WIDTH - 40, 1)
    scroll:SetScrollChild(content)
    historyFrame.content = content
  end

  historyFrame:Show()
  refreshHistoryFrame()
end
