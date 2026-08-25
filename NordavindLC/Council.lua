-- Council.lua
-- Council session management — interest collection, timer, award flow

local NLC = NordavindLC_NS

local catOrder = { upgrade = 1, catalyst = 2, offspec = 3, tmog = 4 }
-- Rank er et hardt skille. Verdiene kommer fra nettsiden i små bokstaver.
--
-- "bench" sendes for backups mens rangorden-bryteren er av: ved sesongstart
-- står alle på trial, og gear skal til dem som konkurrerer om faste raidplasser
-- — ikke til benken. Den treffer ellers `or 99` nedenfor og havner sist uansett;
-- den står her eksplisitt så oppførselen er lest og villet, ikke en heldig
-- bivirkning. Den ekte rangen kommer som `displayRank` og brukes kun til visning.
local rankOrder = { raider = 1, backup = 2, trial = 3, bench = 4 }

-- Seedet terningkast — siste ledd når alt annet står likt.
--
-- MÅ gi nøyaktig samme tall som nettsida (`seededRoll` i
-- nordavind-web/lib/rank-order.ts). Spriker de, gir de to verktøyene hvert sitt
-- svar på samme uavgjort — og det er nettopp det tiebreaken finnes for å hindre.
--
-- FNV-1a over UTF-8-bytes. `string.byte` leser bytes, som er grunnen til at
-- nettsida gikk over til `TextEncoder`: `charCodeAt` teller kodepunkter, og et
-- navn som «Visényá» er 7 kodepunkter men 9 bytes.
--
-- Lua har ingen `Math.imul`. `mul32` gjør 32-bits multiplikasjon med kun `%` og
-- `math.floor` — verifisert mot `Math.imul` over 20 000 strenger i
-- lib/rank-order.test.ts («Lua-transkripsjonen gir identisk tall»).
--
-- Fasit for in-game-sjekk (item «Fang of the Abyss», dato 2026-08-18):
--   Shotgrogg → 0.9258441210086095
--   Visényá   → 0.3998504093382159
local function mul32(a, b)
  local lo = (a % 65536) * b
  local hi = (math.floor(a / 65536) * b) % 65536
  return (lo + hi * 65536) % 4294967296
end

local function seededRoll(seed)
  local h = 2166136261
  for i = 1, #seed do
    -- bit.bxor gir et FORTEGNET 32-bits tall. Uten % 4294967296 blir h negativ,
    -- og da gir math.floor(h / 65536) i mul32 feil svar — stille.
    h = bit.bxor(h, seed:byte(i)) % 4294967296
    h = mul32(h, 16777619)
  end
  return h / 4294967295
end

-- Seed-strengen nettsida bygger: itemName|UTC-dato|spillernavn.
-- «!» i date() gir UTC, som er det toISOString() bruker.
local function rollSeed(session, playerName)
  local itemName = session.itemLink and session.itemLink:match("%[(.-)%]") or ""
  return itemName .. "|" .. date("!%Y-%m-%d") .. "|" .. playerName
end

local activeSessions = {}    -- list of session tables (one per item)
local currentWizardIndex = 0 -- which item officer is viewing in wizard
local respondents = {}       -- set of player names who have responded
local raidAddonUsers = 0     -- count of addon users in raid (for auto-close)
local collectingTimer = nil  -- C_Timer ticker reference
local _rollCallAcks = {}     -- tracks addon users who responded to roll call
local _rollCallVersions = {} -- name → addon version, fra samme ack
local _rollCallComplete = false -- true after 3s roll call window
local _collectingClosed = false -- guard against double CloseCollecting

-- Officer-avstemming. Deklarert HER, ikke nede ved resten av avstemmings-
-- seksjonen: Award leser den som upvalue, og en local må være deklarert før
-- funksjonen som leser den. Ligger den under, leser Award en global nil og
-- avstemmingen slår aldri inn — uten feilmelding.
local _vote = { active = false, sessionIdx = nil, ballot = {}, results = {}, officers = {} }

function NLC.Council.StartMultiSession(items, boss)
  if not NLC.isOfficer then
    NLC.Utils.Print("Only officers can start council.")
    return
  end

  -- Et ekte council overtar: testmodus skal aldri gjelde her.
  NLC.testMode = false

  -- Itemene er tatt i bruk. Uten dette ville en etternoeler-rapport dratt inn
  -- igjen det offiseren nettopp fjernet fra panelet.
  NLC.Council.ClearLootAggregation()

  activeSessions = {}
  respondents = {}
  raidAddonUsers = 0
  currentWizardIndex = 1
  _collectingClosed = false

  for idx, item in ipairs(items) do
    table.insert(activeSessions, {
      sessionIdx = idx,
      itemLink = item.itemLink,
      itemId = item.itemId,
      ilvl = item.ilvl,
      equipLoc = item.equipLoc,
      armorType = item.armorType,
      boss = boss or item.boss or "Unknown",
      timer = NLC.db.config.timer or 90,
      interests = {},
      phase = "collecting",
    })
  end

  -- Ensure all raiders are activated before sending session
  NLC.Comms.Send("ACTIVATE", "")
  NLC.Comms.SendMultiSession(items, boss or items[1].boss or "Unknown")
  NLC.Utils.Print("Council started for " .. #items .. " items")

  -- Count addon users via roll call (3s collection window)
  _rollCallAcks = {}
  _rollCallVersions = {}
  _rollCallComplete = false
  NLC.Comms.SendRollCall()
  C_Timer.After(3, function()
    local count = 0
    for _ in pairs(_rollCallAcks) do count = count + 1 end
    raidAddonUsers = count
    _rollCallComplete = true

    -- En utdatert klient rangerer og viser annerledes — f.eks. «BENCH» der det
    -- skal stå «BACKUP» — uten å si fra. Offiseren skal se det før utdeling,
    -- ikke oppdage det i en diskusjon etterpå.
    local minVer = NLC.Utils.AddonVersion()
    local gamle = {}
    for navn, ver in pairs(_rollCallVersions) do
      if ver ~= minVer then table.insert(gamle, navn .. " (" .. ver .. ")") end
    end
    if #gamle > 0 then
      table.sort(gamle)
      NLC.Utils.Print(string.format("|cffffcc00%d av %d kjører en annen versjon enn deg (%s): %s|r",
        #gamle, count, minVer, table.concat(gamle, ", ")))
    end
    -- Ingen ack i det hele tatt betyr at meldinga ikke naadde fram, eller at
    -- den krasjet hos mottakerne. Uten dette kan ikke offiseren skille «sendt
    -- og alt gikk bra» fra «forsvant i stillhet» — og det var nettopp den
    -- forskjellen som kostet oss kvelden 19.08.
    if count == 0 then
      NLC.Utils.Print("|cffff4444Ingen svarte paa roll call.|r Councilet naadde trolig ikke fram.")
      NLC.Utils.Print("  Sjekk /nordlc version, og at raiderne har addonet aktivert.")
      NLC.Utils.Diag("ROLL_CALL: null ack - councilet naadde ingen")
    else
      NLC.Utils.Diag("ROLL_CALL: " .. count .. " klienter svarte")
    end

    -- Check if enough responses already came in during the 3s window
    local respCount = 0
    for _ in pairs(respondents) do respCount = respCount + 1 end
    if raidAddonUsers > 0 and respCount >= raidAddonUsers then
      if collectingTimer then collectingTimer:Cancel(); collectingTimer = nil end
      NLC.Council.CloseCollecting()
    end
  end)
  NLC.UI.ShowMultiItemPopup(activeSessions, NLC.db.config.timer or 90)

  local remaining = NLC.db.config.timer or 90
  collectingTimer = C_Timer.NewTicker(1, function(ticker)
    remaining = remaining - 1
    if remaining <= 0 then
      ticker:Cancel()
      collectingTimer = nil
      NLC.Council.CloseCollecting()
    end
  end, remaining)
end

function NLC.Council.StartSession(itemLink, itemId, ilvl, equipLoc, boss)
  NLC.Council.StartMultiSession({
    { itemLink = itemLink, itemId = itemId, ilvl = ilvl, equipLoc = equipLoc, boss = boss },
  }, boss)
end

function NLC.Council.OnMultiSessionStart(items, timer, sender)
  NLC.Utils.Diag("SESSION_START mottatt fra " .. tostring(sender) .. " | " .. #items .. " items")
  activeSessions = {}
  for _, item in ipairs(items) do
    table.insert(activeSessions, {
      sessionIdx = item.sessionIdx,
      itemLink = item.itemLink,
      itemId = item.itemId,
      ilvl = item.ilvl,
      equipLoc = item.equipLoc,
      armorType = item.armorType,
      boss = item.boss or "Unknown",
      timer = timer,
      interests = {},
      phase = "collecting",
    })
  end
  NLC.UI.ShowMultiItemPopup(activeSessions, timer)
end

function NLC.Council.SubmitResponses(selections)
  local responses = {}
  for _, session in ipairs(activeSessions) do
    local sel = selections[session.sessionIdx]
    if sel and sel.category ~= "pass" then
      local eqLink, eqIlvl = NLC.Utils.GetEquippedInfo(session.equipLoc or "")
      local tierCount = NLC.Utils.GetTierCount()
      table.insert(responses, {
        sessionIdx = session.sessionIdx,
        category = sel.category,
        eqIlvl = eqIlvl or 0,
        eqLink = eqLink or "",
        tierCount = tierCount,
        note = sel.note or "",
      })
    end
  end
  if #responses > 0 then
    NLC.Comms.SendMultiInterest(responses)
  end
  NLC.Comms.SendRespond()
  NLC.Utils.Print("Responses sent for " .. #responses .. " item(s)")
end

function NLC.Council.OnInterestReceived(sender, sessionIdx, category, eqIlvl, tierCount, note, eqLink)
  if not NLC.isOfficer then return end

  local session = nil
  for _, s in ipairs(activeSessions) do
    if s.sessionIdx == sessionIdx then session = s; break end
  end
  if not session then return end

  local name = sender:match("^([^-]+)") or sender
  -- Full sender, ikke det avkuttede navnet: cross-realm trenger realmen.
  local class = NLC.Utils.ClassForPlayer(sender)

  session.interests[name] = {
    category = category,
    equippedIlvl = eqIlvl,
    equippedLink = (eqLink and eqLink ~= "") and eqLink or nil,
    tierCount = tierCount,
    -- Ingen gjetting. «WARRIOR» som standard fikk rustningsfilteret under til aa
    -- kaste ut alle paa et token som ikke var Plate.
    class = class,
    note = (note and note ~= "") and note or nil,
  }

  -- Live: if the wizard is open and this item is still in the ranking phase, rebuild the
  -- ranking and re-render (debounced ~1s to avoid flicker when many respond at once).
  if NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen() then
    NLC.Theme.Debounce("wizard-refresh", 1.0, function()
      local sessions = NLC.Council.GetActiveSessions()
      local idx = NLC.Council.GetWizardIndex()
      local cur = sessions[idx]
      if cur and cur.phase == "ranking" then
        cur.ranked = NLC.Council.BuildRanking(cur)
        NLC.UI.ShowWizard(sessions, idx)
      end
    end)
  end
end

function NLC.Council.OnRespond(sender)
  if not NLC.isOfficer then return end
  local name = sender:match("^([^-]+)") or sender
  respondents[name] = true

  local count = 0
  for _ in pairs(respondents) do count = count + 1 end

  if _rollCallComplete then
    NLC.Utils.Print(count .. " / " .. raidAddonUsers .. " responded")
    if raidAddonUsers > 0 and count >= raidAddonUsers then
      if collectingTimer then
        collectingTimer:Cancel()
        collectingTimer = nil
      end
      NLC.Council.CloseCollecting()
    end
  else
    NLC.Utils.Print(count .. " responded (counting addon users...)")
  end
end

function NLC.Council.CloseCollecting()
  if _collectingClosed or #activeSessions == 0 then return end
  _collectingClosed = true

  for _, session in ipairs(activeSessions) do
    session.phase = "ranking"
  end

  NLC.UI.HideMultiItemPopup()
  NLC.Utils.Print("Collecting closed. Starting award wizard.")

  for _, session in ipairs(activeSessions) do
    session.ranked = NLC.Council.BuildRanking(session)
  end

  -- Broadcast ranking data so all raiders can see the wizard
  local broadcastData = {}
  for _, session in ipairs(activeSessions) do
    table.insert(broadcastData, {
      sessionIdx = session.sessionIdx, itemLink = session.itemLink, itemId = session.itemId,
      ilvl = session.ilvl, equipLoc = session.equipLoc, armorType = session.armorType,
      boss = session.boss, ranked = session.ranked, phase = session.phase,
    })
  end
  NLC.Comms.Send("SESSION_CLOSE", broadcastData)

  currentWizardIndex = 1
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
end

function NLC.Council.BuildRanking(session)
  local candidates = {}

  for name, interest in pairs(session.interests) do
    local imported = NLC.Scoring.GetImportedScore(name)
    local live = {
      equippedIlvl = interest.equippedIlvl,
      tierCount = interest.tierCount,
      isTier = session.armorType ~= nil or (session.equipLoc and (
        session.equipLoc == "INVTYPE_HEAD" or
        session.equipLoc == "INVTYPE_SHOULDER" or
        session.equipLoc == "INVTYPE_CHEST" or
        session.equipLoc == "INVTYPE_ROBE" or
        session.equipLoc == "INVTYPE_HAND" or
        session.equipLoc == "INVTYPE_LEGS"
      )),
    }

    local score, breakdown = NLC.Scoring.Calculate(imported, live, name)
    local warnings = NLC.Scoring.GetWarnings(imported, name)

    -- Tier token filter: exclude candidates whose armor type doesn't match the token
    local skipCandidate = false
    if session.armorType and interest.class then
      -- Kun naar vi FAKTISK kjenner klassen. Ukjent klasse skal vises og
      -- vurderes av offiseren, ikke forsvinne stille ut av lista.
      local classArmor = NLC.Utils.CLASS_ARMOR[interest.class]
      if classArmor and classArmor ~= session.armorType then
        skipCandidate = true
      end
    end

    -- Wishlist safety filter: skip "upgrade" candidates if item not on their wishlist
    -- (front-end also hides the button, but this handles stale import data edge cases)
    -- Tier-slots er fritatt, akkurat som i knappefilteret (Utils.IsTierSlot).
    -- Uten unntaket kunne raideren trykke «Upgrade» paa en tier-del og likevel
    -- bli kastet ut her — og var alle svarene paa en tier-del, ble lista tom.
    if not skipCandidate and interest.category == "upgrade" and session.itemId
       and not (session.armorType or NLC.Utils.IsTierSlot(session.equipLoc)) then
      if imported and imported.wishlist and #imported.wishlist > 0 then
        local wishlisted = false
        for _, wid in ipairs(imported.wishlist) do
          if wid == session.itemId then wishlisted = true; break end
        end
        if not wishlisted then skipCandidate = true end
      end
    end

    if not skipCandidate then

    -- Tmog: random roll 0-100 (generated fresh each ranking)
    local roll = nil
    if interest.category == "tmog" then
      roll = math.random(0, 100)
    end

    local role = imported and imported.role or "dps"

    table.insert(candidates, {
      name = name,
      class = interest.class,
      category = interest.category,
      note = interest.note,
      score = roll or score,
      roll = roll,
      breakdown = (not roll) and breakdown or nil,
      warnings = warnings,
      rank = imported and imported.rank or "trial",
      displayRank = imported and imported.displayRank or nil,
      role = role,
      lootCount = NLC.Scoring.SeasonLootCount(imported, name),
      -- Regnes her, ikke i komparatoren: table.sort kaller den O(n log n) ganger.
      tiebreakRoll = seededRoll(rollSeed(session, name)),
      equippedIlvl = interest.equippedIlvl,
      equippedLink = interest.equippedLink,
      tierCount = interest.tierCount,
      ilvlDiff = (session.ilvl or 0) - (interest.equippedIlvl or 0),
    })
    end -- if not skipCandidate
  end

  table.sort(candidates, function(a, b)
    local ca, cb = catOrder[a.category] or 99, catOrder[b.category] or 99
    if ca ~= cb then return ca < cb end
    -- Rank er et hardt skille: en trial kan aldri rangeres over en raider.
    -- Ukjent rank gir 99, altså sist — aldri først.
    local ra, rb = rankOrder[a.rank] or 99, rankOrder[b.rank] or 99
    if ra ~= rb then return ra < rb end
    -- Rollen ligger allerede som +5 i baseScore fra nettsiden. Som egen
    -- sorteringsnøkkel telte den dobbelt og gjorde rolle til en bøtte —
    -- da ville en tank aldri fått en trinket.
    if a.score ~= b.score then return a.score > b.score end
    -- Står to helt likt, går itemet til den som har fått færrest items denne
    -- sesongen — samme rekkefølge som nettsiden. Uten dette avgjorde table.sort
    -- utfallet, og de to verktøyene kunne gi hvert sitt svar på samme data.
    if (a.lootCount or 0) ~= (b.lootCount or 0) then
      return (a.lootCount or 0) < (b.lootCount or 0)
    end
    -- Fortsatt likt: seedet terning, samme hash som nettsida. Alfabetisk ville
    -- systematisk favorisert navn tidlig i alfabetet over en hel sesong.
    return (a.tiebreakRoll or 0) < (b.tiebreakRoll or 0)
  end)

  return candidates
end

-- Norwegian category labels for raid-facing messages.
local CAT_NO = {
  upgrade = "Oppgradering", offspec = "Offspec", tmog = "Transmog",
  catalyst = "Catalyst", pass = "Pass",
  disenchant = "Disenchant", bank = "Guildbank", free = "Fri",
}

-- Announce an award or change to the whole raid so everyone sees it.
-- RAID_WARNING when we have lead/assist, otherwise RAID. Raid-only.
function NLC.Council.AnnounceRW(text)
  if not IsInRaid() then return end
  local chatType = (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and "RAID_WARNING" or "RAID"
  SendChatMessage(text, chatType)
end

function NLC.Council.Award(playerName)
  if not NLC.isOfficer or not NLC.IsLootLeader() or #activeSessions == 0 then return end

  local session = activeSessions[currentWizardIndex]
  if not session then return end

  -- Er det stemt over akkurat dette itemet, kreves en begrunnelse før noe skjer.
  -- Reglene lover at unntaket logges *med* grunn, ikke bare at det skjedde.
  if _vote.active and _vote.sessionIdx == session.sessionIdx and NLC.UI.ShowReasonPopup then
    NLC.UI.ShowReasonPopup(playerName, function(reason)
      local tally = NLC.Council.FormatVoteTally() or "officer-avstemming"
      NLC.Council.DoAward(playerName, tally .. " — " .. reason)
    end)
    return
  end

  NLC.Council.DoAward(playerName, nil)
end

function NLC.Council.DoAward(playerName, note)
  local session = activeSessions[currentWizardIndex]
  if not session then return end

  -- Find the player's interest category from ranking
  local category = "upgrade"
  if session.ranked then
    for _, c in ipairs(session.ranked) do
      if c.name == playerName then
        category = c.category or "upgrade"
        break
      end
    end
  end

  NLC.Comms.Send("AWARD", { sessionIdx = session.sessionIdx, itemLink = session.itemLink, playerName = playerName, category = category })
  NLC.RecordAward(session.itemLink, playerName, UnitName("player"), session.boss, category, session.itemId, true, note)
  NLC.Utils.Print(session.itemLink .. " awarded to " .. playerName .. " (" .. category .. ")")

  -- Track weekly loot count in SavedVariables (resets each Wednesday).
  -- Kun straffbare kategorier telles — se NLC.Scoring.CountsAsLoot.
  if NLC.Scoring.CountsAsLoot(category) then
    NLC.db.weeklyLoot = NLC.db.weeklyLoot or { resetTimestamp = 0, counts = {} }
    NLC.db.weeklyLoot.counts[playerName] = (NLC.db.weeklyLoot.counts[playerName] or 0) + 1
  end

  local msg = session.itemLink .. " tildelt " .. playerName .. " (" .. (CAT_NO[category] or category) .. ")"
  if note then msg = msg .. " — " .. note end
  NLC.Council.AnnounceRW(msg)

  for i, s in ipairs(activeSessions) do
    if i ~= currentWizardIndex and s.phase == "ranking" then
      s.ranked = NLC.Council.BuildRanking(s)
    end
  end

  session.phase = "awarded"
  NLC.Council.ClearRoll()
  NLC.Council.ClearVote()
  NLC.Council.AdvanceWizard()
end

-- Award to a non-player target (disenchant/bank/free). Logged and tradeable, but does NOT
-- count as loot: no weekly counter, not exported to the website.
local SPECIAL_LABEL = { disenchant = "Disenchant", bank = "Guild Bank", free = "Free" }
function NLC.Council.AwardSpecial(target)
  if not NLC.isOfficer or not NLC.IsLootLeader() then return end
  local session = activeSessions[currentWizardIndex]
  if not session then return end
  local label = SPECIAL_LABEL[target] or target
  NLC.RecordAward(session.itemLink, label, UnitName("player"), session.boss, target, session.itemId, false)
  NLC.Utils.Print(session.itemLink .. " -> " .. label .. " (teller ikke som loot)")
  NLC.Council.AnnounceRW(session.itemLink .. " → " .. (CAT_NO[target] or label) .. " (teller ikke som loot)")
  -- Broadcast so raiders' read-only wizard advances past this item too.
  NLC.Comms.Send("AWARD", { sessionIdx = session.sessionIdx, itemLink = session.itemLink, playerName = label, category = target })
  session.phase = "awarded"
  NLC.Council.ClearRoll()
  NLC.Council.AdvanceWizard()
end

function NLC.Council.AdvanceWizard()
  -- Search forward first, then wrap around to beginning
  for i = currentWizardIndex + 1, #activeSessions do
    if activeSessions[i].phase == "ranking" then
      currentWizardIndex = i
      NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      return
    end
  end
  for i = 1, currentWizardIndex - 1 do
    if activeSessions[i].phase == "ranking" then
      currentWizardIndex = i
      NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      return
    end
  end
  NLC.Utils.Print("All items awarded!")
  NLC.UI.HideWizard()
  activeSessions = {}
end

function NLC.Council.ReopenWizard()
  -- Find the first ranking-phase session and reopen the wizard
  for i, s in ipairs(activeSessions) do
    if s.phase == "ranking" then
      currentWizardIndex = i
      NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      return true
    end
  end
  return false
end

function NLC.Council.AwardLaterCurrent()
  if #activeSessions == 0 then return end
  local session = activeSessions[currentWizardIndex]
  if not session then return end

  table.insert(NLC.pendingSessions, session)
  NLC.Utils.Print(session.itemLink .. " added to pending")
  NLC.UpdateMinimapCount()

  session.phase = "deferred"
  NLC.Council.AdvanceWizard()
end

function NLC.Council.SkipCurrent()
  if #activeSessions == 0 then return end
  activeSessions[currentWizardIndex].phase = "skipped"
  NLC.Council.AdvanceWizard()
end

function NLC.Council.GetActiveSessions()
  return activeSessions
end

-- Test-søm: lar /nordlc test registrere sine fiktive sessions som aktive, slik
-- at wizard-handlinger (avstemming, award) kan kjøres offline. Samme mønster
-- som NLC.LootDetection._setDetected. Ikke ment for vanlig bruk.
function NLC.Council._setActiveSessions(sessions)
  activeSessions = sessions
  currentWizardIndex = 1
end

-- Number of raiders who have responded on a given item (officer only — interests are
-- only populated on the officer's client).
function NLC.Council.GetResponseCount(sessionIdx)
  for _, s in ipairs(activeSessions) do
    if s.sessionIdx == sessionIdx then
      return NLC.Utils.TableCount(s.interests)
    end
  end
  return 0
end

-- Change a candidate's response category on the current wizard item, then rebuild + re-render.
function NLC.Council.ChangeCategory(name, newCategory)
  local session = activeSessions[currentWizardIndex]
  if not session or not session.interests[name] then return end
  session.interests[name].category = newCategory
  session.ranked = NLC.Council.BuildRanking(session)
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
end

-- Remove a candidate from the current wizard item's list, then rebuild + re-render.
function NLC.Council.RemoveCandidate(name)
  local session = activeSessions[currentWizardIndex]
  if not session or not session.interests[name] then return end
  session.interests[name] = nil
  session.ranked = NLC.Council.BuildRanking(session)
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
end

function NLC.Council.WhisperCandidate(name)
  -- Guardet av samme grunn som tooltip-oppslaget i Utils: et Blizzard-navn som
  -- forsvinner mellom klientversjoner kaster, og her ligger kallet i en
  -- meny-klikkhandler midt i utdelingen. Da skal det koste hvisken, ikke wizarden.
  if type(ChatFrame_SendTell) ~= "function" then
    NLC.Utils.Print("Kan ikke aapne hvisk i denne klientversjonen. Skriv /w " .. name)
    return
  end
  local ok = pcall(ChatFrame_SendTell, name)
  if not ok then
    NLC.Utils.Print("Klarte ikke aapne hvisk. Skriv /w " .. name)
  end
end

-- ============================================================
-- Roll-off between candidates (to break ties)
-- ============================================================
local _roll = { names = {}, results = {}, active = false }
local _rollFrame = CreateFrame("Frame")

-- Build a locale-independent pattern from RANDOM_ROLL_RESULT ("%s rolls %d (%d-%d)").
-- Escape ALL magic characters first (including the % in %s/%d and the literal parens),
-- then restore the placeholders as capture groups.
local _rollPattern = (_G.RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")
  :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  :gsub("%%%%s", "(.+)")
  :gsub("%%%%d", "(%%d+)")

function NLC.Council.GetRollState() return _roll end

function NLC.Council.ClearRoll()
  _roll = { names = {}, results = {}, active = false }
  _rollFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
end

function NLC.Council.AddToRoll(name)
  for _, n in ipairs(_roll.names) do if n == name then return end end
  table.insert(_roll.names, name)
  if NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen() then
    NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
  end
end

_rollFrame:SetScript("OnEvent", function(_, _, text)
  if not _roll.active or not text then return end
  local who, roll = text:match(_rollPattern)
  if not who then return end
  who = who:match("^([^-]+)") or who
  for _, n in ipairs(_roll.names) do
    if n == who and not _roll.results[who] then
      _roll.results[who] = tonumber(roll)
      if NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen() then
        NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
      end
      break
    end
  end
end)

function NLC.Council.StartRoll()
  if #_roll.names < 2 then
    NLC.Utils.Print("Legg til minst 2 kandidater i roll-offen.")
    return
  end
  if _roll.timer then _roll.timer:Cancel() end
  _roll.results = {}
  _roll.active = true
  _rollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
  local session = activeSessions[currentWizardIndex]
  local itemLabel = (session and session.itemLink) or "item"
  local myName = UnitName("player")
  for _, n in ipairs(_roll.names) do
    if n == myName then
      RandomRoll(1, 100)
    else
      SendChatMessage("Roll-off for " .. itemLabel .. " — /roll 100 takk!", "WHISPER", nil, n)
    end
  end
  -- Close the capture window after 15s (cancellable so a re-started roll-off resets it).
  _roll.timer = C_Timer.NewTimer(15, function()
    _roll.timer = nil
    _roll.active = false
    _rollFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
  end)
end

function NLC.Council.GetWizardIndex()
  return currentWizardIndex
end

function NLC.Council.SetWizardIndex(idx)
  if idx >= 1 and idx <= #activeSessions and activeSessions[idx].phase == "ranking" then
    currentWizardIndex = idx
    NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
  end
end

function NLC.Council.ResumePending(index)
  local session = table.remove(NLC.pendingSessions, index)
  if not session then return end
  activeSessions = { session }
  currentWizardIndex = 1
  session.phase = "ranking"
  session.ranked = NLC.Council.BuildRanking(session)
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
  NLC.UpdateMinimapCount()
end

function NLC.Council.ResumeAll()
  if #NLC.pendingSessions == 0 then
    NLC.Utils.Print("Ingen ufordelte items.")
    return
  end

  activeSessions = {}
  for _, session in ipairs(NLC.pendingSessions) do
    session.phase = "ranking"
    session.ranked = NLC.Council.BuildRanking(session)
    table.insert(activeSessions, session)
  end
  NLC.pendingSessions = {}
  NLC.UpdateMinimapCount()

  currentWizardIndex = 1
  NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
  NLC.Utils.Print("Wizard opened with " .. #activeSessions .. " pending items.")
end

local SPECIAL_CAT = { disenchant = true, bank = true, free = true }
function NLC.Council.OnAward(sessionIdx, itemLink, playerName, sender, category)
  if SPECIAL_CAT[category] then
    NLC.Utils.Print(itemLink .. " → " .. (CAT_NO[category] or playerName) .. " (teller ikke som loot)")
  else
    NLC.Utils.Print(itemLink .. " tildelt " .. playerName .. " (" .. (CAT_NO[category] or category or "?") .. ")")
  end

  -- Non-officers: update read-only wizard display
  if not NLC.isOfficer then
    for _, session in ipairs(activeSessions) do
      if session.sessionIdx == sessionIdx then
        session.phase = "awarded"
        break
      end
    end
    -- Advance to next unawarded item
    for i = 1, #activeSessions do
      if activeSessions[i].phase == "ranking" then
        currentWizardIndex = i
        NLC.UI.ShowWizard(activeSessions, currentWizardIndex)
        return
      end
    end
    NLC.UI.HideWizard()
  end
end

function NLC.Council.OnSessionClose(data)
  activeSessions = data
  currentWizardIndex = 1
  -- Raiders don't need the wizard — they receive award announcements via chat
end

function NLC.Council.OnRollCallAck(sender, version)
  local name = sender:match("^([^-]+)") or sender
  _rollCallAcks[name] = true
  -- Tom versjon = klient fra før ack-en bar versjon. Den er per definisjon
  -- gammel, så den skal telles med blant de utdaterte.
  _rollCallVersions[name] = (version ~= nil and version ~= "" and version) or "?"
end

-- ============================================================
-- Distributed loot aggregation (officer only)
-- Each raider sends LOOT_REPORT after a boss; the officer collects reports over a
-- short window and feeds the merged list into the existing Loot Detected panel.
-- ============================================================
local _agg = {}          -- itemKey -> item
local _aggTimer = nil
local _aggBoss = nil

-- Toemmes naar councilet faktisk starter, ikke naar panelet vises. Se under.
function NLC.Council.ClearLootAggregation()
  _agg = {}
  _aggBoss = nil
  if _aggTimer then _aggTimer:Cancel(); _aggTimer = nil end
end

function NLC.Council.OnLootReport(sender, data)
  if not NLC.isOfficer then
    NLC.Utils.Diag("LOOT_REPORT fra " .. tostring(sender) .. " forkastet - jeg er ikke officer")
    return
  end
  if not data or not data.items then return end
  NLC.Utils.Diag("LOOT_REPORT mottatt fra " .. tostring(sender) .. " | " .. #data.items .. " items")
  -- Ny boss = ny runde. Ellers bygger vi videre paa det som allerede ligger.
  if data.boss and _aggBoss and data.boss ~= _aggBoss then _agg = {} end
  _aggBoss = data.boss or _aggBoss
  -- Dedup paa tvers av AVSENDERE: samme item rapportert av to klienter er ett
  -- item. Men to EKSEMPLARER av samme item i samme rapport er to items, og de
  -- skal begge med.
  --
  -- 24.08 sto det «Sendte LOOT_REPORT: 5 items» og ti sekunder senere
  -- «Aggregering ferdig | 4 items totalt -> panel». Noekkelen var itemId:looter,
  -- saa det andre eksemplaret av Frostscale's Mystic Frond forsvant uten et ord.
  -- Det ble likevel delt ut — men foerst etter at lederen tydde til
  -- /nordlc addall, som ser hele baggen og gaar utenom aggregeringa.
  --
  -- Telleren er per MELDING. To eksemplarer i én rapport gir #1 og #2; den samme
  -- rapporten fra en annen avsender starter paa #1 igjen og treffer dermed samme
  -- noekkel som foer. Begge egenskapene beholdes altsaa samtidig.
  local forekomst = {}
  for _, it in ipairs(data.items) do
    local grunnlag = (it.itemId or 0) .. ":" .. (it.looter or sender)
    forekomst[grunnlag] = (forekomst[grunnlag] or 0) + 1
    local key = grunnlag .. "#" .. forekomst[grunnlag]
    if not _agg[key] then _agg[key] = it end
  end
  -- Vent til det har vaert stille i 10 sekunder, og vis SUMMEN av alt som har
  -- kommet inn for denne bossen — ikke bare siste pulje.
  --
  -- Klientene stenger ikke samtidig lenger: hver enkelt forlenger sitt eget
  -- innsamlingsvindu etter rullene den selv er med i, saa en som ikke kunne
  -- rulle paa noe melder foer de andre. Med en pulje som ERSTATTET forrige ville
  -- den foerste rapporten forsvunnet fra panelet i det neste kom inn.
  if _aggTimer then _aggTimer:Cancel() end
  _aggTimer = C_Timer.NewTimer(10, function()
    _aggTimer = nil
    local items = {}
    for _, it in pairs(_agg) do table.insert(items, it) end
    NLC.Utils.Diag("Aggregering ferdig | " .. #items .. " items totalt -> panel")
    if #items > 0 then
      NLC.LootDetection._setDetected(items)
      NLC.UI.ShowLootDetected(items)
    end
  end)
end

-- ============================================================
-- Officer-avstemming
--
-- Rådgivende: lederen deler ut som før, men når en avstemming er aktiv kreves
-- en begrunnelse, og stemmetallet følger itemet til databasen.
--
-- NLC.isOfficer avgjøres lokalt på hver klient (se Core.lua), så en raider kan
-- teknisk sett stemme ved å endre egne SavedVariables. Vi låser ikke dette —
-- det er et guild-addon, ikke en sikkerhetsgrense — men opptellingen viser
-- navn, slik at et misbruk blir synlig i stedet for skjult.
--
-- Tilstanden (_vote) er deklarert øverst i fila, se kommentaren der.
-- ============================================================

function NLC.Council.GetVoteState() return _vote end

function NLC.Council.ClearVote()
  _vote = { active = false, sessionIdx = nil, ballot = {}, results = {}, officers = {} }
end

-- Lederen starter. Egen kringkasting kommer tilbake til oss selv, så vi blir
-- talt med blant officers og får stemmevinduet på lik linje med de andre.
function NLC.Council.StartVote(sessionIdx, ballot)
  if not NLC.isOfficer or not NLC.IsLootLeader() then return end
  if #ballot < 2 then
    NLC.Utils.Print("Legg minst to kandidater på stemmeseddelen.")
    return
  end
  _vote = { active = true, sessionIdx = sessionIdx, ballot = ballot, results = {}, officers = {} }
  NLC.Comms.Send("VOTE_START", { sessionIdx = sessionIdx, ballot = ballot })
  NLC.Council.AnnounceRW("Officer-avstemming startet — " .. #ballot .. " kandidater")
end

function NLC.Council.OnVoteStart(sender, data)
  if not NLC.isOfficer then return end
  NLC.Comms.Send("VOTE_ACK", { sessionIdx = data.sessionIdx })
  if NLC.UI.ShowVotePopup then
    NLC.UI.ShowVotePopup(data.sessionIdx, data.ballot)
  end
end

function NLC.Council.OnVoteAck(sender, data)
  if not _vote.active or data.sessionIdx ~= _vote.sessionIdx then return end
  local name = sender:match("^([^-]+)") or sender
  _vote.officers[name] = true
  NLC.Council.RefreshVoteUI()
end

function NLC.Council.CastVote(sessionIdx, choice)
  NLC.Comms.Send("VOTE_CAST", { sessionIdx = sessionIdx, choice = choice })
end

function NLC.Council.OnVoteCast(sender, data)
  if not _vote.active or data.sessionIdx ~= _vote.sessionIdx then return end
  local name = sender:match("^([^-]+)") or sender
  -- Ny stemme fra samme avsender overskriver forrige, så feilklikk kan rettes.
  _vote.results[name] = data.choice
  NLC.Council.RefreshVoteUI()
end

-- Tegner wizarden på nytt hvis den står åpen.
function NLC.Council.RefreshVoteUI()
  if not (NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen()) then return end
  NLC.Theme.Debounce("vote-refresh", 0.5, function()
    NLC.UI.ShowWizard(NLC.Council.GetActiveSessions(), NLC.Council.GetWizardIndex())
  end)
end

function NLC.Council.GetVoteTally()
  if not _vote.active then return nil end

  local counts, voters = {}, {}
  for voter, choice in pairs(_vote.results) do
    counts[choice] = (counts[choice] or 0) + 1
    voters[choice] = voters[choice] or {}
    table.insert(voters[choice], voter)
  end

  local rows = {}
  for _, name in ipairs(_vote.ballot) do
    local v = voters[name] or {}
    table.sort(v)
    table.insert(rows, { name = name, count = counts[name] or 0, voters = v })
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)

  local cast = 0
  for _ in pairs(_vote.results) do cast = cast + 1 end
  local officers = 0
  for _ in pairs(_vote.officers) do officers = officers + 1 end

  return { rows = rows, cast = cast, officers = officers }
end

-- "officer-avstemming 3-2-1" — stemmetallet i synkende rekkefølge.
function NLC.Council.FormatVoteTally()
  local tally = NLC.Council.GetVoteTally()
  if not tally then return nil end
  local parts = {}
  for _, row in ipairs(tally.rows) do
    table.insert(parts, tostring(row.count))
  end
  return "officer-avstemming " .. table.concat(parts, "-")
end
