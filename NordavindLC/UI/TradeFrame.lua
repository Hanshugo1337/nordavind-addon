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

-- Finn et item i baggen paa itemId.
--
-- `brukte` er slots som allerede ligger i handelsvinduet, paa formen
-- {["0:3"] = true}. De MAA hoppes over: et item som er lagt i traden staar
-- fortsatt i bag-sloten sin for API-et, saa skylder du noen to eksemplarer av
-- samme item, ville et rent itemId-oppslag funnet den samme sloten begge
-- ganger — og du la ett item inn to steder.
--
-- Laaste slots hoppes ogsaa over: et item midt i en flytting kan ikke plukkes.
local function FindItemInBags(itemId, brukte)
  for bag = 0, 4 do
    local numSlots = C_Container.GetContainerNumSlots(bag)
    for slot = 1, numSlots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == itemId and not info.isLocked
         and not (brukte and brukte[bag .. ":" .. slot]) then
        return bag, slot
      end
    end
  end
  return nil, nil
end

-- Try to initiate trade with a player
local function InitiateTradeWith(playerName)
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
  -- UnitInRange var neste forsoek, og den doede ogsaa — paa en styggere maate.
  -- Fra 12.0 returnerer den en SECRET BOOLEAN naar den kalles fra addon-kode.
  -- Et secret value kan ikke testes: baade `if x then` og `x == false` kaster
  -- «attempt to perform boolean test ... while execution tainted». Feilen traff
  -- oss midt i raid 26.08, og den er verre enn den ser ut — her stod testen rett
  -- FOER InitiateTrade, saa en kastet feil betyr at handelen aldri starter.
  --
  -- Det finnes ingen tredje avstands-API vi har lov til aa lese. Vi maaler derfor
  -- ikke lenger avstand i det hele tatt. Det koster en advarsel og redder
  -- utdelinga, og det foelger regelen fra forrige runde: en avstandsmaaling skal
  -- aldri staa mellom deg og en utdeling.

  -- Hele gjelda til denne personen, ikke bare den raden du trykket paa.
  -- Sortert med kortest handelstid foerst: har du mer enn seks utestaaende,
  -- skal de som holder paa aa loepe ut vaere de som faktisk blir med.
  NLC.Trade._autoAddItems = NLC.Trade.PendingFor(playerName)
  NLC.Trade._autoAddTarget = playerName

  InitiateTrade(unit)
end

--- Alt vi skylder én person, kortest handelstid foerst.
function NLC.Trade.PendingFor(playerName)
  local ut = {}
  for _, p in ipairs(NLC.Trade.GetPending()) do
    if p.awardedTo == playerName then table.insert(ut, p) end
  end
  table.sort(ut, function(a, b)
    return (a._tradeSec or math.huge) < (b._tradeSec or math.huge)
  end)
  return ut
end

--- Aapne handel med en spiller og legg inn alt vi skylder ham.
-- Eksponert saa knappen i lista og testriggen gaar samme vei inn.
function NLC.Trade.StartTradeWith(playerName)
  return InitiateTradeWith(playerName)
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

-- 12.0 gjorde mottakernavnet til et SECRET STRING.
--
-- TradeFrameRecipientNameText:GetText() svarer fortsatt, men verdien kan ikke
-- roeres av addon-kode: `navn == ""` kastet «attempt to compare local navn
-- (a secret string value, while execution tainted by NordavindLC)» — ni ganger
-- paa rad, midt i raid 26.08. Det samme gjelder gsub og match.
--
-- Vi kan ikke vite paa forhaand hvilke operasjoner spillet tillater paa en
-- secret verdi, og reglene har endret seg to ganger paa én kveld. Derfor
-- isolerer vi hvert forsoek i pcall i stedet for aa gjette: virker det, bruker
-- vi navnet; kaster det, gaar vi videre til neste kilde. En feillest mottaker
-- skal aldri ta ned handelen.
-- 12.0 gir oss `issecretvalue` — spoer, ikke gjett.
--
-- pcall fanger kun de kallene som KASTER. Et secret value som lar seg lese, men
-- ikke sammenligne senere, slipper gjennom en pcall og gir feil mottaker — og
-- da fjernes feil gjeld hos feil person. Det er verre enn aa ikke vite noe.
-- BugGrabber og RCLootCouncil spoer denne foer de roerer verdien; det gjoer vi
-- ogsaa naa. Finnes den ikke (eldre klient), er svaret nei og pcall-ene under
-- er fortsatt sikkerhetsnettet.
local function erHemmelig(v)
  local f = _G.issecretvalue
  if not f then return false end
  local ok, res = pcall(f, v)
  return ok and res == true
end

local function renskNavn(n)
  if erHemmelig(n) then return nil end
  if type(n) ~= "string" or n == "" then return nil end
  -- «Navn(*)» betyr cross-realm. Kutt merket, behold navnet.
  n = n:gsub("%(%*%)%s*$", "")
  return (n:match("^([^-]+)") or n)
end

local function lesMottaker()
  -- 1: Blizzards handelsvindu. Foerstevalget naar det er lesbart.
  local ok, navn = pcall(function()
    local fs = _G.TradeFrameRecipientNameText
    return renskNavn(fs and fs.GetText and fs:GetText())
  end)
  if ok and navn then return navn end

  -- 2: unit-token-en for handelspartneren. Egen pcall — den kan vaere stengt
  -- uavhengig av den over.
  local ok2, navn2 = pcall(function()
    return renskNavn(UnitName("NPC"))
  end)
  if ok2 and navn2 then return navn2 end

  -- 3: GUID-en. Denne staar her fordi de to over deler skjebne: begge leser en
  -- STRENG fra spillet, og 12.0 har stengt tre navne- og avstands-API-er paa
  -- like mange maaneder. En GUID er en annen datatype og gaar en annen vei inn
  -- — BugGrabber og BigWigs bruker GetPlayerInfoByGUID fritt, ogsaa i 12.0.
  local ok3, navn3 = pcall(function()
    local guid = _G.UnitGUID and _G.UnitGUID("NPC")
    if not guid or erHemmelig(guid) then return nil end
    if not _G.GetPlayerInfoByGUID then return nil end
    local _, _, _, _, _, navnet = _G.GetPlayerInfoByGUID(guid)
    return renskNavn(navnet)
  end)
  if ok3 and navn3 then return navn3 end

  -- 4: ingen lesbar kilde. Kallstedet faller tilbake paa _autoAddTarget —
  -- navnet vi selv startet handelen med.
  return nil
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

    -- Ingen av de fire kildene svarte. Da BLIR raden staaende som ventende —
    -- det er riktig, vi skal ikke gjette — men offiseren maa faa vite hvorfor.
    -- Uten linja ser det ut som om addonet glemte utdelinga, og 24.08 gikk en
    -- hel kveld med paa aa lete etter en feil som ikke fantes.
    if not tradeTarget and #NLC.Trade.GetPending() > 0 then
      NLC.Utils.Print("Fikk ikke lest mottakeren i handelsvinduet — denne "
        .. "handelen blir staaende som ventende. Bruk Trade-knappen i "
        .. "loot-vinduet, saa vet vi hvem det er.")
      NLC.Utils.Diag("TRADE_SHOW: ingen lesbar mottaker (alle fire kilder tomme)")
    end

    -- Legg inn ALT vi skylder personen, ikke bare raden du trykket paa.
    --
    -- Forsinkelsen paa 0.3 s er der fordi TRADE_SHOW fyrer foer vinduet er klart
    -- til aa ta imot. Den trengs kun én gang; selve plasseringene gaar i strekk
    -- etterpaa, slik RCLootCouncil ogsaa gjoer det.
    local liste = NLC.Trade._autoAddItems
    if liste and #liste > 0 then
      C_Timer.After(0.3, function()
        local maksSlots = (_G.MAX_TRADE_ITEMS or 7) - 1  -- siste byttes ikke
        local brukte = {}      -- bag-slots som alt ligger i vinduet
        local lagtInn, mangler = 0, {}

        for _, entry in ipairs(liste) do
          if lagtInn >= maksSlots then break end
          local bag, slot = FindItemInBags(entry.itemId, brukte)
          if bag and slot then
            -- ClearCursor foerst: henger noe paa musepekeren, feiler
            -- plasseringen stille og du staar igjen med et halvfylt vindu.
            ClearCursor()
            C_Container.PickupContainerItem(bag, slot)
            lagtInn = lagtInn + 1
            ClickTradeButton(lagtInn)
            brukte[bag .. ":" .. slot] = true
          else
            table.insert(mangler, entry.item or "?")
          end
        end

        if lagtInn > 0 then
          NLC.Utils.Print(lagtInn .. " item(s) lagt i handelen automatisk.")
        end
        local igjen = #liste - lagtInn - #mangler
        if igjen > 0 then
          NLC.Utils.Print("|cffff8800" .. igjen .. " til venter — vinduet tar " ..
                          maksSlots .. ". Ta en runde til.|r")
        end
        for _, navn in ipairs(mangler) do
          NLC.Utils.Print("|cffff4444Fant ikke i baggen:|r " .. navn .. " — dra det manuelt.")
        end
      end)
    end

  elseif event == "TRADE_CLOSED" then
    NLC.Trade._autoAddItems = nil
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

    NLC.Trade._autoAddItems = nil
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

    -- Avstandsindikatoren er FJERNET, ikke glemt.
    --
    -- Den bygde paa UnitInRange, som fra 12.0 gir en secret boolean til
    -- addon-kode. `if iNaerheten then` paa denne linja kastet feil og avbrot
    -- hele raden — med elleve ventende trades ble vinduet ubrukelig midt i
    -- raid 26.08. CheckInteractDistance (protected) og UnitInRange (secret) var
    -- de to veiene vi hadde; begge er stengt, og vi har ingen tredje.
    --
    -- Raden viser heller ingen avstand enn aa risikere at den ikke vises.

    -- Trade-knappen tar HELE gjelda til personen, ikke bare denne raden.
    -- Antallet staar i teksten, saa det er tydelig foer du trykker at det
    -- kommer tre items i vinduet og ikke ett.
    local antall = #NLC.Trade.PendingFor(entry.awardedTo)
    local tekst = antall > 1 and (T.GREEN .. "Trade (" .. antall .. ")|r")
                             or (T.GREEN .. "Trade|r")
    local tradeBtn = T.CreateButton(row, 80, 32, tekst)
    tradeBtn:SetPoint("RIGHT", -12, 0)
    tradeBtn:SetScript("OnClick", function()
      InitiateTradeWith(entry.awardedTo)
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
