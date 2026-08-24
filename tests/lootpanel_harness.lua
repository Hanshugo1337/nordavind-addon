-- Testrigg for stoerrelsen paa Loot Detected-panelet.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/lootpanel_harness.lua',encoding='utf-8').read())"
--
-- Bruker 2026-08-19: «det add vinduet er ALT for stort» og «kan ikke scrolle paa
-- det engang». Panelet satte hoeyden til 110 + antall * 44 uten tak og uten
-- scroll-ramme, saa /nordlc addall med femten items ga en rute hoeyere enn
-- skjermen der radene nederst var uleselige og uklikkbare.
--
-- Kravet: hoeyden staar stille naar lista vokser, og innholdet blir hoeyere enn
-- ruta, slik at det faktisk FINNES noe aa scrolle.

local scrollBarn = nil
local sisteScrollFrame = nil

local navngitte = {}
local function nyRamme(_, navn, _, template)
  local f = {
    _h = 0, _w = 0, _template = template,
    SetHeight = function(self, h) self._h = h end,
    SetWidth = function(self, w) self._w = w end,
    SetSize = function(self, w, h) self._w, self._h = w, h end,
    GetHeight = function(self) return self._h end,
    SetPoint = function() end, SetAllPoints = function() end,
    SetMovable = function() end, EnableMouse = function() end,
    RegisterForDrag = function() end, SetScript = function() end,
    SetFrameStrata = function() end, Show = function() end, Hide = function() end,
    GetChildren = function() return end, GetRegions = function() return end,
    SetText = function() end, Enable = function() end, Disable = function() end,
    SetNormalFontObject = function() end, SetJustifyH = function() end,
    SetColorTexture = function() end, SetTexture = function() end,
    SetVerticalScroll = function() end, SetScrollChild = function(self, c) scrollBarn = c end,
    SetAutoFocus = function() end, SetMaxLetters = function() end, SetFocus = function() end,
    ClearFocus = function() end, GetText = function() return "" end,
    SetAlpha = function() end, SetItem = function() end, SetOwner = function() end,
  }
  f.CreateFontString = function() return nyRamme() end
  f.CreateTexture = function() return nyRamme() end
  if template == "UIPanelScrollFrameTemplate" then sisteScrollFrame = f end
  if navn then navngitte[navn] = f end
  return f
end

CreateFrame = nyRamme
UIParent = nyRamme()
GameTooltip = nyRamme()
GetTime = function() return 0 end
UnitClass = function() return "Paladin", "PALADIN" end
IsEquippableItem = function() return false end
C_Item = { GetItemInfo = function() return nil end, GetItemInfoInstant = function() return 1 end }

NordavindLC_NS = {
  isOfficer = true,
  Theme = {
    MUTED = "|cffb8aa98", GOLD = "|cffc9a84c", GOLD_LIGHT = "|cfff0d080",
    GOLD_DIM = "|cff7a5c1e", GREEN = "|cff33cc33", RED = "|cffff3333", BLUE = "|cff00ccff",
    WHITE = "|cffffffff", ORANGE = "|cffff8800",
    Recolor = function(link, c) return link and (c .. link) or nil end,
    ApplyBackdrop = function() end,
    CreateTitleBar = function() end,
    CreateItemIcon = function() return nyRamme() end,
    Debounce = function(_, _, fn) fn() end,
  },
  UI = {}, Council = { GetResponseCount = function() return 0 end },
  Utils = { GetEquippedInfo = function() return nil, 0 end,
            GetAvailableCategories = function() return {} end,
            Print = function() end },
  LootDetection = { GetDroppedItems = function() return {} end, RemoveItem = function() end },
}

dofile("NordavindLC/UI/CouncilFrame.lua")
local UI = NordavindLC_NS.UI

local function lagItems(n)
  local t = {}
  for i = 1, n do
    t[i] = { itemLink = "|cffa335ee|Hitem:2701" .. i .. "::::::::90:::::|h[Item " .. i .. "]|h|r",
             itemId = 270100 + i, ilvl = 671, equipLoc = "INVTYPE_CHEST",
             boss = "Nek'zali", looter = "Raider" .. i }
  end
  return t
end

-- Panelet er en singleton; foerste kall bygger det.
UI.ShowLootDetected(lagItems(3))
local panel = navngitte["NordavindLCLootPanel"]
assert(panel, "panelet ble aldri opprettet")
-- Rammene vaare er lokale, saa vi henter hoeyden via det scroll-barnet som ble satt.
assert(sisteScrollFrame, "scroll-ramma ble aldri opprettet — da kan det ikke scrolles")
assert(scrollBarn, "scroll-ramma fikk aldri et barn — innholdet ville staatt fast")
print("scroll-ramme       : OK -> opprettet med innhold")

local h3 = scrollBarn:GetHeight()
assert(h3 == 3 * 44, "innholdshoeyde ved 3 items: forventet 132, fikk " .. h3)

UI.ShowLootDetected(lagItems(20))
local h20 = scrollBarn:GetHeight()
assert(h20 == 20 * 44, "innholdshoeyde ved 20 items: forventet 880, fikk " .. h20)
print("innholdshoeyde     : OK -> vokser med lista (132 -> 880)")

-- Selve poenget: RUTA skal ikke vokse i takt med lista.
UI.ShowLootDetected(lagItems(8))
local rute8 = panel:GetHeight()
UI.ShowLootDetected(lagItems(20))
local rute20 = panel:GetHeight()
UI.ShowLootDetected(lagItems(3))
local rute3 = panel:GetHeight()

assert(rute20 == rute8,
       "ruta vokste forbi taket: 8 items ga " .. rute8 .. ", 20 ga " .. rute20)
assert(rute20 <= 500,
       "ruta er fortsatt for hoey ved 20 items: " .. rute20 .. " px")
assert(rute3 < rute8, "smaa lister skal fortsatt gi en liten rute")
print(string.format("tak paa ruta       : OK -> 3=%dpx, 8=%dpx, 20=%dpx (taket holder)",
      rute3, rute8, rute20))

-- Regresjonen: gammel formel var 110 + antall*44 = 990 px ved 20 items.
assert(rute20 < 110 + 20 * 44,
       "hoeyden foelger fortsatt den gamle formelen")

-- Og det maa finnes noe aa scrolle: innholdet hoeyere enn det synlige taket.
assert(h20 > 8 * 44, "innholdet er ikke hoeyere enn ruta — da har scrollbaren ingenting aa gjoere")
print("scrollbart innhold : OK -> 880 px innhold i en rute paa 8 rader")

print("\nALLE PAASTANDER HOLDT")
