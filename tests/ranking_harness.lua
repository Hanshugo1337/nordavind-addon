-- Testrigg for at rangeringsvinduet ikke ender tomt.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/ranking_harness.lua',encoding='utf-8').read())"
--
-- Bruker 2026-08-19: «rangeringsvinduet er tomt». To filtre i BuildRanking kunne
-- toemme lista, og begge slaar til i et cross-realm raid — som er nettopp det
-- Nordavind kjoerer (Draenor, Stormscale, TarrenMill, Darksorrow samme kveld).
--
-- 1) UnitClass tar en unit-id. Et spillernavn duger for folk i gruppa di, men
--    cross-realm MAA realmen vaere med. Offiseren strippet den og falt tilbake
--    paa «WARRIOR» for alle. Paa et tier-token sammenlignet rustningsfilteret da
--    Plate mot alle: var tokenet Cloth, ble HVER kandidat kastet ut.
--
-- 2) Front-end fritar tier-slots fra wishlist-filteret, rangeringen gjorde ikke.
--    Raideren kunne trykke «Upgrade» paa en tier-del og likevel forsvinne.

CreateFrame = function()
  return { RegisterEvent = function() end, UnregisterEvent = function() end,
           UnregisterAllEvents = function() end, SetScript = function() end }
end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function() return { Cancel = function() end } end }
GetTime = function() return 0 end
IsInRaid = function() return true end
UnitIsGroupLeader = function() return true end
UnitName = function() return "Bobletount" end
date = date or function() return "2026-08-19" end
bit = { bxor = function(a, b) return a ~ b end }

-- Cross-realm raid. UnitClass svarer KUN paa fullt navn med realm, slik spillet
-- oppfoerer seg. Rosteret kjenner alle.
local roster = {
  { navn = "Bobletount-Draenor",  klasse = "PALADIN" },  -- Plate
  { navn = "Moggin-TarrenMill",   klasse = "WARLOCK" },  -- Cloth
  { navn = "Areniir-Darksorrow",  klasse = "PRIEST"  },  -- Cloth
  { navn = "Shotgrogg-Stormscale",klasse = "WARRIOR" },  -- Plate
}
UnitClass = function(id)
  for _, r in ipairs(roster) do
    if r.navn == id then return "visningsnavn", r.klasse end
  end
  return nil
end
GetNumGroupMembers = function() return #roster end
GetRaidRosterInfo = function(i)
  local r = roster[i]
  if not r then return nil end
  return r.navn, 0, 1, 80, "Klasse", r.klasse
end

NordavindLC_NS = {}
dofile("NordavindLC/Utils.lua")
local NLC = NordavindLC_NS
NLC.isOfficer = true
NLC.db = { config = { timer = 90 }, importData = { players = {} }, weeklyLoot = { counts = {} } }

local wishlister = {}
sisteLive = nil           -- det BuildRanking sist sendte til Calculate
local harSims = {}        -- navn -> false naar spilleren mangler sims
local simDataOk = false   -- svarer paa om sim-hentingen lyktes
NLC.Scoring = {
  GetImportedScore = function(navn)
    return { rank = "raider", role = "dps", baseScore = 40, wishlist = wishlister[navn] or {},
             hasSims = harSims[navn] }
  end,
  Calculate = function(_, live) sisteLive = live; return 40, {} end,
  GetWarnings = function() return {} end,
  SeasonLootCount = function() return 0 end,
  SimPctFor = function() return nil end,
  SimDataOk = function() return simDataOk end,
}
NLC.Comms = { Send = function() end, SendMultiSession = function() end,
              SendRollCall = function() end, IsRestricted = function() return false end }
NLC.UI = { ShowMultiItemPopup = function() end, ShowWizard = function() end,
           HideMultiItemPopup = function() end, IsWizardOpen = function() return false end }
NLC.Theme = { Debounce = function(_, _, fn) fn() end }
NLC.LootDetection = { GetCurrentBoss = function() return "Nek'zali" end }
NLC.Trade = { Add = function() end }
dofile("NordavindLC/Council.lua")

local function navnene(rangert)
  local t = {}
  for _, c in ipairs(rangert) do t[#t + 1] = c.name end
  table.sort(t)
  return table.concat(t, ", ")
end

-- --- 1: klassen loeses opp cross-realm ---
assert(NLC.Utils.ClassForPlayer("Moggin-TarrenMill") == "WARLOCK",
       "fullt navn med realm ga ikke klassen")
assert(NLC.Utils.ClassForPlayer("Moggin") == "WARLOCK",
       "kortformen fant ikke klassen via rosteret")
assert(NLC.Utils.ClassForPlayer("Ukjentfyr-Annen") == nil,
       "en som ikke er i raidet skal gi nil, ikke en gjetning")
print("klasseoppslag        : OK -> cross-realm loest, ukjent gir nil")

-- --- 2: Cloth-token i et cross-realm raid ---
local token = {
  sessionIdx = 1, itemLink = "|cffa335ee|Hitem:268999::::::::90:::::|h[Token]|h|r",
  itemId = 268999, ilvl = 678, equipLoc = "", armorType = "Cloth",
  interests = {}, phase = "ranking",
}
for _, r in ipairs(roster) do
  local kort = r.navn:match("^([^-]+)")
  token.interests[kort] = {
    category = "upgrade", equippedIlvl = 660, tierCount = 2,
    class = NLC.Utils.ClassForPlayer(r.navn),
  }
end

local rangert = NLC.Council.BuildRanking(token)
assert(#rangert > 0, "TOMT rangeringsvindu paa et Cloth-token — dette ER feilen")
assert(#rangert == 2, "forventet de to cloth-klassene, fikk " .. #rangert .. ": " .. navnene(rangert))
assert(navnene(rangert) == "Areniir, Moggin",
       "feil kandidater: " .. navnene(rangert))
print("Cloth-token          : OK -> " .. navnene(rangert) .. " (plate filtrert bort)")

-- Med den gamle «WARRIOR»-gjettinga ville CLASS_ARMOR gitt Plate for alle fire,
-- og Plate ~= Cloth hadde kastet ut samtlige.

-- --- 3: ukjent klasse skal vises, ikke forsvinne ---
token.interests["Nykommer"] = { category = "upgrade", equippedIlvl = 650, tierCount = 0, class = nil }
local medUkjent = NLC.Council.BuildRanking(token)
local fantUkjent = false
for _, c in ipairs(medUkjent) do if c.name == "Nykommer" then fantUkjent = true end end
assert(fantUkjent, "ukjent klasse ble filtrert bort i stillhet")
print("ukjent klasse        : OK -> vises for offiseren i stedet for aa forsvinne")

-- --- 4: tier-slot uten wishlist skal IKKE filtreres ---
wishlister["Moggin"] = { 999999 }  -- har wishlist, men ikke dette itemet
local tierDel = {
  sessionIdx = 2, itemLink = "|cffa335ee|Hitem:268235::::::::90:::::|h[Tier-bryst]|h|r",
  itemId = 268235, ilvl = 671, equipLoc = "INVTYPE_CHEST",
  interests = { Moggin = { category = "upgrade", equippedIlvl = 660, tierCount = 2, class = "WARLOCK" } },
  phase = "ranking",
}
local tierRangert = NLC.Council.BuildRanking(tierDel)
assert(#tierRangert == 1,
       "tier-slot ble filtrert bort av wishlist-filteret — front-end fritar den, rangeringen maa ogsaa")
print("tier-slot + wishlist : OK -> beholdt, som i knappefilteret")

-- --- 5: item utenfor wishlista skal IKKE lenger utelukke noen ---
--
-- Endret 2026-08-25. Filteret utelukket kandidaten helt; nettsida sluttet med
-- det med vilje («0 % i sim utelukker IKKE lenger noen»), og addonet var dermed
-- strengere enn regelverket. Nå står han i lista og taper bare sim-poengene.
local vanlig = {
  sessionIdx = 3, itemLink = "|cffa335ee|Hitem:270162::::::::90:::::|h[Ring]|h|r",
  itemId = 270162, ilvl = 671, equipLoc = "INVTYPE_FINGER",
  interests = { Moggin = { category = "upgrade", equippedIlvl = 660, tierCount = 2, class = "WARLOCK" } },
  phase = "ranking",
}
assert(#NLC.Council.BuildRanking(vanlig) == 1,
       "item utenfor wishlista skal gi 0 sim-poeng, ikke utestengelse")
print("utenfor wishlista    : OK -> beholdt, som paa nettsida")

-- --- 6: sim-porten (regeltekst linje 74) ---
harSims["Moggin"] = false

simDataOk = false
assert(#NLC.Council.BuildRanking(vanlig) == 1,
       "feilet sim-henting skal ALDRI utestenge noen")
print("sim-porten, data ute : OK -> ingen utestengt naar hentingen feilet")

simDataOk = true
assert(#NLC.Council.BuildRanking(vanlig) == 1,
       "porten er AV som standard - healerne har ingen sims og ville forsvunnet")
print("sim-porten av        : OK -> ingen utestengt naar porten er av")

NLC.db.config.simPort = true
assert(#NLC.Council.BuildRanking(vanlig) == 0,
       "slaas porten paa, skal spilleren uten sims ikke vurderes")
print("sim-porten paa       : OK -> uten sims, ikke kandidat")
NLC.db.config.simPort = nil

harSims["Moggin"] = nil
simDataOk = false

-- --- 7: vanlige items i tier-sloter er IKKE tier ---
--
-- Raidet 23.09: Soulslither Spaulders, Awoken Dreadfang Cuirass og Initiate's
-- Sacrificial Tights ble regnet som tier fordi de satt i skulder/bryst/bukse.
-- Da byttet Calculate ut sim-poengene med tierGain, som nesten alltid er 0.
-- Nettsida regner kun tokenene som tier (isTier: false i lib/loot-tables.ts).
local vanligBryst = {
  sessionIdx = 4, itemLink = "|cffa335ee|Hitem:268250::::::::90:::::|h[Awoken Dreadfang Cuirass]|h|r",
  itemId = 268250, ilvl = 671, equipLoc = "INVTYPE_CHEST",
  interests = { Moggin = { category = "upgrade", equippedIlvl = 660, tierCount = 2, class = "WARLOCK" } },
  phase = "ranking",
}
NLC.Council.BuildRanking(vanligBryst)
assert(sisteLive and sisteLive.isTier == false,
       "vanlig brystplagg ble regnet som tier - mister sim-poengene")
NLC.Council.BuildRanking(token)
assert(sisteLive and sisteLive.isTier == true, "tier-token skal fortsatt vaere tier")
print("tier = kun tokens    : OK -> vanlig bryst er ikke tier, token er")

-- --- 8: roll per kategori (offspec/tmog) ---
--
-- Bruker 23.09: «trykke roll på offspec, istedenfor at ALLE må /roll». Addonet
-- trekker kastene selv, og de LIGGER FAST til itemet er delt ut. Tmog ble
-- trukket paa nytt ved hver ombygging (hvert nytt svar), saa rekkefoelgen hoppet.
local sendt = {}
SendChatMessage = function(tekst) sendt[#sendt + 1] = tekst end
UnitIsGroupAssistant = function() return false end
NLC.IsLootLeader = function() return true end

local function kandidat(liste, navn)
  for _, c in ipairs(liste) do if c.name == navn then return c end end
end

local os = {
  sessionIdx = 5, itemLink = "|cffa335ee|Hitem:270200::::::::90:::::|h[Ring]|h|r",
  itemId = 270200, ilvl = 671, equipLoc = "INVTYPE_FINGER", phase = "ranking",
  interests = {
    Moggin  = { category = "offspec", class = "WARLOCK" },
    Areniir = { category = "offspec", class = "PRIEST" },
    Shotgrogg = { category = "tmog", class = "WARRIOR" },
    Bobletount = { category = "upgrade", class = "PALADIN" },
  },
}
NLC.Council._setActiveSessions({ os })

local r1 = NLC.Council.BuildRanking(os)
assert(kandidat(r1, "Moggin").roll == nil, "offspec skal ikke rulles foer knappen trykkes")
local tmogKast = kandidat(r1, "Shotgrogg").roll
assert(type(tmogKast) == "number", "tmog skal rulles automatisk")
for _ = 1, 20 do
  assert(kandidat(NLC.Council.BuildRanking(os), "Shotgrogg").roll == tmogKast,
         "tmog-kastet ble trukket paa nytt ved ombygging")
end
print("tmog-kast ligger fast: OK -> samme tall etter 20 ombygginger")

NLC.Council.RollCategory("offspec")
local r2 = NLC.Council.BuildRanking(os)
local mK, aK = kandidat(r2, "Moggin").roll, kandidat(r2, "Areniir").roll
assert(type(mK) == "number" and type(aK) == "number", "alle i offspec skal ha fått et kast")
assert(mK >= 1 and mK <= 100 and aK >= 1 and aK <= 100, "kastet skal vaere 1-100 som /roll")
assert(kandidat(r2, "Bobletount").roll == nil, "upgrade skal aldri rulles")
assert(#sendt == 1 and sendt[1]:find("Offspec") and sendt[1]:find("Moggin") and sendt[1]:find("Areniir"),
       "resultatet skulle ut i raid-chatten: " .. tostring(sendt[1]))

-- Innenfor offspec sorteres paa kastet (høyest først).
local foerst
for _, c in ipairs(r2) do if c.category == "offspec" then foerst = c; break end end
assert(foerst.roll == math.max(mK, aK), "offspec er ikke sortert paa kastet")

-- Nytt svar etter kastet: faar eget kast, de gamle staar.
os.interests["Nykommer"] = { category = "offspec" }
local r3 = NLC.Council.BuildRanking(os)
assert(kandidat(r3, "Moggin").roll == mK and kandidat(r3, "Areniir").roll == aK,
       "de gamle kastene ble trukket paa nytt")
assert(type(kandidat(r3, "Nykommer").roll) == "number", "nykommer fikk ikke kast")

-- Trykk igjen: ingen nye tall, bare ny annonsering.
NLC.Council.RollCategory("offspec")
assert(kandidat(NLC.Council.BuildRanking(os), "Moggin").roll == mK, "nytt trykk trakk paa nytt")
assert(#sendt == 2, "nytt trykk skal annonsere igjen")
print("offspec-roll         : OK -> rulles paa knapp, ligger fast, nye faar eget kast")

print("\nALLE PAASTANDER HOLDT")
-- --- BiS/Major/Stat (30.09.2026) ---
assert(NLC.Council.NormaliserKategori("upgrade") == "major", "gammel upgrade -> major")
assert(NLC.Council.NormaliserKategori("catalyst") == "major", "gammel catalyst -> major")
assert(NLC.Council.NormaliserKategori("bis") == "bis", "bis urort")
assert(NLC.Council.NormaliserKategori("tmog") == "tmog", "tmog urort")

local kat = {
  sessionIdx = 90, itemLink = "|cffa335ee|Hitem:270300::::::::90:::::|h[Ring]|h|r", itemId = 270300, ilvl = 678,
  equipLoc = "INVTYPE_FINGER", boss = "Test", timer = 90, phase = "ranking", interests = {
    ["Moggin"]     = { category = "stat",    class = "WARLOCK" },
    ["Areniir"]    = { category = "bis",     class = "PRIEST"  },
    ["Shotgrogg"]  = { category = "major",   class = "WARRIOR" },
    ["Bobletount"] = { category = "offspec", class = "PALADIN" },
  },
}
local rk = NLC.Council.BuildRanking(kat)
local rekke = {}
for _, c in ipairs(rk) do table.insert(rekke, c.category) end
assert(table.concat(rekke, ",") == "bis,major,stat,offspec", "rekkefolge: " .. table.concat(rekke, ","))
print("bis > major > stat   : OK -> knappen gaar foran poengene")

-- Gammel klient sender «upgrade»: skal havne i Major, ikke bakerst.
kat.interests = {}
NLC.Council._setActiveSessions({ kat })
NLC.Council.OnInterestReceived("Moggin-TarrenMill", 90, "upgrade", 670, 0, nil, nil)
assert(kat.interests["Moggin"] and kat.interests["Moggin"].category == "major",
       "upgrade fra gammel klient ble ikke major")
print("gammel klient        : OK -> upgrade blir major")
-- --- Alle ser rangeringen (30.09.2026) ---
-- Officer: en endring etter lukking sendes ut som RANKING.
local sendtRanking = {}
local gammelSend = NLC.Comms.Send
NLC.Comms.Send = function(t, data) if t == "RANKING" then table.insert(sendtRanking, data) end end
local vis = {
  sessionIdx = 91, itemLink = "|cffa335ee|Hitem:270301::::::::90:::::|h[Ring]|h|r", itemId = 270301, ilvl = 678,
  equipLoc = "INVTYPE_FINGER", boss = "Test", timer = 90, phase = "ranking", interests = {
    ["Moggin"]  = { category = "major", class = "WARLOCK" },
    ["Areniir"] = { category = "stat",  class = "PRIEST"  },
  },
}
NLC.Council._setActiveSessions({ vis })
vis.ranked = NLC.Council.BuildRanking(vis)
NLC.Council.ChangeCategory("Areniir", "bis")
assert(#sendtRanking == 1 and sendtRanking[1].sessionIdx == 91, "kategoribytte sendte ikke RANKING")
assert(sendtRanking[1].ranked[1].name == "Areniir", "RANKING bar ikke den nye rekkefolgen")
NLC.Comms.Send = gammelSend
print("RANKING sendes       : OK -> etter kategoribytte")

-- Raider: tar imot og bytter lista for riktig item.
NLC.isOfficer = false
local raiderSesjon = { sessionIdx = 91, phase = "ranking", ranked = {} }
NLC.Council.OnSessionClose({ raiderSesjon })
NLC.Council.OnRanking({ sessionIdx = 91, ranked = { { name = "Areniir", category = "bis" } } })
assert(raiderSesjon.ranked[1] and raiderSesjon.ranked[1].name == "Areniir", "raideren fikk ikke oppdateringen")
assert(NLC.Council.ReopenWizard() == true, "/nordlc council virker ikke for raidere")
NLC.isOfficer = true
print("RANKING mottas       : OK -> raideren ser ny rekkefolge")
-- Raideren ser, men kan ikke hoppe over eller utsette et item.
NLC.isOfficer = false
local kunSe = { sessionIdx = 92, phase = "ranking", ranked = {} }
NLC.Council.OnSessionClose({ kunSe })
NLC.Council.SkipCurrent()
assert(kunSe.phase == "ranking", "raideren kunne hoppe over et item")
NLC.Council.AwardLaterCurrent()
assert(kunSe.phase == "ranking", "raideren kunne utsette et item")
NLC.isOfficer = true
print("raider kun visning   : OK -> ingen handlinger")
-- --- Review-funn (30.09.2026) ---
SendChatMessage = function() end
NLC.RecordAward = function() end
NLC.Scoring.AddWeeklyAward = NLC.Scoring.AddWeeklyAward or function() end
NLC.UI.HideWizard = NLC.UI.HideWizard or function() end
local fanget = {}
local gSend = NLC.Comms.Send
NLC.Comms.Send = function(t, data, mottaker, prio)
  if t == "RANKING" then table.insert(fanget, { data = data, prio = prio }) end
end
local function sesjon(idx, interesser)
  return { sessionIdx = idx, itemLink = "|cffa335ee|Hitem:2703" .. idx .. "::::::::90:::::|h[Ring]|h|r",
           itemId = 270300 + idx, ilvl = 678, equipLoc = "INVTYPE_FINGER", boss = "Test", timer = 90,
           phase = "ranking", interests = interesser }
end

-- I3: RANKING er slanket, bærer itemLink og går med BULK-prioritet.
local sA = sesjon(1, { ["Moggin"] = { category = "major", class = "WARLOCK", equippedLink = "|cffxx|Hitem:1|h[Gammel]|h|r" } })
NLC.Council._setActiveSessions({ sA })
sA.ranked = NLC.Council.BuildRanking(sA)
NLC.Council.BroadcastRanking(sA)
assert(#fanget == 1, "ingen RANKING")
assert(fanget[1].prio == "BULK", "RANKING skal ha BULK, fikk " .. tostring(fanget[1].prio))
assert(fanget[1].data.itemLink == sA.itemLink, "RANKING mangler itemLink")
local k1 = fanget[1].data.ranked[1]
assert(k1.name == "Moggin" and k1.equippedLink == nil and k1.tiebreakRoll == nil, "RANKING er ikke slanket")
print("RANKING-last         : OK -> slank, itemLink, BULK")

-- I3: etter en utdeling sendes bare items der mottakeren er kandidat.
fanget = {}
local sB = sesjon(2, { ["Areniir"] = { category = "bis", class = "PRIEST" } })
local sC = sesjon(3, { ["Moggin"] = { category = "stat", class = "WARLOCK" }, ["Areniir"] = { category = "major", class = "PRIEST" } })
local sD = sesjon(4, { ["Shotgrogg"] = { category = "major", class = "WARRIOR" } })
NLC.Council._setActiveSessions({ sB, sC, sD })
for _, s in ipairs({ sB, sC, sD }) do s.ranked = NLC.Council.BuildRanking(s) end
NLC.Council.DoAward("Areniir", nil)
assert(#fanget == 1 and fanget[1].data.sessionIdx == 3, "skulle kun sendt item 3, sendte " .. #fanget)
print("RANKING etter award  : OK -> kun items der mottakeren er med")

-- I5: sent svar mens rangeringen er aapen naar ogsaa raidet.
fanget = {}
local sE = sesjon(5, {})
NLC.Council._setActiveSessions({ sE })
sE.ranked = NLC.Council.BuildRanking(sE)
local gOpen = NLC.UI.IsWizardOpen
NLC.UI.IsWizardOpen = function() return true end
NLC.Council.OnInterestReceived("Moggin-TarrenMill", 5, "bis", 670, 0, nil, nil)
NLC.UI.IsWizardOpen = gOpen
assert(#fanget == 1 and fanget[1].data.ranked[1].name == "Moggin", "sent svar ble ikke sendt til raidet")
print("sent svar            : OK -> sendes ut")
NLC.Comms.Send = gSend

-- Minor 2 (oppgradert): RANKING for et annet item med samme sessionIdx ignoreres.
NLC.isOfficer = false
local ny = { sessionIdx = 1, itemLink = "|cffa335ee|Hitem:999::::::::90:::::|h[Ny boss]|h|r", phase = "ranking", ranked = { { name = "Riktig" } } }
NLC.Council.OnSessionClose({ ny })
NLC.Council.OnRanking({ sessionIdx = 1, itemLink = "|cffa335ee|Hitem:111::::::::90:::::|h[Forrige boss]|h|r", ranked = { { name = "Feil" } } })
assert(ny.ranked[1].name == "Riktig", "RANKING fra forrige boss overskrev nytt item")

-- I4: en utdeling aapner ikke vinduet hos raidere som ikke har det oppe.
local aapnet = 0
local gShow = NLC.UI.ShowWizard
NLC.UI.ShowWizard = function() aapnet = aapnet + 1 end
local to = { sessionIdx = 2, itemLink = "x", phase = "ranking", ranked = {} }
NLC.Council.OnSessionClose({ { sessionIdx = 1, itemLink = "y", phase = "ranking", ranked = {} }, to })
NLC.Council.OnAward(1, "y", "Moggin", "Revohunt-TwistingNether", "bis")
assert(aapnet == 0, "utdelingen dyttet vinduet opp hos raideren")
NLC.UI.ShowWizard = gShow
NLC.isOfficer = true
print("raider i fred        : OK -> ingen tvunget vindu, riktig item")

