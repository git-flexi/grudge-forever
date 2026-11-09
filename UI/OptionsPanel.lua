local ADDON, ns = ...

local Const, L = ns.Const, ns.L

local OptionsPanel = {}

local category
local panelBuilt = false

local LABEL_X, CONTROL_X, ROW_HEIGHT = 16, 220, 30
local ICON_ORDER = { "skull", "cross", "exclamation" }

-- Widget helpers -----------------------------------------------------------

local function label(parent, text, x, y, font)
  local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function checkbox(parent, text, y, get, set, refreshers)
  local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", LABEL_X - 4, y + 4)
  check:SetSize(26, 26)
  label(parent, text, LABEL_X + 28, y - 3)
  check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  refreshers[#refreshers + 1] = function() check:SetChecked(get() and true or false) end
  return check
end

local function button(parent, text, x, y, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetPoint("TOPLEFT", x, y)
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- Single-line input; commit(text) runs on Enter or when the focus is lost.
local function editBox(parent, x, y, width, commit, current, refreshers)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetPoint("TOPLEFT", x + 6, y)
  box:SetSize(width, 22)
  box:SetAutoFocus(false)
  box:SetMaxLetters(200)
  local function refresh() box:SetText(current() or "") end
  box:SetScript("OnEnterPressed", function(self)
    commit(self:GetText())
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusLost", function(self)
    commit(self:GetText())
    refresh()
  end)
  box:SetScript("OnEscapePressed", function(self)
    refresh()
    self:ClearFocus()
  end)
  refreshers[#refreshers + 1] = refresh
  return box
end

-- Radio dropdown; entries = list of { text, value }, or a function returning one.
local function dropdown(parent, x, y, width, entries, get, set, refreshers)
  local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dd:SetPoint("TOPLEFT", x, y + 2)
  dd:SetWidth(width)
  dd:SetupMenu(function(_, root)
    local list = type(entries) == "function" and entries() or entries
    if root.SetScrollMode then root:SetScrollMode(300) end
    for _, entry in ipairs(list) do
      root:CreateRadio(entry[1], function(value) return get() == value end,
        function(value) set(value) end, entry[2])
    end
  end)
  refreshers[#refreshers + 1] = function() dd:GenerateMenu() end
  return dd
end

-- Plain horizontal slider with a value label, built from basic frames.
local function slider(parent, x, y, width, minValue, maxValue, step, get, set, refreshers)
  local s = CreateFrame("Slider", nil, parent)
  s:SetPoint("TOPLEFT", x, y - 4)
  s:SetSize(width, 16)
  s:SetOrientation("HORIZONTAL")
  s:SetMinMaxValues(minValue, maxValue)
  s:SetValueStep(step)
  s:SetObeyStepOnDrag(true)
  s:EnableMouse(true)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(4)
  track:SetColorTexture(0.4, 0.4, 0.4, 0.8)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  value:SetPoint("LEFT", s, "RIGHT", 12, 0)

  local refreshing = false
  s:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v + 0.5)
    value:SetText(string.format(L["OPT_SECONDS"], v))
    if not refreshing then set(v) end
  end)
  refreshers[#refreshers + 1] = function()
    refreshing = true
    s:SetValue(get())
    value:SetText(string.format(L["OPT_SECONDS"], get()))
    refreshing = false
  end
  return s
end

-- Panel --------------------------------------------------------------------

local function soundEntries()
  local entries = {
    { L["OPT_SOUND_NONE"], "none" },
    { L["OPT_SOUND_RAIDWARNING"], "raidwarning" },
    { L["OPT_SOUND_MAPPING"], "mapping" },
  }
  local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
  if lsm then
    for _, name in ipairs(lsm:List("sound")) do entries[#entries + 1] = { name, name } end
  end
  return entries
end

local function iconEntries()
  local entries = {}
  for _, key in ipairs(ICON_ORDER) do entries[#entries + 1] = { L["OPT_ICON_" .. key:upper()], key } end
  return entries
end

local function buildList(content, y, listKey, settings, callbacks, refreshers)
  local s = settings.lists[listKey]
  local defaults = ns.Options.Defaults().lists[listKey]

  label(content, L["LIST_" .. listKey:upper()], LABEL_X, y, "GameFontNormalLarge")
  y = y - 32

  checkbox(content, L["OPT_ENABLED"], y, function() return s.enabled end,
    function(v) s.enabled = v end, refreshers)
  y = y - ROW_HEIGHT

  label(content, L["OPT_SOUND"], LABEL_X, y - 3)
  dropdown(content, CONTROL_X, y, 200, soundEntries, function() return s.sound end,
    function(v) s.sound = v end, refreshers)
  button(content, L["OPT_TEST"], CONTROL_X + 210, y, 110, function()
    if callbacks.testAlert then callbacks.testAlert(listKey) end
  end)
  y = y - ROW_HEIGHT

  label(content, L["OPT_ICON"], LABEL_X, y - 3)
  local iconDropdown = dropdown(content, CONTROL_X, y, 200, iconEntries, function() return s.icon end,
    function(v) s.icon = v end, refreshers)
  y = y - ROW_HEIGHT

  label(content, L["OPT_ICON_CUSTOM"], LABEL_X, y - 3)
  editBox(content, CONTROL_X, y, 380, function(text)
    if text ~= "" then
      s.icon = text
    elseif not ns.Alerts.ICONS[s.icon] then
      s.icon = defaults.icon -- clearing a custom path falls back to the default icon
    end
    iconDropdown:GenerateMenu()
  end, function() return not ns.Alerts.ICONS[s.icon] and s.icon or "" end, refreshers)
  y = y - ROW_HEIGHT

  label(content, L["OPT_TEXT"], LABEL_X, y - 3)
  editBox(content, CONTROL_X, y, 380, function(text)
    s.text = text ~= "" and text or defaults.text
  end, function() return s.text end, refreshers)
  y = y - 24
  label(content, L["OPT_TEXT_HINT"], CONTROL_X + 6, y, "GameFontDisableSmall")
  y = y - 22

  checkbox(content, L["OPT_BANNER"], y, function() return s.banner end,
    function(v) s.banner = v end, refreshers)
  y = y - ROW_HEIGHT
  checkbox(content, L["OPT_CHAT"], y, function() return s.chat end,
    function(v) s.chat = v end, refreshers)
  y = y - ROW_HEIGHT

  label(content, L["OPT_COOLDOWN"], LABEL_X, y - 3)
  slider(content, CONTROL_X + 6, y, 300, ns.Options.COOLDOWN_MIN, ns.Options.COOLDOWN_MAX, 10,
    function() return s.cooldown end, function(v) s.cooldown = v end, refreshers)
  return y - ROW_HEIGHT - 16
end

local function build(settings, callbacks)
  local panel = CreateFrame("Frame")
  panel.name = L["ADDON_TITLE"]

  local scroll = CreateFrame("ScrollFrame", nil, panel)
  scroll:SetPoint("TOPLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", -8, 8)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(660, 10)
  scroll:SetScrollChild(content)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 40)))
  end)

  local refreshers = {}
  local y = -8

  label(content, L["OPT_GLOBAL"], LABEL_X, y, "GameFontNormalLarge")
  y = y - 32

  label(content, L["OPT_SYNC_MODE"], LABEL_X, y - 3)
  dropdown(content, CONTROL_X, y, 200, {
    { L["OPT_SYNC_AUTO"], "auto" }, { L["OPT_SYNC_MANUAL"], "manual" }, { L["OPT_SYNC_OFF"], "off" },
  }, function() return settings.syncMode end, function(v)
    if settings.syncMode == v then return end
    settings.syncMode = v
    if callbacks.syncModeChanged then callbacks.syncModeChanged(v) end
  end, refreshers)
  y = y - ROW_HEIGHT

  local unlock = checkbox(content, L["OPT_BANNER_UNLOCK"], y, function() return false end, function(v)
    if callbacks.bannerLock then callbacks.bannerLock(not v) end
  end, refreshers)
  button(content, L["OPT_BANNER_RESET"], CONTROL_X + 40, y, 140, function()
    if callbacks.bannerReset then callbacks.bannerReset() end
  end)
  y = y - ROW_HEIGHT

  checkbox(content, L["OPT_MINIMAP"], y, function() return not settings.minimap.hide end, function(v)
    if callbacks.minimapShown then callbacks.minimapShown(v) end
  end, refreshers)
  y = y - ROW_HEIGHT

  checkbox(content, L["OPT_DEBUG"], y, function() return settings.debug end,
    function(v) settings.debug = v end, refreshers)
  y = y - ROW_HEIGHT - 16

  for _, listKey in ipairs({ Const.LIST_FRIENDLY, Const.LIST_ENEMY }) do
    y = buildList(content, y, listKey, settings, callbacks, refreshers)
  end
  content:SetHeight(-y)

  panel:SetScript("OnShow", function()
    for _, refresh in ipairs(refreshers) do refresh() end
  end)
  panel:SetScript("OnHide", function()
    -- leaving the panel locks the banner again so it cannot be dragged by accident
    if unlock:GetChecked() then
      unlock:SetChecked(false)
      if callbacks.bannerLock then callbacks.bannerLock(true) end
    end
  end)
  return panel
end

-- settingsTable is the live saved settings; controls write straight into it.
-- callbacks = { testAlert = fn(list), bannerLock = fn(bool), bannerReset = fn(), syncModeChanged = fn(mode),
--   minimapShown = fn(bool) }
function OptionsPanel.Register(settingsTable, callbacks)
  if not Settings or not Settings.RegisterCanvasLayoutCategory then return nil end
  if panelBuilt then return category end
  panelBuilt = true
  local panel = build(settingsTable, callbacks or {})
  category = Settings.RegisterCanvasLayoutCategory(panel, L["ADDON_TITLE"])
  Settings.RegisterAddOnCategory(category)
  return category
end

function OptionsPanel.Open()
  if category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(category:GetID())
  end
end

ns.OptionsPanel = OptionsPanel
