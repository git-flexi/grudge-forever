local ADDON, ns = ...

-- Shared "dark journal" look: window chrome, panels, tabs and list rows.
local Skin = {}

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CREST = "Interface\\AddOns\\GrudgeForever\\Media\\icon"
local TITLE_HEIGHT = 34
local TAB_PADDING = 28
local TAB_GAP = 2

local HEXES = {
  bgTop = "1b1712", bgBottom = "120f0b", titleTop = "2b2318", titleBottom = "1b1610",
  line = "5c4a2a", divider = "3a3020", gold = "f0c45a", text = "e8dcc2",
  muted = "8a7a5c", by = "8fb7e0", alert = "ff6a4a",
}

Skin.COLORS = {}
Skin.HEX = {}
for name, hex in pairs(HEXES) do
  Skin.COLORS[name] = {
    r = tonumber(hex:sub(1, 2), 16) / 255,
    g = tonumber(hex:sub(3, 4), 16) / 255,
    b = tonumber(hex:sub(5, 6), 16) / 255,
  }
  Skin.HEX[name] = "ff" .. hex
end
local C = Skin.COLORS

local function rgba(color, a) return { r = color.r, g = color.g, b = color.b, a = a or 1 } end
Skin.RGBA = rgba

-- Vertical (top to bottom) or horizontal (left to right) gradient from `from` to `to` ({ r, g, b, a }).
-- Flat `from` when unsupported.
-- Needs the 10.0+ SetGradient(orientation, colorA, colorB) signature, which the Forever client has.
function Skin.Gradient(texture, orientation, from, to)
  if _G.CreateColor and texture.SetGradient then
    texture:SetColorTexture(1, 1, 1, 1)
    local a, b = from, to
    if orientation == "VERTICAL" then a, b = to, from end -- SetGradient puts its first color at the bottom
    texture:SetGradient(orientation, CreateColor(a.r, a.g, a.b, a.a), CreateColor(b.r, b.g, b.b, b.a))
  else
    texture:SetColorTexture(from.r, from.g, from.b, from.a)
  end
end

function Skin.Font(name)
  if _G[name] then return name end
  return "GameFontNormal"
end

local function setBorder(frame, edge, bgAlpha)
  frame:SetBackdrop({ bgFile = bgAlpha and WHITE or nil, edgeFile = WHITE, edgeSize = 1 })
  if bgAlpha then frame:SetBackdropColor(0, 0, 0, bgAlpha) end
  frame:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
end

-- Styles a BackdropTemplate frame; returns the content frame below the title bar.
function Skin.Window(frame, title)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  Skin.Gradient(bg, "VERTICAL", rgba(C.bgTop), rgba(C.bgBottom))

  setBorder(frame, C.line)
  local outer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  outer:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
  outer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
  outer:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
  outer:SetBackdropBorderColor(0, 0, 0, 1)

  local bar = frame:CreateTexture(nil, "ARTWORK")
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  bar:SetHeight(TITLE_HEIGHT)
  Skin.Gradient(bar, "VERTICAL", rgba(C.titleTop), rgba(C.titleBottom))

  local rule = frame:CreateTexture(nil, "BORDER")
  rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -TITLE_HEIGHT - 1)
  rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -TITLE_HEIGHT - 1)
  rule:SetHeight(1)
  rule:SetColorTexture(C.line.r, C.line.g, C.line.b, 1)

  local crest = frame:CreateTexture(nil, "OVERLAY")
  crest:SetTexture(CREST)
  crest:SetSize(26, 26)
  crest:SetPoint("LEFT", bar, "LEFT", 8, 0)

  local text = frame:CreateFontString(nil, "OVERLAY", Skin.Font("GameFontNormalLarge"))
  text:SetPoint("LEFT", crest, "RIGHT", 6, 0)
  text:SetTextColor(C.gold.r, C.gold.g, C.gold.b, 1)
  text:SetText(title)
  frame.TitleText = text

  local ok, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
  if not ok or not close then
    close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(22, 22)
    close:SetText("X")
  end
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() frame:Hide() end)
  frame.CloseButton = close

  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -TITLE_HEIGHT)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  frame.content = content
  return content
end

-- Darker inset panel with a divider-colored border.
function Skin.Panel(parent)
  local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  panel:SetFrameLevel(parent:GetFrameLevel()) -- keeps the parent's text above the panel's backdrop
  setBorder(panel, C.divider, 0.35)
  return panel
end

local Tabs = {}
Tabs.__index = Tabs

local function paint(self, i)
  local button = self.buttons[i]
  local fs = button.label
  if not button:IsEnabled() then
    fs:SetTextColor(C.muted.r, C.muted.g, C.muted.b, 0.5)
  elseif i == self.active then
    fs:SetTextColor(C.gold.r, C.gold.g, C.gold.b, 1)
  else
    fs:SetTextColor(C.muted.r, C.muted.g, C.muted.b, 1)
  end
  button.underline:SetShown(i == self.active)
end

local function fit(button)
  local width = button.label:GetStringWidth()
  if type(width) ~= "number" then width = 0 end
  button:SetWidth(width + TAB_PADDING)
end

function Tabs:SetTab(i)
  self.active = i
  for n = 1, #self.buttons do paint(self, n) end
end

function Tabs:EnableTab(i)
  self.buttons[i]:SetEnabled(true)
  paint(self, i)
end

function Tabs:DisableTab(i)
  self.buttons[i]:SetEnabled(false)
  paint(self, i)
end

function Tabs:SetTabText(i, text)
  local button = self.buttons[i]
  button:SetText(text)
  fit(button)
end

function Tabs:GetTab(i) return self.buttons[i] end

function Skin.Tabs(parent, namePrefix, labels, onSelect)
  local self = setmetatable({ buttons = {}, active = nil }, Tabs)
  for i, label in ipairs(labels) do
    local button = CreateFrame("Button", namePrefix .. i, parent)
    button:SetHeight(24)
    local fs = button:CreateFontString(nil, "OVERLAY", Skin.Font("GameFontNormal"))
    fs:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetFontString(fs)
    button.label = fs
    local wash = button:CreateTexture(nil, "HIGHLIGHT")
    wash:SetAllPoints(button)
    wash:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 0.12)
    button:SetText(label)
    fit(button)
    if i == 1 then
      button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    else
      button:SetPoint("LEFT", self.buttons[i - 1], "RIGHT", TAB_GAP, 0)
    end
    local underline = button:CreateTexture(nil, "OVERLAY")
    underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    underline:SetHeight(2)
    underline:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 1)
    underline:Hide()
    button.underline = underline
    button:SetScript("OnClick", function()
      if button:IsEnabled() then onSelect(i) end
    end)
    self.buttons[i] = button
    paint(self, i)
  end
  return self
end

-- Adds the zebra, selection and hover textures to a list row (once).
function Skin.Row(row)
  if row.zebra then return end
  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetAllPoints(row)
  zebra:SetColorTexture(1, 1, 1, 0.03)
  zebra:Hide()
  row.zebra = zebra

  local selection = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  selection:SetAllPoints(row)
  Skin.Gradient(selection, "HORIZONTAL", rgba(C.gold, 0.18), rgba(C.gold, 0))
  selection:Hide()
  row.selection = selection

  local edge = row:CreateTexture(nil, "ARTWORK")
  edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  edge:SetWidth(2)
  edge:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 1)
  edge:Hide()
  row.selectionEdge = edge

  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  Skin.Gradient(highlight, "HORIZONTAL", rgba(C.gold, 0.10), rgba(C.gold, 0.02))
  row.highlight = highlight
end

function Skin.SetRowState(row, index, selected)
  row.zebra:SetShown(index % 2 == 1)
  row.selection:SetShown(selected and true or false)
  row.selectionEdge:SetShown(selected and true or false)
end

ns.Skin = Skin
