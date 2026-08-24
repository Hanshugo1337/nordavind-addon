-- Testrigg for NLC.Theme.Recolor.
--
-- Kjoeres fra repo-rot. Krever en Lua-tolk; med Python:
--     pip install lupa
--     python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/theme_harness.lua',encoding='utf-8').read())"
--
-- Itemlenker baerer sin egen farge, og spillet bruker TO formater om hverandre:
-- det gamle |cffRRGGBB og det nyere |cnIQ4:. Fangsten fra Nek'zali 2026-08-19 kom
-- inn som |cnIQ4:. En omfarging som bare kjenner det ene formatet lager enten en
-- ufarget rad eller en oedelagt lenke uten tooltip.

CreateFrame = function()
  return {
    SetPoint = function() end, SetSize = function() end, SetText = function() end,
    CreateFontString = function() return { SetPoint = function() end, SetText = function() end } end,
    CreateTexture = function() return { SetPoint = function() end, SetSize = function() end,
                                        SetColorTexture = function() end, SetTexture = function() end } end,
    SetScript = function() end, SetBackdrop = function() end, Show = function() end, Hide = function() end,
  }
end
UIParent = {}
GetTime = function() return 0 end

NordavindLC_NS = { Theme = {}, UI = {}, Utils = {} }
dofile("NordavindLC/UI/Theme.lua")

local T = NordavindLC_NS.Theme
assert(T.Recolor, "Theme.Recolor ble ikke eksponert")
assert(T.BLUE, "Theme.BLUE mangler")

local HALE = "|Hitem:270162::::::::90:65::3:3::::::|h[Soulcoiler Ritual Vessel]|h|r"

-- Format 1: det gamle |cffRRGGBB
local gammel = "|cffa335ee" .. HALE
assert(T.Recolor(gammel, T.BLUE) == T.BLUE .. HALE,
       "gammelt lenkeformat ble ikke omfarget: " .. tostring(T.Recolor(gammel, T.BLUE)))
print("format |cffRRGGBB: OK -> bl\195\165, lenken intakt")

-- Format 2: det nyere |cnIQ4:, som er det vi faktisk fikk inn fra bossen
local ny = "|cnIQ4:" .. HALE
assert(T.Recolor(ny, T.BLUE) == T.BLUE .. HALE,
       "nytt lenkeformat ble ikke omfarget: " .. tostring(T.Recolor(ny, T.BLUE)))
print("format |cnIQ4:  : OK -> bl\195\165, lenken intakt")

-- Halen maa vaere urort, ellers mister raden tooltip og klikk.
local resultat = T.Recolor(ny, T.BLUE)
assert(resultat:find("|h[Soulcoiler Ritual Vessel]|h|r", 1, true),
       "lenkehalen ble skadet")
assert(resultat:find("|Hitem:270162", 1, true), "item-ID-en forsvant ut av lenken")

-- Ting som ikke er lenker skal passere uendret, ikke krasje.
assert(T.Recolor(nil, T.BLUE) == nil, "nil skal gi nil")
assert(T.Recolor("bare tekst", T.BLUE) == "bare tekst", "tekst uten |H skal staa urort")
print("kanttilfeller   : OK -> nil og ren tekst overlever")

print("\nALLE PAASTANDER HOLDT")
