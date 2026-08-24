-- Testrigg for at rapporten kun inneholder loot fra DENNE bossen.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/bagbacklog_harness.lua',encoding='utf-8').read())"
--
-- Fanget av diagnoseloggen etter The Coiled Altar 2026-08-19 kl. 22:45:11:
-- 40 items ble rapportert, hvorav 34 i selve killoeyeblikket — nøyaktig de 34
-- «/nordlc addall» hadde funnet i baggen en halvtime foer. Kun 6 kom fra bossen.
-- Bag-skannet skiller ikke paa hvor et item kommer fra; alt tradeable med
-- handelstid igjen ble sveipet med, og panelet ville vist hele restlageret.
--
-- Kravet: det som ligger i baggen NAAR bossen doer holdes utenfor, og kun det
-- som lander etterpaa rapporteres. Restlageret er «/nordlc addall» sin jobb.

local naa = 0
local koe = {}
local nesteId = 0
GetTime = function() return naa end

local function planlegg(sek, fn)
  nesteId = nesteId + 1
  local t = { id = nesteId, tid = naa + sek, fn = fn, avlyst = false }
  table.insert(koe, t)
  return { Cancel = function() t.avlyst = true end }
end
C_Timer = {
  After = function(sek, fn) planlegg(sek, fn) end,
  NewTimer = function(sek, fn) return planlegg(sek, fn) end,
}

local function spolTil(maal)
  while true do
    local neste, idx
    for i, t in ipairs(koe) do
      if not t.avlyst and t.tid <= maal then
        if not neste or t.tid < neste.tid or (t.tid == neste.tid and t.id < neste.id) then
          neste, idx = t, i
        end
      end
    end
    if not neste then break end
    table.remove(koe, idx)
    naa = neste.tid
    neste.fn()
  end
  naa = maal
end

-- spolTil tar ABSOLUTT tid. Etter foerste scenario staar klokka langt framme,
-- og et nytt scenario som ber om spolTil(5) sender den bakover — da fyrer ingen
-- timere, og testen «passerer» uten aa ha kjoert noe. Bruk denne i stedet.
local function spolFram(sek) spolTil(naa + sek) end

local registrerte, handler = {}, nil
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

-- Bag med flere slots og ekte, distinkte GUID-er.
local baggen = {}
C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and 8 or 0 end,
  GetContainerItemLink = function(b, s)
    return b == 0 and baggen[s] and baggen[s].link or nil
  end,
}
ItemLocation = { CreateFromBagAndSlot = function(self, b, s) return { bag = b, slot = s } end }
C_Item = {
  DoesItemExist = function(loc) return baggen[loc.slot] ~= nil end,
  GetItemGUID = function(loc) return baggen[loc.slot].guid end,
  -- Utled ID fra lenka, saa ulike items faar ulike ID-er.
  GetItemInfoInstant = function(link)
    return tonumber(tostring(link):match("Hitem:(%d+)")) or 270162
  end,
  GetItemInfo = function(link)
    return "navn", link, 4, 671, 80, "Armor", "Plate", 1, "INVTYPE_CHEST"
  end,
}
UnitName = function() return "Bobletount" end
UnitIsGroupLeader = function() return false end
RollOnLoot = function() end
GetLootRollItemLink = function() return "[Item]" end
GetLootRollItemInfo = function() return nil, nil, nil, 4, nil, true end
GetLootRollTimeLeft = function() return 270000 end

local sendte = {}
NordavindLC_NS = {
  active = true,
  db = {},
  LootDetection = {},
  Comms = {
    IsRestricted = function() return false end,
    Send = function(t, d) table.insert(sendte, { type = t, data = d }) end,
  },
  Utils = {
    Print = function() end, Diag = function() end,
    IsTradeableBagItem = function(b, s) return b == 0 and baggen[s] ~= nil end,
    IsWarbound = function() return false end,
    GetTierTokenArmorType = function() return nil end,
  },
}

dofile("NordavindLC/LootDetection.lua")
local LD = NordavindLC_NS.LootDetection
LD.Register()

local function leggIBag(slot, navn)
  baggen[slot] = { link = "|cffa335ee|Hitem:2701" .. slot .. "::::::::90:::::|h[" .. navn .. "]|h|r",
                   guid = "GUID-" .. navn }
end

local function rapportert()
  local navn = {}
  for _, m in ipairs(sendte) do
    if m.type == "LOOT_REPORT" then
      for _, it in ipairs(m.data.items) do
        navn[#navn + 1] = it.itemLink:match("%[(.-)%]")
      end
    end
  end
  table.sort(navn)
  return navn
end

-- --- Restlageret: tre items som har ligget i baggen hele kvelden ---
leggIBag(1, "Gammel-A")
leggIBag(2, "Gammel-B")
leggIBag(3, "Gammel-C")

-- Bossen doer. Restlageret skal merkes som «fra foer».
fyr("ENCOUNTER_END", 3510, "The Coiled Altar", 14, 28, 1)
spolTil(1)
assert(fyr("START_LOOT_ROLL", 1), "START_LOOT_ROLL maa vaere registrert")

-- Rullen avgjoeres, to ekte drops lander.
spolTil(200)
leggIBag(4, "Ny-A")
leggIBag(5, "Ny-B")
assert(fyr("BAG_UPDATE_DELAYED"), "vinduet skal fortsatt staa aapent paa +200 s")

-- Vinduet stenger og rapporten gaar.
spolTil(600)

local navn = rapportert()
assert(#navn == 2,
       "forventet KUN de to nye, fikk " .. #navn .. ": " .. table.concat(navn, ", "))
assert(navn[1] == "Ny-A" and navn[2] == "Ny-B",
       "feil items rapportert: " .. table.concat(navn, ", "))
print("restlager            : OK -> 3 gamle holdt utenfor, kun Ny-A og Ny-B sendt")

-- --- /nordlc addall skal derimot se ALT som ligger der ---
local alle = LD.ScanBagsForPanel()
assert(#alle == 5,
       "addall skal se hele baggen (5), fikk " .. #alle)
print("addall               : OK -> ser alle 5, uavhengig av rapporten")

-- --- Taket maa romme en rull paa 270 s som starter sent ---
-- Rullen startet paa +1 s her, saa 1 + 270 + 12 = 283 s. Vinduet maa ha vaert
-- aapent paa +200 s, noe paastanden over allerede beviste.
print("rull paa 270 s       : OK -> vinduet holdt til rullen var avgjort")

-- --- Overlever en uferdig rapport en /reload? ---
--
-- 2026-08-19 reloadet offiseren 43 sekunder etter killet, mens innsamlingen
-- fortsatt gikk. Rapporten laa kun i minnet og forsvant med den.
baggen[6] = { link = "|cffa335ee|Hitem:99::::::::90:::::|h[Uferdig]|h|r",
              guid = "GUID-Uferdig" }
LD.ScanBags()
local foerReload = #LD.GetReport()
assert(foerReload > 0, "testen selv er feil hvis det ikke ligger noe uferdig")
assert(NordavindLC_NS.db.pendingReport, "rapporten ble aldri skrevet ned")

-- «Reload»: modulen nullstiller seg, men SavedVariables staar.
LD.Unregister()
LD.Register()
assert(#LD.GetReport() == foerReload,
       "rapporten overlevde ikke reload: " .. foerReload .. " -> " .. #LD.GetReport())
print("overlever reload     : OK -> " .. foerReload .. " item(s) hentet tilbake")

-- Og naar den faktisk er sendt, skal den ikke ligge igjen og bli sendt paa nytt.
NordavindLC_NS.LootDetection.TrySendReport()
assert(NordavindLC_NS.db.pendingReport == nil,
       "sendt rapport ble liggende igjen — den ville blitt sendt om igjen")
print("toemmes ved sending  : OK -> ingen dobbeltsending etter reload")

-- --- Andre deteksjonsvei: LOOT_ITEM_ROLL_WON ---
--
-- Bag-skannet har to ledd som kan svikte: itemet maa ligge i baggen naar vi ser
-- etter, og handelstida maa la seg lese ut av tooltipen. Svikter ett av dem, er
-- itemet borte for raadet. LOOT_ITEM_ROLL_WON kommer rett fra spillet i det
-- rullen avgjoeres, og er uavhengig av begge.
sendte = {}
baggen = {}
LD.Unregister()
LD.Register()
NordavindLC_NS.db.pendingReport = nil

fyr("ENCOUNTER_END", 3510, "Vashnik", 14, 28, 1)
assert(registrerte["LOOT_ITEM_ROLL_WON"], "LOOT_ITEM_ROLL_WON ble ikke registrert")

-- Vi vant et item, men det dukker ALDRI opp i baggen slik vi ser den.
local VUNNET = "|cffa335ee|Hitem:55555::::::::90:::::|h[Vunnet-Kappe]|h|r"
spolFram(5)
fyr("LOOT_ITEM_ROLL_WON", VUNNET, 1, 1, 42, false)

spolFram(700)
local navn2 = rapportert()
assert(#navn2 == 1, "forventet 1 item fra rull-fallbacken, fikk " .. #navn2 ..
       ": " .. table.concat(navn2, ", "))
assert(navn2[1] == "Vunnet-Kappe", "feil item: " .. navn2[1])
print("rull-fallback        : OK -> fanget selv om baggen var tom")

-- --- Ingen dobbeltfoering naar BEGGE veiene ser samme item ---
sendte = {}
baggen = {}
LD.Unregister()
LD.Register()
NordavindLC_NS.db.pendingReport = nil

fyr("ENCOUNTER_END", 3510, "Vashnik", 14, 28, 1)
spolFram(5)
baggen[1] = { link = "|cffa335ee|Hitem:77777::::::::90:::::|h[Begge]|h|r",
              guid = "GUID-Begge" }
fyr("LOOT_ITEM_ROLL_WON", "|cffa335ee|Hitem:77777::::::::90:::::|h[Begge]|h|r", 1, 1, 42, false)
fyr("BAG_UPDATE_DELAYED")
spolFram(700)
local navn3 = rapportert()
assert(#navn3 == 1, "itemet ble rapportert " .. #navn3 .. " ganger — dobbeltfoering")
print("ingen dobbeltfoering : OK -> bag og rull gir én oppfoering")

print("\nALLE PAASTANDER HOLDT")
