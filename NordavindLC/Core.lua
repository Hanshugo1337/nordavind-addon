-- Core.lua
-- Main addon initialization, SavedVariables, slash commands

local ADDON_NAME = ...
local NLC = NordavindLC_NS

-- Version from TOC
NLC.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"

-- State
NLC.active = false
NLC.isOfficer = false
NLC.db = {}
NLC.importData = {}
NLC.pendingSessions = {}

local function GetLastWednesdayResetUTC()
  -- Spør spillet framfor å regne. Resetten er onsdag 07:00 lokal servertid,
  -- altså 06:00 UTC om vinteren og 05:00 UTC om sommeren — en hardkodet
  -- UTC-time er riktig maks halve året. C_DateAndTime kjenner både sommertid
  -- og region, så den er autoritativ.
  if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
    local secs = C_DateAndTime.GetSecondsUntilWeeklyReset()
    if secs and secs > 0 then
      return time() + secs - 7 * 86400
    end
  end

  -- Fallback hvis API-et mangler: onsdag 06:00 UTC. Kan ligge én time feil i
  -- sommerhalvåret, men brukes kun til å avgjøre om telleren skal nullstilles.
  -- Epoch (Jan 1 1970) was Thursday. First Wednesday = Jan 7 1970 = day 6.
  local FIRST_RESET = 6 * 86400 + 6 * 3600  -- 540000
  local WEEK = 7 * 86400
  local now = time()
  local weeksSince = math.floor((now - FIRST_RESET) / WEEK)
  return FIRST_RESET + weeksSince * WEEK
end

-- Testmodus har ingenting i et raid aa gjoere.
--
-- /nordlc test og /nordlc testloot setter active for at utdelingsknappene skal
-- kunne oeves solo. Flagget ble aldri ryddet, saa det fulgte med inn i neste
-- raid — og aktiv addon betyr auto-pass paa alt. Den klienten satt da og passet
-- i en pug uten at eieren hadde bedt om noe.
local function ryddTestmodus()
  if NLC.testMode and IsInRaid() then
    NLC.Deactivate()
    NLC.Utils.Print("Testmodus avsluttet — du kom i et raid.")
  end
end

-- Initialize
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PARTY_LEADER_CHANGED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    NordavindLC_DB = NordavindLC_DB or {
      importData = { players = {} },
      lootHistory = {},
      config = { officers = {}, timer = 90 },
      pendingExport = {},
      pendingTrades = {},
      pendingEdits = {},
      weeklyLoot = { resetTimestamp = 0, counts = {} },
    }
    NordavindLC_DB.pendingTrades = NordavindLC_DB.pendingTrades or {}
    NordavindLC_DB.pendingEdits  = NordavindLC_DB.pendingEdits  or {}
    NordavindLC_DB.weeklyLoot    = NordavindLC_DB.weeklyLoot    or { resetTimestamp = 0, counts = {} }
    NordavindLC_DB.config        = NordavindLC_DB.config        or {}
    NordavindLC_DB.config.timer  = math.max(NordavindLC_DB.config.timer or 90, 90)
    NLC.db = NordavindLC_DB

    if NordavindLC_Import and NordavindLC_Import.players then
      NLC.db.importData = NLC.Utils.DeepCopy(NordavindLC_Import)
      NLC.Utils.Print("Import data loaded (" .. NLC.Utils.TableCount(NLC.db.importData.players) .. " players)")
    end

    -- Always register comms so we can receive ACTIVATE from leader
    NLC.Comms.Register()
    NLC.Utils.Print("Loaded. Use /nordlc for commands.")

  elseif event == "PLAYER_ENTERING_WORLD" or event == "PARTY_LEADER_CHANGED" then
    ryddTestmodus()
    if IsInRaid() and not NLC.active then
      C_Timer.After(2, function()
        if IsInRaid() and not NLC.active then
          if UnitIsGroupLeader("player") then
            NLC.UI.ShowActivationPrompt()
          else
            -- Raider: poll for activation every 5s until activated (max 60s)
            NLC.Comms.Send("ACTIVATE_CHECK", "")
            if NLC._activateTicker then NLC._activateTicker:Cancel() end
            NLC._activateTicker = C_Timer.NewTicker(5, function(ticker)
              if NLC.active or not IsInRaid() then
                ticker:Cancel()
                NLC._activateTicker = nil
                return
              end
              NLC.Comms.Send("ACTIVATE_CHECK", "")
            end, 12)
          end
        end
      end)
    end
    -- Deactivate when leaving raid
    if not IsInRaid() and NLC.active then
      NLC.Deactivate()
      NLC.Utils.Print("Deaktivert (forlot raid).")
    end
    -- Weekly loot reset check (onsdag 07:00 lokal servertid — se funksjonen)
    local lastReset = GetLastWednesdayResetUTC()
    if NLC.db.weeklyLoot.resetTimestamp < lastReset then
      NLC.db.weeklyLoot.counts = {}
      NLC.db.weeklyLoot.resetTimestamp = lastReset
      NLC.Utils.Print("Ukentlig loot-teller nullstilt.")
    end

  elseif event == "GROUP_ROSTER_UPDATE" then
    -- Blir du invitert mens du staar i byen, fyrer ikke PLAYER_ENTERING_WORLD.
    ryddTestmodus()
    -- Deactivate when no longer in raid
    if not IsInRaid() and NLC.active then
      NLC.Deactivate()
      NLC.Utils.Print("Deaktivert (forlot raid).")
    end
    -- Kun raidlederen kringkaster ACTIVATE naar rosteret endrer seg, saa en
    -- raider som logger inn eller reloader midt i kvelden blir tatt opp igjen.
    --
    -- Her sto «NLC.isOfficer or UnitIsGroupLeader», og isOfficer er billig:
    -- CheckOfficer gir den til alle som leder en vilkaarlig gruppe eller har
    -- rank <= 2 i en vilkaarlig guild. Hver aktiv officer kringkastet altsaa
    -- til alle med addonet, ogsaa i en pug. Mottakersiden slipper naa uansett
    -- bare lederen gjennom (se Comms.OnMessage), men avsenderen skal ikke sende
    -- det heller — da slipper vi aa forklare meldinger ingen skal ha.
    --
    -- Konsekvens: er council-offiseren ikke raidleder, aktiveres ingen av seg
    -- selv. Det henger sammen med resten — auto-Need og utdelingen forutsetter
    -- allerede at lederen er den som deler ut, jf. NLC.IsLootLeader.
    if NLC.active and IsInRaid() and UnitIsGroupLeader("player") then
      NLC.Comms.Send("ACTIVATE", "")
    end

  elseif event == "PLAYER_LOGOUT" then
    NordavindLC_DB = NLC.db
    -- Preserve import data so companion writes survive /reload.
    -- Without this, WoW writes nil back on every reload (in-memory state wins).
    if NLC.db.importData and NLC.db.importData.players and
       NLC.Utils.TableCount(NLC.db.importData.players) > 0 then
      NordavindLC_Import = NLC.db.importData
    end
  end
end)


-- ============================================================
-- Egen feilfangst
--
-- I går var vi avhengige av at brukeren hadde BugGrabber og at noen leste den.
-- Det er ikke en plan. Blizzard fyrer tre events når et addon gjør noe som ikke
-- er lov, og de koster ingenting å lytte på: ADDON_ACTION_BLOCKED og
-- ADDON_ACTION_FORBIDDEN (protected funksjon kalt fra addon-kode — akkurat det
-- som gjorde trade-vinduet dødt uten en eneste synlig feilmelding), og
-- LUA_WARNING.
--
-- Vi logger kun det som nevner oss, og hver melding én gang. Uten dedupen ville
-- ett blokkert kall i en OnUpdate spist hele diagnoseloggen.
-- ============================================================
local feilRamme = CreateFrame("Frame")
local sett = {}

local function fangFeil(_, event, ...)
  local tekst = table.concat({ tostring(event), ... }, " ")
  if not tekst:find("NordavindLC", 1, true) then return end
  if sett[tekst] then return end
  sett[tekst] = true
  if NLC.Utils and NLC.Utils.Diag then
    NLC.Utils.Diag("FEIL: " .. tekst:sub(1, 300))
  end
end

for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "LUA_WARNING" }) do
  pcall(function() feilRamme:RegisterEvent(e) end)
end
feilRamme:SetScript("OnEvent", fangFeil)

--- Ekte officer — UTEN snarveien for gruppeleder.
--
-- `NLC.isOfficer` er sann for den som er gruppeleder in-game, uansett rank.
-- Det er greit for det meste, men ikke for aa starte et council: gir du lead
-- til en raider for én pull, ville han ellers kunne dratt i gang loot-councilet
-- for hele raidet.
--
-- rankIndex fra GetGuildInfo er 0-basert: 0 = Guild Master, 1 og 2 = de to
-- rangene som begge heter «Officer», 3 = Officer Alt. Derfor <= 2. Blir en
-- ekte officer nektet, er det denne linja som skal sjekkes foerst.
function NLC.ErEkteOfficer()
  local name = UnitName("player")
  for _, officer in ipairs(NLC.db.config.officers or {}) do
    if officer == name then return true end
  end
  local _, _, rankIndex = GetGuildInfo("player")
  if rankIndex and rankIndex <= 2 then return true end
  return false
end

function NLC.CheckOfficer()
  -- Raid leader always gets officer access
  if UnitIsGroupLeader("player") then NLC.isOfficer = true; return true end
  if NLC.ErEkteOfficer() then NLC.isOfficer = true; return true end
  NLC.isOfficer = false
  return false
end

-- AddonCompartment handles the minimap icon via TOC fields

-- AddonCompartment (minimap addon menu) handlers
function NordavindLC_OnAddonCompartmentClick(_, button)
  if button == "LeftButton" then
    if NLC.Council.ReopenWizard and NLC.Council.ReopenWizard() then
      -- reopened active council
    elseif #NLC.pendingSessions > 0 then
      SlashCmdList["NORDLC"]("pending")
    else
      SlashCmdList["NORDLC"]("status")
    end
  elseif button == "RightButton" then
    if NLC.active then
      NLC.Deactivate()
    else
      NLC.AktiverManuelt()
    end
  end
end

function NordavindLC_OnAddonCompartmentEnter(_, menuButtonFrame)
  GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
  GameTooltip:AddLine("NordavindLC", 0, 0.8, 1)
  GameTooltip:AddLine(NLC.active and "|cff00ff00Active|r" or "|cffff0000Inactive|r", 1, 1, 1)
  if NLC.isOfficer then
    GameTooltip:AddLine("Officer mode", 0.5, 1, 0.5)
  end
  local pending = #NLC.pendingSessions
  if pending > 0 then
    GameTooltip:AddLine(pending .. " pending items", 1, 0.8, 0)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Left-click: Status / Gjenåpne council", 0.6, 0.6, 0.6)
  GameTooltip:AddLine("Right-click: Activate/Deactivate", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

function NordavindLC_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end

function NLC.UpdateMinimapCount()
  -- No-op: compartment doesn't support dynamic count display
end

-- Manuell paaskruing: kun raidlederen.
--
-- Ingen andre TRENGER aa aktivere. Lederen sier ja i popupen, og resten tas av
-- ACTIVATE — enten kringkastet ved neste roster-oppdatering, eller som svar paa
-- ACTIVATE_CHECK, som hver klient sender selv ved innlogging. Lot vi kommandoen
-- staa aapen, var den bare en vei rundt lederporten i Comms: en raider som
-- skrev /nordlc activate i en pug auto-passet paa alt.
--
-- Utenfor raid slipper alle gjennom. Der finnes ingen rull aa passe paa, og
-- offiseren maa kunne aapne addonet og se over importen foer folk er invitert.
--
-- Porten gaar én vei. Deactivate er ikke gated: den som ble aktivert av lederen
-- maa alltid kunne skru av igjen.
function NLC.AktiverManuelt()
  if IsInRaid() and not UnitIsGroupLeader("player") then
    NLC.Utils.Print("Bare raidlederen aktiverer NordavindLC.")
    NLC.Utils.Print("  Du blir skrudd paa automatisk naar lederen gjoer det.")
    return false
  end
  NLC.Activate()
  return true
end

function NLC.Activate()
  NLC.active = true
  NLC.CheckOfficer()
  NLC.Comms.Register()
  NLC.LootDetection.Register()

  -- Refresh import data from the in-memory SavedVariable in case companion wrote it
  -- before this session started but after the last manual import.
  if NordavindLC_Import and NordavindLC_Import.players then
    NLC.db.importData = NLC.Utils.DeepCopy(NordavindLC_Import)
  end

  local playerCount = NLC.Utils.TableCount(NLC.db.importData and NLC.db.importData.players or {})
  NLC.Utils.Print("Aktivert! " .. (NLC.isOfficer and "(Officer mode)" or "(Raider mode)"))
  if playerCount > 0 then
    NLC.Utils.Print("|cff00ff00" .. playerCount .. " spillere lastet fra import.|r")
  else
    NLC.Utils.Print("|cffff4444Advarsel: Ingen import-data funnet!|r")
    NLC.Utils.Print("  1. Start companion-appen")
    NLC.Utils.Print("  2. Skriv |cffffffff/reload|r i WoW")
    NLC.Utils.Print("  3. Aktiver addon på nytt")
  end
end

function NLC.Deactivate()
  NLC.active = false
  NLC.testMode = false
  -- testkommandoene setter denne for aa vise utdelingsknappene solo. Ble den
  -- staaende, trodde klienten den var officer i neste raid og aggregerte
  -- LOOT_REPORT den ikke skulle sett.
  NLC.isOfficer = false
  NLC.LootDetection.Unregister()
  NLC.Utils.Print("Deactivated.")
end

-- Loot-lederen: den som faktisk deler ut. Solo er UnitIsGroupLeader alltid
-- false, så uten testMode kunne ingen av utdelingsknappene testes offline —
-- og da fanger man ingenting før man står i et raid med tjue mann.
-- Settes kun av /nordlc test, nullstilles ved Deactivate og ved ekte council.
function NLC.IsLootLeader()
  return UnitIsGroupLeader("player") or NLC.testMode == true
end

function NLC.RecordAward(item, awardedTo, awardedBy, boss, category, itemId, exportable, note)
  if exportable == nil then exportable = true end
  local entry = {
    item = item,
    awardedTo = awardedTo,
    awardedBy = awardedBy,
    boss = boss or "Unknown",
    category = category or "upgrade",
    timestamp = time(),
  }
  -- Settes kun når den finnes, så eksisterende oppføringer i SavedVariables
  -- ikke får en tom note-nøkkel de aldri hadde.
  if note and note ~= "" then entry.note = note end

  table.insert(NLC.db.lootHistory, entry)
  if exportable then
    -- Only real player awards are exported to the website. Disenchant/Bank/Free are not.
    table.insert(NLC.db.pendingExport, entry)
  end

  -- Add to pending trades (so the item can still be traded onward)
  local id = itemId or C_Item.GetItemInfoInstant(item)
  NLC.Trade.Add(item, id, awardedTo, awardedBy, boss, category)
end

SLASH_NORDLC1 = "/nordlc"
SlashCmdList["NORDLC"] = function(msg)
  local trimmed = msg:trim()
  local cmd = trimmed:match("^(%S+)") or ""
  cmd = cmd:lower()
  local arg = trimmed:match("^%S+%s+(.+)$") or ""

  if cmd == "add" then
    -- Manual council: /nordlc add [item-link]
    if not NLC.active then
      NLC.Utils.Print("Addon is not active. Use /nordlc activate first.")
      return
    end
    if not NLC.isOfficer then
      NLC.Utils.Print("Only officers can start council.")
      return
    end
    -- arg contains one or more item links (preserved case)
    local items = {}
    for itemLink in arg:gmatch("|c.-|h.-|h|r") do
      local _, _, _, ilvl, _, _, _, _, equipLoc = C_Item.GetItemInfo(itemLink)
      local itemId = C_Item.GetItemInfoInstant(itemLink)
      table.insert(items, {
        itemLink = itemLink,
        itemId = itemId or 0,
        ilvl = ilvl or 0,
        equipLoc = equipLoc or "",
        boss = "Manuelt",
      })
    end
    if #items == 0 then
      NLC.Utils.Print("Usage: /nordlc add [shift-click items here]")
      NLC.Utils.Print("  Eller /nordlc addall for alt tradeable i baggen.")
      return
    end
    NLC.Council.StartMultiSession(items, "Manuelt")
    return

  elseif cmd == "award" then
    -- Del ut uten council: /nordlc award <spiller> [shift-klikk items]
    --
    -- Councilet krever at raidernes klienter svarer. Gjoer de ikke det, staar
    -- offiseren med items i baggen og ingen maate aa registrere hvem som fikk
    -- hva — og da mister nettsida bade loot-historikk og ukesteller. Denne veien
    -- gaar utenom hele comms-kjeden: du deler ut som du vil, og skriver det inn.
    if not NLC.isOfficer then
      NLC.Utils.Print("Only officers can award.")
      return
    end
    local navn = arg:match("^(%S+)")
    local items = {}
    for itemLink in arg:gmatch("|c.-|h.-|h|r") do table.insert(items, itemLink) end

    -- Ingen lenker? Da er resten av linja et soek i baggen.
    --
    -- Med foerti uutdelte items er shift-klikking av hver enkelt uholdbart.
    -- Vi leter kun blant tradeable raid-loot (samme liste som /nordlc addall),
    -- saa et soek kan aldri treffe tilfeldig skrot i baggen.
    if navn and #items == 0 then
      local soek = arg:match("^%S+%s+(.-)%s*$")
      local GYLDIGE_KAT = { upgrade = true, catalyst = true, offspec = true, tmog = true }
      -- Kategorien staar til slutt og er ikke en del av soeketeksten.
      if soek then
        local sisteOrd = soek:match("(%S+)%s*$")
        if sisteOrd and GYLDIGE_KAT[sisteOrd:lower()] then
          soek = soek:sub(1, #soek - #sisteOrd):match("^(.-)%s*$")
        end
      end
      if soek and soek ~= "" then
        local treff = {}
        for _, it in ipairs(NLC.LootDetection.ScanBagsForPanel()) do
          local itemNavn = it.itemLink and it.itemLink:match("%[(.-)%]") or ""
          if itemNavn:lower():find(soek:lower(), 1, true) then
            table.insert(treff, it.itemLink)
          end
        end
        if #treff == 0 then
          NLC.Utils.Print("Fant ingen tradeable items som matcher «" .. soek .. "».")
          return
        end
        if #treff > 1 then
          NLC.Utils.Print("|cffff8800" .. #treff .. " items matcher «" .. soek .. "»:|r")
          for _, l in ipairs(treff) do NLC.Utils.Print("  " .. l) end
          NLC.Utils.Print("Skriv mer av navnet, eller shift-klikk itemet.")
          return
        end
        items = treff
      end
    end

    if not navn or #items == 0 then
      NLC.Utils.Print("Bruk: /nordlc award <spiller> <del av item-navnet>")
      NLC.Utils.Print("  eller /nordlc award <spiller> [shift-klikk items]")
      NLC.Utils.Print("  Legg paa offspec/tmog/catalyst til slutt ved behov.")
      return
    end
    -- Kategori kan henges paa til slutt: upgrade/catalyst/offspec/tmog.
    local GYLDIGE = { upgrade = true, catalyst = true, offspec = true, tmog = true }
    local siste = arg:match("(%S+)%s*$")
    local kategori = (siste and GYLDIGE[siste:lower()]) and siste:lower() or "upgrade"

    local boss = (NLC.LootDetection.GetCurrentBoss and NLC.LootDetection.GetCurrentBoss())
                 or "Manuelt"
    for _, link in ipairs(items) do
      local itemId = C_Item.GetItemInfoInstant(link)
      NLC.RecordAward(link, navn, UnitName("player"), boss, kategori, itemId, true, nil)
      NLC.Utils.Print(link .. " -> " .. navn .. " (" .. kategori .. ")")
      if NLC.Council.AnnounceRW then
        NLC.Council.AnnounceRW(link .. " tildelt " .. navn)
      end
    end
    NLC.Utils.Diag("/nordlc award | " .. #items .. " items -> " .. navn)
    NLC.Utils.Print("|cff33cc33" .. #items .. " registrert.|r Eksporteres til nordavind.cc ved neste synk.")
    return

  elseif cmd == "addall" then
    -- Alt tradeable i baggen, uten aa shift-klikke hvert eneste item.
    if not NLC.active then
      NLC.Utils.Print("Addon is not active. Use /nordlc activate first.")
      return
    end
    if not NLC.isOfficer then
      NLC.Utils.Print("Only officers can start council.")
      return
    end
    local funnet = NLC.LootDetection.ScanBagsForPanel()
    NLC.Utils.Diag("/nordlc addall | " .. #funnet .. " items funnet i baggen")
    if #funnet == 0 then
      NLC.Utils.Print("Fant ingen tradeable items i baggen.")
      NLC.Utils.Print("  Kun epic+ med handelstid igjen telles med.")
      NLC.Utils.Print("  /nordlc add [shift-klikk items] legger inn manuelt.")
      return
    end
    -- Panelet, ikke councilet. Du skal se over lista og kunne slette items
    -- foer noe som helst gaar ut til raidet.
    NLC.LootDetection._setDetected(funnet)
    NLC.UI.ShowLootDetected(funnet)
    NLC.Utils.Print(#funnet .. " item" .. (#funnet > 1 and "s" or "") ..
                    " lagt i panelet. Fjern med X, og trykk Start Council.")
    return

  elseif cmd == "activate" then
    NLC.AktiverManuelt()
  elseif cmd == "deactivate" then
    NLC.Deactivate()
  elseif cmd == "pending" then
    if #NLC.pendingSessions > 0 then
      for i, session in ipairs(NLC.pendingSessions) do
        NLC.Utils.Print(string.format("  %d. %s (%s) — %d interest(s)", i, session.itemLink or "?", session.boss or "?", NLC.Utils.TableCount(session.interests)))
      end
      NLC.Utils.Print("Use /nordlc resume <number> to resume.")
    else
      NLC.Utils.Print("No pending items.")
    end
  elseif cmd == "resume" then
    if arg == "all" then
      NLC.Council.ResumeAll()
    else
      local idx = tonumber(arg)
      if idx then
        NLC.Council.ResumePending(idx)
      else
        NLC.Utils.Print("Usage: /nordlc resume <number> or /nordlc resume all")
      end
    end
  elseif cmd == "council" then
    if not NLC.Council.ReopenWizard() then
      NLC.Utils.Print("Ingen aktiv council å gjenåpne.")
    end
  elseif cmd == "history" then
    NLC.UI.ShowHistoryFrame()
  elseif cmd == "trade" then
    NLC.UI.ShowTradeFrame()

  elseif cmd == "import" then
    if NordavindLC_Import and NordavindLC_Import.players then
      NLC.db.importData = NLC.Utils.DeepCopy(NordavindLC_Import)
      NLC.Utils.Print("Import oppdatert: " .. NLC.Utils.TableCount(NLC.db.importData.players) .. " spillere")
    else
      NLC.Utils.Print("|cffff4444Ingen import-data funnet.|r")
      NLC.Utils.Print("  WoW leser filen kun ved innlogging/reload.")
      NLC.Utils.Print("  1. Start companion-appen")
      NLC.Utils.Print("  2. Skriv |cffffffff/reload|r i WoW")
      NLC.Utils.Print("  3. Data lastes automatisk ved neste aktivering")
    end
  elseif cmd == "reset" then
    NLC.db.pendingTrades = {}
    NLC.Utils.Print("Pending trades cleared.")
  elseif cmd == "version" then
    if not IsInRaid() then
      NLC.Utils.Print("NordavindLC v" .. NLC.version)
      return
    end
    NLC.Utils.Print("Checking addon versions in raid...")
    NLC.versionCheckResults = {}
    -- Add own version
    local myName = UnitName("player")
    NLC.versionCheckResults[myName] = NLC.version
    NLC.Comms.Send("VERSION_CHECK", "")
    -- Collect replies for 3 seconds then show results
    C_Timer.After(3, function()
      local raidCount = GetNumGroupMembers()
      local results = NLC.versionCheckResults or {}
      local hasAddon, outdated, noAddon = {}, {}, {}
      for i = 1, raidCount do
        local name = GetRaidRosterInfo(i)
        if name then
          name = name:match("^([^-]+)") or name
          local ver = results[name]
          if ver then
            if ver == NLC.version then
              table.insert(hasAddon, "|cff00ff00" .. name .. "|r (v" .. ver .. ")")
            else
              table.insert(outdated, "|cffff8800" .. name .. "|r (v" .. ver .. " — outdated!)")
            end
          else
            table.insert(noAddon, "|cff888888" .. name .. "|r")
          end
        end
      end
      NLC.Utils.Print("--- Version Check ---")
      if #hasAddon > 0 then
        NLC.Utils.Print("|cff00ff00Current:|r " .. table.concat(hasAddon, ", "))
      end
      if #outdated > 0 then
        NLC.Utils.Print("|cffff8800Outdated:|r " .. table.concat(outdated, ", "))
      end
      if #noAddon > 0 then
        NLC.Utils.Print("|cff888888No addon:|r " .. table.concat(noAddon, ", "))
      end
      NLC.Utils.Print(string.format("Total: %d/%d have addon", #hasAddon + #outdated, raidCount))
      NLC.versionCheckResults = nil
    end)
    return

  elseif cmd == "debug" then
    NLC.LootDetection.ToggleDebug()

  elseif cmd == "diag" then
    -- Diagnoseloggen rett i chatten. SavedVariables skrives kun ved /reload,
    -- og midt i et raid er det en dyr måte å stille et spørsmål på.
    local logg = (NLC.db and NLC.db.diagLog) or {}
    if arg:lower() == "clear" then
      if NLC.db then NLC.db.diagLog = {} end
      NLC.Utils.Print("Diagnoselogg tømt.")
      return
    end
    NLC.Utils.Print("--- Diagnose ---")
    NLC.Utils.Print(string.format("Aktiv: %s | Officer: %s | I raid: %s | Leder: %s",
      tostring(NLC.active), tostring(NLC.isOfficer),
      tostring(IsInRaid()), tostring(UnitIsGroupLeader("player"))))
    local n = tonumber(arg) or 20
    local start = math.max(1, #logg - n + 1)
    if #logg == 0 then
      NLC.Utils.Print("  (loggen er tom — ingen boss eller /nordlc addall siden innlasting)")
    end
    for i = start, #logg do
      NLC.Utils.Print("  " .. logg[i])
    end
    NLC.Utils.Print(string.format("--- %d linjer totalt (/nordlc diag 50 for flere) ---", #logg))

  elseif cmd == "timer" then
    local secs = tonumber(arg)
    if secs and secs >= 30 then
      NLC.db.config.timer = secs
      NLC.Utils.Print("Timer satt til " .. secs .. " sekunder.")
    elseif secs then
      NLC.Utils.Print("Timer må være minst 30 sekunder.")
    else
      NLC.Utils.Print("Timer: " .. (NLC.db.config.timer or 90) .. " sekunder. Endre med /nordlc timer <sekunder>")
    end

  elseif cmd == "status" then
    NLC.Utils.Print(NLC.active and "Aktiv" or "Inaktiv")
    NLC.Utils.Print("Officer: " .. (NLC.isOfficer and "Ja" or "Nei"))
    NLC.Utils.Print("Import: " .. NLC.Utils.TableCount(NLC.db.importData.players or {}) .. " spillere")
    NLC.Utils.Print("Ufordelt: " .. #NLC.pendingSessions .. " items")
    NLC.Utils.Print("Pending trades: " .. #(NLC.db.pendingTrades or {}) .. " items")
    NLC.Utils.Print("Export: " .. #(NLC.db.pendingExport or {}) .. " awards")
  elseif cmd == "test" then
    NLC.isOfficer = true
    NLC.active = true
    -- Lar utdelingsknappene vises solo. Nullstilles ved Deactivate og ved
    -- ekte council, så den aldri kan henge igjen inn i et raid.
    NLC.testMode = true

    -- Mock imported scoring data
    NLC.db.importData = NLC.db.importData or {}
    NLC.db.importData.players = NLC.db.importData.players or {}

    if not NLC._testSeeded then
      local testPlayers = {
        { name = "Testwarrior",  class = "WARRIOR",  rank = "raider", attendance = 95, wclParse = 92, defensives = 1.8, baseScore = 38.5 },
        { name = "Testshaman",   class = "SHAMAN",   rank = "raider", attendance = 90, wclParse = 88, defensives = 2.1, baseScore = 36.2 },
        { name = "Testpaladin",  class = "PALADIN",  rank = "raider", attendance = 85, wclParse = 95, defensives = 0.6, baseScore = 32.0 },
        { name = "Testmage",     class = "MAGE",     rank = "trial",  attendance = 70, wclParse = 97, defensives = 0.3, baseScore = 25.8 },
        { name = "Testrogue",    class = "ROGUE",    rank = "backup", attendance = 80, wclParse = 90, defensives = 1.2, baseScore = 30.5 },
      }
      for _, p in ipairs(testPlayers) do
        NLC.db.importData.players[p.name] = {
          attendance = p.attendance, wclParse = p.wclParse, defensives = p.defensives,
          baseScore = p.baseScore, rank = p.rank, lootThisWeek = 0, lootTotal = 2,
          mplusEffort = 10, role = "dps", deathPenalty = 0,
        }
      end
      NLC._testSeeded = true
      NLC.Utils.Print("Mock data created (5 test players)")
    end

    local fakeItems = {
      { itemLink = "|cffa335ee|Hitem:270162::::::::90:::::|h[Soulcoiler Ritual Vessel]|h|r", itemId = 270162, ilvl = 671, equipLoc = "INVTYPE_CHEST", boss = "Test Boss" },
      { itemLink = "|cffa335ee|Hitem:268235::::::::90:::::|h[Vestment of the Awakening]|h|r", itemId = 268235, ilvl = 671, equipLoc = "INVTYPE_LEGS", boss = "Test Boss" },
      -- Token-grenen: equipLoc = "" er den ENESTE veien inn i
      -- GetTierTokenArmorType, og det var den som drepte alle popupene 19.08.
      -- Uten en slik rad kan ingen testkommando naa dit.
      { itemLink = "|cffa335ee|Hitem:268208::::::::90:::::|h[Strongblood's Ceremonial Cleaver]|h|r", itemId = 268208, ilvl = 678, equipLoc = "", armorType = "Plate", boss = "Test Boss" },
    }

    local fakeSessions = {}
    local testInterests = {
      { name = "Testwarrior",  class = "WARRIOR",  cat = "upgrade",  tier = 3 },
      { name = "Testshaman",   class = "SHAMAN",   cat = "upgrade",  tier = 3 },
      { name = "Testpaladin",  class = "PALADIN",  cat = "catalyst", tier = 1 },
      { name = "Testmage",     class = "MAGE",     cat = "tmog",     tier = 1 },
      { name = "Testrogue",    class = "ROGUE",    cat = "tmog",     tier = 2 },
    }

    for _, item in ipairs(fakeItems) do
      local session = {
        itemLink = item.itemLink, itemId = item.itemId, ilvl = item.ilvl,
        equipLoc = item.equipLoc, boss = item.boss,
        timer = 999, interests = {}, phase = "ranking",
      }
      for _, p in ipairs(testInterests) do
        session.interests[p.name] = {
          category = p.cat, equippedIlvl = 626, tierCount = p.tier, class = p.class,
        }
      end
      session.ranked = NLC.Council.BuildRanking(session)
      table.insert(fakeSessions, session)
    end

    -- Registrer dem som aktive, ellers finner wizard-handlingene (avstemming,
    -- award) ingen session å jobbe mot.
    NLC.Council._setActiveSessions(fakeSessions)
    NLC.UI.ShowWizard(fakeSessions, 1)
    NLC.Utils.Print("Test wizard shown with " .. #fakeSessions .. " items. Click Award to test auto-advance.")

  elseif cmd == "testvote" then
    -- Seeder en avstemming direkte i tilstanden, uten comms, så hele flyten
    -- (seddel → opptelling → begrunnelse → note) kan kjøres alene offline.
    local sessions = NLC.Council.GetActiveSessions()
    local session = sessions[NLC.Council.GetWizardIndex()]
    if not session then
      NLC.Utils.Print("Ingen aktiv session — kjør /nordlc test først.")
      return
    end
    local ballot = {}
    for _, c in ipairs(session.ranked or {}) do table.insert(ballot, c.name) end
    if #ballot < 2 then
      NLC.Utils.Print("Trenger minst to kandidater — kjør /nordlc test først.")
      return
    end
    NLC.Council.StartVote(session.sessionIdx, ballot)
    local vs = NLC.Council.GetVoteState()
    if not vs.active then
      -- StartVote krever raid leader. Offline seeder vi tilstanden direkte.
      vs.active = true
      vs.sessionIdx = session.sessionIdx
      vs.ballot = ballot
      vs.results = {}
      vs.officers = {}
    end
    vs.officers = { Fisk = true, Braxina = true, Bell = true, Gyddian = true }
    vs.results = { Fisk = ballot[1], Braxina = ballot[1], Bell = ballot[2] }
    NLC.UI.ShowWizard(sessions, NLC.Council.GetWizardIndex())
    NLC.Utils.Print("Testavstemming seedet: 3 av 4 officers har stemt. Trykk Tildel på en kandidat.")

  elseif cmd == "testpopup" then
    local fakeItems = {
      { sessionIdx = 1, itemLink = "|cffa335ee|Hitem:270162::::::::90:::::|h[Soulcoiler Ritual Vessel]|h|r", itemId = 270162, ilvl = 671, equipLoc = "INVTYPE_CHEST", boss = "Test Boss" },
      -- Token-raden maa vaere med her ogsaa: popupen er der den krasjet.
      { sessionIdx = 2, itemLink = "|cffa335ee|Hitem:268208::::::::90:::::|h[Strongblood's Ceremonial Cleaver]|h|r", itemId = 268208, ilvl = 678, equipLoc = "", armorType = "Plate", boss = "Test Boss" },
    }
    NLC.UI.ShowMultiItemPopup(fakeItems, 30)
    NLC.Utils.Print("Test multi-item popup shown.")

  elseif cmd == "testloot" then
    NLC.isOfficer = true
    NLC.active = true
    -- MAA settes her ogsaa. ryddTestmodus ser kun paa testMode, saa uten den
    -- ble flagget staaende etter /nordlc testloot - og et hengende active
    -- BLOKKERER lederens ACTIVATE (Comms.lua: «if not NLC.active and fraLeder»).
    -- Da kjoerer Activate() aldri, LootDetection registreres aldri, og du staar
    -- uten auto-pass og uten loot-rapport resten av kvelden. Uten feilmelding.
    -- RELEASE.md punkt 5 paalegger nettopp denne kommandoen foer hver release.
    NLC.testMode = true
    -- Simulate boss loot drop with multiple items
    local fakeItems = {
      { itemLink = "|cffa335ee|Hitem:270162::::::::90:::::|h[Soulcoiler Ritual Vessel]|h|r", itemId = 270162, ilvl = 671, equipLoc = "INVTYPE_CHEST", boss = "Test Boss", looter = "Player1" },
      { itemLink = "|cffa335ee|Hitem:268235::::::::90:::::|h[Vestment of the Awakening]|h|r", itemId = 268235, ilvl = 671, equipLoc = "INVTYPE_LEGS", boss = "Test Boss", looter = "Player2" },
      { itemLink = "|cffa335ee|Hitem:270930::::::::90:::::|h[Tomb-Creeper's Claw]|h|r", itemId = 270930, ilvl = 671, equipLoc = "INVTYPE_WEAPON", boss = "Test Boss", looter = "Player3" },
      { itemLink = "|cffa335ee|Hitem:268208::::::::90:::::|h[Strongblood's Ceremonial Cleaver]|h|r", itemId = 268208, ilvl = 678, equipLoc = "", armorType = "Plate", boss = "Test Boss", looter = "Player1" },
    }
    NLC.LootDetection._setDetected(fakeItems)  -- seed the panel's backing list so remove/Start Council work
    NLC.UI.ShowLootDetected(fakeItems)
    NLC.Utils.Print("Test loot panel shown with 4 items. Remove unwanted items, then click Start Council.")

  elseif cmd == "testend" then
    -- Clean up test mode
    if NLC.Council._origAward then
      NLC.Council.Award = NLC.Council._origAward
      NLC.Council._origAward = nil
    end
    NLC._testSeeded = nil
    NLC.Council._testSession = nil
    NLC.Utils.Print("Test mode ended.")

  elseif cmd == "roster" then
    -- Fanger hele guild-rosteret med noter, for opplasting via companion.
    if arg:lower() == "status" then
      NLC.Roster.Status()
    else
      NLC.Roster.Capture()
    end

  else
    NLC.Utils.Print("Commands:")
    NLC.Utils.Print("  /nordlc activate — Aktiver addon")
    NLC.Utils.Print("  /nordlc deactivate — Deaktiver addon")
    NLC.Utils.Print("  /nordlc award <spiller> [item] — Registrer utdeling UTEN council")
    NLC.Utils.Print("  /nordlc addall — Legg ALT tradeable fra baggen i panelet")
    NLC.Utils.Print("  /nordlc add [item] — Start council (shift-klikk items)")
    NLC.Utils.Print("  /nordlc council — Gjenåpne aktivt loot council vindu")
    NLC.Utils.Print("  /nordlc timer <sek> — Sett respons-timer (min 30, default 90)")
    NLC.Utils.Print("  /nordlc debug — Toggle loot detection debug-logging")
    NLC.Utils.Print("  /nordlc diag [antall] — Vis diagnoselogg (diag clear tømmer)")
    NLC.Utils.Print("  /nordlc roster — Fang guild-rosteret med noter (krever /reload etterpå)")
  NLC.Utils.Print("  /nordlc history — Vis award historikk")
  NLC.Utils.Print("  /nordlc trade — Vis items som venter på trade")
    NLC.Utils.Print("  /nordlc pending — Vis ufordelte items")
    NLC.Utils.Print("  /nordlc resume <nr> — Gjenoppta ufordelt item")
    NLC.Utils.Print("  /nordlc resume all — Gjenoppta alle")
    NLC.Utils.Print("  /nordlc import — Last inn import data")
    NLC.Utils.Print("  /nordlc reset — Nullstill pending trades")
    NLC.Utils.Print("  /nordlc status — Vis status")
  end
end

-- Namespaces initialized in Utils.lua
