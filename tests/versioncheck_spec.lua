local wow = require("tests.helpers.wow")

describe("VersionCheck", function()
  local ns, sent, printed, timers, clock, rnd

  local function newCheck(version)
    return ns.VersionCheck.New({
      version = version,
      send = function(msg, channel) sent[#sent + 1] = { msg = msg, channel = channel } end,
      after = function(seconds, fn)
        local t = { seconds = seconds, fn = fn }
        function t.Cancel() t.cancelled = true end
        timers[#timers + 1] = t
        return t
      end,
      random = function() return rnd end,
      now = function() return clock end,
      print = function(text) printed[#printed + 1] = text end,
      me = function() return "Arthas Menethil" end,
    })
  end

  local function runTimers()
    local pending = timers
    timers = {}
    for _, t in ipairs(pending) do
      if not t.cancelled then t.fn() end
    end
  end

  local function v(av) return { t = "V", av = av } end

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/Store.lua", "Core/VersionCheck.lua")
    sent, printed, timers, clock, rnd = {}, {}, {}, 1700000000, 0.5
  end)

  it("compares version numbers part by part as numbers", function()
    local C = ns.VersionCheck.Compare
    assert.equals(1, C("1.10.0", "1.9.2"))
    assert.equals(-1, C("1.0.0", "1.0.1"))
    assert.equals(0, C("1.1", "1.1.0"))
    assert.equals(0, C("1.1.0-beta", "1.1.0"))
    -- a pre-release suffix never makes a version newer than its release
    assert.equals(0, C("1.2.0-rc2", "1.2.0"))
    assert.equals(-1, C("2.0.0-alpha1", "2.0.1"))
    assert.equals(1, C("2.0.0", "1.99.99"))
    assert.is_nil(C(nil, "1.0.0"))
    assert.is_nil(C("beta", "1.0.0"))
  end)

  it("announces its version on a channel", function()
    newCheck("1.1.0"):Announce("GUILD")
    assert.same({ { msg = { t = "V", av = "1.1.0" }, channel = "GUILD" } }, sent)
  end)

  it("stays silent without a version of its own", function()
    local check = newCheck(nil)
    check:Announce("GUILD")
    check:OnMessage(v("9.0.0"), "Jaina Proudmoore", "GUILD")
    check:OnMessage(v("9.0.0"), "Thrall Earthson", "GUILD")
    check:OnMessage(v("0.1.0"), "Garrosh Hellscream", "GUILD")
    runTimers()
    assert.equals(0, #sent)
    assert.equals(0, #printed)
  end)

  it("tells about a newer version once two players reported it, once per session", function()
    local check = newCheck("1.0.0")
    check:OnMessage(v("1.2.0"), "Jaina Proudmoore", "GUILD")
    -- the same player again does not count twice
    check:OnMessage(v("1.2.0"), "jaina-proudmoore", "PARTY")
    assert.equals(0, #printed)
    check:OnMessage(v("1.1.0"), "Thrall Earthson", "PARTY")
    assert.equals(1, #printed)
    -- the highest version both players run (or newer) is named
    assert.equals(ns.L["VERSION_NEWER"]:format("1.1.0", "1.0.0"), printed[1])
    check:OnMessage(v("1.3.0"), "Garrosh Hellscream", "GUILD")
    assert.equals(1, #printed)
  end)

  it("names only a version that two players reported, not one player's test build", function()
    local check = newCheck("1.1.0")
    check:OnMessage(v("1.3.0"), "Jaina Proudmoore", "GUILD")
    check:OnMessage(v("1.2.0"), "Thrall Earthson", "GUILD")
    assert.equals(ns.L["VERSION_NEWER"]:format("1.2.0", "1.1.0"), printed[1])
  end)

  it("counts the version from a guild hello", function()
    local check = newCheck("1.0.0")
    check:OnVersion("1.2.0", "Jaina Proudmoore")
    check:OnVersion("1.2.0", "Thrall Earthson")
    assert.equals(1, #printed)
    -- a hello is no question: nobody is answered
    check:OnVersion("0.9.0", "Garrosh Hellscream")
    runTimers()
    assert.equals(0, #sent)
  end)

  it("ignores its own messages, malformed versions and nameless senders", function()
    local check = newCheck("1.0.0")
    check:OnMessage(v("2.0.0"), "Arthas-Menethil", "GUILD")
    check:OnMessage(v("2.0.0|cffff0000"), "Jaina Proudmoore", "GUILD")
    check:OnMessage(v(("1"):rep(30)), "Thrall Earthson", "GUILD")
    check:OnMessage({ t = "V", av = 2 }, "Garrosh Hellscream", "GUILD")
    check:OnMessage(v("2.0.0"), nil, "GUILD")
    check:OnMessage(v("2.0.0"), wow.secret("Sylvanas Windrunner"), "GUILD")
    check:OnMessage(v("2.0.0"), "Cairne Bloodhoof", "GUILD")
    assert.equals(0, #printed)
  end)

  it("answers an older version on its channel after a random delay", function()
    local check = newCheck("1.1.0")
    rnd = 0.25
    check:OnMessage(v("1.0.0"), "Jaina Proudmoore", "RAID")
    assert.equals(0, #sent)
    assert.equals(1, #timers)
    assert.is_true(timers[1].seconds >= 1 and timers[1].seconds <= 8)
    runTimers()
    assert.same({ { msg = { t = "V", av = "1.1.0" }, channel = "RAID" } }, sent)
  end)

  it("does not answer equal or newer versions", function()
    local check = newCheck("1.1.0")
    check:OnMessage(v("1.1.0"), "Jaina Proudmoore", "PARTY")
    check:OnMessage(v("1.2.0"), "Thrall Earthson", "PARTY")
    runTimers()
    assert.equals(0, #sent)
  end)

  it("drops its answer once two others answered with at least its version", function()
    local check = newCheck("1.1.0")
    check:OnMessage(v("1.0.0"), "Jaina Proudmoore", "GUILD")
    check:OnMessage(v("1.1.0"), "Thrall Earthson", "GUILD")
    -- answers on another channel do not count
    check:OnMessage(v("1.2.0"), "Garrosh Hellscream", "PARTY")
    check:OnMessage(v("1.0.5"), "Sylvanas Windrunner", "GUILD")
    check:OnMessage(v("1.2.0"), "Cairne Bloodhoof", "GUILD")
    runTimers()
    assert.equals(0, #sent)
  end)

  it("counts two answers of the same player once", function()
    local check = newCheck("1.1.0")
    check:OnMessage(v("1.0.0"), "Jaina Proudmoore", "GUILD")
    check:OnMessage(v("1.1.0"), "Thrall Earthson", "GUILD")
    check:OnMessage(v("1.1.0"), "Thrall-Earthson", "GUILD")
    runTimers()
    assert.equals(1, #sent)
  end)

  it("answers at most once a minute per channel", function()
    local check = newCheck("1.1.0")
    check:OnMessage(v("1.0.0"), "Jaina Proudmoore", "GUILD")
    check:OnMessage(v("1.0.0"), "Thrall Earthson", "GUILD")
    assert.equals(1, #timers)
    runTimers()
    clock = clock + 30
    check:OnMessage(v("1.0.0"), "Garrosh Hellscream", "GUILD")
    check:OnMessage(v("1.0.0"), "Garrosh Hellscream", "PARTY")
    runTimers()
    assert.equals(2, #sent)
    assert.equals("PARTY", sent[2].channel)
    clock = clock + 31
    check:OnMessage(v("1.0.0"), "Garrosh Hellscream", "GUILD")
    runTimers()
    assert.equals(3, #sent)
  end)
end)
