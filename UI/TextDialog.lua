local ADDON, ns = ...

-- Copy/paste window for export ("export": read-only, text selected) and import ("import").
local L = ns.L

ns.UI = ns.UI or {}
local TextDialog = {}

local frame
local mode
local exportText = ""

local function runImport()
  local text = frame.box:GetInputText()
  local added, updated = ns.Core.Change(function(store) return ns.ExportImport.Import(store, text) end)
  if not added then
    -- updated holds the error key ("format" / "version")
    ns.Core.Print(L["IMPORT_ERR_" .. tostring(updated):upper()])
    return
  end
  ns.Core.Print(L["IMPORT_DONE"]:format(added, updated))
  frame:Hide()
end

local function selectAll()
  local editBox = frame.box:GetEditBox()
  editBox:SetFocus()
  editBox:HighlightText()
end

local function create()
  frame = CreateFrame("Frame", "GrudgeForeverTextDialog", UIParent, "ButtonFrameTemplate")
  ButtonFrameTemplate_HidePortrait(frame)
  frame:SetSize(520, 340)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  table.insert(UISpecialFrames, "GrudgeForeverTextDialog")

  frame.hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  frame.hint:SetPoint("TOPLEFT", 16, -32)
  frame.hint:SetPoint("RIGHT", -16, 0)
  frame.hint:SetJustifyH("LEFT")

  frame.Inset:ClearAllPoints()
  frame.Inset:SetPoint("TOPLEFT", 10, -54)
  frame.Inset:SetPoint("BOTTOMRIGHT", -10, 34)

  frame.box = CreateFrame("Frame", nil, frame, "ScrollingEditBoxTemplate")
  frame.box:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 6, -6)
  frame.box:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -22, 6)
  local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", frame.box, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", frame.box, "BOTTOMRIGHT", 6, 0)
  ScrollUtil.RegisterScrollBoxWithScrollBar(frame.box:GetScrollBox(), scrollBar)

  -- export is read-only: typing restores the text and keeps it selected for copying
  frame.box:RegisterCallback("OnTextChanged", function(_, _, userChanged)
    if mode == "export" and userChanged then
      frame.box:SetText(exportText)
      selectAll()
    end
  end, frame)

  frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.close:SetPoint("BOTTOMRIGHT", -8, 6)
  frame.close:SetSize(110, 22)
  frame.close:SetText(L["BTN_CLOSE"])
  frame.close:SetScript("OnClick", function() frame:Hide() end)

  frame.import = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.import:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
  frame.import:SetSize(110, 22)
  frame.import:SetText(L["IMPORT_BUTTON"])
  frame.import:SetScript("OnClick", runImport)
end

-- newMode: "export" or "import".
function TextDialog.Open(newMode)
  if not (ns.Core and ns.Core.ready) then return end
  if not frame then create() end
  mode = newMode
  local export = mode == "export"
  frame:SetTitle(L[export and "EXPORT_TITLE" or "IMPORT_TITLE"])
  frame.hint:SetText(L[export and "EXPORT_HINT" or "IMPORT_HINT"])
  frame.import:SetShown(not export)
  exportText = export and ns.ExportImport.Export(ns.Core.store) or ""
  frame.box:SetText(exportText)
  frame:Show()
  if export then
    selectAll()
  else
    frame.box:SetFocus()
  end
end

ns.UI.TextDialog = TextDialog
