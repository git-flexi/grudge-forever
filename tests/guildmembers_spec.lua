local wow = require("tests.helpers.wow")

describe("GuildMembers.Build", function()
  local ns

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/GuildMembers.lua")
  end)

  local roster = {
    { name = "Thrall-Earthson", online = false },
    { name = "Jaina-Proudmoore", online = true },
    { name = "Arthas-Menethil", online = true },
    { name = "Twink-Char", online = false },
    { name = "Sylvanas-Windrunner", online = true },
  }
  local owners = {
    aaaaaaaaaaaaaaaa = { chars = { ["thrall earthson"] = "Thrall Earthson", ["twink char"] = "Twink Char" },
      version = "0.3.0", seen = 1700000000 },
    -- known only from relayed data: no hello, no version
    bbbbbbbbbbbbbbbb = { chars = { ["sylvanas windrunner"] = "Sylvanas Windrunner" } },
  }
  local me = { chars = { ["arthas menethil"] = "Arthas Menethil" }, version = "0.3.0", now = 1700000500 }

  local function byName(rows)
    local out = {}
    for _, r in ipairs(rows) do out[r.name] = r end
    return out
  end

  it("lists every roster member once with online state, addon and version", function()
    local rows = ns.GuildMembers.Build(roster, owners, me)
    assert.equals(5, #rows)
    local r = byName(rows)
    assert.same({ name = "Thrall Earthson", key = "thrall earthson", online = false, hasAddon = true,
      version = "0.3.0", seen = 1700000000 }, r["Thrall Earthson"])
    assert.is_true(r["Twink Char"].hasAddon)
    assert.is_true(r["Sylvanas Windrunner"].hasAddon)
    assert.is_nil(r["Sylvanas Windrunner"].version)
    assert.is_false(r["Jaina Proudmoore"].hasAddon)
    -- the own characters run this addon right now
    assert.same({ name = "Arthas Menethil", key = "arthas menethil", online = true, hasAddon = true,
      version = "0.3.0", seen = 1700000500, isMe = true }, r["Arthas Menethil"])
  end)

  it("sorts online before offline, with addon before without, then by name", function()
    local names = {}
    for i, r in ipairs(ns.GuildMembers.Build(roster, owners, me)) do names[i] = r.name end
    assert.same({ "Arthas Menethil", "Sylvanas Windrunner", "Jaina Proudmoore", "Thrall Earthson", "Twink Char" },
      names)
  end)

  it("also knows a member by the last character it used", function()
    local rows = ns.GuildMembers.Build({ { name = "Jaina-Proudmoore" } },
      { cccccccccccccccc = { chars = {}, lastChar = "Jaina Proudmoore" } }, { chars = {} })
    assert.is_true(rows[1].hasAddon)
  end)

  it("counts members with the addon", function()
    local withAddon, total = ns.GuildMembers.Count(ns.GuildMembers.Build(roster, owners, me))
    assert.equals(4, withAddon)
    assert.equals(5, total)
  end)

  it("skips unreadable and duplicate roster names", function()
    local rows = ns.GuildMembers.Build({ { name = wow.secret("X Y") }, { name = nil }, { name = "Jaina-Proudmoore" },
      { name = "Jaina Proudmoore", online = true } }, {}, { chars = {} })
    assert.equals(1, #rows)
    assert.is_true(rows[1].online)
  end)
end)
