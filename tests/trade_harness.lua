-- Testrigg for at fullfoerte handler fjerner RIKTIG oppfoering.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/trade_harness.lua',encoding='utf-8').read())"
--
-- Tre feil laa her, alle synlige 2026-08-19 da hele raidets loot ble delt ut
-- manuelt fordi councilet var nede:
--
--   1. Mottakeren var kun kjent naar handelen ble startet fra VAART vindu.
--      Trader du noen ved aa hoeyreklikke dem, visste vi ingenting, og itemet
--      ble staaende i «venter paa trade» for alltid.
--   2. Vi fjernet FOERSTE pending-oppfoering for personen uansett hva som laa i
--      vinduet. Skylder du tre og gir ett, forsvant feil rad.
--   3. Cross-realm viser navnet som «Navn(*)».
--
-- Teknikken er RCLootCouncils: les mottakeren fra Blizzards handelsvindu, og
-- fang slottene paa TRADE_ACCEPT_UPDATE — siste oeyeblikk der innholdet er kjent.

local hendelser, handler = {}, nil
CreateFrame = function()
  return {
    RegisterEvent = function(_, e) hendelser[e] = true end,
    UnregisterEvent = function() end,
    SetScript = function(self, s, fn) if s == "OnEvent" then handler = fn end end,
    SetPoint = function() end, SetSize = function() end, SetText = function() end,
    Show = function() end, Hide = function() end, IsShown = function() return false end,
    SetMovable = function() end, EnableMouse = function() end,
    RegisterForDrag = function() end, SetFrameStrata = function() end,
    CreateFontString = function() return { SetPoint = function() end, SetText = function() end } end,
    CreateTexture = function() return { SetAllPoints = function() end,
                                        SetColorTexture = function() end } end,
  }
end
local tickere = {}
-- Utsatte callbacks fyrer IKKE av seg selv. Testene som ikke bryr seg om dem
-- slipper aa forholde seg til dem, og den som gjoer det kaller kjoerUtsatte().
-- Foer dette droppet stubben callbacken helt, saa auto-add-koden inne i
-- C_Timer.After var aldri testet.
local utsatte = {}
local function kjoerUtsatte()
  local koe = utsatte
  utsatte = {}
  for _, fn in ipairs(koe) do fn() end
end
C_Timer = {
  After = function(_, fn) if fn then table.insert(utsatte, fn) end end,
  NewTimer = function() return { Cancel = function() end } end,
  NewTicker = function(_, fn) table.insert(tickere, fn); return { Cancel = function() end } end,
}
-- Baggen: styres per test, saa handelstid-varselet kan proeves.
local baggen = {}
C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and 8 or 0 end,
  GetContainerItemLink = function(b, s) return b == 0 and baggen[s] and baggen[s].link or nil end,
  GetContainerItemInfo = function(b, s)
    if b == 0 and baggen[s] then
      return { itemID = baggen[s].itemId, isLocked = baggen[s].laast }
    end
    return nil
  end,
  PickupContainerItem = function(b, s) table.insert(_G.__plukket, { bag = b, slot = s }) end,
}
-- Spioner paa handelsvindu-API-ene. Uten disse kan vi ikke se AT vi la inn
-- flere items, bare at ingenting krasjet.
_G.__plukket, _G.__klikket, _G.__ryddet = {}, {}, 0
ClearCursor = function() _G.__ryddet = _G.__ryddet + 1 end
ClickTradeButton = function(n) table.insert(_G.__klikket, n) end
InitiateTrade = function() end
InCombatLockdown = function() return false end
GetTime = function() return 100000 end
C_Item = { GetItemInfoInstant = function() return 1 end }
UIParent = {}
GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end,
                Hide = function() end }
UnitName = function() return "Ukjent" end
UnitInRange = function() return true end
-- Raidet: tomt som standard, saa eksisterende tester er uendret.
local raidet = {}
GetNumGroupMembers = function() return #raidet end
GetRaidRosterInfo = function(i) return raidet[i] end
time = time or os.time

-- Blizzards handelsvindu.
local mottakerTekst = "Braxina"
_G = _G or {}
TradeFrameRecipientNameText = { GetText = function() return mottakerTekst end }
MAX_TRADE_ITEMS = 7
LE_GAME_ERR_TRADE_COMPLETE = 219
ERR_TRADE_COMPLETE = "Handel fullfoert."

local iVinduet = {}
GetTradePlayerItemLink = function(i) return iVinduet[i] end

NordavindLC_NS = {
  db = { pendingTrades = {} },
  Theme = {
    MUTED = "|c1", GOLD = "|c2", GOLD_LIGHT = "|c3", GOLD_DIM = "|c4", GREEN = "|c5",
    RED = "|c6", WHITE = "|c7", ORANGE = "|c8", BLUE = "|c9",
    ApplyBackdrop = function() end, CreateTitleBar = function() end,
    CreateItemIcon = function() return { SetPoint = function() end, SetItem = function() end } end,
  },
  Utils = {
    Print = function(m) table.insert(_G.__utskrift or {}, m) end,
    Diag = function() end,
    GetBagItemTradeSeconds = function(b, s)
      return b == 0 and baggen[s] and baggen[s].sek or nil
    end,
  },
  UI = {}, Trade = {}, Council = {}, LootDetection = {},
}

dofile("NordavindLC/UI/TradeFrame.lua")
local NLC = NordavindLC_NS

assert(hendelser["TRADE_ACCEPT_UPDATE"], "TRADE_ACCEPT_UPDATE ble ikke registrert")
print("registrering        : OK -> TRADE_ACCEPT_UPDATE lyttes paa")

local function LENKE(navn) return "|cffa335ee|Hitem:1::::::::90:::::|h[" .. navn .. "]|h|r" end

local function seedGjeld()
  NLC.db.pendingTrades = {}
  NLC.Trade.Add(LENKE("Kappe"),  1, "Braxina", "Bobletount", "Boss", "upgrade")
  NLC.Trade.Add(LENKE("Ringen"), 2, "Braxina", "Bobletount", "Boss", "upgrade")
  NLC.Trade.Add(LENKE("Staven"), 3, "Braxina", "Bobletount", "Boss", "upgrade")
  NLC.Trade.Add(LENKE("Hjelmen"), 4, "Prectus", "Bobletount", "Boss", "upgrade")
end

local function gjeldFor(navn)
  local n = 0
  for _, p in ipairs(NLC.Trade.GetPending()) do
    if p.awardedTo == navn then n = n + 1 end
  end
  return n
end

local function fullfoerHandel()
  handler(nil, "UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE)
end

-- --- 1: MANUELL handel skal registreres ---
-- Ingen _autoAddTarget: handelen ble startet ved aa hoeyreklikke spilleren.
seedGjeld()
mottakerTekst = "Braxina"
handler(nil, "TRADE_SHOW")
iVinduet = { LENKE("Ringen") }
handler(nil, "TRADE_ACCEPT_UPDATE", 1, 0)
fullfoerHandel()
assert(gjeldFor("Braxina") == 2,
       "manuell handel ble ikke registrert (gjeld: " .. gjeldFor("Braxina") .. " av 3)")
print("manuell handel      : OK -> registrert uten at vi startet den")

-- --- 2: KUN itemet som faktisk laa i vinduet fjernes ---
local igjen = {}
for _, p in ipairs(NLC.Trade.GetPending()) do
  if p.awardedTo == "Braxina" then igjen[#igjen + 1] = p.item:match("%[(.-)%]") end
end
table.sort(igjen)
assert(table.concat(igjen, ",") == "Kappe,Staven",
       "feil item fjernet — igjen: " .. table.concat(igjen, ", "))
print("riktig item         : OK -> kun Ringen borte, Kappe og Staven staar")

-- --- 3: to items i samme handel ---
seedGjeld()
handler(nil, "TRADE_SHOW")
iVinduet = { LENKE("Kappe"), LENKE("Staven") }
handler(nil, "TRADE_ACCEPT_UPDATE", 0, 1)
fullfoerHandel()
assert(gjeldFor("Braxina") == 1,
       "begge items i handelen ble ikke fjernet (gjeld: " .. gjeldFor("Braxina") .. ")")
print("to i samme handel   : OK -> begge fjernet")

-- --- 4: andres gjeld skal ikke roeres ---
assert(gjeldFor("Prectus") == 1, "Prectus mistet gjelden sin")
print("andres gjeld        : OK -> uroert")

-- --- 5: cross-realm «Navn(*)» ---
seedGjeld()
mottakerTekst = "Braxina(*)"
handler(nil, "TRADE_SHOW")
iVinduet = { LENKE("Ringen") }
handler(nil, "TRADE_ACCEPT_UPDATE", 1, 0)
fullfoerHandel()
assert(gjeldFor("Braxina") == 2,
       "cross-realm-navnet ble ikke gjenkjent (gjeld: " .. gjeldFor("Braxina") .. ")")
print("cross-realm (*)     : OK -> merket kuttet, navnet gjenkjent")

-- --- 6: avbrutt handel skal ikke fjerne noe ---
seedGjeld()
mottakerTekst = "Braxina"
handler(nil, "TRADE_SHOW")
iVinduet = { LENKE("Ringen") }
handler(nil, "TRADE_ACCEPT_UPDATE", 1, 0)
handler(nil, "TRADE_CLOSED")
assert(gjeldFor("Braxina") == 3, "avbrutt handel fjernet gjeld likevel")
print("avbrutt handel      : OK -> ingenting fjernet")

-- --- 7: varsel om handelstid som loeper ut ---
--
-- Handelstida er to timer. Gaar den ut, sitter itemet fast hos feil person for
-- godt. Nedtellingen ble bare vist mens trade-vinduet sto aapent, og midt i et
-- raid staar det lukket — 19.08 laa det foerti uutdelte items i baggen uten at
-- noe sa fra.
_G.__utskrift = {}
seedGjeld()
-- Kappe (id 1) har 10 min igjen, Staven (id 3) har halvannen time.
baggen[1] = { itemId = 1, sek = 600 }
baggen[2] = { itemId = 3, sek = 5400 }
NLC.Trade.CheckExpiring(true)

local varslet = table.concat(_G.__utskrift, "\n")
assert(varslet:find("Kappe", 1, true), "varslet ikke om itemet som holder paa aa loepe ut")
assert(not varslet:find("Staven", 1, true), "varslet om et item med halvannen time igjen")
assert(varslet:find("10 min", 1, true), "gjenstaaende tid manglet i varselet")
print("utloepsvarsel       : OK -> kun Kappe, med tid igjen")

-- Spam-sperre: umiddelbart nytt kall skal vaere stille.
_G.__utskrift = {}
NLC.Trade.CheckExpiring()
assert(#_G.__utskrift == 0, "varselet gjentok seg med én gang — ville spammet chatten")
print("spam-sperre         : OK -> stille ved neste kall")

-- I kamp skal det aldri komme.
_G.__utskrift = {}
InCombatLockdown = function() return true end
NLC.Trade.CheckExpiring(true)
assert(#_G.__utskrift == 0, "varslet midt i kamp")
InCombatLockdown = function() return false end
print("stille i kamp       : OK")

print("\nALLE PAASTANDER HOLDT")

-- --- 9: secret string fra handelsvinduet skal ikke ta ned handelen ---
-- 12.0 gjorde TradeFrameRecipientNameText:GetText() til et secret value. Enhver
-- sammenligning kaster «attempt to compare ... while execution tainted», og
-- 26.08 gjorde den det ni ganger midt i raid.
--
-- Et secret value kan ikke bygges i Lua, men effekten kan: kallet kaster. Det er
-- nettopp det pcall-en i lesMottaker skal taale — og den skal falle videre til
-- neste navnekilde i stedet for aa gi opp.
seedGjeld()
NLC.Trade._autoAddTarget = nil   -- manuell handel: vi startet den ikke selv

local ekteGetText = TradeFrameRecipientNameText.GetText
TradeFrameRecipientNameText.GetText = function()
  error("attempt to compare local 'navn' (a secret string value, "
        .. "while execution tainted by 'NordavindLC')")
end
local ekteUnitName = UnitName
UnitName = function(enhet) if enhet == "NPC" then return "Braxina" end return "Ukjent" end

local ok = pcall(handler, nil, "TRADE_SHOW")
assert(ok, "TRADE_SHOW kastet videre — pcall-en i lesMottaker fanget ikke feilen")

iVinduet = { LENKE("Ringen") }
handler(nil, "TRADE_ACCEPT_UPDATE", 1, 0)
fullfoerHandel()
assert(gjeldFor("Braxina") == 2,
       "falt ikke tilbake paa UnitName(\"NPC\") (gjeld: " .. gjeldFor("Braxina") .. " av 3)")

TradeFrameRecipientNameText.GetText = ekteGetText
UnitName = ekteUnitName
print("secret mottakernavn : OK -> fanget, falt tilbake, handelen registrert")

-- --- 10: HELE gjelda til én person i samme handel ---
-- Skylder du noen tre items, skal alle tre inn i vinduet paa ett klikk.
--
-- Den stygge biten er to eksemplarer av SAMME itemId. Et item som ligger i
-- handelsvinduet staar fortsatt i bag-sloten sin, saa et oppslag som bare
-- leter etter itemId finner samme slot om og om igjen — og du legger ett item
-- inn tre ganger. Derfor maa brukte slots ekskluderes.
NLC.db.pendingTrades = {}
NLC.Trade.Add(LENKE("Kappe"),  11, "Braxina", "Bobletount", "Boss", "upgrade")
NLC.Trade.Add(LENKE("Ringen"), 22, "Braxina", "Bobletount", "Boss", "upgrade")
NLC.Trade.Add(LENKE("Ringen"), 22, "Braxina", "Bobletount", "Boss", "upgrade")
NLC.Trade.Add(LENKE("Hjelmen"), 33, "Prectus", "Bobletount", "Boss", "upgrade")

baggen = {
  [1] = { itemId = 11, link = LENKE("Kappe"),  sek = 7000 },
  [2] = { itemId = 22, link = LENKE("Ringen"), sek = 7000 },
  [3] = { itemId = 22, link = LENKE("Ringen"), sek = 7000 },
}
raidet = { "Braxina-Kazzak", "Prectus" }

_G.__plukket, _G.__klikket, _G.__ryddet = {}, {}, 0
assert(NLC.Trade.StartTradeWith, "NLC.Trade.StartTradeWith finnes ikke")
NLC.Trade.StartTradeWith("Braxina")
handler(nil, "TRADE_SHOW")
kjoerUtsatte()

assert(#_G.__plukket == 3,
       "plukket " .. #_G.__plukket .. " items opp fra baggen, ventet 3")
local sett = {}
for _, p2 in ipairs(_G.__plukket) do
  local n = p2.bag .. ":" .. p2.slot
  assert(not sett[n], "samme bag-slot brukt to ganger: " .. n)
  sett[n] = true
end
assert(#_G.__klikket == 3, "klikket " .. #_G.__klikket .. " trade-slots, ventet 3")
for i = 1, 3 do
  assert(_G.__klikket[i] == i, "trade-slot " .. i .. " fikk " .. tostring(_G.__klikket[i]))
end
assert(_G.__ryddet >= 3, "ClearCursor ble kalt " .. _G.__ryddet .. " ganger, ventet minst 3")
print("tre items i én handel: OK -> 3 ulike bag-slots, 3 ulike trade-slots")

-- ...og alle tre skal forsvinne fra gjelda naar handelen gaar igjennom.
iVinduet = { LENKE("Kappe"), LENKE("Ringen"), LENKE("Ringen") }
handler(nil, "TRADE_ACCEPT_UPDATE", 1, 0)
fullfoerHandel()
assert(gjeldFor("Braxina") == 0,
       "Braxina skylder fortsatt " .. gjeldFor("Braxina") .. " items etter handelen")
assert(gjeldFor("Prectus") == 1, "Prectus mistet gjelden sin")
print("gjelda ryddet     : OK -> alle tre borte, andres uroert")

-- Flere enn seks: vinduet har seks brukbare slots, og resten maa vente.
NLC.db.pendingTrades = {}
for i = 1, 8 do
  NLC.Trade.Add(LENKE("Ting" .. i), 100 + i, "Braxina", "Bobletount", "Boss", "upgrade")
end
baggen = {}
for i = 1, 8 do baggen[i] = { itemId = 100 + i, link = LENKE("Ting" .. i), sek = 7000 } end
_G.__plukket, _G.__klikket, _G.__ryddet = {}, {}, 0
NLC.Trade.StartTradeWith("Braxina")
handler(nil, "TRADE_SHOW")
kjoerUtsatte()
assert(#_G.__klikket == 6,
       "la inn " .. #_G.__klikket .. " items, men vinduet har kun 6 brukbare slots")
print("seks-slots-taket  : OK -> 6 inn, resten venter")

-- --- 8: ingen avstands-API i TradeFrame ---
-- Denne testen leser kilden, ikke oppfoerselen, og det er med vilje.
--
-- Stubben over — UnitInRange = function() return true end — ga en helt vanlig
-- boolean. Spillet gir fra 12.0 et SECRET VALUE, som kaster i det du tester det
-- (`if x then`, `x == false`). Ingen stub skrevet i Lua kan etterligne det:
-- alt som ikke er nil/false er sant, saa harnessen kan aldri se feilen.
--
-- 26.08 kostet det oss trade-vinduet midt i raid — elleve ventende utdelinger,
-- og kallet stod rett foer InitiateTrade, saa handelen startet ikke engang.
-- Begge avstands-API-ene vi har proevd er stengt for addons: CheckInteractDistance
-- er protected, UnitInRange gir secret. Det finnes ingen tredje.
--
-- Derfor: kilden skal ikke kalle dem i det hele tatt.
local kilde = io.open("NordavindLC/UI/TradeFrame.lua", "r")
assert(kilde, "fant ikke TradeFrame.lua")
local tekst = kilde:read("*a")
kilde:close()

for _, api in ipairs({ "UnitInRange", "CheckInteractDistance" }) do
  local NL = string.char(10)
  for linje in tekst:gmatch("[^" .. NL .. "]+") do
    local kode = linje:match("^%s*%-%-") and "" or linje
    assert(not kode:find(api .. "%s*%("),
      api .. " kalles fortsatt i TradeFrame.lua: " .. linje)
  end
end

-- --- 11: naar BAADE handelsvinduet og UnitName("NPC") er stengt ---
--
-- Dette er hullet som stod aapent etter 27.08. `lesMottaker` hadde to kilder,
-- og begge leser en STRENG. Stenger 12.0 den ene, er sjansen stor for at den
-- andre gaar samme vei — det er tredje avstands-/navne-API som forsvinner paa
-- like mange maaneder. Da ble trade-raden staaende i «venter paa trade» uten at
-- noe krasjet, altsaa uten at noen skjoente hvorfor.
--
-- GUID-en er en helt annen datatype og gaar en annen vei inn: BugGrabber og
-- BigWigs bruker GetPlayerInfoByGUID fritt, ogsaa i 12.0. Den er derfor den
-- eneste kilden som ikke deler skjebne med de to andre.
seedGjeld()
NLC.Trade._autoAddTarget = nil

local ekteGetText2 = TradeFrameRecipientNameText.GetText
TradeFrameRecipientNameText.GetText = function()
  error("attempt to compare local 'navn' (a secret string value, "
        .. "while execution tainted by 'NordavindLC')")
end
local ekteUnitName2 = UnitName
UnitName = function(enhet)
  if enhet == "NPC" then return nil end   -- ogsaa stengt
  return "Ukjent"
end
UnitGUID = function(enhet)
  if enhet == "NPC" then return "Player-1301-0A1B2C3D" end
  return nil
end
GetPlayerInfoByGUID = function(guid)
  if guid == "Player-1301-0A1B2C3D" then
    -- localizedClass, englishClass, localizedRace, englishRace, sex, navn, realm
    return "Trollmann", "MAGE", "Blodalv", "BloodElf", 2, "Braxina", "Kazzak"
  end
end

local ok11 = pcall(handler, nil, "TRADE_SHOW")
assert(ok11, "TRADE_SHOW kastet videre da begge navnekildene var stengt")
iVinduet = { LENKE("Ringen") }
handler(nil, "TRADE_ACCEPT_UPDATE", 1, 0)
fullfoerHandel()
assert(gjeldFor("Braxina") == 2,
       "fant ikke mottakeren via GUID (gjeld: " .. gjeldFor("Braxina") .. " av 3)")
print("mottaker via GUID   : OK -> navnet hentet ut av GUID-en")

-- --- 12: ingen lesbar mottaker skal SIES fra om ---
--
-- Faller alle tre kildene, og handelen heller ikke ble startet fra vaart eget
-- vindu, kan vi ikke vite hvem dette er. Da skal raden bli staaende — men
-- offiseren skal faa vite hvorfor, ellers leter han etter en feil som ser ut
-- som at addonet «glemte» utdelinga.
seedGjeld()
NLC.Trade._autoAddTarget = nil
UnitGUID = function() return nil end
GetPlayerInfoByGUID = function() return nil end
_G.__utskrift = {}

local ok12 = pcall(handler, nil, "TRADE_SHOW")
assert(ok12, "TRADE_SHOW kastet da ingen navnekilde svarte")
local sagt = table.concat(_G.__utskrift, "\n")
assert(sagt:find("mottaker", 1, true) or sagt:find("Mottaker", 1, true),
       "sa ikke fra om at mottakeren ikke kunne leses (utskrift: " .. sagt .. ")")
print("ulesbar mottaker    : OK -> sier fra i stedet for aa tie")

-- --- 13: issecretvalue skal spoerres, ikke gjettes ---
--
-- pcall fanger kun de kallene som KASTER. Et secret value som lar seg lese, men
-- ikke sammenligne senere, slipper gjennom og gir feil mottaker — og da fjernes
-- feil gjeld hos feil person. 12.0 har `issecretvalue` nettopp for dette;
-- BugGrabber og RCLootCouncil spoer den foer de roerer verdien.
seedGjeld()
NLC.Trade._autoAddTarget = nil
TradeFrameRecipientNameText.GetText = function() return "Prectus" end
UnitName = function(enhet) if enhet == "NPC" then return "Braxina" end return "Ukjent" end
issecretvalue = function(v) return v == "Prectus" end

handler(nil, "TRADE_SHOW")
iVinduet = { LENKE("Ringen") }
handler(nil, "TRADE_ACCEPT_UPDATE", 1, 0)
fullfoerHandel()
assert(gjeldFor("Braxina") == 2,
       "brukte den hemmelige verdien i stedet for neste kilde (gjeld Braxina: "
       .. gjeldFor("Braxina") .. ", Prectus: " .. gjeldFor("Prectus") .. ")")
assert(gjeldFor("Prectus") == 1, "fjernet gjeld hos feil person")
print("issecretvalue       : OK -> hemmelig verdi forkastet, neste kilde brukt")

issecretvalue = nil
TradeFrameRecipientNameText.GetText = ekteGetText2
UnitName = ekteUnitName2
