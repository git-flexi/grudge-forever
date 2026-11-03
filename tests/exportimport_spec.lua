local wow = require("tests.helpers.wow")

describe("Codec", function()
  local ns

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Codec.lua")
  end)

  it("roundtrips a table in both modes", function()
    local t = { v = 1, s = "grüße", n = { 1, 2, 3 }, nested = { a = true, b = 1.5 } }
    for _, mode in ipairs({ "comm", "print" }) do
      assert.same(t, ns.Codec.Decode(ns.Codec.Encode(t, mode), mode))
    end
  end)

  it("encodes print mode as a single printable line", function()
    local s = ns.Codec.Encode({ text = string.rep("abc ", 200) }, "print")
    assert.is_nil(s:find("[^%w%(%)]"))
  end)

  it("reports an error key for garbage", function()
    local t, err = ns.Codec.Decode("x", "comm")
    assert.is_nil(t)
    assert.is_string(err)
    t, err = ns.Codec.Decode("hallo welt", "print")
    assert.is_nil(t)
    assert.is_string(err)
  end)
end)

describe("ExportImport", function()
  local ns, clock, seq

  local function newStore(sv, char)
    local store = ns.Store.New(sv, {
      now = function() return clock end,
      random = function(n) seq = seq + 1; return (seq % n) + 1 end,
    })
    store:SetCurrentCharacter(char or "Arthas Menethil", "Die Gilde")
    return store
  end

  -- Builds an import string the way Export would, from raw rows.
  local function pack(rows, v)
    return "GF1:" .. ns.Codec.Encode({ v = v or 1, e = rows }, "print")
  end

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/Store.lua", "Core/Codec.lua", "Core/ExportImport.lua")
    clock = 1700000000
    seq = 0
  end)

  it("roundtrips own entries into a fresh saved-variables table", function()
    local a = newStore({})
    a:AddOrUpdate("enemy", "Thrall Earthson", "pöbelt")
    a:AddOrUpdate("friendly", "Jaina Proudmoore", "hilft immer")
    a:AddOrUpdate("enemy", "Sylvanas Windrunner", "")

    local text = ns.ExportImport.Export(a)
    assert.equals("GF1:", text:sub(1, 4))
    assert.is_nil(text:find("%s"))

    local sv = {}
    local b = newStore(sv, "Anduin Wrynn")
    local added, updated = ns.ExportImport.Import(b, text)
    assert.equals(3, added)
    assert.equals(0, updated)

    local got = {}
    for _, e in ipairs(b:GetOwnEntries()) do got[e.list .. ":" .. e.name] = e.reason end
    assert.same({
      ["enemy:Thrall Earthson"] = "pöbelt",
      ["friendly:Jaina Proudmoore"] = "hilft immer",
      ["enemy:Sylvanas Windrunner"] = "",
    }, got)
    assert.equals(3, sv.own.rev)
    for _, e in ipairs(b:GetOwnEntries()) do assert.equals("Anduin Wrynn", e.char) end
  end)

  it("exports only own entries that are not deleted", function()
    local sv = {}
    local a = newStore(sv)
    a:AddOrUpdate("enemy", "Thrall Earthson", "bleibt")
    a:AddOrUpdate("enemy", "Garrosh Hellscream", "weg")
    a:Delete("enemy", "Garrosh Hellscream")
    a:SetCurrentCharacter("Arthas Menethil", "Die Gilde")
    a:ApplyDelta({
      o = "ffffffffffffffff", rev = 1, base = 0, lastChar = "Jaina Proudmoore",
      chars = { ["jaina proudmoore"] = "Jaina Proudmoore" },
      e = { {
        key = "illidan stormrage", name = "Illidan Stormrage", list = "enemy", reason = "fremd",
        created = clock, updated = clock, rev = 1, deleted = false,
      } },
    })

    local b = newStore({}, "Anduin Wrynn")
    assert.equals(1, (ns.ExportImport.Import(b, ns.ExportImport.Export(a))))
    local entries = b:GetOwnEntries()
    assert.equals(1, #entries)
    assert.equals("Thrall Earthson", entries[1].name)
  end)

  it("changes nothing when importing the own export again, and updates on newer data", function()
    local sv = {}
    local a = newStore(sv)
    a:AddOrUpdate("enemy", "Thrall Earthson", "alt")
    local text = ns.ExportImport.Export(a)
    local rev = sv.own.rev

    local added, updated = ns.ExportImport.Import(a, text)
    assert.equals(0, added)
    assert.equals(0, updated)
    assert.equals(rev, sv.own.rev)

    added, updated = ns.ExportImport.Import(a, pack({
      { "Thrall Earthson", "enemy", "neu", "Jaina Proudmoore", clock - 100, clock + 50 },
    }))
    assert.equals(0, added)
    assert.equals(1, updated)
    local e = a:GetOwnEntries()[1]
    assert.equals("neu", e.reason)
    assert.equals(clock + 50, e.updated)
    assert.equals(clock - 100, e.created)
    assert.equals(rev + 1, sv.own.rev)
    assert.equals(sv.own.rev, e.rev)
  end)

  it("does not overwrite an own entry with an older import", function()
    local a = newStore({})
    a:AddOrUpdate("enemy", "Thrall Earthson", "aktuell")
    local added, updated = ns.ExportImport.Import(a, pack({
      { "Thrall Earthson", "enemy", "alt", nil, clock - 100, clock - 50 },
    }))
    assert.equals(0, added)
    assert.equals(0, updated)
    assert.equals("aktuell", a:GetOwnEntries()[1].reason)
  end)

  it("counts an import over an own tombstone as added", function()
    local a = newStore({})
    a:AddOrUpdate("enemy", "Thrall Earthson", "x")
    a:Delete("enemy", "Thrall Earthson")
    local added, updated = ns.ExportImport.Import(a, pack({
      { "Thrall Earthson", "enemy", "zurück", nil, clock, clock },
    }))
    assert.equals(1, added)
    assert.equals(0, updated)
    local e = a:GetOwnEntries()[1]
    assert.equals("zurück", e.reason)
    assert.is_false(e.deleted)
  end)

  it("rejects text without the prefix or with undecodable content", function()
    local a = newStore({})
    local r, err = ns.ExportImport.Import(a, "hallo")
    assert.is_nil(r)
    assert.equals("format", err)
    r, err = ns.ExportImport.Import(a, "GF1:hallo welt")
    assert.is_nil(r)
    assert.equals("format", err)
    r, err = ns.ExportImport.Import(a, "GF1:" .. ns.Codec.Encode("kein table", "print"))
    assert.is_nil(r)
    assert.equals("format", err)
    r, err = ns.ExportImport.Import(a, "GF1:" .. ns.Codec.Encode({ v = 1 }, "print"))
    assert.is_nil(r)
    assert.equals("format", err)
  end)

  it("rejects an unknown version", function()
    local r, err = ns.ExportImport.Import(newStore({}), pack({}, 2))
    assert.is_nil(r)
    assert.equals("version", err)
  end)

  it("skips invalid rows and imports the rest", function()
    local a = newStore({})
    local added = ns.ExportImport.Import(a, pack({
      { "Thrall Earthson", "enemy", string.rep("x", 200), nil, clock, clock },
      { "Jaina Proudmoore", "friendly", "ok", nil, clock, clock },
      { "Bad List", "neutral", "x", nil, clock, clock },
      { "   ", "enemy", "x", nil, clock, clock },
      { "Num Reason", "enemy", 5, nil, clock, clock },
      { "No Updated", "enemy", "x", nil, clock, "gestern" },
      { "No Created", "enemy", "x", nil, nil, clock },
      "kein row",
      { "Umlaut Name", "enemy", string.rep("ö", 80), nil, clock, clock },
    }))
    assert.equals(2, added)
    local names = {}
    for _, e in ipairs(a:GetOwnEntries()) do names[#names + 1] = e.name end
    table.sort(names)
    assert.same({ "Jaina Proudmoore", "Umlaut Name" }, names)
  end)

  it("keeps the original creator as origin and drops own characters", function()
    local a = newStore({})
    a:AddOrUpdate("enemy", "Thrall Earthson", "übernommen")
    a:AddOrUpdate("friendly", "Jaina Proudmoore", "selbst")
    -- an adopted entry: origin points at somebody else
    for _, e in pairs(a.sv.own.entries) do
      if e.key == "thrall earthson" then e.origin = "Thrall Earthson" end
    end
    local text = ns.ExportImport.Export(a)

    local b = newStore({}, "Anduin Wrynn")
    ns.ExportImport.Import(b, text)
    local byName = {}
    for _, e in ipairs(b:GetOwnEntries()) do byName[e.name] = e end
    assert.equals("Thrall Earthson", byName["Thrall Earthson"].origin)
    -- foreign creator character is kept as origin for entries that had none
    assert.equals("Arthas Menethil", byName["Jaina Proudmoore"].origin)

    -- re-import into the same saved variables: own character is no origin
    local sv = {}
    local c = newStore(sv)
    c:AddOrUpdate("friendly", "Jaina Proudmoore", "selbst")
    local text2 = ns.ExportImport.Export(c)
    local d = newStore({}, "Arthas Menethil")
    ns.ExportImport.Import(d, text2)
    assert.is_nil(d:GetOwnEntries()[1].origin)
  end)

  it("tolerates surrounding whitespace and line breaks", function()
    local a = newStore({})
    a:AddOrUpdate("enemy", "Thrall Earthson", "x")
    local text = ns.ExportImport.Export(a)
    local mid = math.floor(#text / 2)
    local wrapped = "\n  " .. text:sub(1, mid) .. "\n" .. text:sub(mid + 1) .. " \r\n"
    local b = newStore({}, "Anduin Wrynn")
    assert.equals(1, (ns.ExportImport.Import(b, wrapped)))
  end)
end)
