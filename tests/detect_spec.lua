local wow = require("tests.helpers.wow")

describe("Detect", function()
  local ns, store, fired, resets, logs, debugOn, detect

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/Store.lua", "Core/Detect.lua")
    local clock, seq = 1700000000, 0
    store = ns.Store.New({}, {
      now = function() return clock end,
      random = function(n) seq = seq + 1; return (seq % n) + 1 end,
    })
    store:SetCurrentCharacter("Arthas Menethil", "Die Gilde")
    fired, resets, logs, debugOn = {}, 0, {}, false
    local alerts = {
      Fire = function(_, list, displayName, matches, trigger)
        fired[#fired + 1] = { list = list, name = displayName, matches = matches, trigger = trigger }
        return true
      end,
      ResetGroup = function() resets = resets + 1 end,
    }
    detect = ns.Detect.New({
      store = store,
      alerts = alerts,
      debug = function() return debugOn end,
      log = function(text) logs[#logs + 1] = text end,
    })
  end)

  describe("OnWhisper", function()
    it("fires a friendly whisper warning for a hyphenated sender", function()
      store:AddOrUpdate("friendly", "Thrall Earthson", "lieb")
      detect:OnWhisper("Thrall-Earthson")
      assert.equals(1, #fired)
      assert.equals("friendly", fired[1].list)
      assert.equals("Thrall Earthson", fired[1].name)
      assert.equals("whisper", fired[1].trigger)
      assert.equals(1, #fired[1].matches)
      assert.equals("lieb", fired[1].matches[1].entry.reason)
    end)

    it("ignores a name that is only on the enemy list", function()
      store:AddOrUpdate("enemy", "Thrall Earthson", "pöbelt")
      detect:OnWhisper("Thrall-Earthson")
      assert.equals(0, #fired)
    end)

    it("ignores unknown names", function()
      detect:OnWhisper("Jaina Proudmoore")
      assert.equals(0, #fired)
    end)

    it("does nothing for secret, empty or missing senders", function()
      store:AddOrUpdate("friendly", "Thrall Earthson", "lieb")
      assert.has_no.errors(function()
        detect:OnWhisper(wow.secret("Thrall Earthson"))
        detect:OnWhisper("")
        detect:OnWhisper(nil)
      end)
      assert.equals(0, #fired)
    end)
  end)

  describe("OnInvite", function()
    it("fires a friendly invite warning", function()
      store:AddOrUpdate("friendly", "Thrall Earthson", "lieb")
      detect:OnInvite("Thrall Earthson")
      assert.equals(1, #fired)
      assert.equals("friendly", fired[1].list)
      assert.equals("invite", fired[1].trigger)
    end)

    it("does nothing for a secret inviter", function()
      store:AddOrUpdate("friendly", "Thrall Earthson", "lieb")
      detect:OnInvite(wow.secret("Thrall Earthson"))
      assert.equals(0, #fired)
    end)
  end)

  describe("OnGroup", function()
    it("only resets the group tracking for an empty array", function()
      detect:OnGroup({})
      assert.equals(1, resets)
      assert.equals(0, #fired)
    end)

    it("fires for each known member and skips secret or empty entries", function()
      store:AddOrUpdate("friendly", "Thrall Earthson", "lieb")
      store:AddOrUpdate("friendly", "Jaina Proudmoore", "nett")
      store:AddOrUpdate("enemy", "Garrosh Hellscream", "pöbelt")
      detect:OnGroup({
        "Thrall Earthson", wow.secret("Jaina Proudmoore"), "", "Garrosh Hellscream", "Jaina-Proudmoore",
      })
      assert.equals(0, resets)
      assert.equals(2, #fired)
      assert.equals("Thrall Earthson", fired[1].name)
      assert.equals("Jaina Proudmoore", fired[2].name)
      assert.equals("group", fired[1].trigger)
      assert.equals("friendly", fired[2].list)
    end)
  end)

  describe("OnUnit", function()
    local function unit(token, faction, extra)
      local u = { name = "Garrosh", surname = "Hellscream", player = true, faction = faction }
      for k, v in pairs(extra or {}) do u[k] = v end
      wow.units[token] = u
    end

    before_each(function()
      wow.units["player"] = { name = "Arthas", surname = "Menethil", player = true, faction = "Alliance" }
      store:AddOrUpdate("enemy", "Garrosh Hellscream", "pöbelt")
    end)

    it("fires an enemy sight warning for an opposing player", function()
      unit("nameplate1", "Horde")
      detect:OnUnit("nameplate1")
      assert.equals(1, #fired)
      assert.equals("enemy", fired[1].list)
      assert.equals("Garrosh Hellscream", fired[1].name)
      assert.equals("sight", fired[1].trigger)
    end)

    it("ignores players of the own faction", function()
      unit("nameplate1", "Alliance")
      detect:OnUnit("nameplate1")
      assert.equals(0, #fired)
    end)

    it("ignores non-players, missing units and unknown factions", function()
      unit("nameplate1", "Horde", { player = false })
      unit("nameplate2", nil)
      detect:OnUnit("nameplate1")
      detect:OnUnit("nameplate2")
      detect:OnUnit("nameplate3")
      assert.equals(0, #fired)
    end)

    it("ignores everything while the own faction is unknown", function()
      wow.units["player"].faction = nil
      unit("nameplate1", "Horde")
      detect:OnUnit("nameplate1")
      assert.equals(0, #fired)
    end)

    it("does nothing for secret names", function()
      unit("nameplate1", "Horde", { secret = true })
      unit("nameplate2", "Horde", { secretSurname = true })
      assert.has_no.errors(function()
        detect:OnUnit("nameplate1")
        detect:OnUnit("nameplate2")
      end)
      assert.equals(0, #fired)
    end)

    it("does not look at enemy entries for friendly-only matches", function()
      store:Delete("enemy", "Garrosh Hellscream")
      store:AddOrUpdate("friendly", "Garrosh Hellscream", "doch nett")
      unit("nameplate1", "Horde")
      detect:OnUnit("nameplate1")
      assert.equals(0, #fired)
    end)
  end)

  describe("debug mode", function()
    it("logs nothing while debug is off", function()
      detect:OnWhisper("Thrall-Earthson")
      assert.equals(0, #logs)
    end)

    it("logs event, raw value and match result", function()
      debugOn = true
      store:AddOrUpdate("friendly", "Thrall Earthson", "lieb")
      detect:OnWhisper("Thrall-Earthson")
      detect:OnInvite("Jaina Proudmoore")
      assert.equals(2, #logs)
      assert.truthy(logs[1]:find("whisper", 1, true))
      assert.truthy(logs[1]:find("Thrall-Earthson", 1, true))
      assert.truthy(logs[1]:find("match", 1, true))
      assert.is_nil(logs[1]:find("no match", 1, true))
      assert.truthy(logs[2]:find("invite", 1, true))
      assert.truthy(logs[2]:find("no match", 1, true))
    end)

    it("prints <secret> instead of secret values", function()
      debugOn = true
      local secret = wow.secret("Thrall Earthson")
      detect:OnWhisper(secret)
      detect:OnGroup({ secret })
      assert.equals(2, #logs)
      for _, line in ipairs(logs) do
        assert.truthy(line:find("<secret>", 1, true))
        assert.is_nil(line:find("Thrall", 1, true))
      end
    end)

    it("logs secret unit names without leaking them", function()
      debugOn = true
      wow.units["player"] = { name = "Arthas", surname = "Menethil", player = true, faction = "Alliance" }
      wow.units["nameplate1"] = {
        name = "Garrosh", surname = "Hellscream", player = true, faction = "Horde", secret = true,
      }
      detect:OnUnit("nameplate1")
      assert.equals(1, #logs)
      assert.truthy(logs[1]:find("<secret>", 1, true))
      assert.is_nil(logs[1]:find("Garrosh", 1, true))
    end)

    it("logs nameplate sightings with the readable name", function()
      debugOn = true
      wow.units["player"] = { name = "Arthas", surname = "Menethil", player = true, faction = "Alliance" }
      wow.units["nameplate1"] = { name = "Garrosh", surname = "Hellscream", player = true, faction = "Horde" }
      store:AddOrUpdate("enemy", "Garrosh Hellscream", "x")
      detect:OnUnit("nameplate1")
      assert.equals(1, #logs)
      assert.truthy(logs[1]:find("Garrosh Hellscream", 1, true))
    end)
  end)
end)
