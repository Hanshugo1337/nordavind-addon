-- Roster.lua
-- Namespacet er GLOBALT i dette addonet (NordavindLC_NS), ikke `...`-varargen.
-- Bruker man `local _, NLC = ...` faar man addonets private tabell i stedet,
-- og da er NLC.Utils nil.
NordavindLC_NS = NordavindLC_NS or {}
local NLC = NordavindLC_NS

--[[
  Roster.lua — leser hele guild-rosteret med offentlige noter, og legger det i
  SavedVariables saa companion kan laste det opp til nordavind.cc.

  Guilden har ~400 karakterer mot 152 Discord-medlemmer. Noten kobler karakter
  til Discord-bruker, og alt til main. Rangen sier hvilken Discord-rolle som
  hoerer til.

  TRE FELLER, alle haandtert nedenfor:

  1. OFFLINE-MEDLEMMER ER SKJULT SOM STANDARD. Uten SetGuildRosterShowOffline(true)
     returnerer GetNumGuildMembers() bare paalogget-medlemmer — typisk ~10 av 400.
     Det ser ut som et gyldig svar. Serveren avviser slike importer, men vi advarer
     ogsaa hoeylytt her, saa feilen oppdages med en gang.

  2. ROSTERET ER THROTTLET. C_GuildInfo.GuildRoster() er en FORESPOERSEL, ikke et
     oppslag. Leser man rett etterpaa faar man forrige svar eller ingenting.
     Vi venter paa GUILD_ROSTER_UPDATE, med timeout.

  3. rankIndex ER 0-BASERT. GetGuildRosterInfo gir 0 for Guild Master, mens
     Guild Control-vinduet viser «Rank 1: Guild Master». Vi lagrer +1 slik at
     tallet stemmer med det menneskene ser. Uten dette forskyves ALLE roller ett
     hakk — Raider blir Backup — og ingenting kraesjer.

  I tillegg: SavedVariables skrives foerst ved /reload eller utlogging. Companion
  ser ingenting foer da, saa vi sier det eksplisitt i chatten.
]]

NLC.Roster = {}

local MIN_FORVENTET = 50   -- under dette er rosteret nesten sikkert avkuttet
local TIMEOUT_SEK   = 15   -- GuildRoster() er throttlet til ~10s

-- Navn kommer som «Revo-TwistingNether». Realm maa bort foer matching mot
-- Discord — karakternavn kan ikke inneholde bindestrek, saa dette er trygt.
local function stripRealm(navn)
  if not navn then return nil end
  return navn:match("^([^-]+)") or navn
end

local function visOfflineMedlemmer()
  -- API-et har flyttet paa seg mellom klientversjoner. Proev begge, og rapporter
  -- om ingen av dem finnes — da er hele importen upaalitelig.
  if C_GuildInfo and C_GuildInfo.SetGuildRosterShowOffline then
    C_GuildInfo.SetGuildRosterShowOffline(true)
    return true
  end
  if type(SetGuildRosterShowOffline) == "function" then
    SetGuildRosterShowOffline(true)
    return true
  end
  return false
end

local function lesRoster()
  local totalt = GetNumGuildMembers()
  local karakterer = {}

  for i = 1, totalt do
    local navn, rangNavn, rankIndex, niva, _, _, publicNote, officerNote = GetGuildRosterInfo(i)
    if navn then
      local aar, mnd, dag, time = GetGuildRosterLastOnline(i)
      local dagerOffline = ((aar or 0) * 365) + ((mnd or 0) * 30) + (dag or 0)
      if (aar or 0) == 0 and (mnd or 0) == 0 and (dag or 0) == 0 and (time or 0) >= 0 then
        dagerOffline = 0
      end

      table.insert(karakterer, {
        name        = stripRealm(navn),
        rankIndex   = (rankIndex or 0) + 1,  -- 0-basert API -> 1-basert som i Guild Control
        rankName    = rangNavn,
        level       = niva,
        publicNote  = publicNote or "",
        -- Officer note er tom for den som mangler rettighet. Tas med fordi
        -- identitet ofte staar der i stedet for i den offentlige noten.
        officerNote = officerNote or "",
        daysOffline = dagerOffline,
      })
    end
  end

  return karakterer, totalt
end

local function oppsummer(karakterer)
  local medNote, tomme, medOfficerNote = 0, 0, 0
  local perRang = {}
  for _, k in ipairs(karakterer) do
    if k.officerNote ~= "" then medOfficerNote = medOfficerNote + 1 end
    if k.publicNote ~= "" then medNote = medNote + 1 else tomme = tomme + 1 end
    local n = k.rankName or ("rank " .. tostring(k.rankIndex))
    perRang[n] = (perRang[n] or 0) + 1
  end
  return medNote, tomme, perRang, medOfficerNote
end

--- Fanger rosteret og legger det i SavedVariables.
function NLC.Roster.Capture()
  if not IsInGuild() then
    NLC.Utils.Print("Du er ikke i en guild.")
    return
  end

  if not visOfflineMedlemmer() then
    NLC.Utils.Print("|cffff5555FEIL:|r fant ikke SetGuildRosterShowOffline i denne klientversjonen. " ..
      "Rosteret ville blitt ufullstendig. Avbryter.")
    return
  end

  NLC.Utils.Print("Henter guild-roster … (kan ta noen sekunder)")

  local ramme = CreateFrame("Frame")
  local ferdig = false

  local function fullfoer()
    if ferdig then return end
    ferdig = true
    ramme:UnregisterAllEvents()
    ramme:SetScript("OnEvent", nil)
    ramme:SetScript("OnUpdate", nil)

    local karakterer, totalt = lesRoster()

    if #karakterer == 0 then
      NLC.Utils.Print("|cffff5555Fikk ingen karakterer.|r Proev igjen om ti sekunder — " ..
        "rosteret er throttlet.")
      return
    end

    NordavindLC_DB.pendingRosterImport = {
      capturedAt = time(),
      characters = karakterer,
    }

    local medNote, tomme, perRang, medOfficerNote = oppsummer(karakterer)

    NLC.Utils.Print(("Fanget |cff55ff55%d|r karakterer (GetNumGuildMembers sa %d)."):format(#karakterer, totalt))
    NLC.Utils.Print(("  Med note: |cff55ff55%d|r   Uten note: |cffffff55%d|r   Officer note: |cff55ff55%d|r"):format(medNote, tomme, medOfficerNote))
    for rang, antall in pairs(perRang) do
      NLC.Utils.Print(("    %s: %d"):format(rang, antall))
    end

    -- Selvkontroll: dette er offline-fella, og den ser ut som suksess.
    if #karakterer < MIN_FORVENTET then
      NLC.Utils.Print(("|cffff5555ADVARSEL: bare %d karakterer.|r Guilden har langt flere. " ..
        "Rosteret er nesten sikkert avkuttet — serveren kommer til aa avvise denne importen. " ..
        "Aapne guild-vinduet (J), huk av for aa vise offline-medlemmer, og proev igjen."):format(#karakterer))
      return
    end

    NLC.Utils.Print("|cff55ff55Klart.|r Skriv nå |cffffff55/reload|r — SavedVariables lagres " ..
      "foerst da, og companion ser ingenting foer fila er skrevet.")
  end

  ramme:RegisterEvent("GUILD_ROSTER_UPDATE")
  ramme:SetScript("OnEvent", function() fullfoer() end)

  -- Timeout: GuildRoster() er throttlet, saa eventet kan utebli helt hvis noen
  -- ba om rosteret nettopp. Da leser vi det vi har framfor aa henge for alltid.
  local gaatt = 0
  ramme:SetScript("OnUpdate", function(_, elapsed)
    gaatt = gaatt + elapsed
    if gaatt >= TIMEOUT_SEK then
      NLC.Utils.Print("Fikk ikke svar innen " .. TIMEOUT_SEK .. "s — leser det som ligger i cache.")
      fullfoer()
    end
  end)

  if C_GuildInfo and C_GuildInfo.GuildRoster then
    C_GuildInfo.GuildRoster()
  elseif type(GuildRoster) == "function" then
    GuildRoster()
  end
end

-- Egen slash-kommando, slik at fila kan slippes inn i en hvilken som helst
-- versjon av addonet uten aa roere Core.lua. `/nordlc roster` finnes ogsaa
-- naar Core.lua er oppdatert; denne virker uansett.
SLASH_NORDROSTER1 = "/nordroster"
SlashCmdList["NORDROSTER"] = function(msg)
  if (msg or ""):trim():lower() == "status" then
    NLC.Roster.Status()
  else
    NLC.Roster.Capture()
  end
end

--- Viser hva som ligger klart til opplasting.
function NLC.Roster.Status()
  local ventende = NordavindLC_DB and NordavindLC_DB.pendingRosterImport
  if not ventende or not ventende.characters then
    NLC.Utils.Print("Ingen roster ligger klart. Kjør /nordlc roster.")
    return
  end
  local alder = time() - (ventende.capturedAt or 0)
  NLC.Utils.Print(("%d karakterer fanget for %d minutter siden."):format(
    #ventende.characters, math.floor(alder / 60)))
end
