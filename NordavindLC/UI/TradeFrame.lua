-- UI/TradeFrame.lua
-- Shows all awarded but not-yet-traded items.
-- Click "Trade" → targets winner → opens trade window → auto-adds item if possible.

local NLC = NordavindLC_NS
local T = NLC.Theme

local tradeFrame = nil
local ROW_HEIGHT = 48
local FRAME_WIDTH = 520

-- ============================================================
-- TRADE TRACKING
-- ============================================================

-- pendingTrades stored in NLC.db.pendingTrades (persists across sessions)
-- Each entry: { item, itemId, awardedTo, awardedBy, boss, category, timestamp }

function NLC.Trade.Add(itemLink, itemId, awardedTo, awardedBy, boss, category)
  NLC.db.pendingTrades = NLC.db.pendingTrades or {}
  table.insert(NLC.db.pendingTrades, {
    item = itemLink,
    itemId = itemId,
    awardedTo = awardedTo,
    awardedBy = awardedBy,
    boss = boss or "Unknown",
    category = category or "upgrade",
    timestamp = time(),
  })
end

function NLC.Trade.Remove(index)
  NLC.db.pendingTrades = NLC.db.pendingTrades or {}
  table.remove(NLC.db.pendingTrades, index)
end

function NLC.Trade.GetPending()
  NLC.db.pendingTrades = NLC.db.pendingTrades or {}
  return NLC.db.pendingTrades
end

-- Find item in player's bags by itemId
local function FindItemInBags(itemId)
  for bag = 0, 4 do
    local numSlots = C_Container.GetContainerNumSlots(bag)
    for slot = 1, numSlots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == itemId then
        return bag, slot
      end
    end
  end
  return nil, nil
end

-- Try to initiate trade with a player
local function InitiateTradeWith(playerName, itemId)
  -- Find unit in raid
  local unit = nil
  for i = 1, GetNumGroupMembers() do
    local name = GetRaidRosterInfo(i)
    if name then
      local shortName = name:match("^([^-]+)") or name
      if shortName == playerName then
        unit = "raid" .. i
        break
      end
    end
  end

  if not unit then
    NLC.Utils.Print("Finner ikke " .. playerName .. " i raidet.")
    return
  end

  if not CheckInteractDistance(unit, 2) then
    NLC.Utils.Print(playerName .. " er ikke i nærheten (for langt unna).")
    return
  end

  -- Store pending auto-add info
  NLC.Trade._autoAddItemId = itemId
  NLC.Trade._autoAddTarget = playerName

  InitiateTrade(unit)
end

-- ============================================================
-- TRADE EVENT LISTENER
-- ============================================================

local tradeEventFrame = CreateFrame("Frame")
tradeEventFrame:RegisterEvent("TRADE_SHOW")
tradeEventFrame:RegisterEvent("TRADE_CLOSED")
tradeEventFrame:RegisterEvent("UI_INFO_MESSAGE")

tradeEventFrame:SetScript("OnEvent", function(self, event, ...)
  if event == "TRADE_SHOW" then
    -- Try to auto-add item to trade window
    if NLC.Trade._autoAddItemId then
      local bag, slot = FindItemInBags(NLC.Trade._autoAddItemId)
      if bag and slot then
        -- Pick up item and place in trade slot
        C_Timer.After(0.3, function()
          C_Container.PickupContainerItem(bag, slot)
          ClickTradeButton(1) -- Place in first trade slot
        end)
        NLC.Utils.Print("Item lagt til i trade automatisk.")
      else
        NLC.Utils.Print("Fant ikke itemet i bags — dra det manuelt.")
      end
    end

  elseif event == "TRADE_CLOSED" then
    NLC.Trade._autoAddItemId = nil
    NLC.Trade._autoAddTarget = nil

  elseif event == "UI_INFO_MESSAGE" then
    local _, msg = ...
    if msg and (msg == ERR_TRADE_COMPLETE or (type(msg) == "string" and msg:find("Trade complete"))) then
      -- Trade completed — check if any pending trade items were traded
      local target = NLC.Trade._autoAddTarget
      if target then
        local pending = NLC.Trade.GetPending()
        for i = #pending, 1, -1 do
          if pending[i].awardedTo == target then
            NLC.Utils.Print("Trade fullført: " .. (pending[i].item or "?") .. " til " .. target)
            NLC.Trade.Remove(i)
            break
          end
        end
        -- Refresh UI if open
        if tradeFrame and tradeFrame:IsShown() then
          NLC.UI.ShowTradeFrame()
        end
      end
      NLC.Trade._autoAddItemId = nil
      NLC.Trade._autoAddTarget = nil
    end
  end
end)

-- ============================================================
-- TRADE FRAME UI
-- ============================================================

local function refreshTradeFrame()
  if not tradeFrame then return end

  -- Clear previous rows
  for _, child in ipairs({ tradeFrame.content:GetChildren() }) do child:Hide() end
  for _, region in ipairs({ tradeFrame.content:GetRegions() }) do region:Hide() end

  local pending = NLC.Trade.GetPending()
  local count = #pending

  if count == 0 then
    tradeFrame:SetHeight(140)
    local empty = tradeFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetText(T.MUTED .. "Ingen items venter på trade.|r")
    empty:Show()
    return
  end

  tradeFrame:SetHeight(math.min(100 + count * ROW_HEIGHT, 500))

  for i, entry in ipairs(pending) do
    local rowBg = tradeFrame.content:CreateTexture(nil, "BACKGROUND")
    rowBg:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    rowBg:SetSize(FRAME_WIDTH - 40, ROW_HEIGHT)
    rowBg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
    rowBg:Show()

    local row = CreateFrame("Frame", nil, tradeFrame.content)
    row:SetSize(FRAME_WIDTH - 40, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:Show()

    -- Item link
    local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemText:SetPoint("LEFT", 12, 8)
    itemText:SetWidth(280)
    itemText:SetJustifyH("LEFT")
    itemText:SetText(entry.item or "?")

    -- Item tooltip
    if entry.item then
      local hover = CreateFrame("Frame", nil, row)
      hover:SetSize(280, 20)
      hover:SetPoint("LEFT", 12, 8)
      hover:EnableMouse(true)
      hover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(entry.item)
        GameTooltip:Show()
      end)
      hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Awarded to
    local toText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toText:SetPoint("LEFT", 12, -8)
    toText:SetText(T.MUTED .. "Til:|r " .. (entry.awardedTo or "?") .. "  " .. T.MUTED .. "(" .. (entry.category or "?") .. ")|r")

    -- Trade button
    local tradeBtn = T.CreateButton(row, 80, 32, T.GREEN .. "Trade|r")
    tradeBtn:SetPoint("RIGHT", -12, 0)
    tradeBtn:SetScript("OnClick", function()
      InitiateTradeWith(entry.awardedTo, entry.itemId)
    end)

    -- Endre button — edit recipient / category
    local editBtn = T.CreateButton(row, 70, 32, T.GOLD .. "Endre|r")
    editBtn:SetPoint("RIGHT", -96, 0)
    local capturedEntry = entry
    local capturedIdx   = i
    editBtn:SetScript("OnClick", function()
      NLC.UI.ShowEditPopup(capturedEntry, function(newRecipient, newCategory)
        NLC.History.ApplyAwardEdit(capturedEntry, newRecipient, newCategory)
        capturedEntry.awardedTo = newRecipient
        capturedEntry.category  = newCategory
        refreshTradeFrame()
      end)
    end)

    -- Remove button (X) — manually mark as done
    local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
    removeBtn:SetSize(22, 22)
    removeBtn:SetPoint("RIGHT", -172, 0)
    removeBtn:SetScript("OnClick", function()
      NLC.Trade.Remove(capturedIdx)
      refreshTradeFrame()
    end)
  end
end

function NLC.UI.ShowTradeFrame()
  if not tradeFrame then
    tradeFrame = CreateFrame("Frame", "NordavindLCTradeFrame", UIParent, "BackdropTemplate")
    tradeFrame:SetSize(FRAME_WIDTH, 200)
    tradeFrame:SetPoint("CENTER")
    tradeFrame:SetMovable(true)
    tradeFrame:EnableMouse(true)
    tradeFrame:RegisterForDrag("LeftButton")
    tradeFrame:SetScript("OnDragStart", tradeFrame.StartMoving)
    tradeFrame:SetScript("OnDragStop", tradeFrame.StopMovingOrSizing)
    tradeFrame:SetFrameStrata("DIALOG")
    T.ApplyBackdrop(tradeFrame)

    T.CreateTitleBar(tradeFrame, "Trades")
    tradeFrame.title:SetText(T.GOLD .. "Pending Trades|r")

    local closeBtn = CreateFrame("Button", nil, tradeFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    tradeFrame.content = CreateFrame("Frame", nil, tradeFrame)
    tradeFrame.content:SetPoint("TOPLEFT", 15, -42)
    tradeFrame.content:SetPoint("RIGHT", -15, 0)
    tradeFrame.content:SetHeight(400)
  end

  refreshTradeFrame()
  tradeFrame:Show()
end

function NLC.UI.HideTradeFrame()
  if tradeFrame then tradeFrame:Hide() end
end
