local wow = require("tests.helpers.wow")

-- Multi-client simulation: every client has its own sv, Store and Sync. A shared bus delivers
-- each sent message (deep-copied) to all *other* online clients; a manual clock and timer
-- queue stand in for C_Timer.
describe("Sync", function()
  local GUILD = "Die Gilde"
  local COOLDOWN = 300
  local ns, clock, timers, timerSeq, log, clients, bulkDelay, normalDelay

  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[copy(k)] = copy(x) end
    return out
  end

  local function after(seconds, fn)
    timerSeq = timerSeq + 1
    local t = { due = clock + seconds, seq = timerSeq, fn = fn }
    timers[#timers + 1] = t
    return { Cancel = function() t.cancelled = true end }
  end

  local function pendingTimers()
    local n = 0
    for _, t in ipairs(timers) do
      if not t.cancelled then n = n + 1 end
    end
    return n
  end

  -- Fires timers in due order (moving the clock to each) until none is left.
  local function runTimers()
    for _ = 1, 10000 do
      local best
      for i, t in ipairs(timers) do
        if not t.cancelled then
          local b = best and timers[best]
          if not b or t.due < b.due or (t.due == b.due and t.seq < b.seq) then best = i end
        end
      end
      if not best then
        timers = {}
        return
      end
      local t = table.remove(timers, best)
      if t.due > clock then clock = t.due end
      t.fn()
    end
    error("timers never settle")
  end

  -- Delivery latency: NORMAL messages arrive after normalDelay seconds, BULK ones after bulkDelay
  -- (chunked AceComm data); 0 delivers at once.
  local function broadcast(from, msg, prio)
    msg = copy(msg)
    log[#log + 1] = { from = from, msg = msg, prio = prio }
    local function deliver()
      for _, c in ipairs(clients) do
        if c ~= from and c.online then c.sync:OnMessage(copy(msg), from.wireName) end
      end
    end
    local delay = prio == "BULK" and bulkDelay or normalDelay
    if delay > 0 then after(delay, deliver) else deliver() end
  end

  -- opts: mode ("auto"), guild (GUILD; false = none), sv (fresh), wireName (char name),
  --       random (math.random: the source of answer delays)
  local function newClient(name, opts)
    opts = opts or {}
    local c = { name = name, wireName = opts.wireName or name, mode = opts.mode or "auto", online = true }
    c.sv = opts.sv or {}
    c.store = ns.Store.New(c.sv, {
      now = function() return clock end,
      random = function(n) return math.random(n) end,
    })
    local guild = GUILD
    if opts.guild ~= nil then guild = opts.guild or nil end
    c.store:SetCurrentCharacter(name, guild)
    c.sync = ns.Sync.New({
      store = c.store,
      send = function(msg, prio) broadcast(c, msg, prio) end,
      now = function() return clock end,
      after = after,
      random = opts.random or function() return math.random() end,
      mode = function() return c.mode end,
      sv = c.sv,
    })
    c.pid = function() return c.store:GetPlayerId() end
    clients[#clients + 1] = c
    return c
  end

  local function add(c, list, name, reason)
    local prev = c.store:GetRev(c.pid())
    assert.truthy(c.store:AddOrUpdate(list, name, reason))
    c.sync:OnOwnChange(prev)
  end

  local function delete(c, list, name)
    local prev = c.store:GetRev(c.pid())
    assert.is_true(c.store:Delete(list, name))
    c.sync:OnOwnChange(prev)
  end

  -- Logged messages since index `from`, filtered by sender client, type and owner.
  local function sent(filter, from)
    local out = {}
    for i = from or 1, #log do
      local l = log[i]
      if (filter.from == nil or l.from == filter.from) and (filter.t == nil or l.msg.t == filter.t)
        and (filter.o == nil or l.msg.o == filter.o) then
        out[#out + 1] = l
      end
    end
    return out
  end

  local function hello(sender, digest)
    return {
      t = "H", v = 1, pid = sender.pid(), char = sender.name, chars = { sender.name },
      d = digest or { [sender.pid()] = 0 },
    }
  end

  local function request(sender, want)
    return { t = "R", v = 1, pid = sender.pid(), want = want }
  end

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/Store.lua", "Core/Sync.lua")
    math.randomseed(4711)
    clock = 1700000000
    timers, timerSeq, log, clients, bulkDelay, normalDelay = {}, 0, {}, {}, 0, 0
  end)

  it("brings a new member up to date after its hello", function()
    local a = newClient("Jaina Proudmoore")
    add(a, "enemy", "Thrall Earthson", "pöbelt")
    add(a, "friendly", "Sylvanas Windrunner", "nett")

    local b = newClient("Arthas Menethil")
    local mark = #log + 1
    b.sync:OnRosterReady()
    local h = sent({ from = b, t = "H" }, mark)
    assert.equals(1, #h)
    assert.equals("NORMAL", h[1].prio)
    assert.equals(1, h[1].msg.v)
    assert.is_false(h[1].msg.full)
    assert.same({ "Arthas Menethil" }, h[1].msg.chars)

    runTimers()
    local d = sent({ from = a, t = "D", o = a.pid() }, mark)
    assert.equals(1, #d)
    assert.equals("BULK", d[1].prio)
    assert.equals(a.pid(), d[1].msg.from)
    -- a planned answer is announced first
    local ann = sent({ from = a, t = "A" }, mark)
    assert.equals(1, #ann)
    assert.equals("NORMAL", ann[1].prio)
    assert.same({ t = "A", v = 1, from = a.pid(), o = a.pid(), rev = 2, base = 0 }, ann[1].msg)
    local m = b.store:Lookup("Thrall Earthson", "enemy")
    assert.equals(1, #m)
    assert.equals(a.pid(), m[1].ownerId)
    assert.equals("pöbelt", m[1].entry.reason)
    assert.equals("Jaina Proudmoore", m[1].by)
    assert.equals(1, #b.store:Lookup("Sylvanas Windrunner", "friendly"))
  end)

  it("says hello only once and only in auto mode", function()
    local a = newClient("Jaina Proudmoore")
    local m = newClient("Arthas Menethil", { mode = "manual" })
    local o = newClient("Thrall Earthson", { mode = "off" })
    a.sync:OnRosterReady()
    a.sync:OnRosterReady()
    m.sync:OnRosterReady()
    o.sync:OnRosterReady()
    assert.equals(1, #sent({ t = "H" }))
    assert.equals(a, sent({ t = "H" })[1].from)
    -- not having said hello yet, a client switched to auto still does
    m.mode = "auto"
    m.sync:OnRosterReady()
    assert.equals(2, #sent({ t = "H" }))
  end)

  it("sends only the changed entry as a live delta", function()
    local a = newClient("Jaina Proudmoore")
    local b = newClient("Arthas Menethil")
    add(a, "enemy", "Thrall Earthson", "pöbelt")
    add(a, "enemy", "Garrosh Hellscream", "ninjat")
    assert.equals(1, #b.store:Lookup("Garrosh Hellscream"))

    local mark = #log + 1
    add(a, "enemy", "Thrall Earthson", "doch nett")
    local d = sent({ from = a, t = "D" }, mark)
    assert.equals(1, #d)
    assert.equals(1, #d[1].msg.e)
    assert.equals(2, d[1].msg.base)
    assert.equals(3, d[1].msg.rev)
    assert.equals("doch nett", b.store:Lookup("Thrall Earthson")[1].entry.reason)
    assert.equals(0, pendingTimers())
    -- live changes go out at once, without an announce
    assert.equals(0, #sent({ t = "A" }))
  end)

  it("spreads deletions", function()
    local a = newClient("Jaina Proudmoore")
    local b = newClient("Arthas Menethil")
    add(a, "enemy", "Thrall Earthson", "pöbelt")
    assert.equals(1, #b.store:Lookup("Thrall Earthson"))
    delete(a, "enemy", "Thrall Earthson")
    assert.same({}, b.store:Lookup("Thrall Earthson"))
  end)

  it("asks for the full state when a live delta does not fit", function()
    local a = newClient("Jaina Proudmoore")
    local b = newClient("Arthas Menethil")
    add(a, "enemy", "Thrall Earthson", "eins")
    b.online = false
    add(a, "enemy", "Garrosh Hellscream", "zwei")
    b.online = true
    local mark = #log + 1
    add(a, "enemy", "Varian Wrynn", "drei")
    assert.same({}, b.store:Lookup("Varian Wrynn"))

    runTimers()
    local r = sent({ from = b, t = "R" }, mark)
    assert.equals(1, #r)
    assert.equals("NORMAL", r[1].prio)
    assert.same({ [a.pid()] = 0 }, r[1].msg.want)
    assert.equals(3, b.store:GetRev(a.pid()))
    assert.equals(1, #b.store:Lookup("Garrosh Hellscream"))
    assert.equals(1, #b.store:Lookup("Varian Wrynn"))
  end)

  it("answers a hello once even if several members hold the data", function()
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore")
    local c = newClient("Anduin Wrynn")
    add(x, "enemy", "Thrall Earthson", "pöbelt")
    x.online = false

    local b = newClient("Arthas Menethil")
    local mark = #log + 1
    b.sync:OnRosterReady()
    runTimers()
    assert.equals(1, #sent({ t = "D", o = x.pid() }, mark))
    assert.equals(1, #b.store:Lookup("Thrall Earthson"))
    assert.equals(1, #a.store:Lookup("Thrall Earthson"))
    assert.equals(1, #c.store:Lookup("Thrall Earthson"))
  end)

  it("answers once even when the data itself arrives much later than the answer timers", function()
    bulkDelay = 30
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore")
    local c = newClient("Anduin Wrynn")
    local d = newClient("Muradin Bronzebeard")
    add(x, "enemy", "Thrall Earthson", "pöbelt")
    runTimers()
    x.online = false

    local b = newClient("Arthas Menethil")
    local mark = #log + 1
    b.sync:OnRosterReady()
    runTimers()
    assert.equals(1, #sent({ t = "A", o = x.pid() }, mark))
    assert.equals(1, #sent({ t = "D", o = x.pid() }, mark))
    assert.equals(1, #b.store:Lookup("Thrall Earthson"))
    assert.equals(1, #d.store:Lookup("Thrall Earthson"))
    assert.equals(1, #a.store:Lookup("Thrall Earthson"))
    assert.equals(1, #c.store:Lookup("Thrall Earthson"))
  end)

  -- A large guild with realistic latency: every question is answered about once.
  local GUILD_SIZE = 24
  local FIRST_NAMES = { "Anduin", "Baine", "Cairne", "Drek", "Eitrigg", "Falstad", "Genn", "Hamuul" }
  local SURNAMES = { "Ashbringer", "Bloodhoof", "Crowley" }

  local function bigGuild()
    local members = {}
    for i = 1, GUILD_SIZE do
      local name = FIRST_NAMES[(i - 1) % #FIRST_NAMES + 1] .. " " .. SURNAMES[math.floor((i - 1) / #FIRST_NAMES) + 1]
      members[i] = newClient(name)
    end
    for i, c in ipairs(members) do add(c, "enemy", "Target Nummer" .. i, "grund " .. i) end
    -- two members whose data everyone holds go offline
    local gone = { members[1], members[2] }
    for _, c in ipairs(gone) do c.online = false end
    runTimers()
    normalDelay, bulkDelay = 0.2, 20
    return members, gone
  end

  local function maxPerOwner(t, mark, owners)
    local most = 0
    for _, c in ipairs(owners) do most = math.max(most, #sent({ t = t, o = c.pid() }, mark)) end
    return most
  end

  it("answers a hello in a large guild with one delta per owner", function()
    local members = bigGuild()
    local newcomer = newClient("Neu Ankoemmling")
    local mark = #log + 1
    newcomer.sync:OnRosterReady()
    runTimers()

    assert.equals(1, maxPerOwner("D", mark, members))
    for i = 1, GUILD_SIZE do
      assert.equals(1, #newcomer.store:Lookup("Target Nummer" .. i), "owner " .. i)
    end
    -- online owners answer for their own data themselves
    for i = 3, GUILD_SIZE do
      local d = sent({ t = "D", o = members[i].pid() }, mark)
      assert.equals(1, #d, "owner " .. i)
      assert.equals(members[i], d[1].from)
    end
  end)

  it("requests newer data in a large guild with few requests and one answer", function()
    local members, gone = bigGuild()
    local x = gone[1]
    -- x changes its list on another computer; only the relay knows the new state
    for _, c in ipairs(members) do c.online = false end
    local relay = newClient("Relay Bote")
    relay.online = false
    x.online = true
    normalDelay, bulkDelay = 0, 0
    relay.online = true
    add(x, "enemy", "Neues Ziel", "frisch")
    runTimers() -- the relay missed x's first entry and fetches the full state
    assert.equals(2, relay.store:GetRev(x.pid()))
    x.online = false
    for _, c in ipairs(members) do if c ~= x and c ~= gone[2] then c.online = true end end
    normalDelay, bulkDelay = 0.2, 20

    local mark = #log + 1
    relay.sync:OnRosterReady()
    runTimers()
    -- requests are small and several of them still get one answer
    assert.truthy(#sent({ t = "R" }, mark) <= 3)
    assert.equals(1, #sent({ t = "D", o = x.pid() }, mark))
    for i = 3, GUILD_SIZE do
      assert.equals(1, #members[i].store:Lookup("Neues Ziel"), "member " .. i)
    end
  end)

  it("lets only the lowest player id send the data when announces cross", function()
    local same = function() return 0.5 end
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore", { random = same })
    local c = newClient("Anduin Wrynn", { random = same })
    add(x, "enemy", "Thrall Earthson", "pöbelt")
    x.online = false
    normalDelay, bulkDelay = 0.2, 20

    local b = newClient("Arthas Menethil")
    local mark = #log + 1
    b.sync:OnRosterReady()
    runTimers()
    assert.equals(2, #sent({ t = "A", o = x.pid() }, mark))
    local d = sent({ t = "D", o = x.pid() }, mark)
    assert.equals(1, #d)
    assert.equals(a.pid() < c.pid() and a or c, d[1].from)
    assert.equals(1, #b.store:Lookup("Thrall Earthson"))
  end)

  it("keeps a member that is online only on a twink no data mentioned yet", function()
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore", { mode = "manual" })
    add(x, "enemy", "Thrall Earthson", "pöbelt")
    x.online = false
    local roster = { ["jaina proudmoore"] = true, ["varian wrynn"] = true }
    a.sync:OnRoster(roster, true)

    -- the same player logs in on a twink and says hello; a manual client still learns the twink
    local twink = newClient("Twink Char", { sv = x.sv })
    twink.sync:OnRosterReady()
    roster["varian wrynn"] = nil
    roster["twink char"] = true
    assert.same({}, a.sync:OnRoster(roster, true))
    local m = a.store:Lookup("Thrall Earthson")
    assert.equals(1, #m)
    assert.equals("Twink Char", m[1].by)
  end)

  it("takes a pruned member back when it says hello and lets its data flow again", function()
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore")
    add(x, "enemy", "Thrall Earthson", "pöbelt")
    x.online = false
    assert.same({ x.pid() }, a.sync:OnRoster({ ["jaina proudmoore"] = true }, true))
    assert.is_true(a.store:IsPruned(x.pid()))

    -- x is back (the roster has not shown it yet) and changes its list while a is away
    a.online = false
    x.online = true
    add(x, "enemy", "Garrosh Hellscream", "ninjat")
    a.online = true
    local x2 = newClient("Varian Wrynn", { sv = x.sv })
    x.online = false
    x2.sync:OnRosterReady()
    runTimers()
    assert.is_false(a.store:IsPruned(x.pid()))
    assert.equals(1, #a.store:Lookup("Thrall Earthson"))
    assert.equals(1, #a.store:Lookup("Garrosh Hellscream"))
  end)

  it("answers a manual sync right after the automatic login hello of the same sender", function()
    local a = newClient("Jaina Proudmoore")
    add(a, "enemy", "Thrall Earthson", "pöbelt")
    local b = newClient("Arthas Menethil", { mode = "manual" })
    b.mode = "auto"
    b.sync:OnRosterReady()
    b.mode = "manual"
    runTimers()
    -- b was told nothing new; its manual sync a moment later is still answered
    clock = clock + 10
    local mark = #log + 1
    local full = hello(b, { [b.pid()] = 0 })
    full.full = true
    a.sync:OnMessage(full, "Arthas Menethil")
    runTimers()
    assert.equals(1, #sent({ from = a, t = "D" }, mark))
    -- a second manual sync within 300 s is not
    clock = clock + 10
    mark = #log + 1
    a.sync:OnMessage(copy(full), "Arthas Menethil")
    assert.equals(0, pendingTimers())
    runTimers()
    assert.equals(0, #sent({ from = a, t = "D" }, mark))
  end)

  it("drops a planned request when someone else asks for at least as much", function()
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore")
    add(x, "enemy", "Thrall Earthson", "eins")
    x.online = false
    local b = newClient("Arthas Menethil")
    local c = newClient("Anduin Wrynn")
    a.sync:OnMessage(hello(b, { [x.pid()] = 2 }), "Arthas Menethil")
    assert.truthy(pendingTimers() > 0)
    -- asking from a newer state does not cover us
    a.sync:OnMessage(request(c, { [x.pid()] = 2 }), "Anduin Wrynn")
    a.sync:OnMessage(request(c, { [x.pid()] = 0 }), "Anduin Wrynn")
    runTimers()
    assert.equals(0, #sent({ from = a, t = "R" }))
  end)

  it("still requests when the overheard request asks for less", function()
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore")
    add(x, "enemy", "Thrall Earthson", "eins")
    x.online = false
    local b = newClient("Arthas Menethil")
    local c = newClient("Anduin Wrynn")
    a.sync:OnMessage(hello(b, { [x.pid()] = 2 }), "Arthas Menethil")
    a.sync:OnMessage(request(c, { [x.pid()] = 2 }), "Anduin Wrynn")
    runTimers()
    local r = sent({ from = a, t = "R" })
    assert.equals(1, #r)
    assert.same({ [x.pid()] = 1 }, r[1].msg.want)
  end)

  it("drops a planned request or answer when an announce covers it", function()
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore")
    add(x, "enemy", "Thrall Earthson", "eins")
    x.online = false
    local b = newClient("Arthas Menethil")
    local announce = { t = "A", v = 1, from = b.pid(), o = x.pid(), rev = 2, base = 0 }

    a.sync:OnMessage(hello(b, { [x.pid()] = 2 }), "Arthas Menethil")
    assert.truthy(pendingTimers() > 0)
    a.sync:OnMessage(copy(announce), "Arthas Menethil")
    assert.equals(0, pendingTimers())

    -- a planned answer stops too
    local c = newClient("Anduin Wrynn")
    a.sync:OnMessage(request(c, { [x.pid()] = 0 }), "Anduin Wrynn")
    assert.truthy(pendingTimers() > 0)
    -- malformed announces that would otherwise cover it are dropped
    for _, field in ipairs({ { "rev", math.huge }, { "base", -1 }, { "v", 2 }, { "from", false } }) do
      local bad = copy(announce)
      bad[field[1]] = field[2]
      a.sync:OnMessage(bad, "Arthas Menethil")
      assert.truthy(pendingTimers() > 0)
    end
    a.sync:OnMessage(copy(announce), "Arthas Menethil")
    assert.equals(0, pendingTimers())
    assert.equals(1, a.store:GetRev(x.pid()))
  end)

  it("keeps a departed owner gone although others still advertise it", function()
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore")
    local c = newClient("Anduin Wrynn")
    add(x, "enemy", "Thrall Earthson", "pöbelt")
    x.online = false

    -- x left the guild; only a has seen the complete roster since
    local roster = { ["jaina proudmoore"] = true, ["anduin wrynn"] = true }
    assert.same({ x.pid() }, a.sync:OnRoster(roster, true))
    assert.equals(1, #c.store:Lookup("Thrall Earthson"))

    c.sync:OnRosterReady()
    runTimers()
    assert.same({}, a.store:Lookup("Thrall Earthson"))
    assert.equals(0, #sent({ from = a, t = "R" }))
    local d = c.store:DeltaFor(x.pid(), 0)
    d.t, d.v, d.from = "D", 1, c.pid()
    a.sync:OnMessage(d, "Anduin Wrynn")
    assert.same({}, a.store:Lookup("Thrall Earthson"))

    -- x rejoins: the next sync brings the data back
    roster["varian wrynn"] = true
    a.sync:OnRoster(roster, true)
    clock = clock + COOLDOWN + 1
    assert.is_true((c.sync:ManualSync()))
    runTimers()
    assert.equals(1, #a.store:Lookup("Thrall Earthson"))
  end)

  it("sends nothing for a guild change until the new guild's roster is ready", function()
    local a = newClient("Jaina Proudmoore", { guild = false })
    add(a, "enemy", "Thrall Earthson", "pöbelt")
    a.sync:OnRosterReady()
    assert.equals(0, #sent({ from = a }))

    a.store:SetCurrentCharacter("Jaina Proudmoore", GUILD)
    a.sync:OnGuildChanged()
    a.sync:OnRosterReady()
    assert.equals(1, #sent({ from = a, t = "H" }))

    -- pending work for the old guild is dropped
    local b = newClient("Arthas Menethil")
    a.sync:OnMessage(hello(b, {}), "Arthas Menethil")
    assert.truthy(pendingTimers() > 0)
    a.store:SetCurrentCharacter("Jaina Proudmoore", "Andere Gilde")
    a.sync:OnGuildChanged()
    assert.equals(0, pendingTimers())
    a.sync:OnRosterReady()
    assert.equals(2, #sent({ from = a, t = "H" }))
  end)

  it("sends newer data once even if several members request it", function()
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore")
    local c = newClient("Anduin Wrynn")
    local b = newClient("Arthas Menethil")
    add(x, "enemy", "Thrall Earthson", "eins")
    a.online, c.online = false, false
    add(x, "enemy", "Garrosh Hellscream", "zwei")
    x.online = false
    a.online, c.online = true, true

    local mark = #log + 1
    b.sync:OnRosterReady()
    runTimers()
    assert.truthy(#sent({ t = "R" }, mark) >= 1)
    assert.equals(1, #sent({ t = "D", o = x.pid() }, mark))
    assert.equals(1, #a.store:Lookup("Garrosh Hellscream"))
    assert.equals(1, #c.store:Lookup("Garrosh Hellscream"))
  end)

  it("drops a planned request when the data arrives first", function()
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore")
    add(x, "enemy", "Thrall Earthson", "eins")
    a.online = false
    add(x, "enemy", "Garrosh Hellscream", "zwei")
    x.online = false
    a.online = true

    local b = newClient("Arthas Menethil")
    a.sync:OnMessage(hello(b, { [x.pid()] = 2 }), "Arthas Menethil")
    assert.truthy(pendingTimers() > 0)
    local d = x.store:DeltaFor(x.pid(), 1)
    d.t, d.v, d.from = "D", 1, x.pid()
    a.sync:OnMessage(d, "Arthas Menethil")
    assert.equals(0, pendingTimers())
    runTimers()
    assert.equals(0, #sent({ from = a }))
    assert.equals(1, #a.store:Lookup("Garrosh Hellscream"))
  end)

  it("answers overlapping requests with one delta from the oldest base", function()
    local a = newClient("Jaina Proudmoore")
    add(a, "enemy", "Thrall Earthson", "eins")
    add(a, "enemy", "Garrosh Hellscream", "zwei")
    local b = newClient("Arthas Menethil")
    local c = newClient("Anduin Wrynn")
    a.sync:OnMessage(request(b, { [a.pid()] = 1 }), "Arthas Menethil")
    a.sync:OnMessage(request(c, { [a.pid()] = 0 }), "Anduin Wrynn")
    local mark = #log + 1
    runTimers()
    local d = sent({ from = a, t = "D" }, mark)
    assert.equals(1, #d)
    assert.equals(0, d[1].msg.base)
    assert.equals(2, #d[1].msg.e)
    assert.equals(1, #c.store:Lookup("Thrall Earthson"))
  end)

  it("ignores a second hello from the same sender within 300 s", function()
    local a = newClient("Jaina Proudmoore")
    local b = newClient("Thrall Earthson")
    add(a, "enemy", "Garrosh Hellscream", "ninjat")
    local t0 = clock

    a.sync:OnMessage(hello(b), "Thrall Earthson")
    assert.truthy(pendingTimers() > 0)
    local mark = #log + 1
    runTimers()
    assert.equals(1, #sent({ from = a, t = "D" }, mark))

    clock = t0 + 10
    a.sync:OnMessage(hello(b), "thrall-earthson")
    assert.equals(0, pendingTimers())

    clock = t0 + COOLDOWN + 1
    a.sync:OnMessage(hello(b), "Thrall Earthson")
    assert.truthy(pendingTimers() > 0)
    mark = #log + 1
    runTimers()
    assert.equals(1, #sent({ from = a, t = "D" }, mark))
  end)

  it("answers requests per sender and owner at most every 300 s", function()
    local c = newClient("Anduin Wrynn")
    local a = newClient("Jaina Proudmoore")
    local b = newClient("Thrall Earthson")
    add(c, "enemy", "Garrosh Hellscream", "ninjat")
    add(a, "enemy", "Varian Wrynn", "zu laut")
    c.online = false
    local t0 = clock

    a.sync:OnMessage(request(b, { [a.pid()] = 0 }), "Thrall Earthson")
    local mark = #log + 1
    runTimers()
    assert.equals(1, #sent({ from = a, t = "D", o = a.pid() }, mark))

    clock = t0 + 10
    a.sync:OnMessage(request(b, { [a.pid()] = 0 }), "Thrall Earthson")
    assert.equals(0, pendingTimers())
    -- another owner from the same sender is still answered
    a.sync:OnMessage(request(b, { [c.pid()] = 0 }), "Thrall Earthson")
    assert.truthy(pendingTimers() > 0)
    runTimers()

    clock = t0 + COOLDOWN + 1
    a.sync:OnMessage(request(b, { [a.pid()] = 0 }), "Thrall Earthson")
    mark = #log + 1
    runTimers()
    assert.equals(1, #sent({ from = a, t = "D", o = a.pid() }, mark))
  end)

  it("rate-limits the manual sync across reloads", function()
    local a = newClient("Jaina Proudmoore")
    local ok, rest = a.sync:ManualSync()
    assert.is_true(ok)
    assert.is_nil(rest)
    local h = sent({ from = a, t = "H" })
    assert.equals(1, #h)
    assert.is_true(h[1].msg.full)
    assert.equals("NORMAL", h[1].prio)
    assert.equals(clock, a.sv.lastManualSync)

    clock = clock + 100
    ok, rest = a.sync:ManualSync()
    assert.is_false(ok)
    assert.equals(200, rest)

    -- /reload: a fresh Sync on the same saved variables
    a.online = false
    local a2 = newClient("Jaina Proudmoore", { sv = a.sv })
    ok, rest = a2.sync:ManualSync()
    assert.is_false(ok)
    assert.equals(200, rest)
    assert.equals(1, #sent({ t = "H" }))

    clock = clock + 200
    assert.is_true((a2.sync:ManualSync()))
    assert.equals(2, #sent({ t = "H" }))
  end)

  it("reports the remaining manual sync cooldown", function()
    local a = newClient("Jaina Proudmoore")
    assert.equals(0, a.sync:CooldownRemaining())
    a.sync:ManualSync()
    assert.equals(COOLDOWN, a.sync:CooldownRemaining())
    clock = clock + 120
    assert.equals(180, a.sync:CooldownRemaining())
    clock = clock + 180
    assert.equals(0, a.sync:CooldownRemaining())
    -- a clock set back before the last sync never blocks
    a.sv.lastManualSync = clock + 50
    assert.equals(0, a.sync:CooldownRemaining())
  end)

  it("does nothing at all in off mode", function()
    local a = newClient("Jaina Proudmoore", { mode = "off" })
    local b = newClient("Arthas Menethil")
    add(a, "enemy", "Varian Wrynn", "zu laut")
    local ok, rest = a.sync:ManualSync()
    assert.is_false(ok)
    assert.equals(0, rest)

    local before = copy(a.sv)
    b.sync:OnRosterReady()
    add(b, "enemy", "Thrall Earthson", "pöbelt")
    a.sync:OnMessage(request(b, { [a.pid()] = 0 }), "Arthas Menethil")
    runTimers()
    assert.same(before, a.sv)
    assert.equals(0, #sent({ from = a }))
  end)

  it("only receives in manual mode", function()
    local a = newClient("Jaina Proudmoore", { mode = "manual" })
    add(a, "enemy", "Varian Wrynn", "zu laut")
    local b = newClient("Arthas Menethil")
    b.sync:OnRosterReady()
    a.sync:OnMessage(request(b, { [a.pid()] = 0 }), "Arthas Menethil")
    runTimers()
    assert.equals(0, #sent({ from = a }))
    assert.same({}, b.store:Lookup("Varian Wrynn"))

    -- data others send anyway is accepted
    add(b, "enemy", "Thrall Earthson", "pöbelt")
    assert.equals(1, #a.store:Lookup("Thrall Earthson"))
  end)

  it("runs a manual sync in both directions", function()
    local b = newClient("Arthas Menethil")
    add(b, "enemy", "Thrall Earthson", "pöbelt")
    local a = newClient("Jaina Proudmoore", { mode = "manual" })
    add(a, "enemy", "Varian Wrynn", "zu laut")

    assert.is_true((a.sync:ManualSync()))
    runTimers()
    assert.equals(1, #a.store:Lookup("Thrall Earthson"))
    assert.equals(1, #b.store:Lookup("Varian Wrynn"))

    -- once the cooldown is over, a manual client stops answering again
    clock = a.sv.lastManualSync + COOLDOWN
    local c = newClient("Anduin Wrynn")
    a.sync:OnMessage(request(c, { [a.pid()] = 0 }), "Anduin Wrynn")
    assert.equals(0, pendingTimers())
  end)

  it("drops malformed messages whole and without errors", function()
    local a = newClient("Jaina Proudmoore")
    add(a, "enemy", "Thrall Earthson", "pöbelt")
    add(a, "friendly", "Sylvanas Windrunner", "nett")
    a.online = false
    local b = newClient("Arthas Menethil")
    local valid = a.store:DeltaFor(a.pid(), 0)
    valid.t, valid.v, valid.from = "D", 1, a.pid()

    local function tooMany(m)
      local e = {}
      for i = 1, 2001 do e[i] = copy(m.e[1]) end
      m.e = e
    end
    local mutations = {
      function(m) m.e[1].reason = string.rep("x", 81) end,
      function(m) m.e[1].reason = 42 end,
      function(m) m.e = "kaputt" end,
      function(m) m.e = nil end,
      function(m) m.v = 2 end,
      function(m) m.v = nil end,
      function(m) m.o = nil end,
      function(m) m.o = 7 end,
      function(m) m.from = nil end,
      function(m) m.t = "X" end,
      function(m) m.rev = 0 / 0 end,
      function(m) m.rev = math.huge end,
      function(m) m.rev = -1 end,
      function(m) m.base = 0 / 0 end,
      function(m) m.base = "0" end,
      function(m) m.base = m.rev + 1 end,
      function(m) m.e[1].list = "neutral" end,
      function(m) m.e[1].name, m.e[1].key = "   ", nil end,
      function(m) m.e[1].name = 42 end,
      function(m) m.e[1].key = "garrosh hellscream" end,
      function(m) m.e[1].created = math.huge end,
      function(m) m.e[1].updated = 0 / 0 end,
      function(m) m.e[1].created = -5 end,
      function(m) m.e[1].rev = m.rev + 1 end,
      function(m) m.e[1].rev = -math.huge end,
      function(m) m.e[1].rev = m.base end,
      function(m) m.e[1].deleted = "no" end,
      function(m) m.e[1].origin = 42 end,
      function(m) m.e[1] = "eintrag" end,
      function(m) m.e[3], m.e[2] = m.e[2], nil end,
      function(m) m.e.extra = copy(m.e[1]) end,
      tooMany,
      function(m) m.chars = { ["x"] = "Jaina Proudmoore" } end,
      function(m) m.chars = "Jaina Proudmoore" end,
      function(m) m.lastChar = 42 end,
    }
    local before = copy(b.sv)
    for i, mutate in ipairs(mutations) do
      local m = copy(valid)
      mutate(m)
      b.sync:OnMessage(m, "Jaina Proudmoore")
      assert.same(before, b.sv, "mutation " .. i)
      assert.equals(0, pendingTimers(), "mutation " .. i)
    end
    for _, junk in ipairs({ "kaputt", 42, true, {}, { t = "D" } }) do
      b.sync:OnMessage(junk, "Jaina Proudmoore")
    end
    b.sync:OnMessage(nil, "Jaina Proudmoore")
    b.sync:OnMessage(copy(valid), nil)
    b.sync:OnMessage(copy(valid), 42)
    assert.same(before, b.sv)

    -- hellos and requests with bad digests are dropped too
    local good = hello(b, {})
    local badHellos = {
      function(m) m.d = { [a.pid()] = "5" } end,
      function(m) m.d = { [a.pid()] = -1 } end,
      function(m) m.d = { [a.pid()] = 0 / 0 } end,
      function(m) m.d = { [1] = 5 } end,
      function(m) m.d = nil end,
      function(m) m.pid = nil end,
      function(m) m.char = nil end,
      function(m) m.chars = "Arthas Menethil" end,
      function(m) m.chars = { 42 } end,
      function(m) m.full = "yes" end,
    }
    b.online = false
    local a2 = newClient("Jaina Proudmoore", { sv = a.sv })
    for i, mutate in ipairs(badHellos) do
      local m = copy(good)
      mutate(m)
      a2.sync:OnMessage(m, "Arthas Menethil")
      assert.equals(0, pendingTimers(), "hello " .. i)
    end
    for i, want in ipairs({ { [a.pid()] = 0 / 0 }, { [a.pid()] = math.huge }, "alles", { [5] = 0 } }) do
      a2.sync:OnMessage(request(b, want), "Arthas Menethil")
      assert.equals(0, pendingTimers(), "request " .. i)
    end

    -- the untouched messages are fine
    a2.sync:OnMessage(copy(good), "Arthas Menethil")
    assert.truthy(pendingTimers() > 0)
    b.sync:OnMessage(copy(valid), "Jaina Proudmoore")
    assert.equals(1, #b.store:Lookup("Thrall Earthson"))
  end)

  it("ignores messages from the own character and without a guild", function()
    local a = newClient("Jaina Proudmoore")
    add(a, "enemy", "Thrall Earthson", "pöbelt")
    local b = newClient("Arthas Menethil")
    a.sync:OnMessage(hello(b, {}), "Jaina-Proudmoore")
    assert.equals(0, pendingTimers())

    local loner = newClient("Varian Wrynn", { guild = false })
    loner.sync:OnRosterReady()
    assert.is_false((loner.sync:ManualSync()))
    local before = copy(loner.sv)
    local d = a.store:DeltaFor(a.pid(), 0)
    d.t, d.v, d.from = "D", 1, a.pid()
    loner.sync:OnMessage(d, "Jaina Proudmoore")
    loner.sync:OnMessage(hello(b, {}), "Arthas Menethil")
    assert.same(before, loner.sv)
    assert.equals(0, pendingTimers())
    assert.equals(0, #sent({ from = loner }))
  end)

  it("restores the own identity after a reinstall from the guild", function()
    local a = newClient("Jaina Proudmoore")
    local c = newClient("Anduin Wrynn")
    add(a, "enemy", "Thrall Earthson", "pöbelt")
    add(a, "friendly", "Sylvanas Windrunner", "nett")
    local oldId = a.pid()
    a.online = false

    local b = newClient("Arthas Menethil")
    add(b, "enemy", "Garrosh Hellscream", "ninjat")
    local bId = b.pid()

    clock = clock + COOLDOWN + 1
    local fresh = newClient("Jaina Proudmoore")
    assert.are_not.equal(oldId, fresh.pid())
    fresh.sync:OnRosterReady()
    runTimers()

    assert.equals(oldId, fresh.pid())
    local m = fresh.store:Lookup("Thrall Earthson", "enemy")
    assert.equals(1, #m)
    assert.is_true(m[1].isOwn)
    assert.equals(1, #fresh.store:Lookup("Sylvanas Windrunner", "friendly"))
    assert.equals(2, fresh.store:GetRev(oldId))

    -- another character that received the same data keeps its own identity
    assert.equals(bId, b.pid())
    local mb = b.store:Lookup("Thrall Earthson")
    assert.equals(1, #mb)
    assert.is_false(mb[1].isOwn)
    assert.equals(oldId, mb[1].ownerId)
    assert.equals(1, #c.store:Lookup("Garrosh Hellscream"))
  end)

  it("takes over a newer own state relayed by the guild", function()
    local a = newClient("Jaina Proudmoore")
    local c = newClient("Anduin Wrynn")
    add(a, "enemy", "Thrall Earthson", "pöbelt")
    a.online = false

    -- the same account on another computer changes the list while this one is offline
    local other = newClient("Jaina Proudmoore", { sv = copy(a.sv) })
    add(other, "enemy", "Garrosh Hellscream", "ninjat")
    other.online = false
    assert.equals(2, c.store:GetRev(a.pid()))

    a.online = true
    a.sync:OnRosterReady()
    runTimers()
    assert.equals(2, a.store:GetRev(a.pid()))
    local m = a.store:Lookup("Garrosh Hellscream")
    assert.equals(1, #m)
    assert.is_true(m[1].isOwn)
  end)

  it("never sends characters from another guild", function()
    local sv = {}
    local a = newClient("Jaina Proudmoore", { sv = sv })
    -- imported before the twink was ever logged in, so its name survived as origin
    assert.equals("added", a.store:ImportEntry({
      name = "Garrosh Hellscream", list = "enemy", reason = "alt", origin = "Alt Twinkling",
      created = clock, updated = clock,
    }))
    a.store:SetCurrentCharacter("Alt Twinkling", "Andere Gilde")
    a.store:SetCurrentCharacter("Main Hauptmann", GUILD)
    a.store:SetCurrentCharacter("Jaina Proudmoore", GUILD)

    local c = newClient("Anduin Wrynn")
    a.sync:OnRosterReady()
    add(a, "enemy", "Thrall Earthson", "pöbelt")
    runTimers()
    a.sync:ManualSync()
    local b = newClient("Arthas Menethil")
    b.sync:OnRosterReady()
    runTimers()
    assert.equals(1, #b.store:Lookup("Garrosh Hellscream"))
    assert.equals(1, #c.store:Lookup("Thrall Earthson"))

    local h = sent({ from = a, t = "H" })
    assert.equals(2, #h)
    assert.same({ "Jaina Proudmoore", "Main Hauptmann" }, h[1].msg.chars)
    assert.truthy(#sent({ t = "D", o = a.pid() }) >= 2)

    local function mentions(v, key)
      if type(v) == "string" then return ns.Names.Normalize(v) == key end
      if type(v) ~= "table" then return false end
      for k, x in pairs(v) do
        if mentions(k, key) or mentions(x, key) then return true end
      end
      return false
    end
    for _, l in ipairs(log) do
      assert.is_false(mentions(l.msg, "alt twinkling"))
    end
    -- the guild still learns the main from this guild
    assert.equals("main hauptmann", ns.Names.Normalize(b.store:GetOwners()[a.pid()].chars["main hauptmann"]))
  end)

  it("drops owners that left the guild", function()
    local x = newClient("Varian Wrynn")
    local a = newClient("Jaina Proudmoore")
    add(x, "enemy", "Thrall Earthson", "pöbelt")
    assert.equals(1, #a.store:Lookup("Thrall Earthson"))

    a.sync:OnRoster({ ["varian wrynn"] = true, ["jaina proudmoore"] = true }, true)
    assert.equals(1, #a.store:Lookup("Thrall Earthson"))
    local removed = a.sync:OnRoster({ ["jaina proudmoore"] = true }, true)
    assert.same({ x.pid() }, removed)
    assert.same({}, a.store:Lookup("Thrall Earthson"))
  end)
end)
