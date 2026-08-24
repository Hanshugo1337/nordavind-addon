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
NLC.Theme.BLUE       = "|cff00ccff"

-- Farger om en itemlenke uten aa oedelegge den.
--
-- Lenken baerer sin egen farge, og den vinner over alt vi pakker rundt. Spillet
-- gir oss enten |cffRRGGBB eller det nyere |cnIQ4:, saa vi kan ikke bytte ut ett
-- fast moenster — vi kutter alt foran |H og setter vaar egen kode der. Halen
-- (|h[Navn]|h|r) staar urort, saa lenken virker som foer.
function NLC.Theme.Recolor(link, color)
  if not link then return nil end
  local rest = link:match("(|H.*)$")
  if not rest then return link end
  return color .. rest
end

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

-- ============================================================
-- Shared widgets for the loot distribution flow (Leveranse B)
-- ============================================================

-- Item-icon button with tooltip. Call :SetItem(link) to populate.
function NLC.Theme.CreateItemIcon(parent, size)
  size = size or 28
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(size, size)
  btn.tex = btn:CreateTexture(nil, "ARTWORK")
  btn.tex:SetAllPoints()
  btn.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the default icon border
  local border = btn:CreateTexture(nil, "BACKGROUND")
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(0.788, 0.659, 0.298, 0.5)
  function btn:SetItem(itemLink)
    self.itemLink = itemLink
    local icon = itemLink and select(5, C_Item.GetItemInfoInstant(itemLink))
    self.tex:SetTexture(icon or 134400) -- 134400 = default "?" icon
  end
  btn:SetScript("OnEnter", function(self)
    if not self.itemLink then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.itemLink)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return btn
end

-- Small countdown badge. Call :SetSeconds(sec). Green >30m, orange >10m, red otherwise.
function NLC.Theme.CreateTimerBadge(parent)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  function fs:SetSeconds(sec)
    if not sec or sec <= 0 then
      self:SetText(NLC.Theme.MUTED .. "—|r")
      return
    end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local label = (h > 0) and (h .. "t " .. m .. "m") or (m .. "m")
    local color = (sec > 1800) and NLC.Theme.GREEN
      or (sec > 600) and NLC.Theme.ORANGE
      or NLC.Theme.RED
    self:SetText(color .. label .. "|r")
  end
  return fs
end

-- Debounce helper shared by the live-refresh windows: cancels the previous timer with the
-- same key and reschedules fn after delay.
local _debounceTimers = {}
function NLC.Theme.Debounce(key, delay, fn)
  local t = _debounceTimers[key]
  if t then t:Cancel() end
  _debounceTimers[key] = C_Timer.NewTimer(delay, function()
    _debounceTimers[key] = nil
    fn()
  end)
end

-- Reliable custom dropdown menu built from plain frames — no MenuUtil/UIDropDownMenu (those
-- proved unreliable in-game). items = array of { text, func, color, title=bool, divider=bool }.
local _menu, _menuCloser
function NLC.Theme.ShowMenu(anchor, items)
  if not _menu then
    _menuCloser = CreateFrame("Button", nil, UIParent)
    _menuCloser:SetAllPoints(UIParent)
    _menuCloser:SetFrameStrata("FULLSCREEN_DIALOG")
    _menuCloser:SetFrameLevel(1)
    _menuCloser:RegisterForClicks("AnyUp")
    _menuCloser:Hide()

    _menu = CreateFrame("Frame", "NordavindLCMenu", UIParent, "BackdropTemplate")
    _menu:SetFrameStrata("FULLSCREEN_DIALOG")
    _menu:SetFrameLevel(20)
    _menu:EnableMouse(true) -- eat clicks on the menu body so padding-clicks don't close it
    NLC.Theme.ApplyBackdrop(_menu)
    _menu.rows = {}
    _menu:Hide()

    local function closeMenu() _menu:Hide(); _menuCloser:Hide() end
    _menuCloser:SetScript("OnClick", closeMenu)
    _menu.Close = closeMenu
  end

  for _, r in ipairs(_menu.rows) do r:Hide() end

  local WIDTH, ITEM_H, PAD = 172, 22, 6
  local y = -PAD
  for i, item in ipairs(items) do
    local row = _menu.rows[i]
    if not row then
      row = CreateFrame("Button", nil, _menu)
      row:SetPoint("TOPLEFT", 4, 0) -- y set per-show below
      row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      row.text:SetPoint("LEFT", 10, 0)
      row.text:SetJustifyH("LEFT")
      row.hl = row:CreateTexture(nil, "BACKGROUND")
      row.hl:SetAllPoints()
      row.hl:SetColorTexture(0.788, 0.659, 0.298, 0.15)
      row.hl:Hide()
      row.line = row:CreateTexture(nil, "ARTWORK")
      row.line:SetHeight(1)
      row.line:SetPoint("LEFT", 8, 0)
      row.line:SetPoint("RIGHT", -8, 0)
      row.line:SetColorTexture(0.788, 0.659, 0.298, 0.25)
      row.line:Hide()
      row:SetScript("OnEnter", function(self) if self._clickable then self.hl:Show() end end)
      row:SetScript("OnLeave", function(self) self.hl:Hide() end)
      _menu.rows[i] = row
    end
    row:SetWidth(WIDTH - 8)
    row:SetFrameLevel(_menu:GetFrameLevel() + 1)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 4, y)
    row.hl:Hide()
    row.line:Hide()

    if item.divider then
      row.text:SetText("")
      row._clickable = false
      row:EnableMouse(false)
      row:SetScript("OnClick", nil)
      row:SetHeight(7)
      row.line:Show()
      y = y - 7
    elseif item.title then
      row.text:SetText(NLC.Theme.GOLD .. (item.text or "") .. "|r")
      row._clickable = false
      row:EnableMouse(false)
      row:SetScript("OnClick", nil)
      row:SetHeight(ITEM_H)
      y = y - ITEM_H
    else
      row.text:SetText((item.color or NLC.Theme.WHITE) .. (item.text or "") .. "|r")
      row._clickable = true
      row:EnableMouse(true)
      row:SetScript("OnClick", function()
        _menu.Close()
        if item.func then item.func() end
      end)
      row:SetHeight(ITEM_H)
      y = y - ITEM_H
    end
    row:Show()
  end

  _menu:SetSize(WIDTH, -y + PAD)
  _menu:ClearAllPoints()
  _menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  _menuCloser:Show()
  _menu:Show()
end
