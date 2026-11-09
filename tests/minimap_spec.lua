local wow = require("tests.helpers.wow")

describe("MinimapButton", function()
  local ns, settings, icon, broker, toggled, opened

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    broker = { objects = {} }
    function broker:NewDataObject(name, obj) self.objects[name] = obj; return obj end
    function broker:GetDataObjectByName(name) return self.objects[name] end
    icon = { registered = {}, shown = {} }
    function icon:Register(name, obj, db) self.registered[name] = { obj = obj, db = db } end
    function icon:IsRegistered(name) return self.registered[name] ~= nil end
    function icon:Show(name) self.shown[name] = true end
    function icon:Hide(name) self.shown[name] = false end
    LibStub:NewLibrary("LibDataBroker-1.1", 999)
    LibStub.libs["LibDataBroker-1.1"] = broker
    LibStub:NewLibrary("LibDBIcon-1.0", 999)
    LibStub.libs["LibDBIcon-1.0"] = icon
    wow.load(ns, "Core/Names.lua", "UI/MinimapButton.lua")
    settings = { minimap = { hide = false } }
    toggled, opened = 0, 0
    ns.MinimapButton.Install(settings, {
      toggleWindow = function() toggled = toggled + 1 end,
      openOptions = function() opened = opened + 1 end,
    })
  end)

  it("registers a launcher with the addon icon and the saved minimap settings", function()
    local reg = icon.registered.GrudgeForever
    assert.equals(settings.minimap, reg.db)
    assert.equals("launcher", reg.obj.type)
    assert.equals("Interface\\AddOns\\GrudgeForever\\Media\\icon", reg.obj.icon)
  end)

  it("opens the main window on left click and the settings on right click", function()
    local obj = icon.registered.GrudgeForever.obj
    obj.OnClick(nil, "LeftButton")
    obj.OnClick(nil, "RightButton")
    assert.equals(1, toggled)
    assert.equals(1, opened)
  end)

  it("describes both clicks in its tooltip", function()
    local lines = {}
    local tooltip = { AddLine = function(_, text) lines[#lines + 1] = text end }
    icon.registered.GrudgeForever.obj.OnTooltipShow(tooltip)
    assert.same({ "GrudgeForever", ns.L["MINIMAP_LEFT"], ns.L["MINIMAP_RIGHT"] }, lines)
  end)

  it("shows and hides the button and remembers the choice", function()
    ns.MinimapButton.SetShown(false)
    assert.is_true(settings.minimap.hide)
    assert.is_false(icon.shown.GrudgeForever)
    ns.MinimapButton.SetShown(true)
    assert.is_false(settings.minimap.hide)
    assert.is_true(icon.shown.GrudgeForever)
  end)
end)
