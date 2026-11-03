local wow = require("tests.helpers.wow")

describe("Transport", function()
  local ns, comm, received, transport

  local function newComm()
    local c = { sent = {}, registered = {} }
    function c.SendCommMessage(_, prefix, text, distribution, target, prio)
      table.insert(c.sent, { prefix = prefix, text = text, distribution = distribution, target = target, prio = prio })
    end
    function c.RegisterComm(_, prefix, handler)
      table.insert(c.registered, { prefix = prefix, handler = handler })
    end
    return c
  end

  local function decoded(entry)
    return ns.Codec.Decode(entry.text, "comm")
  end

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Codec.lua", "Core/Transport.lua")
    wow.inGuild = true
    comm = newComm()
    received = {}
    transport = ns.Transport.New({
      comm = comm,
      onMessage = function(msg, sender) table.insert(received, { msg = msg, sender = sender }) end,
    })
  end)

  describe("Send", function()
    it("sends an encoded message to the guild channel", function()
      transport:Send({ t = "H", n = 1 }, "NORMAL")
      assert.equals(1, #comm.sent)
      local sent = comm.sent[1]
      assert.equals(ns.Const.PREFIX, sent.prefix)
      assert.equals("GUILD", sent.distribution)
      assert.is_nil(sent.target)
      assert.equals("NORMAL", sent.prio)
      assert.same({ t = "H", n = 1 }, decoded(sent))
    end)

    it("passes the priority through", function()
      transport:Send({ t = "D" }, "BULK")
      assert.equals("BULK", comm.sent[1].prio)
    end)

    it("drops messages outside a guild", function()
      wow.inGuild = false
      transport:Send({ t = "H" }, "NORMAL")
      wow.lockdown = true
      transport:Send({ t = "H" }, "NORMAL")
      wow.lockdown = false
      transport:Flush()
      assert.equals(0, #comm.sent)
    end)

    it("queues during a lockdown and sends in order on Flush", function()
      wow.lockdown = true
      transport:Send({ n = 1 }, "NORMAL")
      transport:Send({ n = 2 }, "BULK")
      transport:Flush()
      assert.equals(0, #comm.sent)

      wow.lockdown = false
      transport:Flush()
      assert.equals(2, #comm.sent)
      assert.same({ n = 1 }, decoded(comm.sent[1]))
      assert.equals("NORMAL", comm.sent[1].prio)
      assert.same({ n = 2 }, decoded(comm.sent[2]))
      assert.equals("BULK", comm.sent[2].prio)

      transport:Flush()
      assert.equals(2, #comm.sent)
    end)

    it("keeps only the newest 50 queued messages", function()
      wow.lockdown = true
      for i = 1, 60 do transport:Send({ n = i }, "NORMAL") end
      wow.lockdown = false
      transport:Flush()
      assert.equals(50, #comm.sent)
      assert.same({ n = 11 }, decoded(comm.sent[1]))
      assert.same({ n = 60 }, decoded(comm.sent[50]))
    end)

    it("snapshots a queued message against later mutation", function()
      wow.lockdown = true
      local msg = { n = 1 }
      transport:Send(msg, "NORMAL")
      msg.n = 2
      wow.lockdown = false
      transport:Flush()
      assert.same({ n = 1 }, decoded(comm.sent[1]))
    end)

    it("discards the queue on Flush when the guild was left", function()
      wow.lockdown = true
      transport:Send({ n = 1 }, "NORMAL")
      wow.lockdown = false
      wow.inGuild = false
      transport:Flush()
      wow.inGuild = true
      transport:Flush()
      assert.equals(0, #comm.sent)
    end)

    it("sends still queued messages first when the lockdown ended before the next Flush", function()
      wow.lockdown = true
      transport:Send({ n = 1 }, "NORMAL")
      transport:Send({ n = 2 }, "BULK")
      wow.lockdown = false
      transport:Send({ n = 3 }, "NORMAL")
      assert.equals(3, #comm.sent)
      for i = 1, 3 do assert.same({ n = i }, decoded(comm.sent[i])) end
      transport:Flush()
      assert.equals(3, #comm.sent)
    end)

    it("treats a missing lockdown API as no lockdown", function()
      C_ChatInfo.InChatMessagingLockdown = nil
      transport:Send({ n = 1 }, "NORMAL")
      assert.equals(1, #comm.sent)
    end)
  end)

  describe("OnComm", function()
    local function payload(tbl) return ns.Codec.Encode(tbl, "comm") end

    it("delivers decoded guild messages with the sender", function()
      transport:OnComm(ns.Const.PREFIX, payload({ t = "R", x = 1 }), "GUILD", "Bob-Realm")
      assert.equals(1, #received)
      assert.same({ t = "R", x = 1 }, received[1].msg)
      assert.equals("Bob-Realm", received[1].sender)
    end)

    it("ignores other distributions and prefixes", function()
      transport:OnComm(ns.Const.PREFIX, payload({ t = "R" }), "WHISPER", "Bob")
      transport:OnComm("Other", payload({ t = "R" }), "GUILD", "Bob")
      assert.equals(0, #received)
    end)

    it("silently drops garbage and non-table payloads", function()
      assert.has_no.errors(function()
        transport:OnComm(ns.Const.PREFIX, "garbage!!", "GUILD", "Bob")
        transport:OnComm(ns.Const.PREFIX, "", "GUILD", "Bob")
        transport:OnComm(ns.Const.PREFIX, nil, "GUILD", "Bob")
        transport:OnComm(ns.Const.PREFIX, payload(42), "GUILD", "Bob")
        transport:OnComm(ns.Const.PREFIX, payload("text"), "GUILD", "Bob")
      end)
      assert.equals(0, #received)
    end)

    it("keeps receiving after a handler error", function()
      local calls = 0
      local t = ns.Transport.New({ comm = comm, onMessage = function()
        calls = calls + 1
        error("boom")
      end })
      assert.has_no.errors(function()
        t:OnComm(ns.Const.PREFIX, payload({ t = "R" }), "GUILD", "Bob")
        t:OnComm(ns.Const.PREFIX, payload({ t = "R" }), "GUILD", "Bob")
      end)
      assert.equals(2, calls)
    end)

    it("reports a handler error to the client's error handler", function()
      local reported = {}
      _G.geterrorhandler = function() return function(err) reported[#reported + 1] = err end end
      local t = ns.Transport.New({ comm = comm, onMessage = function() error("boom") end })
      t:OnComm(ns.Const.PREFIX, payload({ t = "R" }), "GUILD", "Bob")
      assert.equals(1, #reported)
      assert.truthy(tostring(reported[1]):find("boom", 1, true))
    end)
  end)

  describe("Register", function()
    it("registers a function handler for the prefix that routes to OnComm", function()
      transport:Register()
      assert.equals(1, #comm.registered)
      assert.equals(ns.Const.PREFIX, comm.registered[1].prefix)
      assert.is_function(comm.registered[1].handler)

      comm.registered[1].handler(ns.Const.PREFIX, ns.Codec.Encode({ t = "A" }, "comm"), "GUILD", "Eve")
      assert.equals(1, #received)
      assert.same({ t = "A" }, received[1].msg)
      assert.equals("Eve", received[1].sender)
    end)
  end)
end)
