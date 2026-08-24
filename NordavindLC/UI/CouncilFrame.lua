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

  -- Item icon (mockup: icon per row)
  local icon = T.CreateItemIcon(row, 32)
  icon:SetPoint("TOPLEFT", 8, -6)
  icon:SetItem(item.itemLink)

  -- Invisible overlay for item tooltip on hover
  local itemHover = CreateFrame("Frame", nil, row)
  itemHover:SetSize(ITEM_ROW_WIDTH - 58, 18)
  itemHover:SetPoint("TOPLEFT", 46, -6)
  if item.itemLink then AddItemTooltip(itemHover, item.itemLink) end

  local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  itemText:SetPoint("TOPLEFT", 46, -8)
  itemText:SetWidth(ITEM_ROW_WIDTH - 58)
  itemText:SetJustifyH("LEFT")
  itemText:SetText((item.itemLink or "?") .. "  " .. T.MUTED .. "ilvl " .. (item.ilvl or 0) .. "|r")

  local eqLink, eqIlvl = NLC.Utils.GetEquippedInfo(item.equipLoc or "")
  local eqText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  eqText:SetPoint("TOPLEFT", 46, -26)
  eqText:SetWidth(ITEM_ROW_WIDTH - 58)
  eqText:SetJustifyH("LEFT")
  if eqLink then
    local diff = (item.ilvl or 0) - eqIlvl
    local diffColor = diff > 0 and T.GREEN or T.RED
    eqText:SetText(T.MUTED .. "Equipped: |r" .. eqLink .. " " .. T.MUTED .. "(" .. eqIlvl .. ")|r  " .. diffColor .. (diff > 0 and "+" or "") .. diff .. "|r")
  elseif item.armorType then
    eqText:SetText(T.MUTED .. "Tier token — " .. item.armorType .. "|r")
  else
    eqText:SetText(T.MUTED .. "Ingen item i slot|r")
  end

  local available = NLC.Utils.GetAvailableCategories(item.itemLink, item.equipLoc, item.itemId)
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

  -- Officer: live per-item response counter (updated by the popup ticker).
  if NLC.isOfficer then
    rowData.respFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rowData.respFS:SetPoint("TOPRIGHT", -12, -8)
    rowData.respFS:SetText(T.MUTED .. NLC.Council.GetResponseCount(item.sessionIdx) .. " svar|r")
  end

  if #categories == 0 then
    local noUse = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noUse:SetPoint("TOPLEFT", 12, -52)
    noUse:SetText(T.MUTED .. "Ikke brukbart for din klasse|r")
    itemRows[item.sessionIdx or index] = rowData
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

  itemRows[item.sessionIdx or index] = rowData
  return row
end

-- Sant naar spillet kan svare paa alt vi trenger om hvert item.
--
-- C_Item.GetItemInfo returnerer nil for et item klienten ikke har i cachen enda.
-- Bygger vi radene da, er equipLoc nil — og GetAvailableCategories tolker det som
-- et tier-token. Paa 1.9.0 kastet den grenen og tok hele popupen med seg; selv
-- med den feilen rettet ville raideren fatt FEIL knapper, uten et ord om det.
local function itemsAreCached(sessions)
  for _, s in ipairs(sessions) do
    if s.itemLink and not C_Item.GetItemInfo(s.itemLink) then return false end
  end
  return true
end

-- Hvor lenge vi venter foer vi bygger uansett. Et item som aldri caches skal gi
-- en ufullstendig popup, ikke ingen popup.
local CACHE_WAIT_SECONDS = 5
local cacheWaitStarted = nil

-- Eksponert for tests/popupcache_harness.lua. Samme understrek-konvensjon som
-- LootDetection._leaderRollType; ingenting i addonet kaller den herfra.
NLC.UI._itemsAreCached = itemsAreCached

function NLC.UI.ShowMultiItemPopup(sessions, timer)
  if not itemsAreCached(sessions) then
    cacheWaitStarted = cacheWaitStarted or GetTime()
    if GetTime() - cacheWaitStarted < CACHE_WAIT_SECONDS then
      -- Neste frame. Spillet fyller cachen i bakgrunnen.
      C_Timer.After(0, function() NLC.UI.ShowMultiItemPopup(sessions, timer) end)
      return
    end
    if NLC.Utils.Diag then
      NLC.Utils.Diag("Item-cachen ble aldri komplett — bygger popupen likevel")
    end
  end
  cacheWaitStarted = nil

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

  -- Hver rad bygges for seg, med vakt rundt.
  --
  -- 19.08 kastet createItemRow paa det foerste tier-tokenet, og siden loekka laa
  -- naken, doede HELE popupen der. Raiderne saa de radene som tilfeldigvis var
  -- bygget foer tokenet — seks av tolv — eller ingenting. Ingen feilmelding de
  -- kunne handle paa; vinduet bare uteble.
  --
  -- Aarsaken den gangen er rettet, men prinsippet staar: et item vi ikke klarer
  -- aa tegne skal koste DET itemet, aldri raidets mulighet til aa svare paa
  -- resten. Radene som lyktes vises, Send-knappen virker, og du faar vite hvilket
  -- item som sviktet i stedet for aa gjette.
  local feilet = 0
  for i, session in ipairs(sessions) do
    local ok, row = pcall(createItemRow, multiFrame.scrollChild, i, session)
    if ok and row then
      row:Show()
    else
      feilet = feilet + 1
      local hvorfor = tostring(row)
      if NLC.Utils.Diag then
        NLC.Utils.Diag("Kunne ikke tegne rad " .. i .. " (" ..
                       tostring(session.itemLink) .. "): " .. hvorfor)
      end
      NLC.Utils.Print("|cffff8800Klarte ikke vise|r " .. tostring(session.itemLink) ..
                      " |cffff8800— si fra til offiseren.|r")
    end
  end
  if feilet > 0 then
    NLC.Utils.Print("|cffff8800" .. feilet .. " item(s) kunne ikke vises. Resten kan du svare paa som vanlig.|r")
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
    -- Live per-item response counter (officer only)
    if NLC.isOfficer then
      for _, session in ipairs(sessions) do
        local rd = itemRows[session.sessionIdx]
        if rd and rd.respFS then
          rd.respFS:SetText(T.MUTED .. NLC.Council.GetResponseCount(session.sessionIdx) .. " svar|r")
        end
      end
    end
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

-- Radbredde er smalere enn panelet: scrollbaren tar plassen til hoeyre.
local ROW_W, ROW_H, MAX_ROWS = 440, 44, 8

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
  local synlige = math.max(1, math.min(count, MAX_ROWS))
  lootPanel:SetHeight(118 + synlige * ROW_H)
  lootPanel.content:SetHeight(math.max(1, count) * ROW_H)
  lootPanel.scroll:SetVerticalScroll(0)

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

  -- Samme vakt som i interesse-popupen: ett item som ikke lar seg tegne skal
  -- koste den raden, ikke hele panelet — og da med den er du midt i en utdeling.
  for i, item in ipairs(items) do
    local raadOk = pcall(function()
    -- Alternating row bg
    local rowBg = lootPanel.content:CreateTexture(nil, "BACKGROUND")
    rowBg:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    rowBg:SetSize(ROW_W, ROW_H)
    rowBg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
    rowBg:Show()

    local row = CreateFrame("Frame", nil, lootPanel.content)
    row:SetSize(ROW_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:Show()

    -- Item icon
    local icon = T.CreateItemIcon(row, 32)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetItem(item.itemLink)

    -- Item text (shifted right of the icon)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 46, 6)
    text:SetWidth(ROW_W - 190)
    text:SetJustifyH("LEFT")
    -- Blå skrift på det som er fanget opp automatisk, så raden skiller seg fra
    -- kvalitetsfargen items ellers har i spillet.
    local itemLabel = (T.Recolor(item.itemLink, T.BLUE) or "?")
      .. "  " .. T.MUTED .. "(ilvl " .. (item.ilvl or 0) .. ")|r"
    if item.armorType then
      itemLabel = itemLabel .. "  " .. T.GOLD_DIM .. "[" .. item.armorType .. "]|r"
    end
    text:SetText(itemLabel)

    -- Looter name (under the item text)
    if item.looter then
      local looterText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      looterText:SetPoint("LEFT", 46, -10)
      looterText:SetText(T.MUTED .. "looted av " .. item.looter .. "|r")
    end

    -- «Del ut» → liste over raidet → klikk navn. To klikk, ingen tasting.
    --
    -- Gaar helt utenom councilet og comms: ingen popup hos raiderne som kan
    -- krasje, ingen svar aa vente paa. Registreringen foelger likevel med —
    -- historikk, eksport til nordavind.cc og pending trade.
    local delUt = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    delUt:SetSize(92, 22)
    delUt:SetPoint("RIGHT", -36, 0)
    delUt:SetText(T.GOLD_LIGHT .. "Del ut|r ▾")

    local function tildel(navn, kategori, eksporterbar)
      local itemId = item.itemId or C_Item.GetItemInfoInstant(item.itemLink)
      NLC.RecordAward(item.itemLink, navn, UnitName("player"),
                      item.boss or "Manuelt", kategori or "upgrade", itemId,
                      eksporterbar, nil)
      NLC.Utils.Print((item.itemLink or "?") .. " |cff33cc33->|r " .. navn)
      if NLC.Council.AnnounceRW then
        NLC.Council.AnnounceRW((item.itemLink or "?") .. " tildelt " .. navn)
      end
      NLC.LootDetection.RemoveItem(i)
      refreshLootPanel(NLC.LootDetection.GetDroppedItems())
    end

    delUt:SetScript("OnClick", function(self)
      local valg = {}
      -- Raidet, alfabetisk og klassefarget.
      local rad = {}
      for r = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
        local navn, _, _, _, _, klasse = GetRaidRosterInfo(r)
        if navn then
          table.insert(rad, { navn = navn:match("^([^-]+)") or navn, klasse = klasse })
        end
      end
      table.sort(rad, function(a, b) return a.navn < b.navn end)
      for _, m in ipairs(rad) do
        local f = NLC.Utils.CLASS_COLORS[m.klasse]
        local farge = f and string.format("|cff%02x%02x%02x", f.r * 255, f.g * 255, f.b * 255)
        table.insert(valg, {
          text = m.navn, color = farge,
          func = function() tildel(m.navn, "upgrade", true) end,
        })
      end
      if #valg == 0 then
        table.insert(valg, { title = true, text = "Ikke i raid" })
      end
      -- Maal som ikke teller som loot.
      table.insert(valg, { divider = true })
      table.insert(valg, { text = "Guildbank", color = T.MUTED,
        func = function() tildel("Guildbank", "bank", false) end })
      table.insert(valg, { text = "Disenchant", color = T.MUTED,
        func = function() tildel("Disenchant", "disenchant", false) end })
      T.ShowMenu(self, valg)
    end)

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
    end)
    if not raadOk then
      NLC.Utils.Print("|cffff8800Klarte ikke tegne raden for|r " .. tostring(item.itemLink))
      if NLC.Utils.Diag then
        NLC.Utils.Diag("Loot-panel: rad " .. i .. " feilet (" .. tostring(item.itemLink) .. ")")
      end
    end
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

    -- Content area for item rows, i en scroll-ramme.
    --
    -- Uten den vokste panelet fritt med antall items: /nordlc addall drar inn alt
    -- tradeable du har, og med femten items ble ruta høyere enn skjermen — uten
    -- noen måte å komme til radene nederst. Nå står høyden fast på MAX_ROWS rader
    -- og resten scrolles.
    lootPanel.scroll = CreateFrame("ScrollFrame", "NordavindLCLootScroll", lootPanel,
                                   "UIPanelScrollFrameTemplate")
    lootPanel.scroll:SetPoint("TOPLEFT", 15, -52)
    lootPanel.scroll:SetPoint("BOTTOMRIGHT", -34, 66)

    lootPanel.content = CreateFrame("Frame", nil, lootPanel.scroll)
    lootPanel.content:SetSize(ROW_W, 100)
    lootPanel.scroll:SetScrollChild(lootPanel.content)

    -- Start Council button (bottom, prominent)
    lootPanel.startBtn = CreateFrame("Button", nil, lootPanel, "UIPanelButtonTemplate")
    lootPanel.startBtn:SetSize(460, 38)
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
