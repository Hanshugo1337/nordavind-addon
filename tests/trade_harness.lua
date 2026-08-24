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
C_Timer = {
  After = function(_, fn) return fn and nil end,
  NewTimer = function() return { Cancel = function() end } end,
  NewTicker = function(_, fn) table.insert(tickere, fn); return { Cancel = function() end } end,
}
-- Baggen: styres per test, saa handelstid-varselet kan proeves.
local baggen = {}
C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and 8 or 0 end,
  GetContainerItemLink = function(b, s) return b == 0 and baggen[s] and baggen[s].link or nil end,
  GetContainerItemInfo = function(b, s)
    if b == 0 and baggen[s] then return { itemID = baggen[s].itemId } end
    return nil
  end,
  PickupContainerItem = function() end,
}
InCombatLockdown = function() return false end
GetTime = function() return 100000 end
C_Item = { GetItemInfoInstant = function() return 1 end }
UIParent = {}
GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end,
                Hide = function() end }
UnitName = function() return "Ukjent" end
UnitInRange = function() return true end
GetNumGroupMembers = function() return 0 end
GetRaidRosterInfo = function() return nil end
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
