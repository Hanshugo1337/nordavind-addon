-- LootDetection.lua
-- Distributed loot capture for Midnight (patch 12.0).
--
-- Why distributed: in 12.0 the officer's single client no longer sees all loot
-- (START_LOOT_ROLL only fires for items the officer can roll on; ENCOUNTER_LOOT_RECEIVED
-- is unreliable; loot lands after combat; addon comms are blocked during encounters).
-- So each raider captures their OWN tradeable looted items locally and reports them to
-- the officer after the fight.
--
-- Capture model: after ENCOUNTER_END (success) we open a collection window and scan
-- the player's bags for items that still carry a trade timer (BoP looted within the trade
-- window) and pass shouldTrackItem. Items are deduped by item GUID so each physical item is
-- reported once per session. BAG_UPDATE_DELAYED re-scans while the window is open so late
-- loot is caught without a fixed guess.
--
-- The window is anchored on the loot rolls, not on the kill. See COLLECT_BASE below: with
-- Group Loot nothing reaches anyone's bags until the roll is settled, which is far later
-- than the kill, so a window that only counts from ENCOUNTER_END never sees a single item.
--
-- Send model: reports go out via NLC.Comms only when addon comms are NOT restricted
-- (ADDON_RESTRICTION_STATE_CHANGED / C_RestrictedActions). If comms are blocked when the
-- window closes, the report is held and flushed the moment the restriction lifts.
--
-- Officer aggregation of LOOT_REPORT lives in Comms.lua; it feeds detectedItems here via
-- _setDetected so the existing "Loot Detected" panel (GetDroppedItems/RemoveItem) is unchanged.
--
-- Technique reference only (RCLootCouncil): which WoW APIs exist in 12.0. No RC code,
-- names, structure or text. Read again at 3.23.1 (2026-08-18) for two behaviours we
-- were missing: that Need must be checked before it is rolled, and that auto-rolls
-- want a short delay. Both are reimplemented here from the API, not from their source.

local NLC = NordavindLC_NS

local lootFrame = CreateFrame("Frame")
local isRegistered = false

local currentBoss = nil
local reportItems = {}       -- tradeable items THIS client looted, awaiting send
local reportedGUIDs = {}     -- session-wide dedup: itemGUID -> true
local detectedItems = {}     -- aggregated list on the officer (shown in the panel)
local collecting = false     -- true while the post-combat collection window is open
local collectTimer = nil
local collectDeadline = 0    -- GetTime() when the window closes
local collectHardStop = 0    -- GetTime() the window may never outlive
local commsRestricted = false -- true when addon comms are blocked (encounter/challenge)
local pendingSend = false    -- true if a report is waiting for the restriction to lift
local debugMode = false

-- Hvorfor et item IKKE ble med. «Innsamling stengt | 0 items» kan bety at
-- ingenting droppet, eller at filteret kastet alt — 19.08 var det det siste, og
-- loggen kunne ikke skille dem. Grunnene telles her saa nulltallet alltid
-- kommer med en forklaring.
local AVVIST_GRUNNER = {
  "ingenHandelstid", "ikkeEpic", "ekskludert", "ikkeLastet", "klassifiseringFeilet",
}
local AVVIST_TEKST = {
  ingenHandelstid      = "uten handelstid",
  ikkeEpic             = "under epic",
  ekskludert           = "ekskludert type",
  ikkeLastet           = "ikke lastet inn",
  klassifiseringFeilet = "klassifisering feilet",
}
local avvist = {}
-- Maa staa over forEachTradeable og over event-handleren. Se dbg-kommentaren
-- under for hvorfor rekkefoelgen er en felle i denne fila.
local function nullstillAvvist()
  for i = 1, #AVVIST_GRUNNER do avvist[AVVIST_GRUNNER[i]] = 0 end
end
nullstillAvvist()

-- ENCOUNTER_START/END lyttes paa uansett om addonet er aktivt.
--
-- Laa disse i Register(), som kun kalles fra Activate(). Da var grenen «addon er
-- IKKE aktiv» i handleren under doed kode: den kunne bare naas hvis handleren
-- fyrte, og handleren fyrte bare naar noen alt hadde aktivert. Resultatet var at
-- en hel raidkveld med addonet lastet ga null linjer i diagloggen, og
-- spoersmaalet «kjoerte det i det hele tatt?» ikke kunne besvares (22.08).
--
-- Auto-rullen blir bevisst IKKE med hit. START_LOOT_ROLL maa staa bak
-- Activate(), ellers ruller addonet Need eller Pass for deg i tilfeldige
-- pug-raid uten at du har bedt om det.
local function registrerAlltid()
  lootFrame:RegisterEvent("ENCOUNTER_START")
  lootFrame:RegisterEvent("ENCOUNTER_END")
end

-- Maa staa over alt som kaller den. En local deklarert lenger nede er ikke
-- synlig for en funksjon definert over — da slaas «dbg» opp som global, blir
-- nil, og kallet kaster. Den fella har truffet denne fila foer.
local function dbg(msg)
  -- Alt gaar til diagnoseloggen uansett; chat-utskriften er fortsatt valgfri.
  if NLC.Utils.Diag then NLC.Utils.Diag(msg) end
  if debugMode then
    NLC.Utils.Print("|cff00bbff[LootDebug]|r " .. msg)
  end
end


-- Lagre/hente den uferdige rapporten.
--
-- Alt dette laa kun i minnet. Reload 43 sekunder etter killet paa The Coiled
-- Altar 2026-08-19 kastet hele rapporten — seks items forsvant fordi vinduet
-- fortsatt sto aapent. Én tastetrykk, og kvelden var borte for de itemene.
--
-- Nedskrivingen er billig: en liste med lenker og GUID-er, toemt saa snart
-- rapporten faktisk er sendt.
local function lagreRapport()
  if not NLC.db then return end
  if #reportItems == 0 then
    NLC.db.pendingReport = nil
    return
  end
  NLC.db.pendingReport = {
    boss = currentBoss,
    items = reportItems,
    guids = reportedGUIDs,
  }
end

local function hentRapport()
  local lagret = NLC.db and NLC.db.pendingReport
  if not lagret or not lagret.items or #lagret.items == 0 then return false end
  reportItems = lagret.items
  reportedGUIDs = lagret.guids or {}
  currentBoss = currentBoss or lagret.boss
  return true
end

function NLC.LootDetection.Register()
  if isRegistered then return end
  registrerAlltid()
  lootFrame:RegisterEvent("START_LOOT_ROLL") -- auto-roll only
  -- Andre deteksjonsvei, uavhengig av baggen. Se vunnetRull nedenfor.
  lootFrame:RegisterEvent("LOOT_ITEM_ROLL_WON")
  -- New 12.0 event; guard so an older client can't error on RegisterEvent.
  pcall(function() lootFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED") end)
  isRegistered = true
  reportItems = {}
  reportedGUIDs = {}
  pendingSend = false

  -- Laa det en uferdig rapport igjen fra foer reloaden, tar vi den med oss og
  -- sender den saa snart comms tillater det.
  if hentRapport() then
    dbg("Fant uferdig rapport fra foer reload: " .. #reportItems .. " items")
    C_Timer.After(5, function() NLC.LootDetection.TrySendReport() end)
  end
end

function NLC.LootDetection.Unregister()
  lootFrame:UnregisterAllEvents()
  -- UnregisterAllEvents tar ogsaa ENCOUNTER_END. Uten denne linja virker
  -- diagnosenettet kun frem til foerste Deactivate.
  registrerAlltid()
  isRegistered = false
  collecting = false
  pendingSend = false
  collectDeadline = 0
  collectHardStop = 0
  if collectTimer then collectTimer:Cancel(); collectTimer = nil end
end

local EXCLUDED_TYPES = {
  ["Miscellaneous"] = true,
  ["Companion Pets"] = true,
  ["Consumable"] = true,
}

local function shouldTrackItem(itemLink, itemID)
  if not itemLink or not itemID then return false end
  local _, _, quality, ilvl, _, itemType, itemSubType, _, equipLoc = C_Item.GetItemInfo(itemLink)
  if not quality then return nil, nil, nil, nil, "ikkeLastet" end
  if quality < 4 then return false, nil, nil, nil, "ikkeEpic" end
  if itemType == "Recipe" then return true, ilvl or 0, equipLoc or "" end

  -- Tier-tokens sjekkes FØR utelukkelsen under, ikke etter.
  --
  -- Spillet klassifiserer et armor token som Miscellaneous/Junk — samme
  -- itemklasse som pets og skrot. «Miscellaneous» sto i EXCLUDED_TYPES, så hvert
  -- eneste token ble kastet ut en linje før token-sjekken fikk se det. Hele
  -- tier-grenen her var død kode: den kunne aldri nås av det den var skrevet for.
  local ikkeUtstyr = (not equipLoc) or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE"
  if ikkeUtstyr then
    local tokenArmor = NLC.Utils.GetTierTokenArmorType(itemLink)
    if tokenArmor then
      return true, ilvl or 0, "", tokenArmor
    end
  end

  if EXCLUDED_TYPES[itemType] then return false, nil, nil, nil, "ekskludert" end
  if ikkeUtstyr then return false, nil, nil, nil, "ekskludert" end
  if equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return false, nil, nil, nil, "ekskludert" end
  if NLC.Utils.IsWarbound(itemLink) then return false, nil, nil, nil, "ekskludert" end
  return true, ilvl or 0, equipLoc or ""
end

-- True if addon comms are currently blocked.
--
-- Var en egen kopi av logikken i Comms.lua. To kopier av samme regel drev fra
-- hverandre i det øyeblikket den ene lærte noe den andre ikke gjorde: Comms
-- leser nå «Activating» fra event-payloaden, denne pollet API-et og så bare
-- «Active». Nå spør vi den ene kilden. Degraderer fortsatt til false hvis
-- 12.0-API-et mangler — den vakten ligger i Comms.
local function commsAreRestricted()
  return NLC.Comms and NLC.Comms.IsRestricted and NLC.Comms.IsRestricted() or false
end

-- Blizzard's roll types for RollOnLoot. Disenchant (3) is deliberately absent:
-- the council decides what gets sharded, never the auto-roller.
local ROLL_PASS, ROLL_NEED, ROLL_GREED, ROLL_TRANSMOG = 0, 1, 2, 4

-- Auto-rolls are deferred a frame or two. Landing inside the event handler means
-- racing any other addon that rebuilds the roll frame, and a call that arrives
-- mid-rebuild is dropped with no error to show for it.
local function rollLater(rollID, rollType)
  C_Timer.After(0.05, function()
    -- pcall fordi kallet kommer 0,05 s etter eventet: rullen kan ha loept ut,
    -- spilleren kan ha klikket selv, eller START_LOOT_ROLL kan ha fyrt paa nytt
    -- for samme rollID etter en reconnect. Uten pcall gir det en roed Lua-feil
    -- midt i bossen - og verre: `lukk` under kjoerer aldri, saa rull-vinduet
    -- blir staaende. Tjuefem ruller per boss gjoer det til feilspam.
    pcall(RollOnLoot, rollID, rollType)
    -- Rull-vinduet blir staaende etter at vi har svart for spilleren. Over en
    -- kveld er det tjuefem popups folk maa klikke bort selv om addonet allerede
    -- har rullet. RunNextFrame er den presise primitiven; C_Timer.After(0) gjoer
    -- det samme paa klienter uten den.
    local function lukk()
      local container = _G.GroupLootContainer
      local fjern = _G.GroupLootContainer_RemoveFrame
      if not (container and fjern) then return end
      -- Blizzard bruker et fast antall rull-rammer.
      for i = 1, 4 do
        local ramme = _G["GroupLootFrame" .. i]
        if ramme and ramme:IsShown() and ramme.rollID == rollID then
          pcall(fjern, container, ramme)
        end
      end
    end
    if RunNextFrame then RunNextFrame(lukk) else C_Timer.After(0, lukk) end
  end)
end

-- The leader needs the item in their bags for the council to hand out, so we roll
-- Need on their behalf. But Need is only offered for what the leader's own spec can
-- equip — a plate leader cannot Need a leather drop. That call is refused silently,
-- and since every other raider auto-passes, the item would end the roll with no
-- valid entry at all and be lost. Transmog and Greed are always available, so we
-- step down to those rather than gamble on Need being allowed.
local function leaderRollType(rollID)
  local _, _, _, _, _, canNeed, _, _, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
  if canNeed then return ROLL_NEED end
  if canTransmog then return ROLL_TRANSMOG end
  return ROLL_GREED
end

-- Er dette et item raadet deler ut?
--
-- Regelen fra raidlederen: pets, toys og mounts ruller folk fritt paa. Alt annet
-- passer de, saa lederen vinner og councilet deler ut.
--
-- Dette kan IKKE avgjoeres paa typenavnet. Spillet legger tier-tokens i samme
-- itemklasse som pets og mounts (Miscellaneous), saa den gamle sjekken
-- «itemType ~= Miscellaneous» fritok tokens ved et uhell — raiderne passet aldri
-- paa dem, rullen gikk full tid, og hvem som helst kunne Neede itemet lederen
-- skulle dele ut. Underklassen skiller dem. Toys ligger ikke i én bestemt
-- itemklasse i det hele tatt, saa de maa spoerres om for seg.
local MISC_CLASS = 15
local function erCouncilLoot(link)
  if not link then return true end
  local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)

  if itemID and C_ToyBox and C_ToyBox.GetToyInfo then
    local ok, _, toyNavn = pcall(C_ToyBox.GetToyInfo, itemID)
    if ok and toyNavn then return false end
  end

  if classID == MISC_CLASS then
    local E = Enum and Enum.ItemMiscellaneousSubclass
    if E and (subclassID == E.CompanionPet or subclassID == E.Mount) then
      return false
    end
  end

  return true
end

-- Exposed for tests/lootroll_harness.lua only; nothing in the addon calls this.
-- Same underscore convention as _setDetected below.
NLC.LootDetection._leaderRollType = leaderRollType
NLC.LootDetection._erCouncilLoot = erCouncilLoot

-- Gaar gjennom baggene og kaller fn(guid, entry) for hvert tradeable item som
-- passerer filteret. Delt av den automatiske innsamlingen og det manuelle
-- oppslaget under, saa de to aldri kan komme til aa filtrere ulikt.
local function forEachTradeable(fn)
  for bag = 0, 4 do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local link = C_Container.GetContainerItemLink(bag, slot)
      -- Tom slot er ikke en avvisning. Kun ekte items telles.
      if link and not NLC.Utils.IsTradeableBagItem(bag, slot) then
        avvist.ingenHandelstid = avvist.ingenHandelstid + 1
      end
      if link and NLC.Utils.IsTradeableBagItem(bag, slot) then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local guid = C_Item.DoesItemExist(loc) and C_Item.GetItemGUID(loc)
        if guid then
          local itemID = C_Item.GetItemInfoInstant(link)
          -- Ett item som ikke lar seg klassifisere skal koste oss det itemet,
          -- ikke resten av baggen. Slik det sto, rev en enkelt feil med seg hele
          -- runden — og da ser det ut som om ingenting droppet.
          local ok, track, ilvl, equipLoc, armorType, grunn =
            pcall(shouldTrackItem, link, itemID)
          if not ok then
            dbg("Klarte ikke klassifisere " .. tostring(link) .. ": " .. tostring(track))
            track = nil
            avvist.klassifiseringFeilet = avvist.klassifiseringFeilet + 1
          elseif not track then
            local n = grunn or "ekskludert"
            avvist[n] = (avvist[n] or 0) + 1
          end
          if track then
            fn(guid, {
              itemLink = link,
              itemId = itemID,
              ilvl = ilvl or 0,
              equipLoc = equipLoc,
              armorType = armorType,
              boss = currentBoss,
              looter = UnitName("player"),
            })
          end
        end
      end
    end
  end
end

-- Scan all bags for newly-looted tradeable items and add them to reportItems.
function NLC.LootDetection.ScanBags()
  forEachTradeable(function(guid, entry)
    if reportedGUIDs[guid] then return end
    reportedGUIDs[guid] = true
    table.insert(reportItems, entry)
    dbg("Rapport +: " .. entry.itemLink)
  end)
  lagreRapport()
end

-- Merk alt som allerede ligger i baggen som «ikke fra denne bossen».
--
-- Uten dette rapporterte den automatiske innsamlingen HELE restlageret. Loggen
-- fra The Coiled Altar 2026-08-19: 40 items rapportert, hvorav 34 ble sveipet
-- inn i selve killoeyeblikket — nøyaktig de 34 «/nordlc addall» fant i baggen en
-- halvtime foer. Kun 6 kom faktisk fra bossen. Panelet ville vist 40.
--
-- reportedGUIDs er allerede dedup-lista, saa aa merke dem der holder dem ute
-- uten noen ny tilstand. Vil du ha restlageret, er det «/nordlc addall» som
-- gjoer den jobben — og den leser bevisst ikke denne lista.
local function markerEksisterendeSomKjent()
  local n = 0
  forEachTradeable(function(guid)
    if not reportedGUIDs[guid] then
      reportedGUIDs[guid] = true
      n = n + 1
    end
  end)
  return n
end

-- Alt tradeable som ligger i baggen NAA, som en fersk liste.
--
-- Bevisst uavhengig av reportedGUIDs: dette er offiseren som spoer «hva holder
-- jeg paa?», ikke innsamlingen som spoer «hva er nytt?». Den roerer heller ikke
-- dedup-tilstanden, saa et manuelt oppslag kan aldri spise et item slik at den
-- automatiske rapporten mister det etterpaa.
function NLC.LootDetection.ScanBagsForPanel()
  local items = {}
  forEachTradeable(function(_, entry)
    entry.boss = entry.boss or "Manuelt"
    table.insert(items, entry)
  end)
  return items
end

-- Send the collected report if comms allow; otherwise hold and flush when the restriction lifts.
function NLC.LootDetection.TrySendReport()
  if #reportItems == 0 then
    pendingSend = false
    dbg("Ingen tradeable items å rapportere.")
    return
  end
  if commsRestricted then
    pendingSend = true
    dbg("Comms blokkert — venter på at restriksjon løftes (" .. #reportItems .. " items).")
    return
  end
  NLC.Comms.Send("LOOT_REPORT", { boss = currentBoss, items = reportItems })
  dbg("Sendte LOOT_REPORT: " .. #reportItems .. " items")
  reportItems = {}
  pendingSend = false
  lagreRapport()
end

-- ============================================================
-- Innsamlingsvinduet
--
-- Vinduet var 12 sekunder fra ENCOUNTER_END. Det rakk aldri fram. Loggen fra
-- Nek'zali the Soulcoiler (heroic, 28 mann, 2026-08-19) viser hvorfor:
--
--   20:42:47  ENCOUNTER_END           vinduet aapnes, bagen er tom
--   20:42:48  START_LOOT_ROLL x6      alt gaar til rull, ingenting til noen bag
--   20:42:59  vinduet stengte her
--   20:43:04  «not found in bags» for alle seks itemene
--   20:43:23  foerste rull avgjort    +36 s: NAA finnes itemet i en bag
--
-- Med Group Loot eksisterer ikke itemet hos noen foer rullen er avgjort, og
-- rullen starter foerst naar noen har gaatt bort og lootet liket. Derfor er
-- killtidspunktet feil anker. Vi gir en grunnperiode som daekker gaaturen, og
-- forlenger deretter ut fra rullens EGEN gjenstaaende tid — det tallet eier
-- spillet, ikke vi. Taket finnes bare saa en henglende rull ikke lar bag-scannet
-- staa paa resten av kvelden.
-- ============================================================
local COLLECT_BASE = 45          -- sekunder fra ENCOUNTER_END
local COLLECT_ROLL_GRACE = 12    -- monn etter at siste rull kan vaere ute
-- Taket maa romme en full rull som starter sent. Maalt in-game 19.08:
-- GetLootRollTimeLeft ga 270 sekunder. Blir liket lootet ett minutt etter
-- killet, trengs 60 + 270 + 12 = 342 — og da var det gamle taket paa 300 for
-- lavt til at rullen rakk aa bli avgjort foer vi stengte.
local COLLECT_MAX = 480          -- absolutt tak, regnet fra ENCOUNTER_END
local DEFAULT_ROLL_SECONDS = 270 -- hvis GetLootRollTimeLeft ikke svarer

-- Hvor lenge vi venter paa at en rull skal SETTE SEG, uansett hva fristen sier.
--
-- 270 sekunder er hvor lenge en rull KAN vare, ikke hvor lenge den varer. Alle
-- med addonet passer automatisk og lederen Needer automatisk, saa rullene er
-- avgjort paa sekunder: RCLootCouncil-loggen fra Nek'zali viser vinnerne paa
-- +36, +43 og +45 sekunder. Ventet vi ut fristen, stengte innsamlingen foerst
-- paa +283 s og panelet kom paa +293 s — nesten fem minutter etter killet, med
-- loot synlig i baggen hele tiden. Da griper folk til /nordlc addall i stedet,
-- og det gjorde de hver eneste boss 24.08.
--
-- Aa stenge tidlig er trygt: LOOT_ITEM_ROLL_WON VEKKER vinduet igjen (se
-- extendCollection), reportedGUIDs hindrer dobbeltrapportering, og officeren
-- legger sen loot til i panelet som allerede staar aapent (Council.OnLootReport
-- bygger videre paa samme boss). En sen rull koster altsaa en ekstra runde —
-- ikke et tapt item.
local ROLL_SETTLE = 45

-- Items vi VET vi vant, uavhengig av hva baggen sier.
--
-- Bag-skannet har to ledd som kan svikte: itemet maa ligge i baggen naar vi ser
-- etter, og handelstida maa la seg lese ut av tooltipen. LOOT_ITEM_ROLL_WON
-- kommer rett fra spillet i det rullen avgjoeres, og sier hva DU vant. Den gir
-- ett item om gangen og ingen GUID, saa den erstatter ikke skannet — men som
-- ettersjekk ved stenging fanger den opp det skannet gikk glipp av.
local vunnetRull = {}

local function fangOppVunnet()
  local lagtTil = 0
  for _, v in ipairs(vunnetRull) do
    local alleredeMed = false
    for _, it in ipairs(reportItems) do
      if it.itemId == v.itemId then alleredeMed = true; break end
    end
    if not alleredeMed then
      local _, _, quality, ilvl, _, _, _, _, equipLoc = C_Item.GetItemInfo(v.link)
      -- Samme kvalitetskrav som ellers, saa en gruppe-rull paa skrot ikke
      -- havner i raadet bare fordi vi tilfeldigvis vant den.
      if (quality or 0) >= 4 then
        table.insert(reportItems, {
          itemLink = v.link,
          itemId = v.itemId,
          ilvl = ilvl or 0,
          equipLoc = equipLoc or "",
          boss = currentBoss,
          looter = UnitName("player"),
        })
        lagtTil = lagtTil + 1
        dbg("Rapport + (fra rull, ikke funnet i baggen): " .. v.link)
      end
    end
  end
  vunnetRull = {}
  return lagtTil
end

local function closeCollection()
  collectTimer = nil
  collecting = false
  lootFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
  -- Siste scan: et item kan ha landet etter forrige BAG_UPDATE_DELAYED.
  NLC.LootDetection.ScanBags()
  local fraRull = fangOppVunnet()
  lagreRapport()
  local avvistTekst = NLC.LootDetection.AvvistTekst()
  dbg("Innsamling stengt | " .. #reportItems .. " items (" .. fraRull .. " fra rull-fallback)"
      .. (avvistTekst ~= "" and " | avvist: " .. avvistTekst or ""))
  NLC.LootDetection.TrySendReport()
end

local function armCollectTimer()
  if collectTimer then collectTimer:Cancel() end
  local remaining = collectDeadline - GetTime()
  if remaining < 0.1 then remaining = 0.1 end
  collectTimer = C_Timer.NewTimer(remaining, closeCollection)
end

-- Skyver stengetiden utover — aldri innover, aldri forbi taket — og aapner
-- vinduet hvis det var stengt. En rull som kommer sent skal kunne vekke det:
-- reportedGUIDs er dedupet for hele oekten, saa en ny runde rapporterer kun det
-- som faktisk er nytt, og en tom rapport sendes ikke i det hele tatt.
local function extendCollection(seconds)
  local now = GetTime()
  if now >= collectHardStop then return end
  local target = math.min(now + seconds, collectHardStop)
  if collecting and target <= collectDeadline then return end
  if target > collectDeadline then collectDeadline = target end
  if not collecting then
    collecting = true
    lootFrame:RegisterEvent("BAG_UPDATE_DELAYED")
  end
  armCollectTimer()
end

lootFrame:SetScript("OnEvent", function(self, event, ...)
  -- ADDON_RESTRICTION_STATE_CHANGED must be handled even outside active councils so a held
  -- report can flush; but reportItems is only ever populated while active, so gating the
  -- rest on NLC.active is fine.
  if event == "ADDON_RESTRICTION_STATE_CHANGED" then
    commsRestricted = commsAreRestricted()
    dbg("Comms-restriksjon: " .. tostring(commsRestricted))
    if not commsRestricted and pendingSend then
      NLC.LootDetection.TrySendReport()
    end
    return
  end

  if not NLC.active then
    if event == "ENCOUNTER_END" and NLC.Utils.Diag then
      NLC.Utils.Diag("ENCOUNTER_END, men addon er IKKE aktiv - ingenting samles inn")
    end
    return
  end

  if event == "ENCOUNTER_START" then
    local encounterID, name = ...
    currentBoss = name or "Unknown Boss"
    dbg("ENCOUNTER_START: " .. currentBoss)

  elseif event == "ENCOUNTER_END" then
    local encounterID, name, difficultyID, groupSize, success = ...
    dbg(string.format("ENCOUNTER_END: %s | success=%s", tostring(name), tostring(success)))
    if name then currentBoss = name end
    if not (success == 1 or success == true) then
      dbg("Encounter feilet, ingen innsamling.")
      return
    end
    -- Open the collection window: scan now, scan again on each BAG_UPDATE_DELAYED,
    -- and hold it open until the rolls have had time to settle (see COLLECT_BASE).
    commsRestricted = commsAreRestricted()
    -- Alt som ligger i baggen NAA er fra foer denne bossen. Merk det, saa
    -- rapporten kun inneholder det som faktisk faller etterpaa.
    local frafoer = markerEksisterendeSomKjent()
    nullstillAvvist()
    collectHardStop = GetTime() + COLLECT_MAX
    collectDeadline = 0
    extendCollection(COLLECT_BASE)
    dbg(frafoer .. " items laa i baggen fra foer - holdes utenfor rapporten")
    dbg(string.format("ENCOUNTER_END success | officer=%s | restriktert=%s | samler %ds (forlenges av ruller)",
      tostring(NLC.isOfficer), tostring(commsRestricted), COLLECT_BASE))

  elseif event == "BAG_UPDATE_DELAYED" then
    if collecting then NLC.LootDetection.ScanBags() end

  elseif event == "LOOT_ITEM_ROLL_WON" then
    -- Vi vant noe. Noter det, og hold vinduet aapent til itemet har rukket aa
    -- lande i baggen — den lander et sekund eller to etter at rullen er avgjort.
    local link = ...
    if type(link) ~= "string" then return end
    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then return end
    local kjent = false
    for _, v in ipairs(vunnetRull) do
      if v.itemId == itemID then kjent = true; break end
    end
    if not kjent then
      table.insert(vunnetRull, { link = link, itemId = itemID })
    end
    extendCollection(20)
    dbg("Vant rull: " .. link)

  elseif event == "START_LOOT_ROLL" then
    local rollID = ...
    if not rollID then return end

    -- Rullen er den eneste kilden som vet naar itemet blir tilgjengelig. Hold
    -- innsamlingen aapen til den er avgjort, ellers stenger vi foer itemet finnes.
    local ms = GetLootRollTimeLeft and GetLootRollTimeLeft(rollID)
    local rollSeconds = (ms and ms > 0) and (ms / 1000) or DEFAULT_ROLL_SECONDS
    -- Vi venter paa at rullen setter seg, ikke paa at fristen loeper ut. Se
    -- ROLL_SETTLE: fristen er et tak spillet oppgir, ikke en varighet.
    local ventetid = math.min(rollSeconds, ROLL_SETTLE)
    extendCollection(ventetid + COLLECT_ROLL_GRACE)
    dbg(string.format("START_LOOT_ROLL | rull %.0fs igjen | venter %.0fs + %ds monn",
      rollSeconds, ventetid, COLLECT_ROLL_GRACE))

    -- Auto-roll behaviour; capture itself happens via ScanBags.
    local link = GetLootRollItemLink(rollID)

    -- Pets, toys og mounts deles ikke ut av raadet — der ruller folk fritt.
    -- Addonet holder fingrene helt unna dem, ogsaa hos lederen: rullet han Need
    -- automatisk, ville han snappet hver eneste mount foer noen rakk aa svare.
    if not erCouncilLoot(link) then
      dbg("Fri rull (pet/toy/mount), addonet ruller ikke: " .. tostring(link))
      return
    end

    if UnitIsGroupLeader("player") then
      -- Lederen tar itemet i baggen saa councilet kan dele det ut.
      local rollType = leaderRollType(rollID)
      if rollType ~= ROLL_NEED then
        dbg("Need not offered on " .. tostring(link) .. ", rolling " .. rollType .. " instead.")
      end
      rollLater(rollID, rollType)
    else
      rollLater(rollID, ROLL_PASS)
    end
  end
end)

-- ============================================================
-- Client report (this player's captured loot)
-- ============================================================
-- Avvisningstellerne for innevaerende innsamling. Nullstilles ved ENCOUNTER_END,
-- ikke ved hvert scan: vinduet skanner om igjen ved hver BAG_UPDATE_DELAYED, og
-- tallet skal gjelde hele bossen.
function NLC.LootDetection.GetAvvist()
  return avvist
end

NLC.LootDetection.NullstillAvvist = nullstillAvvist

-- Tellerne som én lesbar setning, i fast rekkefoelge. Tom streng naar ingenting
-- ble avvist — «0 uten handelstid» er stoey, ikke opplysning.
function NLC.LootDetection.AvvistTekst()
  local deler = {}
  for i = 1, #AVVIST_GRUNNER do
    local grunn = AVVIST_GRUNNER[i]
    local antall = avvist[grunn] or 0
    if antall > 0 then
      table.insert(deler, antall .. " " .. AVVIST_TEKST[grunn])
    end
  end
  return table.concat(deler, ", ")
end

function NLC.LootDetection.GetReport()
  return reportItems
end

-- ============================================================
-- Officer panel (aggregated list, set by Comms.OnLootReport)
-- ============================================================
function NLC.LootDetection._setDetected(items)
  detectedItems = items
end

function NLC.LootDetection.GetDroppedItems()
  return detectedItems
end

function NLC.LootDetection.RemoveItem(index)
  table.remove(detectedItems, index)
end

function NLC.LootDetection.GetCurrentBoss()
  return currentBoss
end

function NLC.LootDetection.ToggleDebug()
  debugMode = not debugMode
  NLC.Utils.Print("Loot debug: " .. (debugMode and "|cff00ff00PÅ|r" or "|cffff0000AV|r"))
  if debugMode then
    NLC.Utils.Print("  currentBoss=" .. tostring(currentBoss))
    NLC.Utils.Print("  reportItems=" .. #reportItems)
    NLC.Utils.Print("  commsRestricted=" .. tostring(commsRestricted))
    NLC.Utils.Print("  collecting=" .. tostring(collecting))
  end
end

-- Slaas paa i det fila lastes, ikke ved aktivering. Se registrerAlltid over.
registrerAlltid()
