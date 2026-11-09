local wow = require("tests.helpers.wow")

describe("IgnoreWatch", function()
  local ns, store, ignored, printed, changes, watch

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/Store.lua", "Core/IgnoreWatch.lua")
    store = ns.Store.New({}, { now = function() return 100 end, random = math.random })
    store:SetCurrentCharacter("Arthas Menethil", nil)
    ignored, printed, changes = {}, {}, 0
    watch = ns.IgnoreWatch.New({
      store = store,
      change = function(fn) changes = changes + 1; return fn(store) end,
      isIgnored = function(name) return ignored[name] == true end,
      print = function(text) printed[#printed + 1] = text end,
    })
  end)

  local function ignore(name)
    watch:OnIgnoreCall(name)
    ignored[name] = true
    watch:OnIgnoreListUpdate()
  end

  it("puts a newly ignored player on the Blacklist with the import reason", function()
    ignore("Spitz-Ohr")
    local e = store:GetOwnEntry("friendly", "Spitz Ohr")
    assert.equals("IgnoreList Import", e.reason)
    assert.equals("Spitz Ohr", e.name)
    assert.equals(1, changes)
    assert.same({ ns.L["IGNORE_ADDED"]:format("Spitz Ohr") }, printed)
  end)

  it("does nothing when the call removed the player from the ignore list", function()
    watch:OnIgnoreCall("Spitz Ohr")
    watch:OnIgnoreListUpdate()
    assert.is_nil(store:GetOwnEntry("friendly", "Spitz Ohr"))
    assert.equals(0, changes)
  end)

  it("keeps an existing own Blacklist entry and its reason", function()
    store:AddOrUpdate("friendly", "Spitz Ohr", "Blabla")
    ignore("Spitz Ohr")
    assert.equals("Blabla", store:GetOwnEntry("friendly", "Spitz Ohr").reason)
    assert.equals(0, changes)
    assert.same({}, printed)
  end)

  it("skips first names alone and secret names", function()
    ignore("Spitz")
    watch:OnIgnoreCall(wow.secret("Spitz Ohr"))
    watch:OnIgnoreListUpdate()
    assert.equals(0, changes)
  end)

  it("handles each ignore call once", function()
    ignore("Spitz Ohr")
    store:Delete("friendly", "Spitz Ohr")
    watch:OnIgnoreListUpdate()
    local e = store:GetOwnEntry("friendly", "Spitz Ohr")
    assert.is_true(e == nil or e.deleted)
  end)
end)
