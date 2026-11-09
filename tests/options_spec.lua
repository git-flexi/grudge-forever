local wow = require("tests.helpers.wow")

describe("Options", function()
  local ns

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Options.lua")
  end)

  describe("Defaults", function()
    it("describes both lists with the documented values", function()
      local d = ns.Options.Defaults()
      assert.equals("auto", d.syncMode)
      assert.is_false(d.debug)
      assert.is_nil(d.banner)
      assert.same({ hide = false }, d.minimap)
      assert.same({ enabled = true, sound = "raidwarning", icon = "exclamation", text = ns.L.DEFAULT_TEXT,
        banner = true, chat = true, cooldown = 300 }, d.lists.friendly)
      assert.same({ enabled = true, sound = "raidwarning", icon = "skull", text = ns.L.DEFAULT_TEXT,
        banner = true, chat = true, cooldown = 300 }, d.lists.enemy)
    end)

    it("returns a fresh table on every call", function()
      local a = ns.Options.Defaults()
      a.lists.enemy.sound = "none"
      assert.equals("raidwarning", ns.Options.Defaults().lists.enemy.sound)
    end)

    it("uses the German default text under the German locale", function()
      wow.reset()
      wow.locale = "deDE"
      ns = wow.newNs()
      wow.load(ns, "Core/Options.lua")
      assert.matches("{anlass}", ns.Options.Defaults().lists.enemy.text, 1, true)
    end)
  end)

  describe("Apply", function()
    it("replaces the old default warning texts with the new default and keeps custom texts", function()
      local sv = { settings = { lists = {
        friendly = { text = "{name} {trigger}! {reason} (by {by})" },
        enemy = { text = "{name} {anlass}! {grund} (von {von})" },
      } } }
      ns.Options.Apply(sv)
      assert.equals(ns.L.DEFAULT_TEXT, sv.settings.lists.friendly.text)
      assert.equals(ns.L.DEFAULT_TEXT, sv.settings.lists.enemy.text)

      sv.settings.lists.enemy.text = "{name} is here"
      ns.Options.Apply(sv)
      assert.equals("{name} is here", sv.settings.lists.enemy.text)

      -- only once: the old text chosen on purpose later stays
      sv.settings.lists.friendly.text = "{name} {trigger}! {reason} (by {by})"
      ns.Options.Apply(sv)
      assert.equals("{name} {trigger}! {reason} (by {by})", sv.settings.lists.friendly.text)
    end)

    it("fills an empty saved table with the defaults and returns sv.settings", function()
      local sv = {}
      local settings = ns.Options.Apply(sv)
      assert.equals(sv.settings, settings)
      assert.same(ns.Options.Defaults(), settings)
    end)

    it("keeps existing values, including false", function()
      local sv = { settings = { debug = true, lists = { enemy = { sound = "foo", enabled = false, chat = false } } } }
      local s = ns.Options.Apply(sv)
      assert.is_true(s.debug)
      assert.equals("foo", s.lists.enemy.sound)
      assert.is_false(s.lists.enemy.enabled)
      assert.is_false(s.lists.enemy.chat)
      assert.equals("skull", s.lists.enemy.icon)
      assert.equals("exclamation", s.lists.friendly.icon)
    end)

    it("keeps a saved banner position", function()
      local sv = { settings = { banner = { point = "CENTER", x = 1, y = 2 } } }
      assert.same({ point = "CENTER", x = 1, y = 2 }, ns.Options.Apply(sv).banner)
    end)

    it("leaves unknown keys alone", function()
      local sv = { settings = { future = 7, lists = { enemy = { extra = "x" } } } }
      local s = ns.Options.Apply(sv)
      assert.equals(7, s.future)
      assert.equals("x", s.lists.enemy.extra)
    end)

    it("resets an invalid sync mode to auto and keeps valid ones", function()
      assert.equals("auto", ns.Options.Apply({ settings = { syncMode = "x" } }).syncMode)
      assert.equals("auto", ns.Options.Apply({ settings = { syncMode = 5 } }).syncMode)
      assert.equals("manual", ns.Options.Apply({ settings = { syncMode = "manual" } }).syncMode)
      assert.equals("off", ns.Options.Apply({ settings = { syncMode = "off" } }).syncMode)
    end)

    it("resets a cooldown that is not a number or outside 10-3600 to 300", function()
      local function cooldown(value)
        return ns.Options.Apply({ settings = { lists = { friendly = { cooldown = value } } } }).lists.friendly.cooldown
      end
      assert.equals(300, cooldown(0))
      assert.equals(300, cooldown(9))
      assert.equals(300, cooldown(3601))
      assert.equals(300, cooldown("fast"))
      assert.equals(10, cooldown(10))
      assert.equals(3600, cooldown(3600))
      assert.equals(45, cooldown(45))
    end)

    it("validates the cooldown of every list", function()
      local s = ns.Options.Apply({ settings = { lists = { enemy = { cooldown = -1 } } } })
      assert.equals(300, s.lists.enemy.cooldown)
      assert.equals(300, s.lists.friendly.cooldown)
    end)

    it("replaces a corrupted lists value with the defaults", function()
      assert.same(ns.Options.Defaults().lists, ns.Options.Apply({ settings = { lists = "broken" } }).lists)
    end)

    it("is idempotent", function()
      local sv = {}
      ns.Options.Apply(sv)
      local copy = ns.Options.Defaults()
      assert.same(copy, ns.Options.Apply(sv))
    end)
  end)
end)

describe("OptionsPanel", function()
  it("loads and Register is a no-op without the Settings API", function()
    wow.reset()
    local ns = wow.newNs()
    wow.load(ns, "Core/Options.lua", "UI/OptionsPanel.lua")
    assert.is_nil(ns.OptionsPanel.Register({}, {}))
    assert.has_no.errors(function() ns.OptionsPanel.Open() end)
  end)
end)
