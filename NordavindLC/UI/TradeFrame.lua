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

  -- CheckInteractDistance er PROTECTED. Kallet blokkeres for addons
  -- (ADDON_ACTION_BLOCKED i BugGrabber 2026-05-06) og returnerer nil — og siden
  -- «not nil» er sant, sa denne sjekken ALLTID «for langt unna» og nektet aa
  -- starte handelen. Funksjonen var i praksis doed.
  --
  -- UnitInRange er ikke protected (aatte andre addons i klienten bruker den).
  -- Den er grovere — rundt 40 yards mot handelens ~11 — saa den duger til aa
  -- advare, ikke til aa nekte. Vi advarer og lar deg proeve uansett: en feil
  -- avstandsmaaling skal aldri staa mellom deg og en utdeling.
  if type(UnitInRange) == "function" then
    local iNaerheten = UnitInRange(unit)
    if iNaerheten == false then
      NLC.Utils.Print(playerName .. " ser ut til aa vaere langt unna — proever likevel.")
    end
  end

  -- Store pending auto-add info
  NLC.Trade._autoAddItemId = itemId
  NLC.Trade._autoAddTarget = playerName

  InitiateTrade(unit)
end

-- ============================================================
-- TRADE EVENT LISTENER
-- ============================================================

-- ============================================================
-- Varsel om handelstid som holder paa aa loepe ut
--
-- Handelstida er to timer. Gaar den ut, sitter itemet fast hos feil person for
-- godt — det finnes ingen vei tilbake. I dag viste vi nedtellingen KUN mens
-- trade-vinduet sto aapent, og midt i et raid staar det lukket. 19.08 laa det
-- foerti uutdelte items i baggen samtidig; ingenting ville sagt fra.
--
-- Terskelen og sperren mot spam foelger samme tanke som RCLootCouncil: varsle i
-- god tid, men ikke mer enn én gang i kvarteret, og aldri midt i en pull. Det
-- siste er hele grunnen til at vi lytter paa PLAYER_REGEN_ENABLED: kommer
-- varselet mens du kjemper, er det bare stoey — vi venter til kampen er over.
-- ============================================================
local VARSEL_TERSKEL = 1200   -- 20 minutter igjen
local VARSEL_PAUSE   = 900    -- ikke oftere enn hvert kvarter
local sisteVarsel = 0

function NLC.Trade.CheckExpiring(tvunget)
  local pending = NLC.Trade.GetPending()
  if #pending == 0 then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if not tvunget and (GetTime() - sisteVarsel) < VARSEL_PAUSE then return end

  local haster = {}
  for _, entry in ipairs(pending) do
    local bag, slot = FindItemInBags(entry.itemId)
    if bag and slot then
      local sek = NLC.Utils.GetBagItemTradeSeconds(bag, slot)
      if sek and sek > 0 and sek < VARSEL_TERSKEL then
        table.insert(haster, { entry = entry, sek = sek })
      end
    end
  end
  if #haster == 0 then return end

  table.sort(haster, function(a, b) return a.sek < b.sek end)
  NLC.Utils.Print("|cffff4444Handelstida loeper ut paa " .. #haster ..
                  " item(s):|r")
  for _, h in ipairs(haster) do
    local min = math.floor(h.sek / 60)
    NLC.Utils.Print(string.format("  %s -> %s (|cffff8800%d min igjen|r)",
      h.entry.item or "?", h.entry.awardedTo or "?", min))
  end
  NLC.Utils.Print("  /nordlc trade for aa handle dem ut.")
  sisteVarsel = GetTime()
end

-- Hvem handler vi med, og hva ligger faktisk i vinduet?
--
-- Tre feil laa her, alle synlige i gaar da hele raidets loot ble delt ut
-- manuelt:
--
--   1. Mottakeren ble kun kjent naar handelen var startet fra VAART vindu
--      (`_autoAddTarget`). Trader du noen ved aa hoeyreklikke dem, visste vi
--      ingenting — og de itemene ble staaende i «venter paa trade» for alltid.
--   2. Vi fjernet den FOERSTE pending-oppfoeringen for personen, uansett hva som
--      faktisk laa i vinduet. Skylder du tre items og gir ett, forsvant feil rad.
--   3. Cross-realm viser navnet som «Navn(*)» i handelsvinduet.
--
-- Loesningen er den samme som RCLootCouncil bruker: les mottakeren fra Blizzards
-- eget handelsvindu, og fang hva som ligger i slottene paa TRADE_ACCEPT_UPDATE —
-- det er siste oeyeblikk der innholdet er kjent foer handelen lukkes.
local tradeTarget = nil
local itemsInTrade = {}

local function lesMottaker()
  local fs = _G.TradeFrameRecipientNameText
  local navn = fs and fs.GetText and fs:GetText()
  if not navn or navn == "" then
    navn = UnitName("NPC")
  end
  if type(navn) ~= "string" or navn == "" then return nil end
  -- «Navn(*)» betyr cross-realm. Kutt merket, behold navnet.
  navn = navn:gsub("%(%*%)%s*$", "")
  return (navn:match("^([^-]+)") or navn)
end

local tradeEventFrame = CreateFrame("Frame")
tradeEventFrame:RegisterEvent("TRADE_SHOW")
tradeEventFrame:RegisterEvent("TRADE_CLOSED")
tradeEventFrame:RegisterEvent("TRADE_ACCEPT_UPDATE")
tradeEventFrame:RegisterEvent("UI_INFO_MESSAGE")
-- Ute av kamp: da er det trygt aa si fra om handelstid som loeper ut.
tradeEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Fast puls i tillegg, saa varselet ikke avhenger av at du nettopp var i kamp.
C_Timer.NewTicker(60, function() NLC.Trade.CheckExpiring() end)

tradeEventFrame:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_REGEN_ENABLED" then
    -- Rett etter en pull er du som regel i ferd med aa dele ut. Sjekk med én
    -- gang, framfor aa vente paa neste puls.
    C_Timer.After(2, function() NLC.Trade.CheckExpiring() end)
    return
  end

  if event == "TRADE_ACCEPT_UPDATE" then
    -- Fyres naar en av partene trykker godta. Naa — og bare naa — vet vi hva som
    -- faktisk ligger i vinduet.
    local megOk, hanOk = ...
    if megOk == 1 or hanOk == 1 then
      itemsInTrade = {}
      local maks = (_G.MAX_TRADE_ITEMS or 7) - 1 -- siste slotten byttes ikke
      for i = 1, maks do
        local link = GetTradePlayerItemLink and GetTradePlayerItemLink(i)
        if link then table.insert(itemsInTrade, link) end
      end
    end
    return
  end

  if event == "TRADE_SHOW" then
    tradeTarget = lesMottaker() or NLC.Trade._autoAddTarget
    itemsInTrade = {}

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
    tradeTarget = nil
    itemsInTrade = {}

  elseif event == "UI_INFO_MESSAGE" then
    -- Foerste argument er meldings-ID-en, andre er teksten. Vi sjekker ID-en
    -- foerst: den er den samme uansett klientspraak.
    local id, msg = ...
    local fullfoert = (_G.LE_GAME_ERR_TRADE_COMPLETE and id == _G.LE_GAME_ERR_TRADE_COMPLETE)
      or (msg and msg == _G.ERR_TRADE_COMPLETE)
    if not fullfoert then return end

    local target = tradeTarget or NLC.Trade._autoAddTarget
    if target then
      local pending = NLC.Trade.GetPending()
      local fjernet = 0

      if #itemsInTrade > 0 then
        -- Fjern nøyaktig det som laa i vinduet. Itemnavnet er noek nok: to
        -- eksemplarer av samme item til samme person er uansett samme gjeld.
        for _, link in ipairs(itemsInTrade) do
          local navn = link:match("%[(.-)%]")
          for i = #pending, 1, -1 do
            local p = pending[i]
            if p.awardedTo == target and navn
               and p.item and p.item:find(navn, 1, true) then
              NLC.Utils.Print("Trade fullført: " .. (p.item or "?") .. " til " .. target)
              NLC.Trade.Remove(i)
              fjernet = fjernet + 1
              break
            end
          end
        end
      end

      -- Fanget vi ikke innholdet (f.eks. handelen gikk uten at vi saa
      -- TRADE_ACCEPT_UPDATE), faller vi tilbake til én oppfoering — som foer.
      if fjernet == 0 then
        for i = #pending, 1, -1 do
          if pending[i].awardedTo == target then
            NLC.Utils.Print("Trade fullført: " .. (pending[i].item or "?") .. " til " .. target)
            NLC.Trade.Remove(i)
            break
          end
        end
      end

      if tradeFrame and tradeFrame:IsShown() then
        NLC.UI.ShowTradeFrame()
      end
    end

    NLC.Trade._autoAddItemId = nil
    NLC.Trade._autoAddTarget = nil
    tradeTarget = nil
    itemsInTrade = {}
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

  -- Estimate remaining trade time per entry and sort ascending (most urgent first).
  for _, entry in ipairs(pending) do
    local bag, slot = FindItemInBags(entry.itemId)
    entry._tradeSec = (bag and slot) and NLC.Utils.GetBagItemTradeSeconds(bag, slot) or nil
  end
  table.sort(pending, function(a, b)
    return (a._tradeSec or math.huge) < (b._tradeSec or math.huge)
  end)

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

    -- Item icon
    local icon = T.CreateItemIcon(row, 34)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetItem(entry.item)

    -- Item link (shifted right of the icon)
    local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemText:SetPoint("LEFT", 48, 8)
    itemText:SetWidth(250)
    itemText:SetJustifyH("LEFT")
    itemText:SetText(entry.item or "?")

    -- Item tooltip
    if entry.item then
      local hover = CreateFrame("Frame", nil, row)
      hover:SetSize(250, 20)
      hover:SetPoint("LEFT", 48, 8)
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
    toText:SetPoint("LEFT", 48, -8)
    toText:SetText(T.MUTED .. "Til:|r " .. (entry.awardedTo or "?") .. "  " .. T.MUTED .. "(" .. (entry.category or "?") .. ")|r")

    -- Trade-timer countdown badge (right of the item line, left of the buttons)
    local badge = T.CreateTimerBadge(row)
    badge:SetPoint("RIGHT", -200, 8)
    badge:SetSeconds(entry._tradeSec)

    -- Distance indicator (mockup: "I nærheten" / "For langt")
    local distText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    distText:SetPoint("RIGHT", -200, -8)
    local unit = nil
    if IsInRaid() then
      for r = 1, GetNumGroupMembers() do
        local n = GetRaidRosterInfo(r)
        if n and (n:match("^([^-]+)") or n) == entry.awardedTo then unit = "raid" .. r; break end
      end
    end
    -- Samme grunn som over: CheckInteractDistance er protected og svarer nil,
    -- saa denne indikatoren sto permanent paa «For langt».
    local iNaerheten = unit and type(UnitInRange) == "function" and UnitInRange(unit)
    if iNaerheten then
      distText:SetText(T.GREEN .. "• I nærheten|r")
    elseif unit then
      distText:SetText(T.MUTED .. "• Langt unna|r")
    end

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

  -- Trade timers count down — refresh every 30s while the window is open.
  if not tradeFrame._ticker then
    tradeFrame._ticker = C_Timer.NewTicker(30, function()
      if tradeFrame and tradeFrame:IsShown() then
        refreshTradeFrame()
      end
    end)
  end
end

function NLC.UI.HideTradeFrame()
  if tradeFrame then tradeFrame:Hide() end
end
