-- Testrigg for tooltip-oppslaget i Utils.lua.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/tooltipapi_harness.lua',encoding='utf-8').read())"
--
-- Ekte feil, fanget av BugGrabber 2026-08-19 21:02:09 midt i raidet:
--
--   Utils.lua:105: attempt to call a nil value
--     Utils.lua:105:        in function 'IsWarbound'
--     LootDetection.lua:92: in function <LootDetection.lua:77>   (shouldTrackItem)
--     LootDetection.lua:146: in function 'ScanBags'
--     LootDetection.lua:216: in function <LootDetection.lua:184> (ENCOUNTER_END)
--
-- Funksjonen het C_TooltipInfo.GetItemByHyperlink. Det navnet finnes ikke i
-- klienten — det heter GetHyperlink. NordavindLC var det eneste addonet i hele
-- AddOns-mappa som brukte det gale navnet. Kallet kastet, og siden det skjedde
-- inne i ScanBags, doede HELE bag-gjennomgangen paa det foerste itemet som
-- ellers ville blitt fanget opp.

NordavindLC_NS = nil
C_TooltipInfo = nil

local function lastUtils()
  NordavindLC_NS = nil
  dofile("NordavindLC/Utils.lua")
  return NordavindLC_NS.Utils
end

local LENKE = "|cffa335ee|Hitem:268235::::::::90:::::|h[Vestment of the Awakening]|h|r"

-- --- Scenario 1: klienten slik den faktisk er (kun GetHyperlink) ---
local kalt = false
C_TooltipInfo = {
  GetHyperlink = function(link)
    kalt = true
    return { lines = { { leftText = "Vestment of the Awakening" },
                       { leftText = "Warbound until equipped" } } }
  end,
}
local U = lastUtils()
assert(U.IsWarbound(LENKE) == true,
       "IsWarbound fant ikke Warbound-linja via GetHyperlink")
assert(kalt, "GetHyperlink ble aldri kalt — feil funksjonsnavn?")
print("scenario 1 (kun GetHyperlink, som i klienten): OK -> leste tooltipen")

-- --- Scenario 2: gammelt navn finnes ogsaa (skal fortsatt virke) ---
C_TooltipInfo = {
  GetItemByHyperlink = function()
    return { lines = { { leftText = "Warbound until equipped" } } }
  end,
}
U = lastUtils()
assert(U.IsWarbound(LENKE) == true, "fallback til det gamle navnet virker ikke")
print("scenario 2 (kun gammelt navn):              OK -> fallback holder")

-- --- Scenario 3: ingen av delene. Skal IKKE kaste. Dette er selve regresjonen ---
C_TooltipInfo = {}
U = lastUtils()
local ok, res = pcall(U.IsWarbound, LENKE)
assert(ok, "IsWarbound kastet i stedet for aa gi opp pent: " .. tostring(res))
assert(res == false, "uten tooltip skal svaret vaere false, ikke " .. tostring(res))

-- GetTierTokenArmorType gaar samme vei og maa taale det samme.
C_Item = { GetItemInfo = function() return nil, nil, 4, nil, nil, nil, nil, nil, "" end }
local ok2, res2 = pcall(U.GetTierTokenArmorType, LENKE)
assert(ok2, "GetTierTokenArmorType kastet: " .. tostring(res2))
print("scenario 3 (API-et mangler helt):           OK -> ga opp uten aa kaste")

-- --- Scenario 4: API-et finnes, men selve kallet feiler ---
C_TooltipInfo = { GetHyperlink = function() error("secret value") end }
U = lastUtils()
local ok3, res3 = pcall(U.IsWarbound, LENKE)
assert(ok3, "en tooltip som kaster maa fanges, ikke slippes videre: " .. tostring(res3))
assert(res3 == false, "forventet false, fikk " .. tostring(res3))
print("scenario 4 (kallet kaster):                 OK -> fanget av pcall")

print("\nALLE PAASTANDER HOLDT")
