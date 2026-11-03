local wow = require("tests.helpers.wow")

describe("Slash.Parse", function()
  local Parse

  before_each(function()
    wow.reset()
    local ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/Slash.lua")
    Parse = ns.Slash.Parse
  end)

  it("toggles the main window on an empty command", function()
    assert.equals("toggle", (Parse("")))
    assert.equals("toggle", (Parse("   ")))
    assert.equals("toggle", (Parse(nil)))
  end)

  it("takes the first two tokens as the name and the rest as the reason", function()
    local cmd, args = Parse("add Thrall Earthson pöbelt rum")
    assert.equals("add", cmd)
    assert.equals("Thrall Earthson", args.name)
    assert.equals("pöbelt rum", args.reason)
  end)

  it("takes a hyphenated first token alone as the name", function()
    local cmd, args = Parse("add Thrall-Earthson pöbelt")
    assert.equals("add", cmd)
    assert.equals("Thrall-Earthson", args.name)
    assert.equals("pöbelt", args.reason)
  end)

  it("leaves the name empty without tokens so the target is used", function()
    local cmd, args = Parse("add")
    assert.equals("add", cmd)
    assert.is_nil(args.name)
    assert.is_nil(args.reason)
  end)

  it("keeps a single name token and an empty reason", function()
    local _, args = Parse("add Thrall")
    assert.equals("Thrall", args.name)
    assert.is_nil(args.reason)
  end)

  it("reads a name for remove but never a reason", function()
    local cmd, args = Parse("remove Thrall Earthson")
    assert.equals("remove", cmd)
    assert.equals("Thrall Earthson", args.name)
    assert.is_nil(args.reason)
    local _, more = Parse("remove Thrall Earthson extra words")
    assert.equals("Thrall Earthson", more.name)
    assert.is_nil(more.reason)
  end)

  it("matches commands case-insensitively", function()
    assert.equals("sync", (Parse("SYNC")))
    assert.equals("export", (Parse("Export")))
    assert.equals("add", (Parse("  ADD   Thrall   Earthson  ")))
  end)

  it("knows every documented command", function()
    for _, cmd in ipairs({ "toggle", "add", "remove", "sync", "export", "import", "debug", "config", "help" }) do
      assert.equals(cmd, (Parse(cmd)))
    end
  end)

  it("falls back to help for unknown commands", function()
    assert.equals("help", (Parse("frobnicate")))
    assert.equals("help", (Parse("addx Thrall")))
  end)

  it("always returns an argument table", function()
    local _, args = Parse("sync")
    assert.same({}, args)
  end)
end)
