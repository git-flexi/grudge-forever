local wow = require("tests.helpers.wow")

describe("Store", function()
  local ns, sv, clock, seq, store
  local GUILD = "Die Gilde"
  local DAY = 86400

  local function deps()
    return {
      now = function() return clock end,
      random = function(n) seq = seq + 1; return (seq % n) + 1 end,
    }
  end

  local function newStore(s) return ns.Store.New(s, deps()) end

  local function entry(list, name, rev, extra)
    local e = {
      key = ns.Names.Normalize(name), name = ns.Names.Display(name), list = list, reason = "grund",
      created = clock, updated = clock, rev = rev, deleted = false,
    }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
  end

  -- Feeds an owner into the current guild's cache through the public sync path.
  local function giveOwner(ownerId, rev, entries, lastChar, chars)
    return store:ApplyDelta({
      o = ownerId, rev = rev, base = 0, e = entries,
      lastChar = lastChar or "Jaina Proudmoore",
      chars = chars or { ["jaina proudmoore"] = "Jaina Proudmoore" },
    })
  end

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/Store.lua")
    sv = {}
    clock = 1700000000
    seq = 0
    store = newStore(sv)
    store:SetCurrentCharacter("Arthas Menethil", GUILD)
  end)

  it("creates a 16 hex player id once and keeps it", function()
    local id = store:GetPlayerId()
    assert.truthy(id:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$"))
    assert.equals(id, newStore(sv):GetPlayerId())
  end)

  it("adds and updates an own entry and bumps the revision", function()
    local e = store:AddOrUpdate("friendly", "Thrall-Earthson", "pöbelt")
    assert.equals("thrall earthson", e.key)
    assert.equals("Thrall Earthson", e.name)
    assert.equals("Arthas Menethil", e.char)
    assert.equals(1, sv.own.rev)
    assert.equals(1, e.rev)
    clock = clock + 10
    local e2 = store:AddOrUpdate("friendly", "Thrall Earthson", "ganz lieb")
    assert.equals(e, e2)
    assert.equals("ganz lieb", e2.reason)
    assert.equals(2, sv.own.rev)
    assert.equals(2, e2.rev)
    assert.equals(clock, e2.updated)
    assert.equals(1, #store:GetOwnEntries())
  end)

  it("keeps the same player on different lists as separate entries", function()
    store:AddOrUpdate("friendly", "Thrall Earthson", "a")
    store:AddOrUpdate("enemy", "Thrall Earthson", "b")
    assert.equals(2, #store:GetOwnEntries())
    assert.equals(2, #store:Lookup("Thrall Earthson"))
    assert.equals(1, #store:Lookup("Thrall Earthson", "enemy"))
  end)

  it("rejects invalid input", function()
    local e, err = store:AddOrUpdate("friendly", "Thrall Earthson", string.rep("x", 81))
    assert.is_nil(e); assert.equals("reason_too_long", err)
    e, err = store:AddOrUpdate("foo", "Thrall Earthson", "x")
    assert.is_nil(e); assert.equals("invalid_list", err)
    e, err = store:AddOrUpdate("friendly", "   ", "x")
    assert.is_nil(e); assert.equals("invalid_name", err)
    e, err = store:AddOrUpdate("friendly", wow.secret("Thrall Earthson"), "x")
    assert.is_nil(e); assert.equals("invalid_name", err)
    assert.equals(0, sv.own.rev)
    assert.is_table(store:AddOrUpdate("friendly", "Thrall Earthson", string.rep("x", 80)))
  end)

  it("counts reason length in characters, not bytes", function()
    assert.is_table(store:AddOrUpdate("enemy", "Thrall Earthson", string.rep("ö", 80)))
    local e, err = store:AddOrUpdate("enemy", "Thrall Earthson", string.rep("ö", 81))
    assert.is_nil(e); assert.equals("reason_too_long", err)
  end)

  it("deletes into a tombstone and revives it on re-add", function()
    local id = store:GetPlayerId()
    store:AddOrUpdate("enemy", "Thrall Earthson", "pöbelt")
    clock = clock + 10
    assert.is_true(store:Delete("enemy", "Thrall-Earthson"))
    assert.same({}, store:GetOwnEntries())
    assert.same({}, store:Lookup("Thrall Earthson"))
    local tomb = store:DeltaFor(id, 0).e[1]
    assert.is_true(tomb.deleted)
    assert.equals("", tomb.reason)
    assert.equals(2, tomb.rev)
    assert.equals(clock, tomb.updated)
    assert.is_false(store:Delete("enemy", "Thrall Earthson"))
    assert.is_false(store:Delete("enemy", "Nobody Known"))
    local revived = store:AddOrUpdate("enemy", "Thrall Earthson", "wieder da")
    assert.is_false(revived.deleted)
    assert.equals(3, revived.rev)
    assert.equals(1, #store:GetOwnEntries())
  end)

  it("looks up own entries and current guild owners, own first, other guilds hidden", function()
    store:AddOrUpdate("enemy", "Thrall Earthson", "mein")
    clock = clock + 10
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("enemy", "Thrall Earthson", 1) }, "Jaina Proudmoore")
    clock = clock + 10
    giveOwner("bbbbbbbbbbbbbbbb", 1, { entry("enemy", "Thrall Earthson", 1) }, "Sylvanas Windrunner",
      { ["sylvanas windrunner"] = "Sylvanas Windrunner" })
    local ms = store:Lookup("Thrall-Earthson", "enemy")
    assert.equals(3, #ms)
    assert.is_true(ms[1].isOwn)
    assert.equals("Arthas Menethil", ms[1].by)
    assert.equals(store:GetPlayerId(), ms[1].ownerId)
    assert.equals("bbbbbbbbbbbbbbbb", ms[2].ownerId)
    assert.equals("Sylvanas Windrunner", ms[2].by)
    assert.equals("aaaaaaaaaaaaaaaa", ms[3].ownerId)
    assert.is_false(ms[3].isOwn)

    store:SetCurrentCharacter("Arthas Menethil", "Andere Gilde")
    assert.equals(1, #store:Lookup("Thrall Earthson"))
    assert.same({}, store:GetOwners())
    store:SetCurrentCharacter("Arthas Menethil", GUILD)
    assert.equals(3, #store:Lookup("Thrall Earthson"))
  end)

  it("ignores owner tombstones in lookups", function()
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("enemy", "Thrall Earthson", 1, { deleted = true, reason = "" }) })
    assert.same({}, store:Lookup("Thrall Earthson"))
  end)

  it("mutes per player and list, flagging every match", function()
    store:AddOrUpdate("friendly", "Thrall Earthson", "mein")
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("friendly", "Thrall Earthson", 1) })
    giveOwner("bbbbbbbbbbbbbbbb", 1, { entry("enemy", "Thrall Earthson", 1) }, "Sylvanas Windrunner",
      { ["sylvanas windrunner"] = "Sylvanas Windrunner" })
    assert.is_false(store:IsMuted("friendly", "Thrall Earthson"))
    store:SetMuted("friendly", "Thrall Earthson", true)
    assert.is_true(store:IsMuted("friendly", "Thrall-Earthson"))
    assert.is_true(sv.mutes["friendly:thrall earthson"])
    local friendly = store:Lookup("Thrall Earthson", "friendly")
    assert.equals(2, #friendly)
    for _, m in ipairs(friendly) do assert.is_true(m.muted) end
    assert.is_false(store:Lookup("Thrall Earthson", "enemy")[1].muted)
    store:SetMuted("friendly", "Thrall Earthson", false)
    assert.is_false(store:IsMuted("friendly", "Thrall Earthson"))
    assert.is_nil(sv.mutes["friendly:thrall earthson"])
  end)

  it("adopts owner entries once, with origin, as one revision", function()
    giveOwner("aaaaaaaaaaaaaaaa", 5, {
      entry("enemy", "Thrall Earthson", 3),
      entry("friendly", "Cairne Bloodhoof", 4),
      entry("enemy", "Gone Player", 5, { deleted = true, reason = "" }),
    }, "Jaina Proudmoore")
    clock = clock + 10
    assert.equals(2, store:Adopt("aaaaaaaaaaaaaaaa"))
    assert.equals(1, sv.own.rev)
    local own = store:GetOwnEntries()
    assert.equals(2, #own)
    for _, e in ipairs(own) do
      assert.equals("Jaina Proudmoore", e.origin)
      assert.equals("Arthas Menethil", e.char)
      assert.equals(1, e.rev)
      assert.is_false(e.deleted)
    end
    assert.equals(0, store:Adopt("aaaaaaaaaaaaaaaa"))
    assert.equals(1, sv.own.rev)
    assert.equals(0, store:Adopt("unknownunknownun"))
  end)

  it("adopts a single entry and keeps an existing origin and own entries", function()
    giveOwner("aaaaaaaaaaaaaaaa", 2, {
      entry("enemy", "Thrall Earthson", 1, { origin = "Sylvanas Windrunner" }),
      entry("enemy", "Cairne Bloodhoof", 2),
    })
    store:AddOrUpdate("enemy", "Cairne Bloodhoof", "meins")
    assert.equals(0, store:Adopt("aaaaaaaaaaaaaaaa", "enemy:cairne bloodhoof"))
    assert.equals("meins", store:Lookup("Cairne Bloodhoof", "enemy")[1].entry.reason)
    assert.equals(1, store:Adopt("aaaaaaaaaaaaaaaa", "enemy:thrall earthson"))
    assert.equals("Sylvanas Windrunner", store:Lookup("Thrall Earthson", "enemy")[1].entry.origin)
  end)

  it("builds the entry id Adopt expects from a list and key", function()
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("enemy", "Thrall Earthson", 1) })
    local e = store:Lookup("Thrall Earthson", "enemy")[1].entry
    assert.equals("enemy:thrall earthson", ns.Store.EntryId(e.list, e.key))
    assert.equals(1, store:Adopt("aaaaaaaaaaaaaaaa", ns.Store.EntryId(e.list, e.key)))
  end)

  it("tracks revisions, digest and rejects stale or gapped deltas", function()
    local id = store:GetPlayerId()
    store:AddOrUpdate("enemy", "Thrall Earthson", "x")
    assert.equals("applied", giveOwner("aaaaaaaaaaaaaaaa", 3, { entry("enemy", "Cairne Bloodhoof", 3) }))
    assert.equals(3, store:GetRev("aaaaaaaaaaaaaaaa"))
    assert.equals(1, store:GetRev(id))
    assert.equals(0, store:GetRev("unknownunknownun"))
    assert.same({ [id] = 1, aaaaaaaaaaaaaaaa = 3 }, store:Digest())
    assert.equals("stale", store:ApplyDelta({ o = "aaaaaaaaaaaaaaaa", rev = 3, base = 0, e = {} }))
    assert.equals("stale", store:ApplyDelta({ o = "aaaaaaaaaaaaaaaa", rev = 2, base = 0, e = {} }))
    assert.equals("need_full", store:ApplyDelta({ o = "aaaaaaaaaaaaaaaa", rev = 9, base = 5, e = {} }))
    assert.equals(3, store:GetRev("aaaaaaaaaaaaaaaa"))
    assert.equals("applied", store:ApplyDelta({
      o = "aaaaaaaaaaaaaaaa", rev = 5, base = 3, lastChar = "Sylvanas Windrunner",
      chars = { ["sylvanas windrunner"] = "Sylvanas Windrunner" },
      e = { entry("enemy", "Thrall Earthson", 5) },
    }))
    local owner = store:GetOwners().aaaaaaaaaaaaaaaa
    assert.equals(5, owner.rev)
    assert.equals("Sylvanas Windrunner", owner.lastChar)
    assert.equals("Jaina Proudmoore", owner.chars["jaina proudmoore"])
    assert.equals("Sylvanas Windrunner", owner.chars["sylvanas windrunner"])
    assert.is_table(owner.entries["enemy:cairne bloodhoof"])
    assert.is_table(owner.entries["enemy:thrall earthson"])
  end)

  it("applies a delta addressed to the own id into own and keeps the local char", function()
    local id = store:GetPlayerId()
    local mine = store:AddOrUpdate("enemy", "Thrall Earthson", "x")
    assert.equals("applied", store:ApplyDelta({
      o = id, rev = 4, base = 1, lastChar = "Zweit Charakter", chars = {},
      e = {
        entry("enemy", "Thrall Earthson", 3, { reason = "neu" }),
        entry("enemy", "Cairne Bloodhoof", 4),
      },
    }))
    assert.equals(4, sv.own.rev)
    assert.equals("neu", mine.reason)
    assert.equals("Arthas Menethil", sv.own.entries["enemy:thrall earthson"].char)
    assert.equals("Zweit Charakter", sv.own.entries["enemy:cairne bloodhoof"].char)
    assert.same({}, store:GetOwners())
  end)

  it("builds deltas without char and with only current guild chars", function()
    local id = store:GetPlayerId()
    store:SetCurrentCharacter("Jaina Proudmoore", "Andere Gilde")
    store:SetCurrentCharacter("Arthas Menethil", GUILD)
    store:SetCurrentCharacter("Muradin Bronzebeard", GUILD)
    store:AddOrUpdate("enemy", "Thrall Earthson", "a")
    store:AddOrUpdate("enemy", "Cairne Bloodhoof", "b")
    store:AddOrUpdate("friendly", "Baine Bloodhoof", "c")
    local d = store:DeltaFor(id, 0)
    assert.equals(id, d.o)
    assert.equals(3, d.rev)
    assert.equals(0, d.base)
    assert.equals("Muradin Bronzebeard", d.lastChar)
    assert.same({ ["arthas menethil"] = "Arthas Menethil", ["muradin bronzebeard"] = "Muradin Bronzebeard" }, d.chars)
    assert.equals(3, #d.e)
    for _, e in ipairs(d.e) do assert.is_nil(e.char) end
    assert.equals(1, #store:DeltaFor(id, 2).e)
    assert.equals(0, #store:DeltaFor(id, 3).e)
    assert.is_nil(store:DeltaFor("unknownunknownun", 0))
  end)

  it("builds deltas for cached owners", function()
    giveOwner("aaaaaaaaaaaaaaaa", 4, { entry("enemy", "Thrall Earthson", 2), entry("enemy", "Cairne Bloodhoof", 4) })
    local d = store:DeltaFor("aaaaaaaaaaaaaaaa", 2)
    assert.equals(4, d.rev)
    assert.equals(2, d.base)
    assert.equals("Jaina Proudmoore", d.lastChar)
    assert.equals(1, #d.e)
    assert.equals("cairne bloodhoof", d.e[1].key)
  end)

  it("claims an owner identity only on a fresh install", function()
    giveOwner("aaaaaaaaaaaaaaaa", 3, { entry("enemy", "Thrall Earthson", 3) }, "Arthas Menethil",
      { ["arthas menethil"] = "Arthas Menethil" })
    assert.is_true(store:TryClaimIdentity("aaaaaaaaaaaaaaaa"))
    assert.equals("aaaaaaaaaaaaaaaa", store:GetPlayerId())
    assert.equals(3, sv.own.rev)
    assert.equals(1, #store:GetOwnEntries())
    assert.same({}, store:GetOwners())
    assert.equals("aaaaaaaaaaaaaaaa", newStore(sv):GetPlayerId())

    -- own data present -> refuse
    local sv2 = {}
    local s2 = newStore(sv2)
    s2:SetCurrentCharacter("Arthas Menethil", GUILD)
    s2:AddOrUpdate("enemy", "Cairne Bloodhoof", "x")
    s2:ApplyDelta({ o = "cccccccccccccccc", rev = 1, base = 0, e = {}, lastChar = "Arthas Menethil",
      chars = { ["arthas menethil"] = "Arthas Menethil" } })
    assert.is_false(s2:TryClaimIdentity("cccccccccccccccc"))
    assert.not_equals("cccccccccccccccc", s2:GetPlayerId())
  end)

  it("refuses to claim an identity without the current character or owner", function()
    giveOwner("aaaaaaaaaaaaaaaa", 3, { entry("enemy", "Thrall Earthson", 3) })
    local id = store:GetPlayerId()
    assert.is_false(store:TryClaimIdentity("aaaaaaaaaaaaaaaa"))
    assert.is_false(store:TryClaimIdentity("unknownunknownun"))
    assert.equals(id, store:GetPlayerId())
    assert.is_table(store:GetOwners().aaaaaaaaaaaaaaaa)
  end)

  it("prunes owners by roster only after they were seen and the roster is complete", function()
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("enemy", "Thrall Earthson", 1) })
    assert.same({}, store:PruneByRoster({}, true))
    assert.is_table(store:GetOwners().aaaaaaaaaaaaaaaa)
    assert.is_false(store:GetOwners().aaaaaaaaaaaaaaaa.seenInRoster)
    assert.same({}, store:PruneByRoster({ x = true }, false))
    assert.is_table(store:GetOwners().aaaaaaaaaaaaaaaa)
    assert.same({}, store:PruneByRoster({ ["jaina proudmoore"] = true }, false))
    assert.is_true(store:GetOwners().aaaaaaaaaaaaaaaa.seenInRoster)
    assert.same({}, store:PruneByRoster({ x = true }, false))
    assert.is_table(store:GetOwners().aaaaaaaaaaaaaaaa)
    assert.same({ "aaaaaaaaaaaaaaaa" }, store:PruneByRoster({ x = true }, true))
    assert.same({}, store:GetOwners())
    assert.same({}, store:Lookup("Thrall Earthson"))
  end)

  it("prunes every absent owner once the own character proves the roster format", function()
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("enemy", "Thrall Earthson", 1) })
    giveOwner("bbbbbbbbbbbbbbbb", 1, { entry("enemy", "Cairne Bloodhoof", 1) }, "Baine Bloodhoof",
      { ["baine bloodhoof"] = "Baine Bloodhoof" })
    local roster = { ["arthas menethil"] = true, ["baine bloodhoof"] = true }
    assert.same({}, store:PruneByRoster(roster, false))
    assert.is_false(store:IsPruned("aaaaaaaaaaaaaaaa"))
    assert.same({ "aaaaaaaaaaaaaaaa" }, store:PruneByRoster(roster, true))
    assert.is_true(store:IsPruned("aaaaaaaaaaaaaaaa"))
    assert.is_false(store:IsPruned("bbbbbbbbbbbbbbbb"))
    assert.same({}, store:Lookup("Thrall Earthson"))
    assert.equals(1, #store:Lookup("Cairne Bloodhoof"))
    -- pruned only for this guild
    store:SetCurrentCharacter("Jaina Proudmoore", "Andere Gilde")
    assert.is_false(store:IsPruned("aaaaaaaaaaaaaaaa"))
  end)

  it("welcomes a pruned owner back once one of its characters is in a complete roster", function()
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("enemy", "Thrall Earthson", 1) })
    store:PruneByRoster({ ["arthas menethil"] = true }, true)
    assert.is_true(store:IsPruned("aaaaaaaaaaaaaaaa"))
    store:PruneByRoster({ ["arthas menethil"] = true, ["jaina proudmoore"] = true }, false)
    assert.is_true(store:IsPruned("aaaaaaaaaaaaaaaa"))
    store:PruneByRoster({ ["arthas menethil"] = true, ["jaina proudmoore"] = true }, true)
    assert.is_false(store:IsPruned("aaaaaaaaaaaaaaaa"))
  end)

  it("forgets pruned owners after 90 days", function()
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("enemy", "Thrall Earthson", 1) })
    store:PruneByRoster({ ["arthas menethil"] = true }, true)
    clock = clock + 90 * DAY
    store:PruneTombstones()
    assert.is_true(store:IsPruned("aaaaaaaaaaaaaaaa"))
    clock = clock + 1
    store:PruneTombstones()
    assert.is_false(store:IsPruned("aaaaaaaaaaaaaaaa"))
  end)

  it("shares an adopted origin only in the guild it was adopted in, never an imported one", function()
    local id = store:GetPlayerId()
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("enemy", "Thrall Earthson", 1) }, "Jaina Proudmoore")
    assert.equals(1, store:Adopt("aaaaaaaaaaaaaaaa"))
    assert.equals("added", store:ImportEntry({
      name = "Cairne Bloodhoof", list = "enemy", reason = "x", origin = "Sylvanas Windrunner",
      created = clock, updated = clock,
    }))
    local function origins()
      local out = {}
      for _, e in ipairs(store:DeltaFor(id, 0).e) do out[e.key] = e.origin or false end
      return out
    end
    assert.same({ ["thrall earthson"] = "Jaina Proudmoore", ["cairne bloodhoof"] = false }, origins())
    store:SetCurrentCharacter("Muradin Bronzebeard", "Andere Gilde")
    assert.same({ ["thrall earthson"] = false, ["cairne bloodhoof"] = false }, origins())
    -- locally the origin stays
    assert.equals("Jaina Proudmoore", sv.own.entries["enemy:thrall earthson"].origin)
  end)

  it("keeps the local origin of an own entry when a relayed own delta does not share it", function()
    local id = store:GetPlayerId()
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("enemy", "Thrall Earthson", 1) }, "Jaina Proudmoore")
    store:Adopt("aaaaaaaaaaaaaaaa")
    local mine = sv.own.entries["enemy:thrall earthson"]
    assert.equals("applied", store:ApplyDelta({
      o = id, rev = 3, base = 1, chars = {},
      e = {
        entry("enemy", "Thrall Earthson", 2, { reason = "neu", created = mine.created }),
        entry("enemy", "Cairne Bloodhoof", 3, { origin = "Baine Bloodhoof" }),
      },
    }))
    assert.equals("neu", sv.own.entries["enemy:thrall earthson"].reason)
    assert.equals("Jaina Proudmoore", sv.own.entries["enemy:thrall earthson"].origin)
    assert.equals(GUILD, sv.own.entries["enemy:thrall earthson"].originGuild)
    -- an origin that arrives in this guild may be shared in this guild
    assert.equals(GUILD, sv.own.entries["enemy:cairne bloodhoof"].originGuild)
    assert.equals("Baine Bloodhoof", store:DeltaFor(id, 2).e[1].origin)
    -- a revived entry (new created) has no origin any more
    assert.equals("applied", store:ApplyDelta({
      o = id, rev = 4, base = 3, chars = {},
      e = { entry("enemy", "Thrall Earthson", 4, { created = mine.created + 5 }) },
    }))
    assert.is_nil(sv.own.entries["enemy:thrall earthson"].origin)
  end)

  it("drops guild caches without an own character", function()
    giveOwner("aaaaaaaaaaaaaaaa", 1, { entry("enemy", "Thrall Earthson", 1) })
    store:SetCurrentCharacter("Jaina Proudmoore", "Andere Gilde")
    giveOwner("bbbbbbbbbbbbbbbb", 1, { entry("enemy", "Cairne Bloodhoof", 1) })
    store:DropStaleGuildCaches()
    assert.is_table(sv.guilds[GUILD]); assert.is_table(sv.guilds["Andere Gilde"])
    store:SetCurrentCharacter("Arthas Menethil", GUILD)
    sv.myChars["jaina proudmoore"].guild = nil
    store:DropStaleGuildCaches()
    assert.is_table(sv.guilds[GUILD])
    assert.is_nil(sv.guilds["Andere Gilde"])
  end)

  it("prunes only tombstones older than 90 days", function()
    store:AddOrUpdate("enemy", "Old Tomb", "x"); store:Delete("enemy", "Old Tomb")
    giveOwner("aaaaaaaaaaaaaaaa", 2, {
      entry("enemy", "Cache Tomb", 1, { deleted = true, reason = "" }),
      entry("enemy", "Cache Live", 2, { updated = clock - 200 * DAY }),
    })
    clock = clock + 91 * DAY
    store:AddOrUpdate("enemy", "New Tomb", "x"); store:Delete("enemy", "New Tomb")
    store:AddOrUpdate("enemy", "Live", "x")
    store:PruneTombstones()
    assert.is_nil(sv.own.entries["enemy:old tomb"])
    assert.is_table(sv.own.entries["enemy:new tomb"])
    assert.is_table(sv.own.entries["enemy:live"])
    local owner = sv.guilds[GUILD].owners.aaaaaaaaaaaaaaaa
    assert.is_nil(owner.entries["enemy:cache tomb"])
    assert.is_table(owner.entries["enemy:cache live"])
  end)

  it("keeps a tombstone that is exactly 90 days old", function()
    store:AddOrUpdate("enemy", "Edge Tomb", "x"); store:Delete("enemy", "Edge Tomb")
    clock = clock + 90 * DAY
    store:PruneTombstones()
    assert.is_table(sv.own.entries["enemy:edge tomb"])
  end)

  it("lists every player of a list with the same matches as lookup", function()
    store:AddOrUpdate("enemy", "Thrall Earthson", "mein")
    store:AddOrUpdate("friendly", "Only Friend", "x")
    clock = clock + 10
    giveOwner("aaaaaaaaaaaaaaaa", 2, { entry("enemy", "Thrall Earthson", 1), entry("enemy", "Cairne Bloodhoof", 2) })
    giveOwner("bbbbbbbbbbbbbbbb", 1, { entry("enemy", "Thrall Earthson", 1) }, "Sylvanas Windrunner",
      { ["sylvanas windrunner"] = "Sylvanas Windrunner" })
    store:SetCurrentCharacter("Arthas Menethil", "Andere Gilde")
    giveOwner("cccccccccccccccc", 1, { entry("enemy", "Elsewhere Guy", 1) })
    store:SetCurrentCharacter("Arthas Menethil", GUILD)

    local all = store:ListAll("enemy")
    local keys = {}
    for k in pairs(all) do keys[#keys + 1] = k end
    table.sort(keys)
    assert.same({ "cairne bloodhoof", "thrall earthson" }, keys)
    assert.equals(3, #all["thrall earthson"])
    assert.is_true(all["thrall earthson"][1].isOwn)
    assert.same(store:Lookup("Thrall Earthson", "enemy"), all["thrall earthson"])
    assert.equals(1, #all["cairne bloodhoof"])
    assert.same({}, store:ListAll("bogus"))
  end)

  it("reports current character, guild and guild characters", function()
    assert.equals("Arthas Menethil", store:GetCurrentChar())
    assert.equals(GUILD, store:GetCurrentGuild())
    store:SetCurrentCharacter("Jaina Proudmoore", "Andere Gilde")
    assert.equals("Andere Gilde", store:GetCurrentGuild())
    assert.same({ ["jaina proudmoore"] = "Jaina Proudmoore" }, store:GetMyGuildChars())
    store:SetCurrentCharacter("Muradin Bronzebeard", nil)
    assert.is_nil(store:GetCurrentGuild())
    assert.same({}, store:GetMyGuildChars())
    assert.same({}, store:GetOwners())
    assert.equals(clock, sv.myChars["muradin bronzebeard"].lastSeen)
  end)
end)
