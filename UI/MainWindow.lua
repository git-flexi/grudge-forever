local ADDON, ns = ...

-- Main window: one tab per list, one row per player (expandable to all entries of that player),
-- a filter and name search on top, actions at the bottom.
local Const, L, Names = ns.Const, ns.L, ns.Names

ns.UI = ns.UI or {}
local MainWindow = {}

local ROW_HEIGHT = 20
local TABS = {
  { list = Const.LIST_FRIENDLY, key = "MW_TAB_FRIENDLY" },
  { list = Const.LIST_ENEMY, key = "MW_TAB_ENEMY" },
}
local COLUMNS = {
  { key = "MW_COL_NAME", x = 8, width = 160 },
  { key = "MW_COL_REASON", x = 172, width = 230 },
  { key = "MW_COL_BY", x = 406, width = 140 },
  { key = "MW_COL_DATE", x = 550, width = 76 },
  { key = "MW_COL_STATUS", x = 630, width = 54 },
}
local OWN_COLOR = { 1, 0.82, 0 }
local OTHER_COLOR = { 1, 1, 1 }
local ENTRY_COLOR = { 0.75, 0.75, 0.75 }
local SEPARATOR = " \194\183 " -- middle dot

local frame
local buttons = {}
-- selKey: selected player; selOwner: owner of the selected entry row (nil = the player row)
local state = { tab = 1, filter = "all", search = "", expanded = {}, selKey = nil, selOwner = nil }
local current = {} -- key -> visible matches of the shown list

local function listKey()
  return TABS[state.tab].list
end

local function formatDate(ts)
  return type(ts) == "number" and date(L["DATE_FORMAT"], ts) or ""
end

-- Data --------------------------------------------------------------------------------

local function visible(matches)
  if state.filter ~= "mine" then return matches end
  local out = {}
  for _, m in ipairs(matches) do
    if m.isOwn then out[#out + 1] = m end
  end
  return out
end

-- Flat row list: a "player" row per player, followed by its "entry" rows when expanded.
local function buildItems()
  local needle = Names.Normalize(state.search)
  local players = {}
  current = {}
  for key, matches in pairs(ns.Core.store:ListAll(listKey())) do
    matches = visible(matches)
    if #matches > 0 and (not needle or key:find(needle, 1, true)) then
      current[key] = matches
      players[#players + 1] = key
    end
  end
  table.sort(players)

  local items = {}
  for _, key in ipairs(players) do
    local matches = current[key]
    items[#items + 1] = { kind = "player", key = key, matches = matches }
    if state.expanded[key] and #matches > 1 then
      for _, m in ipairs(matches) do items[#items + 1] = { kind = "entry", key = key, match = m } end
    end
  end
  return items
end

-- Selection ---------------------------------------------------------------------------

-- The selected match: a clicked entry row, or the only match of a selected player.
local function selectedMatch()
  local matches = state.selKey and current[state.selKey]
  if not matches then return nil end
  if state.selOwner then
    for _, m in ipairs(matches) do
      if m.ownerId == state.selOwner then return m end
    end
    return nil
  end
  return #matches == 1 and matches[1] or nil
end

-- The own and the first foreign match of the selected player.
local function selectedPlayer()
  local own, foreign
  for _, m in ipairs(state.selKey and current[state.selKey] or {}) do
    if m.isOwn then
      own = own or m
    else
      foreign = foreign or m
    end
  end
  return own, foreign
end

local function dropVanishedSelection()
  if state.selKey and not current[state.selKey] then state.selKey, state.selOwner = nil, nil end
  if state.selOwner and not selectedMatch() then state.selOwner = nil end
end

local function isSelected(item)
  if item.key ~= state.selKey then return false end
  if item.kind == "player" then return state.selOwner == nil end
  return item.match.ownerId == state.selOwner
end

-- Rows --------------------------------------------------------------------------------

-- Names and reasons may come from other players: every one is escaped before it is shown.
local Escape = Names.Escape

local function byText(match)
  local parts = {}
  if match.by and match.by ~= "" then parts[#parts + 1] = Escape(match.by) end
  local origin = match.entry.origin
  if origin and origin ~= "" then parts[#parts + 1] = L["TOOLTIP_ADOPTED_FROM"]:format(Escape(origin)) end
  return table.concat(parts, SEPARATOR)
end

local function playerCells(item)
  local matches = item.matches
  local first = matches[1]
  local name = Escape(first.entry.name)
  local reason = Escape(first.entry.reason)
  local by = byText(first)
  if #matches > 1 then
    name = (state.expanded[item.key] and "- " or "+ ") .. name
    reason = reason .. " " .. L["MW_MORE"]:format(#matches - 1)
  end
  local newest = 0
  for _, m in ipairs(matches) do newest = math.max(newest, m.entry.updated or 0) end
  local status = first.muted and L["TOOLTIP_MUTED"] or ""
  return { name, reason, by, formatDate(newest), status }, first.isOwn and OWN_COLOR or OTHER_COLOR
end

local function entryCells(item)
  local m = item.match
  local status = m.muted and L["TOOLTIP_MUTED"] or ""
  return { "", Escape(m.entry.reason), byText(m), formatDate(m.entry.updated), status }, ENTRY_COLOR
end

local function onRowClick(item)
  if item.kind == "player" then
    if #item.matches > 1 then state.expanded[item.key] = not state.expanded[item.key] end
    state.selKey, state.selOwner = item.key, nil
  else
    state.selKey, state.selOwner = item.key, item.match.ownerId
  end
  MainWindow.Refresh()
end

local function initRow(row, item)
  if not row.cells then
    row:SetHeight(ROW_HEIGHT)
    row.selection = row:CreateTexture(nil, "BACKGROUND")
    row.selection:SetAllPoints()
    row.selection:SetColorTexture(1, 0.82, 0, 0.2)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    row.cells = {}
    for i, col in ipairs(COLUMNS) do
      local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", col.x, 0)
      fs:SetWidth(col.width)
      fs:SetJustifyH("LEFT")
      fs:SetWordWrap(false)
      row.cells[i] = fs
    end
    row:SetScript("OnClick", function(self) onRowClick(self.item) end)
  end
  row.item = item
  local cells, color
  if item.kind == "player" then
    cells, color = playerCells(item)
  else
    cells, color = entryCells(item)
  end
  for i, fs in ipairs(row.cells) do
    fs:SetText(cells[i])
    fs:SetTextColor(color[1], color[2], color[3])
  end
  row.selection:SetShown(isSelected(item))
end

-- Buttons -----------------------------------------------------------------------------

local function updateSyncButton()
  local Core = ns.Core
  local sync = buttons.sync
  sync:SetShown(Core.sv.settings.syncMode ~= "off")
  local remaining = Core.sync:CooldownRemaining()
  if remaining > 0 then
    sync:SetText(L["MW_SYNC_WAIT"]:format(math.ceil(remaining)))
    sync:SetEnabled(false)
  else
    sync:SetText(L["MW_SYNC"])
    sync:SetEnabled(Core.HasSyncGuild())
  end
end

local function updateButtons()
  local own, foreign = selectedPlayer()
  local sel = selectedMatch()
  local foreignSel = sel and not sel.isOwn and sel or nil
  buttons.edit:SetEnabled(own ~= nil)
  buttons.delete:SetEnabled(own ~= nil)
  -- muting is per player and list; it is offered for players listed only by others
  local canMute = foreign ~= nil and own == nil
  buttons.mute:SetEnabled(canMute)
  buttons.mute:SetText(L[(canMute and foreign.muted) and "MENU_UNMUTE" or "MENU_MUTE"])
  buttons.adopt:SetEnabled(foreignSel ~= nil and own == nil)
  buttons.adoptAll:SetEnabled(foreignSel ~= nil)
  buttons.adoptAll:SetText(L["MW_ADOPT_ALL"]:format(foreignSel and Escape(foreignSel.by or "...") or "..."))
  updateSyncButton()
end

local function report(count)
  ns.Core.Print(L["MW_ADOPTED"]:format(count or 0))
end

local actions = {}

function actions.add()
  ns.UI.EditDialog.Open(nil, listKey(), nil)
end

function actions.edit()
  local own = selectedPlayer()
  if own then ns.UI.EditDialog.Open(own.entry.name, own.entry.list, own.entry) end
end

function actions.delete()
  local own = selectedPlayer()
  if not own then return end
  local data = { list = own.entry.list, name = own.entry.name }
  StaticPopup_Show("GRUDGEFOREVER_DELETE", Escape(own.entry.name), nil, data)
end

function actions.mute()
  local _, foreign = selectedPlayer()
  if not foreign then return end
  ns.Core.store:SetMuted(foreign.entry.list, foreign.entry.name, not foreign.muted)
  MainWindow.Refresh()
end

function actions.adopt()
  local sel = selectedMatch()
  if not sel or sel.isOwn then return end
  local id = ns.Store.EntryId(sel.entry.list, sel.entry.key)
  report(ns.Core.Change(function(store) return store:Adopt(sel.ownerId, id) end))
end

function actions.adoptAll()
  local sel = selectedMatch()
  if not sel or sel.isOwn then return end
  report(ns.Core.Change(function(store) return store:Adopt(sel.ownerId) end))
end

-- Frame -------------------------------------------------------------------------------

local function selectTab(index)
  state.tab = index
  state.selKey, state.selOwner = nil, nil
  PanelTemplates_SetTab(frame, index)
  MainWindow.Refresh()
end

local function button(text, width, onClick)
  local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- Lays buttons out left to right from the first one's anchor.
local function row(list)
  for i = 2, #list do list[i]:SetPoint("LEFT", list[i - 1], "RIGHT", 4, 0) end
end

local function createControls()
  local filter = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
  filter:SetPoint("TOPLEFT", 12, -30)
  filter:SetWidth(140)
  filter:SetupMenu(function(_, root)
    for _, option in ipairs({ { "MW_FILTER_ALL", "all" }, { "MW_FILTER_MINE", "mine" } }) do
      root:CreateRadio(L[option[1]], function(value) return state.filter == value end, function(value)
        state.filter = value
        MainWindow.Refresh()
      end, option[2])
    end
  end)

  local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
  search:SetPoint("LEFT", filter, "RIGHT", 16, 0)
  search:SetSize(180, 20)
  search:SetAutoFocus(false)
  search:HookScript("OnTextChanged", function(self)
    state.search = self:GetText() or ""
    MainWindow.Refresh()
  end)

  buttons.sync = button(L["MW_SYNC"], 160, function() ns.Core.ManualSync() end)
  buttons.sync:SetPoint("TOPRIGHT", -12, -30)
  buttons.import = button(L["MW_IMPORT"], 80, function() ns.UI.TextDialog.Open("import") end)
  buttons.import:SetPoint("RIGHT", buttons.sync, "LEFT", -4, 0)
  buttons.export = button(L["MW_EXPORT"], 80, function() ns.UI.TextDialog.Open("export") end)
  buttons.export:SetPoint("RIGHT", buttons.import, "LEFT", -4, 0)

  buttons.add = button(L["MW_ADD"], 96, actions.add)
  buttons.add:SetPoint("BOTTOMLEFT", 8, 6)
  buttons.edit = button(L["MW_EDIT"], 96, actions.edit)
  buttons.delete = button(L["MW_DELETE"], 96, actions.delete)
  buttons.mute = button(L["MENU_MUTE"], 110, actions.mute)
  buttons.adopt = button(L["MW_ADOPT"], 96, actions.adopt)
  buttons.adoptAll = button(L["MW_ADOPT_ALL"]:format("..."), 200, actions.adoptAll)
  row({ buttons.add, buttons.edit, buttons.delete, buttons.mute, buttons.adopt, buttons.adoptAll })
end

local function createList()
  local inset = frame.Inset
  inset:ClearAllPoints()
  inset:SetPoint("TOPLEFT", 4, -60)
  inset:SetPoint("BOTTOMRIGHT", -6, 32)

  for _, col in ipairs(COLUMNS) do
    local header = inset:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", col.x + 4, -6)
    header:SetText(L[col.key])
  end

  local scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 4, -22)
  scrollBox:SetPoint("BOTTOMRIGHT", -22, 4)
  local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("Button", initRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
  frame.scrollBox = scrollBox
end

local function createTabs()
  for i, tab in ipairs(TABS) do
    local b = CreateFrame("Button", "GrudgeForeverMainWindowTab" .. i, frame, "PanelTabButtonTemplate")
    b:SetID(i)
    b:SetText(L[tab.key])
    b:SetScript("OnClick", function(self) selectTab(self:GetID()) end)
    if i == 1 then b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2) end
  end
  PanelTemplates_SetNumTabs(frame, #TABS)
end

local function create()
  frame = CreateFrame("Frame", "GrudgeForeverMainWindow", UIParent, "ButtonFrameTemplate")
  ButtonFrameTemplate_HidePortrait(frame)
  frame:SetTitle(L["ADDON_TITLE"])
  frame:SetSize(720, 480)
  frame:SetPoint("CENTER")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()
  table.insert(UISpecialFrames, "GrudgeForeverMainWindow")

  createControls()
  createList()
  createTabs()

  StaticPopupDialogs.GRUDGEFOREVER_DELETE = {
    text = L["MW_DELETE_CONFIRM"], button1 = L["MW_DELETE"], button2 = L["BTN_CANCEL"],
    OnAccept = function(_, data)
      ns.Core.Change(function(store) store:Delete(data.list, data.name) end)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
  }

  -- the sync cooldown counts down while the window is open
  local elapsed = 0
  frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 1 then return end
    elapsed = 0
    updateSyncButton()
  end)
  frame:SetScript("OnShow", function() MainWindow.Refresh() end)

  state.tab = 1
  PanelTemplates_SetTab(frame, 1)
end

-- Public --------------------------------------------------------------------------------

function MainWindow.Refresh()
  if not frame or not frame:IsShown() then return end
  local items = buildItems()
  dropVanishedSelection()
  frame.scrollBox:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
  updateButtons()
end

function MainWindow.Toggle()
  if not (ns.Core and ns.Core.ready) then return end
  if not frame then create() end
  -- showing refreshes through OnShow
  frame:SetShown(not frame:IsShown())
end

ns.UI.MainWindow = MainWindow
