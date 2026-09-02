-- Testrigg for defensiv-advarselen i addonet.
--
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/defensivvarsel_harness.lua',encoding='utf-8').read())"
--
-- Terskelen MAA foelge DEFENSIVE_WARN_BELOW i nordavind-web/lib/defensives.ts.
-- Staar de paa ulike tall, faar samme spiller advarsel paa nettsida men ikke i
-- addonet, eller omvendt - og ingen av delene sier fra.
--
-- Bakgrunn 02.09.2026: begge sider sto paa 0.8, mens kodebasens egen
-- karakterskala (evaluateDefensives) kalte 0.5 og opp "good". For 31 av 33
-- specer var altsaa den bruken som utloeste advarsel nettopp den raidanalysen
-- ga toppkarakter. Verre: tallet er en ANDEL av knappene, saa 0.8 krevde at en
-- Ret paladin fyrte fire av fem knapper hver fight - tre av dem har flere
-- minutters cooldown. Kravet var uoppnaaelig for specen.

NordavindLC_NS = {
  Scoring = {},
  db = {
    weeklyLoot = { counts = {}, resetTimestamp = 0 },
    importData = nil,
  },
  Utils = { Print = function() end },
}

dofile("NordavindLC/Scoring.lua")
local NLC = NordavindLC_NS

local function harDefensivvarsel(andel)
  local warnings = NLC.Scoring.GetWarnings({ defensives = andel }, "Testperson")
  for _, w in ipairs(warnings or {}) do
    if w:find("defensives") then return true, w end
  end
  return false, nil
end

-- --- Terskelen: 0.25, samme som web ---
local advart = harDefensivvarsel(0.20)
assert(advart, "0.20 er under grensa og skal advares")

advart = harDefensivvarsel(0.25)
assert(not advart, "0.25 er PAA grensa og skal ikke advares")

advart = harDefensivvarsel(0.30)
assert(not advart, "0.30 skal ikke advares - dette var feilen: den gamle 0.8 " ..
       "flagget folk som kodebasens egen skala kalte godt nok")

advart = harDefensivvarsel(0.60)
assert(not advart, "0.60 er 'good' paa web-skalaen og skal aldri advares")
print("terskelen            : OK -> advarer under 0.25, som lib/defensives.ts")

-- --- En Ret paladin med begge korte CD-ene ---
-- Fem knapper, men bare Divine Protection og Shield of Vengeance kommer
-- tilbake fort nok til aa trykkes hver fight. 1.5 kast per fight / 5 knapper
-- = 0.30. Under den gamle grensa var dette en advarsel.
advart = harDefensivvarsel(1.5 / 5)
assert(not advart, "en Ret som bruker begge korte CD-ene skal ikke flagges")
print("ret paladin          : OK -> 0.30 er ikke lenger en advarsel")

-- --- Manglende data er ikke null bruk ---
local warnings = NLC.Scoring.GetWarnings({}, "Testperson")
for _, w in ipairs(warnings or {}) do
  assert(not w:find("defensives"),
         "uten defensiv-data skal det ikke staa noe - web sender nil for tanks")
end
print("manglende data       : OK -> ingen advarsel uten tall")

-- --- Teksten sier andel, ikke kast per fight ---
local _, tekst = harDefensivvarsel(0.20)
assert(tekst:find("20%%"), "teksten skal si 20% av knappene, fikk: " .. tostring(tekst))
assert(not tekst:find("/fight"), "'/fight' var loegna som ble rettet i 1.9.5")
print("teksten              : OK -> andel av knappene, ikke kast/fight")

print("\nALLE PAASTANDER HOLDT")
