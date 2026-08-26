-- Utils.lua
-- Shared utility functions for NordavindLC

NordavindLC_NS = NordavindLC_NS or {}
local NLC = NordavindLC_NS
NLC.Utils = {}
NLC.UI = {}
NLC.Comms = {}
NLC.LootDetection = {}
NLC.Council = {}
NLC.Scoring = {}
NLC.Trade = {}

NLC.Utils.CLASS_COLORS = {
  DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
  DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
  DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
  EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
  HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
  MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
  MONK        = { r = 0.00, g = 1.00, b = 0.60 },
  PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
  PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
  ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
  SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
  WARLOCK     = { r = 0.53, g = 0.53, b = 0.93 },
  WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
}

-- Addonets versjon fra .toc. Sendes i ROLL_CALL_ACK så offiseren kan se hvem
-- som kjører gammelt — en utdatert klient rangerer og viser annerledes uten å
-- si fra. C_AddOns er den moderne veien; den globale finnes fortsatt som fallback.
function NLC.Utils.AddonVersion()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if not get then return "?" end
  local ok, v = pcall(get, "NordavindLC", "Version")
  return (ok and v) or "?"
end

function NLC.Utils.ClassColoredName(name, class)
  local c = NLC.Utils.CLASS_COLORS[class]
  if not c then return name end
  return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end

NLC.Utils.SLOT_MAP = {
  INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
  INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6,
  INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9,
  INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
  INVTYPE_TRINKET = 13,
  INVTYPE_CLOAK = 15, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPON = 16,
  INVTYPE_WEAPONMAINHAND = 16, INVTYPE_RANGED = 16,
  INVTYPE_WEAPONOFFHAND = 17, INVTYPE_HOLDABLE = 17, INVTYPE_SHIELD = 17,
}

function NLC.Utils.GetEquippedInfo(equipLoc)
  local slotId = NLC.Utils.SLOT_MAP[equipLoc]
  if not slotId then return nil, 0 end

  -- Rings and trinkets have two slots — return the lower ilvl one
  local altSlot = nil
  if equipLoc == "INVTYPE_FINGER" then altSlot = 12
  elseif equipLoc == "INVTYPE_TRINKET" then altSlot = 14
  end

  local link = GetInventoryItemLink("player", slotId)
  local ilvl = link and (GetDetailedItemLevelInfo(link) or 0) or 0

  if altSlot then
    local link2 = GetInventoryItemLink("player", altSlot)
    local ilvl2 = link2 and (GetDetailedItemLevelInfo(link2) or 0) or 0
    -- Only compare if both slots are occupied
    if link2 and link then
      if ilvl2 < ilvl then return link2, ilvl2 end
    elseif link2 and not link then
      return link2, ilvl2
    end
  end

  if not link then return nil, 0 end
  return link, ilvl
end

function NLC.Utils.GetTierCount()
  local tierSlots = { 1, 3, 5, 10, 7 } -- head, shoulder, chest, hands, legs
  local count = 0
  for _, slot in ipairs(tierSlots) do
    local tooltipData = C_TooltipInfo.GetInventoryItem("player", slot)
    if tooltipData and tooltipData.lines then
      for _, line in ipairs(tooltipData.lines) do
        local text = line.leftText or ""
        if text:find("%(%d/%d%)") or text:find("Set:") or text:find("Set Bonus") then
          count = count + 1
          break
        end
      end
    end
  end
  return count
end

-- Tooltip-linjene for en itemlenke, eller nil.
--
-- Funksjonen het `C_TooltipInfo.GetItemByHyperlink` her. Det navnet finnes ikke
-- — det heter `GetHyperlink`, og NordavindLC var det eneste addonet i klienten
-- som brukte det gale. Kallet ga ikke feil svar, det var nil, så det KASTET, og
-- fra ScanBags rev det med seg hele bag-gjennomgangen på det første itemet som
-- ellers ville blitt fanget. Derfor pcall også: en tooltip som ikke lar seg lese
-- skal koste oss det ene itemet, aldri hele runden.
local function itemTooltipLines(itemLink)
  if not itemLink or not C_TooltipInfo then return nil end
  local get = C_TooltipInfo.GetHyperlink or C_TooltipInfo.GetItemByHyperlink
  if not get then return nil end
  local ok, data = pcall(get, itemLink)
  if not ok or not data then return nil end
  return data.lines
end

function NLC.Utils.IsWarbound(itemLink)
  if not itemLink then return false end
  local lines = itemTooltipLines(itemLink)
  if not lines then return false end
  for _, line in ipairs(lines) do
    local text = line.leftText or ""
    if text:find("Warbound") or text:find("Account Bound") then
      return true
    end
  end
  return false
end

-- Returns true if the item in (bag, slot) still has an active trade window
-- (BoP looted within the "you may trade this item for the next N" period).
-- Language-independent: matches the localized prefix of BIND_TRADE_TIME_REMAINING.
function NLC.Utils.IsTradeableBagItem(bag, slot)
  if not bag or not slot then return false end
  local data = C_TooltipInfo and C_TooltipInfo.GetBagItem(bag, slot)
  if not data or not data.lines then return false end
  -- Build a plain-text match prefix from the global string (drop the %s tail).
  local marker = _G.BIND_TRADE_TIME_REMAINING or "You may trade this item"
  marker = marker:gsub("%%s.*$", ""):gsub("%s+$", "")
  for _, line in ipairs(data.lines) do
    local text = line.leftText or ""
    if text:find(marker, 1, true) then
      return true
    end
  end
  return false
end

-- Rough estimate of remaining trade seconds for the item in (bag, slot), or nil.
-- Precision is intentionally coarse: the tooltip often shows only "N h"/"N m".
function NLC.Utils.GetBagItemTradeSeconds(bag, slot)
  local data = C_TooltipInfo and C_TooltipInfo.GetBagItem(bag, slot)
  if not data or not data.lines then return nil end
  local marker = _G.BIND_TRADE_TIME_REMAINING or "You may trade this item"
  marker = marker:gsub("%%s.*$", ""):gsub("%s+$", "")
  for _, line in ipairs(data.lines) do
    local text = line.leftText or ""
    if text:find(marker, 1, true) then
      local hours = tonumber(text:match("(%d+)%s*[Hht]")) or 0
      local mins  = tonumber(text:match("(%d+)%s*[Mm]")) or 0
      local sec = hours * 3600 + mins * 60
      if sec == 0 then sec = 7200 end -- found the line but couldn't parse → assume 2h
      return sec
    end
  end
  return nil
end

-- Armor type per class (for filtering council buttons)
NLC.Utils.CLASS_ARMOR = {
  WARRIOR = "Plate", PALADIN = "Plate", DEATHKNIGHT = "Plate",
  HUNTER = "Mail", SHAMAN = "Mail", EVOKER = "Mail",
  ROGUE = "Leather", MONK = "Leather", DRUID = "Leather", DEMONHUNTER = "Leather",
  MAGE = "Cloth", WARLOCK = "Cloth", PRIEST = "Cloth",
}

local TIER_TOKEN_ARMOR_TYPES = { Cloth = true, Leather = true, Mail = true, Plate = true }

-- «Lokalisert klassenavn» -> klassetoken, bygget én gang ved første behov.
-- Blizzard fyller begge tabellene med klassetoken som nøkkel, så vi snur dem.
local localizedClassToToken
local function classNameLookup()
  if localizedClassToToken then return localizedClassToToken end
  localizedClassToToken = {}
  for _, kilde in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
    if type(kilde) == "table" then
      for token, navn in pairs(kilde) do
        if type(navn) == "string" then localizedClassToToken[navn] = token end
      end
    end
  end
  return localizedClassToToken
end

-- Rustningstypen til et tier-token, lest ut av «Classes:»-linja i tooltipen.
--
-- Et token har itemSubType «Junk» og ingen egen linje som bare sier «Plate», så
-- de to sjekkene under fanger det ikke. Men tooltipen lister alltid klassene
-- tokenet gjelder, og alle klassene på ett token deler rustningstype — så den
-- første klassen vi kjenner igjen avgjør. ITEM_CLASSES_ALLOWED er Blizzards egen
-- formatstreng, samme grep som handelstida i IsTradeableBagItem, så dette virker
-- uansett klientspråk.
local function tokenArmorFromClasses(lines)
  if not lines then return nil end
  local prefiks = (_G.ITEM_CLASSES_ALLOWED or "Classes: %s"):gsub("%%s.*$", "")
  if prefiks == "" then return nil end
  local oppslag = classNameLookup()
  for _, line in ipairs(lines) do
    local text = line.leftText or ""
    if text:find(prefiks, 1, true) == 1 then
      for raa in text:sub(#prefiks + 1):gmatch("[^,]+") do
        local navn = raa:match("^%s*(.-)%s*$")
        local token = oppslag[navn]
        local rustning = token and NLC.Utils.CLASS_ARMOR[token]
        if rustning then return rustning end
      end
    end
  end
  return nil
end

-- Returns "Cloth", "Leather", "Mail", or "Plate" if the item is an armor-type tier token.
-- A tier token is epic+, non-equippable, and tied to a specific armor class.
function NLC.Utils.GetTierTokenArmorType(itemLink)
  if not itemLink then return nil end
  local _, _, quality, _, _, _, itemSubType, _, equipLoc = C_Item.GetItemInfo(itemLink)
  if not quality or quality < 4 then return nil end
  if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then return nil end
  if itemSubType and TIER_TOKEN_ARMOR_TYPES[itemSubType] then return itemSubType end
  -- Tooltip fallback: scan for a line that is exactly the armor type name
  local lines = itemTooltipLines(itemLink)
  if lines then
    for _, line in ipairs(lines) do
      local t = line.leftText or ""
      if TIER_TOKEN_ARMOR_TYPES[t] then return t end
    end
  end
  -- Siste utvei, og den som faktisk treffer på ekte tier-tokens: klasselista.
  return tokenArmorFromClasses(lines)
end

local ARMOR_SUBCLASS = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
local TIER_SLOTS = { INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_HAND = true, INVTYPE_LEGS = true }
local JEWELRY_SLOTS = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_NECK = true, INVTYPE_CLOAK = true }
local WEAPON_SLOTS = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true, INVTYPE_RANGED = true }

-- Er slotten en tier-slot? Eksponert fordi BÅDE knappefilteret her og
-- rangeringen i Council må svare likt. De gjorde ikke det: front-end fritok tier
-- fra wishlist-filteret, rangeringen gjorde ikke, og da kunne en raider trykke
-- «Upgrade» på en tier-del og likevel bli kastet ut av lista uten et ord.
function NLC.Utils.IsTierSlot(equipLoc)
  return equipLoc ~= nil and TIER_SLOTS[equipLoc] == true
end

-- Er disse to navnene den samme spilleren?
--
-- Avsenderen på en comms-melding kommer som «Navn-Realm», mens raid-rosteret
-- like gjerne svarer «Navn». Realmen må derfor bort på begge sider før vi
-- sammenligner. Ambiguate er spillets egen stripper og tar tilfellene et
-- mønster på bindestrek ikke tar.
--
-- Kasus må også bort, og det er ikke en formalitet i denne guilda: UnitIsUnit
-- sammenligner «Æver» og «æver» som to ulike spillere. Med et norsk roster er
-- det navn vi faktisk har. Derfor ren strengsammenligning i små bokstaver,
-- med UnitIsUnit kun som ekstra ja — aldri som eneste kilde.
--
-- string.lower kan IKKE brukes på navn her. Den senker byte for byte etter
-- lokalet, og et norsk navn er ikke én byte per tegn: «Æ» er 0xC3 0x86 i
-- UTF-8. Testriggen fanget den — string.lower senket 0xC3 til 0xE3 og gjorde
-- «Æver» om til noe som ikke er et navn i det hele tatt. Derfor senkes ASCII
-- for hånd, og Latin-1-tillegget (Æ Ø Å É …) med sin egen byte-regel.
local function smaaBokstaver(navn)
  navn = navn:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
  return (navn:gsub("\195([\128-\158])", function(b)
    local kode = b:byte()
    if kode == 0x97 then return "\195" .. b end -- U+00D7 er gangetegn, ikke bokstav
    return "\195" .. string.char(kode + 0x20)
  end))
end

function NLC.Utils.ErSammeSpiller(a, b)
  if not a or not b or a == "" or b == "" then return false end

  local function kort(navn)
    if Ambiguate then
      local ok, res = pcall(Ambiguate, navn, "short")
      if ok and res and res ~= "" then navn = res end
    else
      navn = navn:match("^([^-]+)") or navn
    end
    return smaaBokstaver(navn)
  end

  local ka, kb = kort(a), kort(b)
  if ka == kb then return true end

  local ok, res = pcall(UnitIsUnit, ka, kb)
  return (ok and res) == true
end

-- Navnet på den som leder gruppa, eller nil hvis vi ikke vet.
--
-- Rang 2 i GetRaidRosterInfo er lederen. Returnerer nil framfor å gjette:
-- kallere bruker dette til å avgjøre hvem som har lov til å skru addonet på
-- hos andre, og «vet ikke» må bety nei der.
function NLC.Utils.GruppelederNavn()
  if not IsInRaid or not IsInRaid() then return nil end
  for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
    local navn, rang = GetRaidRosterInfo(i)
    if navn and rang == 2 then return navn end
  end
  return nil
end

-- Er avsenderen den som leder gruppa akkurat nå?
--
-- Porten for all fjernaktivering. Se aktivering_harness: uten den kunne hvem
-- som helst med et hengende active-flagg skru på auto-passet hos hele raidet,
-- og i en pug betyr det at alle passer på alt uten å ha bedt om noe.
function NLC.Utils.ErGruppeleder(avsender)
  local leder = NLC.Utils.GruppelederNavn()
  if not leder then return false end
  return NLC.Utils.ErSammeSpiller(avsender, leder)
end

-- Klassetoken for en spiller i raidet, eller nil hvis vi ikke vet.
--
-- UnitClass tar en unit-id. Et spillernavn duger som unit-id for folk i gruppa
-- di — men i et cross-realm raid MÅ realmen være med. Offiseren strippet den
-- («Moggin-TarrenMill» → «Moggin»), fikk nil, og falt tilbake på «WARRIOR» for
-- alle. På et tier-token betyr det at rustningsfilteret sammenlignet Plate mot
-- alle: var tokenet Cloth, Leather eller Mail ble HVER ENESTE kandidat kastet ut
-- og rangeringsvinduet sto tomt.
--
-- Derfor: prøv fullt navn først, så kortformen, og til slutt raid-rosteret, som
-- kjenner klassen uansett realm. Returnerer nil framfor å gjette — den som
-- kaller må skille «feil klasse» fra «vet ikke».
function NLC.Utils.ClassForPlayer(sender)
  if not sender or sender == "" then return nil end
  local kort = sender:match("^([^-]+)") or sender

  for _, id in ipairs({ sender, kort }) do
    local ok, _, klasse = pcall(UnitClass, id)
    if ok and klasse then return klasse end
  end

  for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
    local navn, _, _, _, _, fil = GetRaidRosterInfo(i)
    if navn then
      local navnKort = navn:match("^([^-]+)") or navn
      if navn == sender or navnKort == kort then return fil end
    end
  end

  return nil
end

function NLC.Utils.GetAvailableCategories(itemLink, equipLoc, itemId)
  -- Tmog is available on everything by default.
  -- Only exception: tier-slot items of wrong armor type (can't equip, can't appear).
  local result = { upgrade = false, catalyst = false, offspec = false, tmog = true }
  if not itemLink then return result end

  -- Items without equipLoc: tier tokens or recipes
  if not equipLoc or equipLoc == "" then
    local tokenArmor = NLC.Utils.GetTierTokenArmorType(itemLink)
    if tokenArmor then
      local _, playerClass = UnitClass("player")
      local myArmor = NLC.Utils.CLASS_ARMOR[playerClass]
      if myArmor == tokenArmor then
        result.upgrade = true
        result.offspec = true
      end
      -- Tokens can't be transmogged regardless of armor type
      return result
    end
    -- Non-token (recipe etc.) — leader decides
    result.upgrade = true
    return result
  end

  local _, playerClass = UnitClass("player")
  local myArmor = NLC.Utils.CLASS_ARMOR[playerClass]

  -- Jewelry/cloaks — universal, everyone can use
  if JEWELRY_SLOTS[equipLoc] then
    result.upgrade = true
    result.offspec = true
    return result
  end

  -- Weapons — check if player can equip this weapon type
  if WEAPON_SLOTS[equipLoc] then
    if IsEquippableItem(itemLink) then
      result.upgrade = true
      result.offspec = true
    end
    return result
  end

  -- Armor — check armor type via GetItemInfoInstant (synchronous)
  -- Returns: itemID, itemType(str), itemSubType(str), equipLoc, icon, classID(num), subclassID(num)
  local itemID, itemTypeStr, itemSubTypeStr, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemLink)

  -- Try numeric classID first (classID 4 = Armor)
  local isArmor = (classID == 4) or (itemTypeStr == "Armor")
  local armorSubType = ARMOR_SUBCLASS[subclassID] or itemSubTypeStr

  if isArmor then
    local correctArmor = armorSubType and armorSubType == myArmor
    if correctArmor then
      result.upgrade = true
      result.offspec = true
      if TIER_SLOTS[equipLoc] then
        result.catalyst = true
      end
    end
  elseif IsEquippableItem(itemLink) then
    result.upgrade = true
    result.offspec = true
    if TIER_SLOTS[equipLoc] then
      result.catalyst = true
    end
  else
    -- Item not yet cached — show upgrade/offspec based on equipLoc; tmog stays true
    result.upgrade = true
    result.offspec = true
    if TIER_SLOTS[equipLoc] then
      result.catalyst = true
    end
  end

  -- Wishlist filter: if upgrade would be available, check if this item is on the player's wishlist.
  -- If import data exists but the item is NOT wishlisted, disable upgrade.
  -- Tier-slot items are EXEMPT: tier is build-defining and rarely sits on a wishlist, so
  -- filtering it out wrongly stripped "upgrade" from players who can actually use the tier
  -- piece, leaving only "catalyst". Tier slots always allow upgrade for the right armor type.
  if result.upgrade and itemId and not TIER_SLOTS[equipLoc] then
    local playerName = UnitName("player")
    local imported = NLC.db and NLC.db.importData and NLC.db.importData.players and
                     NLC.db.importData.players[playerName]
    if imported and imported.wishlist and #imported.wishlist > 0 then
      local wishlisted = false
      for _, wid in ipairs(imported.wishlist) do
        if wid == itemId then wishlisted = true; break end
      end
      if not wishlisted then
        result.upgrade = false
      end
    end
  end

  return result
end

function NLC.Utils.DeepCopy(orig)
  if type(orig) ~= "table" then return orig end
  local copy = {}
  for k, v in pairs(orig) do
    copy[k] = NLC.Utils.DeepCopy(v)
  end
  return copy
end

function NLC.Utils.TableCount(t)
  local count = 0
  if t then for _ in pairs(t) do count = count + 1 end end
  return count
end

function NLC.Utils.Print(msg)
  print("|cff00ccff[NordavindLC]|r " .. msg)
end

-- Diagnoselogg som overlever /reload.
--
-- Chatten er borte i det øyeblikket noe går galt, og /nordlc debug spammer
-- skjermen uten å etterlate seg noe. Dette skriver de samme opplysningene til
-- SavedVariables i stedet, så hele innsamlingsrunden kan leses etterpå. Ringen
-- holder de siste 150 linjene; eldre faller ut av seg selv.
local DIAG_MAX = 150
function NLC.Utils.Diag(msg)
  if not NLC.db then return end
  NLC.db.diagLog = NLC.db.diagLog or {}
  local logg = NLC.db.diagLog
  table.insert(logg, date("%H:%M:%S") .. " " .. tostring(msg))
  while #logg > DIAG_MAX do table.remove(logg, 1) end
end
