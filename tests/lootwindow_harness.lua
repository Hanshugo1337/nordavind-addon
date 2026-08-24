-- Testrigg for innsamlingsvinduet i LootDetection.lua.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/lootwindow_harness.lua',encoding='utf-8').read())"
--
-- Tidslinjen under er ikke oppdiktet. Den er hentet ut av RCLootCouncils
-- debug-logg fra Nek'zali the Soulcoiler (heroic, 28 mann) 2026-08-19:
--
--   20:42:47  ENCOUNTER_END success=1
--   20:42:48  START_LOOT_ROLL x6            (+1 s)
--   20:42:49  LOOT_READY, 6 items i vinduet (+2 s)
--   20:42:59  LOOT_CLOSED, slots cleared    (+12 s)
--   20:43:04  «not found in bags» for alle 6 (+17 s)
--   20:43:23  LOOT_ITEM_ROLL_WON #1         (+36 s)  <- foerst NAA finnes itemet
--   20:43:30  LOOT_ITEM_ROLL_WON #2         (+43 s)
--   20:43:32  LOOT_ITEM_ROLL_WON #3         (+45 s)
--
-- Med Group Loot lander ingenting i noens bag foer rullen er avgjort. Et
-- innsamlingsvindu som er anker paa ENCOUNTER_END alene rekker aldri fram.

-- --- Virtuell klokke og timerkoe ---
local naa = 0
local koe = {}
local nesteId = 0

GetTime = function() return naa end

local function planlegg(sek, fn, gjentakende)
  nesteId = nesteId + 1
  local t = { id = nesteId, tid = naa + sek, fn = fn, avlyst = false }
  table.insert(koe, t)
  return {
    Cancel = function() t.avlyst = true end,
    IsCancelled = function() return t.avlyst end,
  }
end

C_Timer = {
  After = function(sek, fn) planlegg(sek, fn) end,
  NewTimer = function(sek, fn) return planlegg(sek, fn) end,
}

-- Kjoerer klokka fram til maal og fyrer alt som forfaller underveis, i riktig
-- rekkefoelge. Timere som planlegger nye timere blir med.
local function spolTil(maal)
  while true do
    local neste, nesteIdx = nil, nil
    for i, t in ipairs(koe) do
      if not t.avlyst and t.tid <= maal then
        if not neste or t.tid < neste.tid or (t.tid == neste.tid and t.id < neste.id) then
          neste, nesteIdx = t, i
        end
      end
    end
    if not neste then break end
    table.remove(koe, nesteIdx)
    naa = neste.tid
    neste.fn()
  end
  naa = maal
end

-- --- Ramme-stubb som respekterer registrering ---
local registrerte = {}
local handler = nil

CreateFrame = function()
  return {
    RegisterEvent = function(_, e) registrerte[e] = true end,
    UnregisterEvent = function(_, e) registrerte[e] = nil end,
    UnregisterAllEvents = function() registrerte = {} end,
    SetScript = function(_, _, fn) handler = fn end,
  }
end

local function fyr(event, ...)
  if not registrerte[event] then return false end
  handler(nil, event, ...)
  return true
end

-- --- Bagger ---
-- Itemet finnes ikke i bagen foer rullen er avgjort. Det er hele poenget.
local bagItem = nil

C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
  GetContainerItemLink = function(bag, slot)
    if bag == 0 and slot == 1 then return bagItem end
    return nil
  end,
}

-- Kalles med kolon i addonet, saa stubben maa ta imot self.
ItemLocation = { CreateFromBagAndSlot = function(self, b, s) return { bag = b, slot = s } end }

C_Item = {
  DoesItemExist = function() return bagItem ~= nil end,
  GetItemGUID = function() return "Item-1403-0-TESTGUID" end,
  GetItemInfoInstant = function() return 270162 end,
  -- 1 name 2 link 3 quality 4 ilvl 5 minLevel 6 type 7 subType 8 stack 9 equipLoc
  GetItemInfo = function()
    return "Soulcoiler Ritual Vessel", bagItem, 4, 671, 80,
           "Armor", "Plate", 1, "INVTYPE_CHEST"
  end,
}

UnitName = function() return "Bobletount" end
UnitIsGroupLeader = function() return false end
RollOnLoot = function() end
GetLootRollItemLink = function() return "[Soulcoiler Ritual Vessel]" end
GetLootRollItemInfo = function()
  return nil, nil, nil, 4, nil, true, nil, nil, nil, nil, nil, nil, true
end
-- Rullen sto paa ~42 s da den startet, jf. loggen (+1 s -> avgjort +36..45 s).
local rullMsIgjen = 42000
GetLootRollTimeLeft = function() return rullMsIgjen end

-- --- Addon-stubber ---
local sendte = {}

NordavindLC_NS = {
  active = true,
  LootDetection = {},
  Comms = {
    IsRestricted = function() return false end,
    Send = function(type, data) table.insert(sendte, { type = type, data = data }) end,
  },
  Utils = {
    Print = function() end,
    IsTradeableBagItem = function() return bagItem ~= nil end,
    IsWarbound = function() return false end,
    GetTierTokenArmorType = function() return nil end,
  },
}

dofile("NordavindLC/LootDetection.lua")

local NLC = NordavindLC_NS
NLC.LootDetection.Register()

-- --- Avspilling av den ekte tidslinjen ---
local function rapporterteItems()
  local n = 0
  for _, m in ipairs(sendte) do
    if m.type == "LOOT_REPORT" then n = n + #m.data.items end
  end
  return n
end

-- t=0: bossen doer. Bagen er tom — loot ligger i rull, ikke hos noen.
fyr("ENCOUNTER_END", 3470, "Nek'zali the Soulcoiler", 14, 28, 1)
assert(rapporterteItems() == 0, "ingenting skal vaere rapportert ved kill")

-- t=+1: seks ruller starter. Klienten vet naa at loot er paa vei.
spolTil(1)
assert(fyr("START_LOOT_ROLL", 1), "START_LOOT_ROLL maa vaere registrert")

-- t=+12: det gamle vinduet stengte her. Bagen er fortsatt tom.
spolTil(12)
assert(bagItem == nil, "testen selv er feil hvis itemet finnes allerede")

-- t=+36: rullen er avgjort, itemet lander i bagen og spillet melder fra.
spolTil(36)
bagItem = "|cffa335ee|Hitem:270162::::::::90:::::|h[Soulcoiler Ritual Vessel]|h|r"
assert(fyr("BAG_UPDATE_DELAYED"),
       "innsamlingsvinduet var allerede stengt da itemet landet i bagen")

-- t=+90: vinduet skal ha stengt av seg selv og sendt rapporten.
spolTil(90)
assert(rapporterteItems() == 1,
       "forventet 1 rapportert item, fikk " .. rapporterteItems())

print("tidslinje 2026-08-19 (Nek'zali): OK -> itemet ble fanget og rapportert")

-- Vinduet kan ikke staa aapent i det uendelige heller.
spolTil(600)
assert(registrerte["BAG_UPDATE_DELAYED"] == nil,
       "innsamlingsvinduet stengte aldri — bag-scan ville kjoert resten av kvelden")
print("takforsikring: OK -> vinduet stenger til slutt")

print("\nALLE PAASTANDER HOLDT")
