-- Testrigg for cache-porten foran interesse-popupen.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/popupcache_harness.lua',encoding='utf-8').read())"
--
-- C_Item.GetItemInfo returnerer nil for et item klienten ikke har cachet enda.
-- Popupen ble bygget umiddelbart, saa et ucachet item ga equipLoc = nil — og
-- GetAvailableCategories tolker nil equipLoc som et tier-token. Paa 1.9.0 kastet
-- den grenen og tok HELE popupen med seg (skjermdump fra raidet 19.08); med den
-- feilen rettet ville raideren fatt feil knapper, i stillhet.
--
-- Teknikken er hentet fra RCLootCouncil: de nekter aa roere loot-tabellen foer
-- GetItemInfo svarer for hvert item, og planlegger seg selv paa nytt neste
-- frame. Kun mekanismen er laant — ingen kode.

local koe = {}
local naa = 0
GetTime = function() return naa end
C_Timer = {
  After = function(sek, fn) table.insert(koe, fn) end,
  NewTimer = function() return { Cancel = function() end } end,
  NewTicker = function() return { Cancel = function() end } end,
}

local function kjoerKoen()
  local n = #koe
  local pending = koe
  koe = {}
  for _, fn in ipairs(pending) do fn() end
  return n
end

local navngitte = {}
local function nyRamme(_, navn, _, template)
  local f = {}
  local function nop() return f end
  for _, m in ipairs({
    "SetHeight","SetWidth","SetSize","SetPoint","SetAllPoints","SetMovable",
    "EnableMouse","RegisterForDrag","SetScript","SetFrameStrata","Show","Hide",
    "SetText","Enable","Disable","SetNormalFontObject","SetJustifyH",
    "SetColorTexture","SetTexture","SetVerticalScroll","SetScrollChild",
    "SetAutoFocus","SetMaxLetters","SetFocus","ClearFocus","SetAlpha","SetItem",
    "SetOwner","SetHyperlink","AddLine","AddDoubleLine","StartMoving",
    "StopMovingOrSizing","SetMinMaxValues","SetValue","SetBackdrop",
  }) do f[m] = nop end
  f.GetHeight = function() return 0 end
  f.GetText = function() return "" end
  f.GetChildren = function() return end
  f.GetRegions = function() return end
  f.IsShown = function() return false end
  f.CreateFontString = function() return nyRamme() end
  f.CreateTexture = function() return nyRamme() end
  if navn then navngitte[navn] = f end
  return f
end
CreateFrame = nyRamme
UIParent = nyRamme()
GameTooltip = nyRamme()
UnitClass = function() return "Paladin", "PALADIN" end
IsEquippableItem = function() return false end

-- Cachen: styres per test.
local cachet = false
C_Item = {
  GetItemInfo = function(link)
    if not cachet then return nil end
    return "navn", link, 4, 671, 80, "Armor", "Plate", 1, "INVTYPE_CHEST"
  end,
  GetItemInfoInstant = function() return 270162 end,
}

NordavindLC_NS = {
  isOfficer = false,
  Theme = {
    MUTED = "|c1", GOLD = "|c2", GOLD_LIGHT = "|c3", GOLD_DIM = "|c4",
    GREEN = "|c5", RED = "|c6", BLUE = "|c7", WHITE = "|c8", ORANGE = "|c9",
    Recolor = function(l, c) return l and (c .. l) or nil end,
    -- Popupen er en singleton: rammen gjenbrukes, saa «ble den bygget?» maa
    -- maales paa noe som skjer hver gang. CreateTitleBar gjoer det.
    ApplyBackdrop = function() end,
    CreateTitleBar = function(f) f.title = nyRamme(); _G.__bygget = (_G.__bygget or 0) + 1 end,
    CreateItemIcon = function() return nyRamme() end,
    Debounce = function(_, _, fn) fn() end,
  },
  UI = {}, Council = { GetResponseCount = function() return 0 end },
  Utils = {
    GetEquippedInfo = function() return nil, 0 end,
    GetAvailableCategories = function() return { upgrade = true, tmog = true } end,
    Print = function() end, Diag = function() end,
  },
  LootDetection = { GetDroppedItems = function() return {} end, RemoveItem = function() end },
}

dofile("NordavindLC/UI/CouncilFrame.lua")
local UI = NordavindLC_NS.UI

local sessions = {
  { sessionIdx = 1, itemLink = "|cffa335ee|Hitem:270162::::::::90:::::|h[Vessel]|h|r",
    itemId = 270162, ilvl = 671, equipLoc = "INVTYPE_CHEST", boss = "Nek'zali" },
}

-- --- 1: predikatet ---
assert(UI._itemsAreCached, "_itemsAreCached ble ikke eksponert")
cachet = false
assert(UI._itemsAreCached(sessions) == false, "ucachet item skal gi false")
cachet = true
assert(UI._itemsAreCached(sessions) == true, "cachet item skal gi true")
print("predikat            : OK -> skiller cachet fra ucachet")

-- --- 2: ucachet item bygger IKKE popupen, men proever igjen ---
cachet = false
_G.__bygget = 0
UI.ShowMultiItemPopup(sessions, 90)
assert(_G.__bygget == 0,
       "popupen ble bygget paa ucachet data — det er nettopp krasjen")
assert(#koe == 1, "ingen ny forsoek ble planlagt; popupen ville aldri kommet")
print("ucachet             : OK -> bygde ingenting, planla nytt forsoek")

-- --- 3: naar cachen fylles, bygges den ---
cachet = true
kjoerKoen()
assert(_G.__bygget == 1,
       "popupen ble aldri bygget etter at cachen var klar")
print("cache klar          : OK -> popupen bygges")

-- --- 4: et item som ALDRI caches skal gi popup til slutt, ikke evig venting ---
_G.__bygget = 0
koe = {}
naa = 0
cachet = false
UI.ShowMultiItemPopup(sessions, 90)
assert(_G.__bygget == 0, "skal vente foerst")
naa = 6  -- forbi CACHE_WAIT_SECONDS
kjoerKoen()
assert(_G.__bygget == 1,
       "ga aldri opp aa vente — raideren hadde staatt uten popup for alltid")
print("aldri cachet        : OK -> bygger likevel etter fristen")

-- --- 5: én rad som kaster skal IKKE ta med seg popupen ---
--
-- Det var nettopp dette som skjedde 19.08: createItemRow kastet paa det foerste
-- tier-tokenet, loekka laa naken, og hele popupen doede. Raiderne saa de radene
-- som tilfeldigvis var bygget foer tokenet — seks av tolv — eller ingenting.
-- Aarsaken er rettet, men vakten skal staa uansett: neste ukjente feil skal
-- koste ETT item, ikke raidets mulighet til aa svare.
cachet = true
_G.__bygget = 0

local BOMBE = "|cffa335ee|Hitem:66666::::::::90:::::|h[Bombe]|h|r"
NordavindLC_NS.Utils.GetAvailableCategories = function(link)
  if link == BOMBE then error("simulert feil i radbygging") end
  return { upgrade = true, tmog = true }
end

local tre = {
  { sessionIdx = 1, itemLink = "|cffa335ee|Hitem:1::::::::90:::::|h[Foer]|h|r",
    itemId = 1, ilvl = 671, equipLoc = "INVTYPE_CHEST", boss = "Nek'zali" },
  { sessionIdx = 2, itemLink = BOMBE,
    itemId = 66666, ilvl = 678, equipLoc = "", boss = "Nek'zali" },
  { sessionIdx = 3, itemLink = "|cffa335ee|Hitem:3::::::::90:::::|h[Etter]|h|r",
    itemId = 3, ilvl = 671, equipLoc = "INVTYPE_LEGS", boss = "Nek'zali" },
}

local ok = pcall(UI.ShowMultiItemPopup, tre, 90)
assert(ok, "popupen kastet ut av seg selv — raideren ser ingenting")
assert(_G.__bygget == 1, "popupen ble aldri bygget ferdig")
print("rad som kaster      : OK -> popupen bygges, kun det ene itemet tapt")

print("\nALLE PAASTANDER HOLDT")
