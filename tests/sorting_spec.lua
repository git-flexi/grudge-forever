local wow = require("tests.helpers.wow")

describe("Sorting", function()
  local ns

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/Sorting.lua")
  end)

  local function match(name, reason, by, updated, muted)
    return { entry = { name = name, reason = reason, updated = updated }, by = by, muted = muted }
  end

  local function players()
    return {
      { key = "thrall earthson", matches = { match("Thrall Earthson", "afk", "Jaina Proudmoore", 300) } },
      { key = "arthas menethil", matches = { match("Arthas Menethil", "Ninja", "zed Zed", 100, true) } },
      { key = "sylvanas windrunner", matches = {
        match("Sylvanas Windrunner", "beleidigt", "Bob Bob", 50), match("Sylvanas Windrunner", "x", "Al Al", 500),
      } },
    }
  end

  local function keys(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.key end
    return out
  end

  it("sorts players newest first by default", function()
    local rows = ns.Sorting.SortPlayers(players(), ns.Sorting.DEFAULT_PLAYERS.column,
      ns.Sorting.DEFAULT_PLAYERS.desc)
    -- the newest entry of a player counts
    assert.same({ "sylvanas windrunner", "thrall earthson", "arthas menethil" }, keys(rows))
  end)

  it("sorts players by any column, both ways, ignoring case", function()
    local S = ns.Sorting
    assert.same({ "arthas menethil", "sylvanas windrunner", "thrall earthson" }, keys(S.SortPlayers(players(), "name")))
    assert.same({ "thrall earthson", "sylvanas windrunner", "arthas menethil" },
      keys(S.SortPlayers(players(), "name", true)))
    assert.same({ "thrall earthson", "sylvanas windrunner", "arthas menethil" },
      keys(S.SortPlayers(players(), "reason")))
    assert.same({ "sylvanas windrunner", "thrall earthson", "arthas menethil" }, keys(S.SortPlayers(players(), "by")))
    assert.same({ "arthas menethil", "thrall earthson", "sylvanas windrunner" },
      keys(S.SortPlayers(players(), "date")))
    assert.same({ "arthas menethil", "sylvanas windrunner", "thrall earthson" },
      keys(S.SortPlayers(players(), "status", true)))
  end)

  local function members()
    return {
      { key = "jaina proudmoore", online = true, hasAddon = true, version = "1.10.0", seen = 200 },
      { key = "thrall earthson", online = false, hasAddon = true, version = "1.9.2", seen = 900 },
      { key = "garrosh hellscream", online = true, hasAddon = false },
      { key = "arthas menethil", online = false, hasAddon = false },
    }
  end

  it("sorts guild members last seen first by default, members never seen last", function()
    local rows = ns.Sorting.SortMembers(members(), ns.Sorting.DEFAULT_MEMBERS.column,
      ns.Sorting.DEFAULT_MEMBERS.desc)
    -- members without a date keep the online, addon, name order
    assert.same({ "thrall earthson", "jaina proudmoore", "garrosh hellscream", "arthas menethil" }, keys(rows))
    rows = ns.Sorting.SortMembers(members(), "seen", false)
    assert.same({ "jaina proudmoore", "thrall earthson", "garrosh hellscream", "arthas menethil" }, keys(rows))
  end)

  it("sorts guild members by name, online state, addon and version", function()
    local S = ns.Sorting
    assert.same({ "arthas menethil", "garrosh hellscream", "jaina proudmoore", "thrall earthson" },
      keys(S.SortMembers(members(), "name")))
    assert.same({ "jaina proudmoore", "garrosh hellscream", "thrall earthson", "arthas menethil" },
      keys(S.SortMembers(members(), "online", true)))
    assert.same({ "jaina proudmoore", "thrall earthson", "garrosh hellscream", "arthas menethil" },
      keys(S.SortMembers(members(), "addon", true)))
    -- version numbers compare as numbers: 1.10.0 is newer than 1.9.2
    assert.same({ "jaina proudmoore", "thrall earthson", "garrosh hellscream", "arthas menethil" },
      keys(S.SortMembers(members(), "version", true)))
    assert.same({ "thrall earthson", "jaina proudmoore", "garrosh hellscream", "arthas menethil" },
      keys(S.SortMembers(members(), "version", false)))
  end)

  it("starts dates, flags and versions newest or true first, text from A", function()
    assert.is_true(ns.Sorting.FirstDesc("date"))
    assert.is_true(ns.Sorting.FirstDesc("seen"))
    assert.is_true(ns.Sorting.FirstDesc("online"))
    assert.is_true(ns.Sorting.FirstDesc("version"))
    assert.is_false(ns.Sorting.FirstDesc("name"))
    assert.is_false(ns.Sorting.FirstDesc("reason"))
  end)
end)
