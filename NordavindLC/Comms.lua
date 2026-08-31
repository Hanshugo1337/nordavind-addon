-- Comms.lua
-- Addon communication using AceComm (auto-chunking for >255 byte messages)
-- and AceSerializer (safe serialization, no separator collisions with item links)

local NLC = NordavindLC_NS

local PREFIX = "NordLC"
local registered = false

local AceComm = LibStub("AceComm-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")
AceComm:Embed(NLC.Comms)
AceSerializer:Embed(NLC.Comms)

function NLC.Comms.Register()
  if registered then return end
  NLC.Comms:RegisterComm(PREFIX, function(prefix, message, channel, sender)
    NLC.Comms.OnMessage(prefix, message, channel, sender)
  end)
  registered = true
end

-- Central addon-comms restriction gating (mirrors Blizzard's SendAddonMessage lockout during
-- encounters / M+). Queue every outgoing message while restricted; flush when the lock lifts.
-- All sends (SESSION_START, INTEREST, AWARD, LOOT_REPORT, ...) route through NLC.Comms.Send,
-- so gating it here protects the whole protocol.
local commsQueue = {}
local commsRestricted = false

-- Restriksjonstilstand per type, oppdatert fra event-payloaden.
local restrictedTypes = {}

-- Vi gater kun på Encounter og ChallengeMode. Combat er unntaket — comms virker
-- der — og map-restriksjonen slår inn i instanser uten å stoppe meldinger.
local function gatedTypes()
  local E = Enum and Enum.AddOnRestrictionType
  if not E then return nil end
  return { E.Encounter, E.ChallengeMode }
end

local function recomputeRestricted()
  local types = gatedTypes()
  if not types then return false end
  for _, t in ipairs(types) do
    if t ~= nil and restrictedTypes[t] then return true end
  end
  return false
end

-- Ved innlasting har ingen event fyrt ennå, så API-et er eneste kilde til
-- starttilstanden. Den kjenner ikke «Activating», men det gjør ingenting her:
-- et vindu som allerede står åpent når vi lastes er enten aktivt eller ikke.
local function seedFromApi()
  local types = gatedTypes()
  if not (types and C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive) then
    return false
  end
  for _, t in ipairs(types) do
    if t ~= nil and C_RestrictedActions.IsAddOnRestrictionActive(t) then
      restrictedTypes[t] = true
    end
  end
  return recomputeRestricted()
end

local function flushCommsQueue()
  if #commsQueue == 0 then return end
  local pending = commsQueue
  commsQueue = {}
  for _, k in ipairs(pending) do
    -- Kanalen laa ikke i koeen foer gjenopptaket kom til. En hvisket melding
    -- som blir liggende under en restriksjon ville da gaatt ut til HELE raidet
    -- naar den slapp — og en gjenopptatt sesjon hos alle er nettopp det vi
    -- ikke vil ha.
    NLC.Comms:SendCommMessage(PREFIX, k.payload, k.kanal, k.mottaker)
  end
end

local _restrictFrame = CreateFrame("Frame")
_restrictFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
_restrictFrame:SetScript("OnEvent", function(_, _, restrictionType, state)
  -- Tilstanden leses fra payloaden, ikke ved å polle
  -- C_RestrictedActions.IsAddOnRestrictionActive. Payloaden har en egen
  -- «Activating»-tilstand — på vei inn i restriksjonen — og meldinger sendt i
  -- det vinduet forsvinner like stille som under «Active». Det vinduet treffer
  -- akkurat encounter-start, som er når en council-sesjon typisk åpnes.
  local S = Enum and Enum.AddOnRestrictionState
  if restrictionType ~= nil and S then
    local pa = (state == S.Active) or (state == S.Activating)
    restrictedTypes[restrictionType] = pa or nil
  end
  commsRestricted = recomputeRestricted()
  if not commsRestricted then flushCommsQueue() end
end)
commsRestricted = seedFromApi()

function NLC.Comms.IsRestricted() return commsRestricted end

-- `mottaker` satt = hvisk til én person i stedet for aa kringkaste til raidet.
-- Brukes av gjenopptaket: den som reloadet skal faa sesjonen tilbake, mens de
-- som allerede har svart ikke skal se popupen rive seg opp igjen.
function NLC.Comms.Send(msgType, data, mottaker)
  if not IsInRaid() then return end
  local payload = NLC.Comms:Serialize(msgType, data)
  local kanal = mottaker and "WHISPER" or "RAID"
  if commsRestricted then
    table.insert(commsQueue, { payload = payload, kanal = kanal, mottaker = mottaker })
    return
  end
  NLC.Comms:SendCommMessage(PREFIX, payload, kanal, mottaker)
end

function NLC.Comms.OnMessage(prefix, message, channel, sender)
  if prefix ~= PREFIX then return end

  local success, msgType, data = NLC.Comms:Deserialize(message)
  if not success then return end

  -- All fjernaktivering krever at meldinga kommer fra den som leder gruppa.
  --
  -- Regelen har alltid vaert at lederen faar popupen og at resten foelger.
  -- Chatlinja lovte det ogsaa — «Activated by raid leader.» — men avsenderen
  -- ble aldri sjekket. Dermed kunne hvem som helst med et hengende
  -- active-flagg, typisk etter /nordlc test, skru paa auto-passet hos alle med
  -- addonet. 26.08 skjedde det i en pug: flere passet paa alt uten aa ha
  -- startet noe. Se tests/aktivering_harness.lua.
  --
  -- «Vet ikke hvem lederen er» maa bety nei, ikke ja. GruppelederNavn gir nil
  -- utenfor raid og foer rosteret er lest, og da slipper ingenting gjennom.
  local fraLeder = NLC.Utils.ErGruppeleder(sender)

  if msgType == "ACTIVATE" then
    if not NLC.active and fraLeder then
      NLC.Activate()
      NLC.Utils.Print("Aktivert av raidlederen.")
      -- Reloader du midt i et council, ligger sesjonen kun i minnet og er borte.
      -- Popupen kom aldri tilbake, du svarte aldri, og offiseren ventet paa et
      -- svar som ikke kunne komme — hele 90-sekunderstimeren maatte loepe ut.
      -- Aktiveringen er noeyaktig det oeyeblikket en gjeninnlastet klient melder
      -- seg igjen, saa spoersmaalet henges her: én gang, ikke i loekke.
      NLC.Comms.Send("SESSION_RESUME_REQ", "")
    end
    return
  end

  -- Et spoersmaal om noen holder paa. Svaret ER en aktivering hos mottakeren,
  -- saa bare lederen har lov til aa gi det. Svarte alle som var aktive, holdt
  -- det at én i raidet hadde flagget hengende igjen — da smittet det videre.
  if msgType == "ACTIVATE_CHECK" then
    if NLC.active and UnitIsGroupLeader("player") then
      NLC.Comms.Send("ACTIVATE", "")
    end
    return
  end

  -- Svar foer aktiveringsporten, uansett hvem som spoer.
  --
  -- En installert men uaktivert klient MAA vaere synlig for /nordlc version og
  -- for opptellingen ved council-start — det var Braxina-saken 19.08. Aa svare
  -- er noe helt annet enn aa skru paa auto-passet, og bare det siste krever
  -- lederen. Derfor ligger svarene her og aktiveringen rett under.
  if msgType == "ROLL_CALL" then
    NLC.Comms.Send("ROLL_CALL_ACK", NLC.Utils.AddonVersion())
  elseif msgType == "VERSION_CHECK" then
    NLC.Comms.Send("VERSION_REPLY", NLC.version)
  end

  -- Lederen holder paa akkurat naa: like god aktiveringsgrunn som ACTIVATE.
  if not NLC.active and fraLeder and
     (msgType == "SESSION_START" or msgType == "SESSION_RESUME"
      or msgType == "ROLL_CALL" or msgType == "VERSION_CHECK") then
    NLC.Activate()
    NLC.Utils.Print("Aktivert av council-oppkall.")
  end

  if not NLC.active then return end

  if msgType == "SESSION_START" then
    -- KUN raidlederen starter council.
    --
    -- Uten denne porten kunne hvilken som helst officer drive interesse-popupen
    -- hos hele raidet — og en klient paa gammel build, eller med hengende
    -- tilstand, gjoer det uten aa mene det. Det er nøyaktig samme felle som laa
    -- i ACTIVATE til 26.08: meldinga het «Activated by raid leader», men
    -- avsenderen ble aldri sjekket.
    --
    -- ErGruppeleder svarer nei naar den ikke vet hvem lederen er, saa
    -- ingenting slipper gjennom foer rosteret er lest.
    if not fraLeder then
      NLC.Utils.Diag("SESSION_START avvist - ikke fra lederen: " .. tostring(sender))
      return
    end

    -- Skip own broadcast — the officer who started it already has state from StartMultiSession
    local myName = UnitName("player")
    local senderName = sender:match("^([^-]+)") or sender
    if senderName == myName then
      -- do nothing, already set up
    elseif NLC.Council.OnMultiSessionStart then
      NLC.Council.OnMultiSessionStart(data.items, data.timer or 90, sender)
    end

  -- Noen ber om aa faa en paagaaende sesjon paa nytt.
  --
  -- Kun lederen svarer, av samme grunn som kun lederen faar starte: en officer
  -- med hengende tilstand kunne ellers dyttet en gammel sesjon inn hos en som
  -- nettopp reloadet. Og svaret HVISKES — kringkastet ville det revet opp igjen
  -- popupen hos alle som allerede hadde svart.
  --
  -- Er ingen innsamling aapen, er stillhet riktig svar. Uten det ville hver
  -- eneste reload i raidet utloest en runde meldinger.
  elseif msgType == "SESSION_RESUME_REQ" then
    if not UnitIsGroupLeader("player") then return end
    if not (NLC.Council.HasOpenCollecting and NLC.Council.HasOpenCollecting()) then return end
    local snapshot = NLC.Council.CollectingSnapshot and NLC.Council.CollectingSnapshot()
    if not snapshot then return end
    NLC.Utils.Diag("SESSION_RESUME: sender sesjonen paa nytt til " .. tostring(sender))
    NLC.Comms.Send("SESSION_RESUME", snapshot, sender)

  -- Sesjonen kommer tilbake. Samme leder-port som SESSION_START.
  elseif msgType == "SESSION_RESUME" then
    if not fraLeder then
      NLC.Utils.Diag("SESSION_RESUME avvist - ikke fra lederen: " .. tostring(sender))
      return
    end
    if NLC.Council.OnMultiSessionStart then
      NLC.Council.OnMultiSessionStart(data.items, data.timer or 90, sender)
      NLC.Utils.Print("Councilet paagaar - henter sesjonen tilbake.")
    end

  elseif msgType == "RESPOND" then
    if NLC.Council.OnRespond then
      NLC.Council.OnRespond(sender)
    end

  elseif msgType == "INTEREST" then
    for _, entry in ipairs(data) do
      if NLC.Council.OnInterestReceived then
        NLC.Council.OnInterestReceived(sender, entry.sessionIdx, entry.category, entry.eqIlvl, entry.tierCount, entry.note, entry.eqLink)
      end
    end

  elseif msgType == "AWARD" then
    if NLC.Council.OnAward then
      NLC.Council.OnAward(data.sessionIdx, data.itemLink, data.playerName, sender, data.category)
    end

  elseif msgType == "SESSION_CLOSE" then
    -- Samme port som SESSION_START. Denne baerer rangeringsdataene alle andre
    -- faar; stoler vi ikke paa hvem som startet, kan vi ikke stole paa hvem som
    -- lukker. Popupen lukkes heller ikke paa en fremmed melding — da kunne én
    -- klient revet interesse-vinduet vekk for hele raidet.
    if not fraLeder then
      NLC.Utils.Diag("SESSION_CLOSE avvist - ikke fra lederen: " .. tostring(sender))
      return
    end

    NLC.UI.HideMultiItemPopup()
    if not NLC.isOfficer and NLC.Council.OnSessionClose then
      NLC.Council.OnSessionClose(data)
    end

  -- ROLL_CALL og VERSION_CHECK besvares over aktiveringsporten, ikke her.
  -- Versjonen ligger i ack-en, ikke i en egen runde: uten den har offiseren
  -- ingen måte å se at noen kjører en gammel versjon som rangerer annerledes.
  elseif msgType == "ROLL_CALL_ACK" then
    if NLC.Council.OnRollCallAck then
      NLC.Council.OnRollCallAck(sender, data)
    end

  elseif msgType == "LOOT_REPORT" then
    -- Distributed loot: each raider reports their own tradeable loot; only the
    -- officer aggregates it into the Loot Detected panel.
    if not NLC.isOfficer then return end
    if NLC.Council.OnLootReport then
      NLC.Council.OnLootReport(sender, data)
    end

  elseif msgType == "VOTE_START" then
    if NLC.Council.OnVoteStart then
      NLC.Council.OnVoteStart(sender, data)
    end

  -- ACK og CAST gates på isOfficer: kun lederens klient teller opp, så
  -- raidere skal ikke bruke minne på tilstand de aldri viser.
  elseif msgType == "VOTE_ACK" then
    if not NLC.isOfficer then return end
    if NLC.Council.OnVoteAck then
      NLC.Council.OnVoteAck(sender, data)
    end

  elseif msgType == "VOTE_CAST" then
    if not NLC.isOfficer then return end
    if NLC.Council.OnVoteCast then
      NLC.Council.OnVoteCast(sender, data)
    end

  elseif msgType == "VERSION_REPLY" then
    if NLC.versionCheckResults then
      local name = sender:match("^([^-]+)") or sender
      NLC.versionCheckResults[name] = data
    end
  end
end

function NLC.Comms.SendMultiSession(items, boss)
  if not IsInRaid() then return end
  local data = { items = {}, timer = NLC.db.config.timer or 90 }
  for idx, item in ipairs(items) do
    table.insert(data.items, {
      sessionIdx = idx,
      itemLink = item.itemLink,
      itemId = item.itemId or 0,
      ilvl = item.ilvl or 0,
      equipLoc = item.equipLoc or "",
      armorType = item.armorType or nil,
      boss = boss or "",
    })
  end
  NLC.Comms.Send("SESSION_START", data)
end

function NLC.Comms.SendMultiInterest(responses)
  NLC.Comms.Send("INTEREST", responses)
end

function NLC.Comms.SendRespond()
  NLC.Comms.Send("RESPOND", "1")
end

function NLC.Comms.SendRollCall()
  NLC.Comms.Send("ROLL_CALL", "")
end
