local wow = require("tests.helpers.wow")

describe("Skin", function()
  local ns, Skin

  before_each(function()
    wow.reset()
    wow.installUI()
    ns = wow.newNs()
    wow.load(ns, "UI/Skin.lua")
    Skin = ns.Skin
  end)

  it("Gradient falls back to a flat color without CreateColor", function()
    _G.CreateColor = nil
    local texture = wow.proxy()
    local args
    rawset(texture, "SetColorTexture", function(_, ...) args = { ... } end)
    local from = { 0.1, 0.2, 0.3, 0.4 }
    Skin.Gradient(texture, "VERTICAL", { r = 0.1, g = 0.2, b = 0.3, a = 0.4 }, { r = 0, g = 0, b = 0, a = 1 })
    assert.same(from, args)
  end)

  it("Window adds a title and a close button that hides the window", function()
    local f = CreateFrame("Frame", "W", UIParent, "BackdropTemplate")
    local content = Skin.Window(f, "T")
    assert.equals("T", f.TitleText:GetText())
    assert.is_not_nil(f.content)
    assert.equals(f.content, content)
    f:Show()
    wow.fire(f.CloseButton, "OnClick")
    assert.is_false(f:IsShown())
  end)

  it("Tabs select, disable and ignore clicks on disabled tabs", function()
    local picked = {}
    local tabs = Skin.Tabs(UIParent, "P", { "A", "B", "C" }, function(i) table.insert(picked, i) end)
    wow.fire(tabs:GetTab(2), "OnClick")
    assert.same({ 2 }, picked)
    tabs:DisableTab(3)
    wow.fire(tabs:GetTab(3), "OnClick")
    assert.same({ 2 }, picked)
    assert.is_false(tabs:GetTab(3):IsEnabled())
    tabs:EnableTab(3)
    assert.is_true(tabs:GetTab(3):IsEnabled())
    tabs:SetTabText(1, "Eigene Fraktion · 2")
    assert.equals("Eigene Fraktion · 2", tabs:GetTab(1):GetText())
    assert.equals("P1", tabs:GetTab(1):GetName())
    assert.equals("P3", tabs:GetTab(3):GetName())
  end)

  it("Tabs resize to their text", function()
    local tabs = Skin.Tabs(UIParent, "P", { "A", "B", "C" }, function() end)
    rawset(tabs:GetTab(2).label, "GetStringWidth", function() return 140 end)
    tabs:SetTabText(2, "Gegnerische Fraktion · 123")
    assert.equals(168, tabs:GetTab(2):GetWidth())
  end)

  it("Tabs keep their colors after hovering", function()
    local tabs = Skin.Tabs(UIParent, "P", { "A", "B" }, function() end)
    local last
    rawset(tabs:GetTab(2).label, "SetTextColor", function(_, r, g, b, a) last = { r = r, g = g, b = b, a = a } end)
    tabs:SetTab(1)
    local muted = Skin.COLORS.muted
    assert.same({ r = muted.r, g = muted.g, b = muted.b, a = 1 }, last)
    last = nil
    wow.fire(tabs:GetTab(2), "OnEnter")
    wow.fire(tabs:GetTab(2), "OnLeave")
    assert.is_nil(last) -- hover never repaints the text
    tabs:SetTab(2)
    assert.equals(Skin.COLORS.gold.r, last.r)
  end)

  it("Gradient passes VERTICAL colors bottom first and HORIZONTAL left first", function()
    local texture = wow.proxy()
    local calls = {}
    rawset(texture, "SetGradient", function(_, o, a, b) table.insert(calls, { o, a, b }) end)
    local top, bottom = { r = 1, g = 0, b = 0, a = 1 }, { r = 0, g = 0, b = 1, a = 0 }
    Skin.Gradient(texture, "VERTICAL", top, bottom)
    Skin.Gradient(texture, "HORIZONTAL", top, bottom)
    assert.same({ "VERTICAL", bottom, top }, calls[1])
    assert.same({ "HORIZONTAL", top, bottom }, calls[2])
  end)

  it("keeps the alert palette in sync with the skin", function()
    wow.load(ns, "Core/Alerts.lua")
    local Alerts = ns.Alerts
    assert.equals(Skin.HEX.alert, Alerts.BANNER_COLORS.list)
    assert.equals(Skin.HEX.by, Alerts.BANNER_COLORS.by)
    assert.equals(Skin.HEX.alert, Alerts.CHAT_COLORS.list)
    assert.equals(Skin.HEX.by, Alerts.CHAT_COLORS.by)
    assert.equals(Skin.HEX.text, Alerts.CHAT_COLORS.reason)
  end)

  it("SetRowState shows zebra on odd rows and the selection when selected", function()
    local row = CreateFrame("Button", nil, UIParent)
    Skin.Row(row)
    Skin.Row(row)
    Skin.SetRowState(row, 1, false)
    assert.is_true(row.zebra:IsShown())
    assert.is_false(row.selection:IsShown())
    Skin.SetRowState(row, 2, true)
    assert.is_false(row.zebra:IsShown())
    assert.is_true(row.selection:IsShown())
    assert.is_true(row.selectionEdge:IsShown())
  end)
end)
