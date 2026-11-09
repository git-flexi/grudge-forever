local wow = require("tests.helpers.wow")

describe("Tooltip and UnitMenu", function()
  local ns, store, clock

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/Store.lua", "Core/Alerts.lua", "UI/Tooltip.lua", "UI/UnitMenu.lua")
    clock = 1700000000
    local seq = 0
    store = ns.Store.New({}, {
      now = function() return clock end,
      random = function(n) seq = seq + 1; return (seq % n) + 1 end,
    })
    store:SetCurrentCharacter("Arthas Menethil", "Die Gilde")
    wow.units.player = { name = "Arthas", surname = "Menethil", player = true, faction = "Alliance" }
  end)

  -- A foreign match as Store:Lookup would return it.
  local function foreign(reason, by, extra)
    local e = { key = "thrall earthson", name = "Thrall Earthson", list = "friendly", reason = reason,
                created = 1, updated = 2, rev = 1 }
    for k, v in pairs(extra or {}) do e[k] = v end
    return { entry = e, ownerId = "o-" .. tostring(by), isOwn = false, by = by, muted = false }
  end

  describe("Tooltip.BuildLines", function()
    it("builds a header, three lines and a +N line for 1 own and 4 foreign matches", function()
      local own = foreign("rude", "Arthas Menethil")
      own.isOwn = true
      local matches = { own, foreign("ninja", "Jaina Proudmoore"), foreign("afk", "Sylvanas Windrunner"),
                        foreign("scam", "Illidan Stormrage"), foreign("gank", "Tyrande Whisperwind") }
      local lines = ns.Tooltip.BuildLines(matches)
      assert.equals(5, #lines)
      assert.equals("GrudgeForever (Blacklist)", lines[1].text)
      assert.equals("rude – by Arthas Menethil", lines[2].text)
      assert.equals("ninja – by Jaina Proudmoore", lines[3].text)
      assert.equals("afk – by Sylvanas Windrunner", lines[4].text)
      assert.equals("+2 more", lines[5].text)
      for _, line in ipairs(lines) do
        assert.is_number(line.r)
        assert.is_number(line.g)
        assert.is_number(line.b)
      end
    end)

    it("names the original creator of an adopted entry", function()
      local lines = ns.Tooltip.BuildLines({ foreign("rude", "Arthas Menethil", { origin = "Jaina Proudmoore" }) })
      assert.equals(2, #lines)
      assert.truthy(lines[2].text:find("rude", 1, true))
      assert.truthy(lines[2].text:find("by Arthas Menethil", 1, true))
      assert.truthy(lines[2].text:find("adopted from Jaina Proudmoore", 1, true))
    end)

    it("escapes pipes in remote reasons, creators and origins", function()
      local lines = ns.Tooltip.BuildLines({ foreign("a|cffb", "C|Hd", { origin = "E|Tf" }) })
      assert.equals("a||cffb – by C||Hd · adopted from E||Tf", lines[2].text)
    end)

    it("marks muted matches and greys them out", function()
      local m = foreign("rude", "Jaina Proudmoore")
      m.muted = true
      local lines = ns.Tooltip.BuildLines({ m })
      assert.truthy(lines[2].text:find(" (muted)", 1, true))
      assert.equals(0.5, lines[2].r)
      assert.equals(0.5, lines[2].g)
      assert.equals(0.5, lines[2].b)
      local normal = ns.Tooltip.BuildLines({ foreign("rude", "Jaina Proudmoore") })
      assert.is_nil(normal[2].text:find("muted", 1, true))
      assert.is_true(normal[2].r > 0.5)
    end)

    it("groups matches per list with their own header", function()
      local e = foreign("kos", "Jaina Proudmoore")
      e.entry.list = "enemy"
      local lines = ns.Tooltip.BuildLines({ foreign("rude", "Arthas Menethil"), e })
      assert.equals(4, #lines)
      assert.equals("GrudgeForever (Blacklist)", lines[1].text)
      assert.equals("GrudgeForever (KOS)", lines[3].text)
    end)

    it("counts the +N line per list", function()
      local matches = {}
      for i = 1, 4 do matches[i] = foreign("r" .. i, "Char" .. i) end
      local enemy = foreign("kos", "Jaina Proudmoore")
      enemy.entry.list = "enemy"
      matches[5] = enemy
      local lines = ns.Tooltip.BuildLines(matches)
      -- friendly: header + 3 + "+1 more"; enemy: header + 1
      assert.equals(7, #lines)
      assert.equals("+1 more", lines[5].text)
    end)

    it("returns no lines without matches and tolerates empty reasons", function()
      assert.same({}, ns.Tooltip.BuildLines({}))
      local lines = ns.Tooltip.BuildLines({ foreign("", "Jaina Proudmoore") })
      assert.equals("by Jaina Proudmoore", lines[2].text)
    end)
  end)

  describe("Tooltip.Install", function()
    local postCall, tooltipLines

    local function fakeTooltip(unit)
      tooltipLines = {}
      return {
        GetUnit = function() return "Thrall", unit end,
        AddLine = function(_, text, r, g, b) tooltipLines[#tooltipLines + 1] = { text, r, g, b } end,
      }
    end

    before_each(function()
      postCall = nil
      _G.Enum = { TooltipDataType = { Unit = 2 } }
      _G.TooltipDataProcessor = {
        AddTooltipPostCall = function(kind, fn)
          assert.equals(2, kind)
          postCall = fn
        end,
      }
      wow.units.mouseover = { name = "Thrall", surname = "Earthson", player = true, faction = "Horde" }
      ns.Tooltip.Install(store)
    end)

    it("adds the list lines for a listed player", function()
      store:AddOrUpdate("enemy", "Thrall Earthson", "kos him")
      postCall(fakeTooltip("mouseover"), {})
      assert.equals(2, #tooltipLines)
      assert.equals("GrudgeForever (KOS)", tooltipLines[1][1])
      assert.truthy(tooltipLines[2][1]:find("kos him", 1, true))
    end)

    it("adds nothing for unlisted players", function()
      postCall(fakeTooltip("mouseover"), {})
      assert.equals(0, #tooltipLines)
    end)

    it("ignores tooltips without a unit or with a secret unit or name", function()
      store:AddOrUpdate("enemy", "Thrall Earthson", "kos him")
      postCall(fakeTooltip(nil), {})
      postCall(fakeTooltip(wow.secret("mouseover")), {})
      assert.equals(0, #tooltipLines)
      wow.units.mouseover.secret = true
      postCall(fakeTooltip("mouseover"), {})
      assert.equals(0, #tooltipLines)
    end)

    it("ignores non-player units", function()
      store:AddOrUpdate("enemy", "Thrall Earthson", "kos him")
      wow.units.mouseover.player = false
      postCall(fakeTooltip("mouseover"), {})
      assert.equals(0, #tooltipLines)
    end)

    it("does nothing without TooltipDataProcessor", function()
      _G.TooltipDataProcessor = nil
      assert.has_no.errors(function() ns.Tooltip.Install(store) end)
    end)
  end)

  describe("UnitMenu.NameFromContext", function()
    it("joins name and surname", function()
      assert.equals("Thrall Earthson", ns.UnitMenu.NameFromContext({ name = "Thrall", surname = "Earthson" }))
    end)

    it("handles a combined chat name without surname", function()
      assert.equals("Thrall Earthson", ns.UnitMenu.NameFromContext({ name = "Thrall-Earthson" }))
    end)

    it("prefers the unit", function()
      wow.units.target = { name = "Jaina", surname = "Proudmoore", player = true }
      assert.equals("Jaina Proudmoore",
        ns.UnitMenu.NameFromContext({ unit = "target", name = "Thrall", surname = "Earthson" }))
    end)

    it("returns nil for secret values", function()
      assert.is_nil(ns.UnitMenu.NameFromContext({ name = wow.secret("Thrall"), surname = "Earthson" }))
      assert.is_nil(ns.UnitMenu.NameFromContext({ name = "Thrall", surname = wow.secret("Earthson") }))
      wow.units.target = { name = "Jaina", surname = "Proudmoore", player = true, secret = true }
      assert.is_nil(ns.UnitMenu.NameFromContext({ unit = "target" }))
      assert.is_nil(ns.UnitMenu.NameFromContext({ unit = wow.secret("target") }))
    end)

    it("returns nil without any name", function()
      assert.is_nil(ns.UnitMenu.NameFromContext({}))
      assert.is_nil(ns.UnitMenu.NameFromContext(nil))
    end)

    it("returns nil for the own character", function()
      assert.is_nil(ns.UnitMenu.NameFromContext({ name = "Arthas", surname = "Menethil" }, "Arthas Menethil"))
      assert.is_nil(ns.UnitMenu.NameFromContext({ name = "arthas-menethil" }, "Arthas Menethil"))
      assert.equals("Thrall Earthson",
        ns.UnitMenu.NameFromContext({ name = "Thrall", surname = "Earthson" }, "Arthas Menethil"))
    end)
  end)

  describe("UnitMenu.Actions", function()
    it("offers add on the enemy list for the enemy player tag", function()
      assert.same({ { labelKey = "MENU_ADD", kind = "add", list = "enemy" } },
        ns.UnitMenu.Actions(store, "Thrall Earthson", "MENU_UNIT_ENEMY_PLAYER"))
    end)

    it("offers add on the friendly list for other tags without a unit", function()
      assert.same({ { labelKey = "MENU_ADD", kind = "add", list = "friendly" } },
        ns.UnitMenu.Actions(store, "Thrall Earthson", "MENU_UNIT_PARTY"))
    end)

    it("picks the list from the unit faction", function()
      wow.units.target = { name = "Thrall", surname = "Earthson", player = true, faction = "Horde" }
      wow.units.focus = { name = "Jaina", surname = "Proudmoore", player = true, faction = "Alliance" }
      assert.equals("enemy", ns.UnitMenu.Actions(store, "Thrall Earthson", "MENU_UNIT_PLAYER", "target")[1].list)
      assert.equals("friendly", ns.UnitMenu.Actions(store, "Jaina Proudmoore", "MENU_UNIT_PLAYER", "focus")[1].list)
    end)

    it("exposes the faction check for the target", function()
      wow.units.target = { name = "Thrall", surname = "Earthson", player = true, faction = "Horde" }
      assert.is_true(ns.UnitMenu.IsOtherFaction("target"))
      wow.units.target.faction = "Alliance"
      assert.is_false(ns.UnitMenu.IsOtherFaction("target"))
      wow.units.target = nil
      assert.is_false(ns.UnitMenu.IsOtherFaction("target"))
    end)

    it("falls back to friendly when a faction is unknown", function()
      wow.units.target = { name = "Thrall", surname = "Earthson", player = true }
      assert.equals("friendly", ns.UnitMenu.Actions(store, "Thrall Earthson", "MENU_UNIT_PLAYER", "target")[1].list)
    end)

    it("fixes the list to the Blacklist only for a unit of the own faction", function()
      wow.units.focus = { name = "Jaina", surname = "Proudmoore", player = true, faction = "Alliance" }
      wow.units.target = { name = "Thrall", surname = "Earthson", player = true, faction = "Horde" }
      assert.is_true(ns.UnitMenu.Actions(store, "Jaina Proudmoore", "MENU_UNIT_PLAYER", "focus")[1].fixed)
      assert.is_nil(ns.UnitMenu.Actions(store, "Thrall Earthson", "MENU_UNIT_PLAYER", "target")[1].fixed)
      assert.is_nil(ns.UnitMenu.Actions(store, "Jaina Proudmoore", "MENU_UNIT_PARTY")[1].fixed)
      wow.units.focus.faction = nil
      assert.is_nil(ns.UnitMenu.Actions(store, "Jaina Proudmoore", "MENU_UNIT_PLAYER", "focus")[1].fixed)
    end)

    it("offers edit for an own entry", function()
      store:AddOrUpdate("enemy", "Thrall Earthson", "x")
      assert.same({ { labelKey = "MENU_EDIT", kind = "edit", list = "enemy" } },
        ns.UnitMenu.Actions(store, "Thrall Earthson", "MENU_UNIT_PLAYER"))
    end)

    it("offers add again once an own entry is deleted", function()
      store:AddOrUpdate("friendly", "Thrall Earthson", "x")
      store:Delete("friendly", "Thrall Earthson")
      assert.equals("add", ns.UnitMenu.Actions(store, "Thrall Earthson", "MENU_UNIT_PLAYER")[1].kind)
    end)

    describe("with a foreign entry", function()
      before_each(function()
        store:SetCurrentCharacter("Arthas Menethil", "Die Gilde")
        store:ApplyDelta({
          o = "other", rev = 1, base = 0, chars = { ["jaina proudmoore"] = "Jaina Proudmoore" },
          lastChar = "Jaina Proudmoore",
          e = { { key = "thrall earthson", name = "Thrall Earthson", list = "friendly", reason = "rude",
                  created = 1, updated = 2, rev = 1, deleted = false } },
        })
      end)

      it("offers mute, then unmute", function()
        assert.same({ { labelKey = "MENU_MUTE", kind = "mute", list = "friendly" } },
          ns.UnitMenu.Actions(store, "Thrall Earthson", "MENU_UNIT_PLAYER"))
        store:SetMuted("friendly", "Thrall Earthson", true)
        assert.same({ { labelKey = "MENU_UNMUTE", kind = "unmute", list = "friendly" } },
          ns.UnitMenu.Actions(store, "Thrall Earthson", "MENU_UNIT_PLAYER"))
      end)

      it("prefers edit when the player also has an own entry", function()
        store:AddOrUpdate("friendly", "Thrall Earthson", "mine")
        assert.same({ { labelKey = "MENU_EDIT", kind = "edit", list = "friendly" } },
          ns.UnitMenu.Actions(store, "Thrall Earthson", "MENU_UNIT_PLAYER"))
      end)
    end)
  end)

  describe("UnitMenu.Install", function()
    local modifiers, openSpy

    local function fakeRoot()
      local root = { divider = 0, titles = {}, buttons = {} }
      function root:CreateDivider() self.divider = self.divider + 1 end
      function root:CreateTitle(text) self.titles[#self.titles + 1] = text end
      function root:CreateButton(text, fn) self.buttons[#self.buttons + 1] = { text = text, fn = fn } end
      return root
    end

    before_each(function()
      modifiers = {}
      _G.Menu = { ModifyMenu = function(tag, fn) modifiers[tag] = fn end }
      openSpy = { calls = {} }
      ns.UI = { EditDialog = { Open = function(...) openSpy.calls[#openSpy.calls + 1] = { ... } end } }
      ns.UnitMenu.Install(store)
    end)

    it("registers every tag", function()
      assert.equals(8, #ns.UnitMenu.TAGS)
      for _, tag in ipairs(ns.UnitMenu.TAGS) do assert.is_function(modifiers[tag]) end
    end)

    it("adds a divider, a title and an add button that opens the dialog", function()
      local root = fakeRoot()
      modifiers.MENU_UNIT_ENEMY_PLAYER(nil, root, { name = "Thrall", surname = "Earthson" })
      assert.equals(1, root.divider)
      assert.same({ "GrudgeForever" }, root.titles)
      assert.equals(1, #root.buttons)
      assert.equals(ns.L["MENU_ADD"], root.buttons[1].text)
      root.buttons[1].fn()
      assert.same({ { "Thrall Earthson", "enemy", nil } }, openSpy.calls)
    end)

    it("opens the dialog with a fixed Blacklist for a friendly unit", function()
      wow.units.focus = { name = "Jaina", surname = "Proudmoore", player = true, faction = "Alliance" }
      local root = fakeRoot()
      modifiers.MENU_UNIT_PLAYER(nil, root, { unit = "focus", name = "Jaina", surname = "Proudmoore" })
      root.buttons[1].fn()
      assert.same({ { "Jaina Proudmoore", "friendly", nil, nil, true } }, openSpy.calls)
    end)

    it("opens the dialog with the own entry for edit", function()
      local entry = store:AddOrUpdate("friendly", "Thrall Earthson", "x")
      local root = fakeRoot()
      modifiers.MENU_UNIT_PARTY(nil, root, { name = "Thrall", surname = "Earthson" })
      assert.equals(ns.L["MENU_EDIT"], root.buttons[1].text)
      root.buttons[1].fn()
      assert.equals(1, #openSpy.calls)
      assert.equals("friendly", openSpy.calls[1][2])
      assert.equals(entry, openSpy.calls[1][3])
    end)

    it("mutes and unmutes through the buttons", function()
      store:ApplyDelta({
        o = "other", rev = 1, base = 0, chars = { ["jaina proudmoore"] = "Jaina Proudmoore" },
        lastChar = "Jaina Proudmoore",
        e = { { key = "thrall earthson", name = "Thrall Earthson", list = "friendly", reason = "rude",
                created = 1, updated = 2, rev = 1, deleted = false } },
      })
      local ctx = { name = "Thrall", surname = "Earthson" }
      local root = fakeRoot()
      modifiers.MENU_UNIT_GUILD(nil, root, ctx)
      assert.equals(ns.L["MENU_MUTE"], root.buttons[1].text)
      root.buttons[1].fn()
      assert.is_true(store:IsMuted("friendly", "Thrall Earthson"))

      root = fakeRoot()
      modifiers.MENU_UNIT_GUILD(nil, root, ctx)
      assert.equals(ns.L["MENU_UNMUTE"], root.buttons[1].text)
      root.buttons[1].fn()
      assert.is_false(store:IsMuted("friendly", "Thrall Earthson"))
    end)

    it("adds nothing for secret names and the own character", function()
      local root = fakeRoot()
      modifiers.MENU_UNIT_PLAYER(nil, root, { name = wow.secret("Thrall"), surname = "Earthson" })
      modifiers.MENU_UNIT_PLAYER(nil, root, { name = "Arthas", surname = "Menethil" })
      modifiers.MENU_UNIT_PLAYER(nil, root, nil)
      assert.equals(0, root.divider)
      assert.equals(0, #root.titles)
      assert.equals(0, #root.buttons)
    end)

    it("does not fail when the edit dialog is missing", function()
      ns.UI = nil
      local root = fakeRoot()
      modifiers.MENU_UNIT_PARTY(nil, root, { name = "Thrall", surname = "Earthson" })
      assert.has_no.errors(function() root.buttons[1].fn() end)
    end)

    it("does nothing without Menu", function()
      _G.Menu = nil
      assert.has_no.errors(function() ns.UnitMenu.Install(store) end)
    end)
  end)
end)
