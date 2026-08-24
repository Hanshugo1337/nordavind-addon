-- Testrigg for NLC.LootDetection.ScanBagsForPanel — «/nordlc add» uten argumenter.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/manualscan_harness.lua',encoding='utf-8').read())"
--
-- To ting maa holde. Den skal returnere alt tradeable som ligger i baggen NAA,
-- ogsaa det den automatiske innsamlingen alt har rapportert — offiseren spoer
-- «hva holder jeg paa?», ikke «hva er nytt?». Og den skal ikke roere
-- dedup-tilstanden, ellers ville et manuelt oppslag spist itemet slik at den
-- automatiske rapporten mistet det etterpaa.

local planlagte = {}
C_Timer = {
  After = function(sek, fn) table.insert(planlagte, fn) end,
  NewTimer = function(sek, fn) return { Cancel = function() end } end,
}
GetTime = function() return 0 end
CreateFrame = function()
  return { RegisterEvent = function() end, UnregisterEvent = function() end,
           UnregisterAllEvents = function() end, SetScript = function() end }
end

-- Tre items i bag 0. Nr. 2 er graatt skrot som filteret skal kaste.
local bag = {
  [1] = { link = "|cffa335ee|Hitem:270162::::::::90:::::|h[Soulcoiler Ritual Vessel]|h|r",
          guid = "Item-A", kvalitet = 4, tradeable = true },
  [2] = { link = "|cff9d9d9d|Hitem:111111::::::::90:::::|h[Worn Shortsword]|h|r",
          guid = "Item-B", kvalitet = 1, tradeable = true },
  [3] = { link = "|cffa335ee|Hitem:268235::::::::90:::::|h[Vestment of the Awakening]|h|r",
          guid = "Item-C", kvalitet = 4, tradeable = true },
}

local function slot(s) return bag[s] end

C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and 3 or 0 end,
  GetContainerItemLink = function(b, s) return b == 0 and slot(s) and slot(s).link or nil end,
}
-- Kalles med kolon i addonet (ItemLocation:CreateFromBagAndSlot), saa stubben
-- MAA ta imot self. Uten den doer oppslaget stille og alt filtreres bort.
ItemLocation = { CreateFromBagAndSlot = function(self, b, s) return { bag = b, slot = s } end }
C_Item = {
  DoesItemExist = function(loc) return slot(loc.slot) ~= nil end,
  GetItemGUID = function(loc) return slot(loc.slot).guid end,
  GetItemInfoInstant = function(link) return 270162 end,
  GetItemInfo = function(link)
    local kvalitet = 4
    for _, it in pairs(bag) do if it.link == link then kvalitet = it.kvalitet end end
    return "navn", link, kvalitet, 671, 80, "Armor", "Plate", 1, "INVTYPE_CHEST"
  end,
}
UnitName = function() return "Bobletount" end
UnitIsGroupLeader = function() return false end

local sendte = {}
NordavindLC_NS = {
  active = true,
  LootDetection = {},
  Comms = {
    IsRestricted = function() return false end,
    Send = function(t, d) table.insert(sendte, { type = t, data = d }) end,
  },
  Utils = {
    Print = function() end,
    IsTradeableBagItem = function(b, s) return b == 0 and slot(s) and slot(s).tradeable or false end,
    IsWarbound = function() return false end,
    GetTierTokenArmorType = function() return nil end,
  },
}

dofile("NordavindLC/LootDetection.lua")
local LD = NordavindLC_NS.LootDetection
LD.Register()

-- --- Scenario 1: tomt utgangspunkt ---
local funnet = LD.ScanBagsForPanel()
assert(#funnet == 2, "forventet 2 items (graatt skrot filtrert bort), fikk " .. #funnet)
assert(funnet[1].boss, "boss maa vaere satt, ellers faar councilet nil")
print("scenario 1 (tom logg):        OK -> 2 av 3 items, skrotet filtrert bort")

-- --- Scenario 2: den automatiske innsamlingen har alt tatt dem ---
LD.ScanBags()
assert(#LD.GetReport() == 2, "den automatiske innsamlingen fant ikke begge")

local igjen = LD.ScanBagsForPanel()
assert(#igjen == 2,
       "manuelt oppslag skal se items som alt er rapportert, fikk " .. #igjen)
print("scenario 2 (alt rapportert):  OK -> ser dem fortsatt")

-- --- Scenario 3: oppslaget maa ikke spise noe fra rapporten ---
local foer = #LD.GetReport()
LD.ScanBagsForPanel()
LD.ScanBagsForPanel()
assert(#LD.GetReport() == foer,
       "manuelt oppslag endret rapportkoeen: " .. foer .. " -> " .. #LD.GetReport())
print("scenario 3 (roerer ikke koen): OK -> rapporten staar urort")

-- --- Scenario 4: tom bag skal gi tom liste, ikke krasj ---
bag = {}
local tom = LD.ScanBagsForPanel()
assert(type(tom) == "table" and #tom == 0, "tom bag skal gi tom liste")
print("scenario 4 (tom bag):         OK -> tom liste, ingen krasj")

print("\nALLE PAASTANDER HOLDT")
