-- Testrigg for avvisningstellerne i NLC.LootDetection.
--
-- Kjoeres fra repo-rot:
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/avvisning_harness.lua',encoding='utf-8').read())"
--
-- Hvorfor denne finnes: «Innsamling stengt | 0 items» kan bety to helt ulike
-- ting — at ingenting droppet, eller at filteret kastet alt. 19.08 var det det
-- siste, og loggen kunne ikke skille dem. Etter dette skal nulltallet alltid
-- komme med en grunn.

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

-- Fire items. Ett skal telles, tre skal avvises — ett per grunn.
local bag = {
  [1] = { link = "|cffa335ee|Hitem:270162::::::::90:::::|h[Soulcoiler Ritual Vessel]|h|r",
          guid = "Item-A", kvalitet = 4, tradeable = true,  type = "Armor" },
  [2] = { link = "|cffa335ee|Hitem:268235::::::::90:::::|h[Vestment of the Awakening]|h|r",
          guid = "Item-B", kvalitet = 4, tradeable = false, type = "Armor" },
  [3] = { link = "|cff9d9d9d|Hitem:111111::::::::90:::::|h[Worn Shortsword]|h|r",
          guid = "Item-C", kvalitet = 1, tradeable = true,  type = "Weapon" },
  [4] = { link = "|cffa335ee|Hitem:222222::::::::90:::::|h[Flask of Power]|h|r",
          guid = "Item-D", kvalitet = 4, tradeable = true,  type = "Consumable" },
}

local function slot(s) return bag[s] end
local function finn(link)
  for _, it in pairs(bag) do if it.link == link then return it end end
end

C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and 4 or 0 end,
  GetContainerItemLink = function(b, s) return b == 0 and slot(s) and slot(s).link or nil end,
}
ItemLocation = { CreateFromBagAndSlot = function(self, b, s) return { bag = b, slot = s } end }
C_Item = {
  DoesItemExist = function(loc) return slot(loc.slot) ~= nil end,
  GetItemGUID = function(loc) return slot(loc.slot).guid end,
  GetItemInfoInstant = function(link) return finn(link) and 270162 or nil end,
  GetItemInfo = function(link)
    local it = finn(link)
    return "navn", link, it.kvalitet, 671, 80, it.type, "Plate", 1, "INVTYPE_CHEST"
  end,
}
UnitName = function() return "Bobletount" end
UnitIsGroupLeader = function() return false end

NordavindLC_NS = {
  active = true,
  db = { diagLog = {} },
  LootDetection = {},
  Comms = {
    IsRestricted = function() return false end,
    Send = function() end,
  },
  Utils = {
    Print = function() end,
    Diag = function(msg) table.insert(NordavindLC_NS.db.diagLog, msg) end,
    IsTradeableBagItem = function(b, s) return b == 0 and slot(s) and slot(s).tradeable or false end,
    IsWarbound = function() return false end,
    GetTierTokenArmorType = function() return nil end,
  },
}

dofile("NordavindLC/LootDetection.lua")
local LD = NordavindLC_NS.LootDetection
LD.Register()

-- --- Scenario 1: hver avvisningsgrunn telles for seg ---
LD.ScanBags()
local avvist = LD.GetAvvist()
assert(type(avvist) == "table", "GetAvvist maa returnere en tabell, fikk " .. type(avvist))
assert(avvist.ingenHandelstid == 1,
  "forventet 1 uten handelstid, fikk " .. tostring(avvist.ingenHandelstid))
assert(avvist.ikkeEpic == 1,
  "forventet 1 under epic, fikk " .. tostring(avvist.ikkeEpic))
assert(avvist.ekskludert == 1,
  "forventet 1 ekskludert type, fikk " .. tostring(avvist.ekskludert))
print("scenario 1 (grunner telles):  OK -> 1 handelstid, 1 kvalitet, 1 type")

-- --- Scenario 2: det ene gyldige itemet slipper fortsatt gjennom ---
local rapport = LD.GetReport()
assert(#rapport == 1, "forventet 1 item i rapporten, fikk " .. #rapport)
print("scenario 2 (gyldig slipper):  OK -> 1 item rapportert")

-- --- Scenario 3: grunnene blir til lesbar tekst for loggen ---
-- Dette er hele poenget med endringen: linja «Innsamling stengt | 0 items» skal
-- aldri igjen staa der uten aa si hvorfor.
local tekst = LD.AvvistTekst()
assert(tekst:find("uten handelstid", 1, true),
  "teksten maa nevne handelstid, fikk: " .. tostring(tekst))
assert(tekst:find("1", 1, true), "teksten maa ha med antall, fikk: " .. tostring(tekst))
print("scenario 3 (lesbar tekst):    OK -> " .. tekst)

-- --- Scenario 4: ingen avvisninger gir tom tekst, ikke «0 uten handelstid» ---
LD.NullstillAvvist()
local etter = LD.GetAvvist()
assert(etter.ingenHandelstid == 0 and etter.ikkeEpic == 0 and etter.ekskludert == 0,
  "tellerne skal vaere nullstilt ved starten av en ny boss")
assert(LD.AvvistTekst() == "",
  "uten avvisninger skal teksten vaere tom, fikk: " .. tostring(LD.AvvistTekst()))
print("scenario 4 (nullstilling):    OK -> alle tellere paa 0, tom tekst")

print("\nalle scenarier OK")
