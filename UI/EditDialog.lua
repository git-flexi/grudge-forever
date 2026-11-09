local ADDON, ns = ...

-- Small dialog to add or edit an own entry: name, list, reason.
local Const, L, Names = ns.Const, ns.L, ns.Names

ns.UI = ns.UI or {}
local EditDialog = {}

local LIST_OPTIONS = { { "LIST_FRIENDLY", Const.LIST_FRIENDLY }, { "LIST_ENEMY", Const.LIST_ENEMY } }
local ERROR_KEYS = {
  invalid_list = "ERR_INVALID_LIST", invalid_name = "ERR_INVALID_NAME", reason_too_long = "ERR_REASON_TOO_LONG",
}
local LABEL_X, FIELD_X = 20, 90

local frame
local state = { list = Const.LIST_FRIENDLY, editing = nil }

local function save()
  local editing, list = state.editing, state.list
  local name = editing and editing.name or frame.name:GetText()
  local reason = frame.reason:GetText()
  local entry, err = ns.Core.Change(function(store)
    local e, why = store:AddOrUpdate(list, name, reason)
    -- moving an entry to the other list replaces the old one
    if e and editing and editing.list ~= list then store:Delete(editing.list, editing.name) end
    return e, why
  end)
  if not entry then
    frame.error:SetText(L[ERROR_KEYS[err] or err])
    return
  end
  frame:Hide()
end

local function ensureDeletePopup()
  if StaticPopupDialogs.GRUDGEFOREVER_DELETE then return end
  StaticPopupDialogs.GRUDGEFOREVER_DELETE = {
    text = L["MW_DELETE_CONFIRM"], button1 = L["MW_DELETE"], button2 = L["BTN_CANCEL"],
    OnAccept = function(_, data)
      ns.Core.Change(function(store) store:Delete(data.list, data.name) end)
      local editing = state.editing
      if frame and editing and editing.list == data.list and editing.name == data.name then frame:Hide() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
  }
end

-- Asks before deleting an own entry; closes the dialog if it shows that entry.
function EditDialog.ConfirmDelete(list, name)
  ensureDeletePopup()
  StaticPopup_Show("GRUDGEFOREVER_DELETE", Names.Escape(name), nil, { list = list, name = name })
end

local function label(text, y)
  local fs = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", LABEL_X, y)
  fs:SetText(text)
  return fs
end

local function input(y, maxLetters)
  local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  box:SetPoint("TOPLEFT", FIELD_X + 6, y + 4)
  box:SetSize(260, 22)
  box:SetAutoFocus(false)
  box:SetMaxLetters(maxLetters)
  box:SetScript("OnEnterPressed", save)
  box:SetScript("OnEscapePressed", function() frame:Hide() end)
  return box
end

local function button(text, x, onClick)
  local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  b:SetPoint("BOTTOMRIGHT", x, 6)
  b:SetSize(96, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function create()
  frame = CreateFrame("Frame", "GrudgeForeverEditDialog", UIParent, "ButtonFrameTemplate")
  ButtonFrameTemplate_HidePortrait(frame)
  frame:SetSize(390, 190)
  frame:SetPoint("CENTER", 0, 80)
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame.Inset:ClearAllPoints()
  frame.Inset:SetPoint("TOPLEFT", 4, -24)
  frame.Inset:SetPoint("BOTTOMRIGHT", -6, 32)
  table.insert(UISpecialFrames, "GrudgeForeverEditDialog")

  label(L["EDIT_NAME"], -40)
  frame.name = input(-40, 60)
  frame.name:SetScript("OnTabPressed", function() frame.reason:SetFocus() end)

  label(L["EDIT_LIST"], -72)
  local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
  dropdown:SetPoint("TOPLEFT", FIELD_X, -66)
  dropdown:SetWidth(180)
  dropdown:SetupMenu(function(_, root)
    for _, option in ipairs(LIST_OPTIONS) do
      root:CreateRadio(L[option[1]], function(value) return state.list == value end,
        function(value) state.list = value end, option[2])
    end
  end)
  frame.list = dropdown

  label(L["EDIT_REASON"], -104)
  frame.reason = input(-104, Const.REASON_MAX)
  frame.reason:SetScript("OnTabPressed", function()
    if frame.name:IsEnabled() then frame.name:SetFocus() end
  end)

  frame.error = frame:CreateFontString(nil, "ARTWORK", "GameFontRed")
  frame.error:SetPoint("TOPLEFT", LABEL_X, -132)
  frame.error:SetPoint("RIGHT", -20, 0)
  frame.error:SetJustifyH("LEFT")

  button(L["BTN_CANCEL"], -8, function() frame:Hide() end)
  button(L["BTN_SAVE"], -108, save)
  frame.delete = button(L["MW_DELETE"], 0, function()
    local editing = state.editing
    if editing then EditDialog.ConfirmDelete(editing.list, editing.name) end
  end)
  frame.delete:ClearAllPoints()
  frame.delete:SetPoint("BOTTOMLEFT", 8, 6)
end

-- name: prefilled name (fixed when editing); list: preselected list (default friendly);
-- entry: an own entry to edit; reason: prefilled reason for a new entry;
-- fixed: the list cannot be changed (a player of the own faction belongs on the Blacklist).
function EditDialog.Open(name, list, entry, reason, fixed)
  if not (ns.Core and ns.Core.ready) then return end
  if not frame then create() end
  if not entry and name and list then
    local own = ns.Core.store:GetOwnEntry(list, name)
    if own and not own.deleted then entry = own end
  end

  state.editing = entry and { name = entry.name, list = entry.list } or nil
  state.list = entry and entry.list or (ns.Store.IsList(list) and list) or Const.LIST_FRIENDLY

  frame:SetTitle(L[entry and "EDIT_TITLE_EDIT" or "EDIT_TITLE_ADD"])
  frame.name:SetText(entry and entry.name or Names.Display(name) or "")
  frame.name:SetEnabled(entry == nil)
  frame.reason:SetText(entry and entry.reason or reason or "")
  frame.error:SetText("")
  frame.delete:SetShown(entry ~= nil)
  frame.list:SetEnabled(not fixed)
  frame.list:GenerateMenu()
  frame:Show()
  if entry or name then frame.reason:SetFocus() else frame.name:SetFocus() end
end

ns.UI.EditDialog = EditDialog
