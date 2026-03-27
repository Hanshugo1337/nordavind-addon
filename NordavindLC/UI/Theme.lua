-- UI/Theme.lua
-- Shared colors and styling helpers matching nordavind.no design

local NLC = NordavindLC_NS

NLC.Theme = {}

-- Colors from nordavind.no globals.css
NLC.Theme.gold       = { r = 0.788, g = 0.659, b = 0.298 }  -- #c9a84c
NLC.Theme.goldLight  = { r = 0.941, g = 0.816, b = 0.502 }  -- #f0d080
NLC.Theme.goldDim    = { r = 0.478, g = 0.361, b = 0.118 }  -- #7a5c1e
NLC.Theme.goldBright = { r = 0.941, g = 0.784, b = 0.400 }  -- #f0c866
NLC.Theme.surface    = { r = 0.039, g = 0.063, b = 0.118 }  -- ~#0a101e
NLC.Theme.surface2   = { r = 0.024, g = 0.043, b = 0.086 }  -- ~#060b16
NLC.Theme.muted      = { r = 0.722, g = 0.667, b = 0.596 }  -- #b8aa98
NLC.Theme.border     = { r = 0.15,  g = 0.13,  b = 0.10  }
NLC.Theme.red        = { r = 1.0,   g = 0.2,   b = 0.2   }
NLC.Theme.green      = { r = 0.2,   g = 0.8,   b = 0.2   }

-- Color string helpers for WoW text
NLC.Theme.GOLD       = "|cffc9a84c"
NLC.Theme.GOLD_LIGHT = "|cfff0d080"
NLC.Theme.GOLD_DIM   = "|cff7a5c1e"
NLC.Theme.MUTED      = "|cffb8aa98"
NLC.Theme.WHITE      = "|cffffffff"
NLC.Theme.RED        = "|cffff3333"
NLC.Theme.GREEN      = "|cff33cc33"
NLC.Theme.ORANGE     = "|cffff8800"

-- Apply dark themed backdrop to a frame
local BACKDROP_INFO = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  tile = true,
  tileSize = 32,
  edgeSize = 24,
  insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

function NLC.Theme.ApplyBackdrop(frame)
  if not frame.SetBackdrop then
    Mixin(frame, BackdropTemplateMixin)
  end
  frame:SetBackdrop(BACKDROP_INFO)
  frame:SetBackdropColor(0.04, 0.06, 0.12, 0.95)
  frame:SetBackdropBorderColor(0.48, 0.36, 0.12, 0.8)
end

-- Create a styled title bar
function NLC.Theme.CreateTitleBar(frame, titleText)
  local titleBg = frame:CreateTexture(nil, "ARTWORK")
  titleBg:SetPoint("TOPLEFT", 4, -4)
  titleBg:SetPoint("TOPRIGHT", -4, -4)
  titleBg:SetHeight(28)
  titleBg:SetColorTexture(0.48, 0.36, 0.12, 0.3)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  title:SetPoint("TOP", 0, -10)
  title:SetText(NLC.Theme.GOLD .. (titleText or "") .. "|r")
  frame.title = title

  -- Gold accent line under title
  local accent = frame:CreateTexture(nil, "ARTWORK")
  accent:SetPoint("TOPLEFT", 20, -32)
  accent:SetPoint("TOPRIGHT", -20, -32)
  accent:SetHeight(1)
  accent:SetColorTexture(0.788, 0.659, 0.298, 0.4)

  return title
end

-- Create a styled button (gold-ish)
function NLC.Theme.CreateButton(parent, width, height, text)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(width, height)
  btn:SetText(text)
  btn:SetNormalFontObject("GameFontNormal")
  return btn
end

-- Separator line
function NLC.Theme.CreateSeparator(parent, yOffset)
  local sep = parent:CreateTexture(nil, "ARTWORK")
  sep:SetPoint("TOPLEFT", 20, yOffset)
  sep:SetPoint("TOPRIGHT", -20, yOffset)
  sep:SetHeight(1)
  sep:SetColorTexture(0.788, 0.659, 0.298, 0.2)
  return sep
end
