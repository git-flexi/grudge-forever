local wow = require("tests.helpers.wow")

describe("Alerts", function()
  local ns, clock, settings, calls, alerts

  local function match(by, reason, muted)
    return { entry = { reason = reason }, ownerId = "o", isOwn = false, by = by, muted = muted or false }
  end

  local function listSettings(extra)
    local s = { enabled = true, sound = "raidwarning", icon = "skull", text = "{name} {trigger}: {reason} ({by})",
      banner = true, chat = false, cooldown = 300 }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
  end

  before_each(function()
    wow.reset()
    ns = wow.newNs()
    wow.load(ns, "Core/Names.lua", "Core/Alerts.lua")
    clock = 1000
    settings = { lists = { friendly = listSettings(), enemy = listSettings({ icon = "custom\\path" }) } }
    calls = { banner = {}, chat = {}, sound = {} }
    alerts = ns.Alerts.New({
      settings = function() return settings end,
      now = function() return clock end,
      out = {
        banner = function(icon, text) calls.banner[#calls.banner + 1] = { icon = icon, text = text } end,
        chat = function(text) calls.chat[#calls.chat + 1] = text end,
        sound = function(resolved) calls.sound[#calls.sound + 1] = resolved end,
      },
    })
  end)

  describe("Render", function()
    it("fills German aliases", function()
      local text = ns.Alerts.Render("{name} {anlass}! {grund} (von {von})",
        { name = "Thrall Earthson", trigger = "flüstert dir", reason = "pöbelt", by = "Jaina" })
      assert.equals("Thrall Earthson flüstert dir! pöbelt (von Jaina)", text)
    end)

    it("fills English placeholders and keeps unknown ones", function()
      local text = ns.Alerts.Render("{name}: {reason} by {by} {trigger} {foo}",
        { name = "A B", trigger = "t", reason = "r", by = "C" })
      assert.equals("A B: r by C t {foo}", text)
    end)

    it("does not interpret % in values", function()
      assert.equals("100% sure", ns.Alerts.Render("{reason}", { reason = "100% sure" }))
    end)

    it("escapes pipes in values but not in the template", function()
      local text = ns.Alerts.Render("|cffff0000{name}|r: {reason} ({by})",
        { name = "A|Hx|h", reason = "|TInterface\\x:99|t", by = "B||C" })
      assert.equals("|cffff0000A||Hx||h|r: ||TInterface\\x:99||t (B||C)", text)
    end)
  end)

  describe("Fire escapes", function()
    it("escapes remote reasons and creators in banner and chat", function()
      settings.lists.friendly.chat = true
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", { match("Ev|cffil", "x|ry") }, "whisper"))
      assert.equals("Thrall Earthson " .. ns.L["TRIGGER_WHISPER"] .. ": x||ry (Ev||cffil)", calls.banner[1].text)
      assert.truthy(calls.chat[1]:find("x||ry", 1, true))
      assert.truthy(calls.chat[1]:find("Ev||cffil", 1, true))
    end)
  end)

  describe("chat colors", function()
    local function one() return { match("Jaina", "pöbelt") } end

    local function plain(text)
      return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end

    it("wraps filled values in their color and leaves others plain", function()
      local text = ns.Alerts.Render("{name}: {reason} ({by})", { name = "A", reason = "r|x", by = "B" },
        { name = "ffffd100", reason = "ffffffff" })
      assert.equals("|cffffd100A|r: |cffffffffr||x|r (B)", text)
    end)

    it("starts the chat line with a colored warning and colors the player name", function()
      settings.lists.friendly.chat = true
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "group"))
      local line = calls.chat[1]
      assert.equals(1, line:find(ns.L["CHAT_WARNING"], 1, true))
      assert.truthy(line:find("|cffffd100Thrall Earthson|r", 1, true))
      assert.equals(plain(ns.L["CHAT_WARNING"]) .. calls.banner[1].text, plain(line))
    end)

    it("fills the list label and reads like the default sentence", function()
      settings.lists.friendly.chat = true
      settings.lists.friendly.text = ns.L["DEFAULT_TEXT"]
      assert.is_true(alerts:Fire("friendly", "Spitz Ohr", { match("Sacricola Umbrae", "Blabla") }, "group"))
      assert.equals("Blacklisted player Spitz Ohr is in your group! Reason: Blabla (by Sacricola Umbrae)",
        calls.banner[1].text)
      assert.equals("WARNING: " .. calls.banner[1].text, plain(calls.chat[1]))
    end)

    it("labels enemies as KOS targets, also through the German alias", function()
      settings.lists.enemy.text = "{liste} {name}"
      assert.is_true(alerts:Fire("enemy", "Garrosh Hellscream", one(), "sight"))
      assert.equals(ns.L["ALERT_LIST_ENEMY"] .. " Garrosh Hellscream", calls.banner[1].text)
    end)
  end)

  describe("Summarize", function()
    it("caps at three non-muted reasons and creators with a +N suffix", function()
      local reasons, by = ns.Alerts.Summarize({
        match("A", "r1"), match("B", "r2"), match("C", "r3"), match("D", "r4"), match("E", "gone", true),
      })
      assert.equals("r1; r2; r3 +1", reasons)
      assert.equals("A, B, C +1", by)
    end)

    it("dedupes reasons and creators", function()
      local reasons, by = ns.Alerts.Summarize({ match("A", "same"), match("A", "same"), match("B", "same") })
      assert.equals("same", reasons)
      assert.equals("A, B", by)
    end)

    it("returns empty strings without usable matches", function()
      local reasons, by = ns.Alerts.Summarize({ match("A", "r", true) })
      assert.equals("", reasons)
      assert.equals("", by)
    end)
  end)

  describe("ResolveSound", function()
    it("maps built-in keys", function()
      assert.same({ kind = "kit", id = 8959 }, ns.Alerts.ResolveSound("raidwarning"))
      assert.same({ kind = "kit", id = 3175 }, ns.Alerts.ResolveSound("mapping"))
      assert.is_nil(ns.Alerts.ResolveSound("none"))
      assert.is_nil(ns.Alerts.ResolveSound(nil))
    end)

    it("fetches other keys from LibSharedMedia", function()
      local lsm = LibStub:NewLibrary("LibSharedMedia-3.0", 1)
      lsm.Fetch = function(_, mediatype, key)
        if mediatype == "sound" and key == "Ping" then return "Interface\\AddOns\\X\\ping.ogg" end
      end
      assert.same({ kind = "file", path = "Interface\\AddOns\\X\\ping.ogg" }, ns.Alerts.ResolveSound("Ping"))
      assert.is_nil(ns.Alerts.ResolveSound("Missing"))
    end)

    it("returns nil for unknown keys without LibSharedMedia", function()
      assert.is_nil(ns.Alerts.ResolveSound("Ping"))
    end)
  end)

  describe("Fire", function()
    local one = function() return { match("Jaina", "pöbelt") } end

    it("outputs banner and sound with the rendered text and resolved icon", function()
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
      assert.equals(1, #calls.banner)
      assert.equals("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", calls.banner[1].icon)
      assert.equals("Thrall Earthson is whispering you: pöbelt (Jaina)", calls.banner[1].text)
      assert.same({ { kind = "kit", id = 8959 } }, calls.sound)
      assert.equals(0, #calls.chat)
    end)

    it("uses custom icon paths verbatim", function()
      alerts:Fire("enemy", "Thrall Earthson", one(), "sight")
      assert.equals("custom\\path", calls.banner[1].icon)
    end)

    it("uses the localized default text when none is set", function()
      settings.lists.friendly.text = nil
      alerts:Fire("friendly", "Thrall Earthson", one(), "invite")
      assert.equals("Blacklisted player Thrall Earthson is inviting you! Reason: pöbelt (by Jaina)",
        calls.banner[1].text)
    end)

    it("localizes trigger text and default template in German", function()
      wow.locale = "deDE"
      ns = wow.newNs()
      wow.load(ns, "Core/Names.lua", "Core/Alerts.lua")
      settings.lists.friendly.text = ""
      local a = ns.Alerts.New({
        settings = function() return settings end, now = function() return clock end,
        out = { banner = function(_, text) calls.banner[#calls.banner + 1] = { text = text } end },
      })
      a:Fire("friendly", "Thrall Earthson", one(), "group")
      assert.equals("Blacklist-Spieler Thrall Earthson ist in deiner Gruppe! Grund: pöbelt (von Jaina)",
        calls.banner[1].text)
    end)

    it("applies a cooldown per player of the configured length", function()
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
      clock = clock + 100
      assert.is_false(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
      clock = clock + 201
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
      assert.equals(2, #calls.banner)
    end)

    it("keeps cooldowns separate per player and list and normalizes names", function()
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
      assert.is_true(alerts:Fire("friendly", "Jaina Proudmoore", one(), "whisper"))
      assert.is_true(alerts:Fire("enemy", "Thrall Earthson", one(), "sight"))
      assert.is_false(alerts:Fire("friendly", "thrall-earthson", one(), "whisper"))
    end)

    it("shares the cooldown between triggers", function()
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
      clock = clock + 10
      assert.is_false(alerts:Fire("friendly", "Thrall Earthson", one(), "invite"))
      assert.equals(1, #calls.banner)
    end)

    it("follows live settings changes of the cooldown", function()
      alerts:Fire("friendly", "Thrall Earthson", one(), "whisper")
      settings.lists.friendly.cooldown = 10
      clock = clock + 11
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
    end)

    it("warns once per player and group until the group is reset", function()
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "group"))
      clock = clock + 301
      assert.is_false(alerts:Fire("friendly", "Thrall Earthson", one(), "group"))
      assert.is_true(alerts:Fire("friendly", "Jaina Proudmoore", one(), "group"))
      alerts:ResetGroup()
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "group"))
    end)

    it("does not consume the group memory when another trigger already warned", function()
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
      assert.is_false(alerts:Fire("friendly", "Thrall Earthson", one(), "group"))
      clock = clock + 301
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "group"))
    end)

    it("stays silent when every match is muted", function()
      assert.is_false(alerts:Fire("friendly", "Thrall Earthson", { match("A", "r", true) }, "whisper"))
      assert.is_false(alerts:Fire("friendly", "Thrall Earthson", {}, "whisper"))
      assert.equals(0, #calls.banner)
      assert.equals(0, #calls.sound)
      -- a muted miss must not start a cooldown
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
    end)

    it("stays silent when the list is disabled or unknown", function()
      settings.lists.friendly.enabled = false
      assert.is_false(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
      assert.is_false(alerts:Fire("other", "Thrall Earthson", one(), "whisper"))
      assert.equals(0, #calls.banner)
    end)

    it("respects banner, chat and sound switches", function()
      settings.lists.friendly.banner = false
      settings.lists.friendly.chat = true
      settings.lists.friendly.sound = "none"
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "whisper"))
      assert.equals(0, #calls.banner)
      assert.equals(1, #calls.chat)
      assert.equals("WARNING: Thrall Earthson is whispering you: pöbelt (Jaina)",
        (calls.chat[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
      assert.equals(0, #calls.sound)
    end)

    it("ignores missing outputs", function()
      local a = ns.Alerts.New({
        settings = function() return settings end, now = function() return clock end, out = {},
      })
      assert.is_true(a:Fire("friendly", "Thrall Earthson", one(), "whisper"))
    end)
  end)
end)

describe("Banner", function()
  local wowEnv

  -- Frame stand-in: every method is a no-op returning the frame itself, except where a real value is needed.
  local function newFrame()
    local f
    f = setmetatable({ shown = false }, { __index = function(_, name)
      if name == "GetCenter" then return function() return 500, 400 end end
      if name == "Show" then return function() f.shown = true end end
      if name == "Hide" then return function() f.shown = false end end
      return function() return f end
    end })
    return f
  end

  before_each(function()
    wow.reset()
    wowEnv = wow.newNs()
  end)

  it("loads and tolerates calls when CreateFrame does not exist", function()
    wow.load(wowEnv, "UI/Banner.lua")
    assert.is_function(wowEnv.Banner.Show)
    assert.has_no.errors(function()
      wowEnv.Banner.SetLocked(true)
      wowEnv.Banner.ResetPosition()
      wowEnv.Banner.Show("icon", "text")
    end)
  end)

  it("creates its frame lazily and survives lock, unlock and reset", function()
    local created = 0
    _G.UIParent = newFrame()
    _G.CreateFrame = function() created = created + 1; return newFrame() end
    _G.GrudgeForeverDB = {}
    wow.load(wowEnv, "UI/Banner.lua")
    assert.equals(0, created)
    wowEnv.Banner.Show("icon", "text")
    assert.is_true(created > 0)
    assert.has_no.errors(function()
      wowEnv.Banner.SetLocked(false)
      wowEnv.Banner.SetLocked(true)
      wowEnv.Banner.ResetPosition()
    end)
    assert.is_nil(GrudgeForeverDB.settings and GrudgeForeverDB.settings.banner)
  end)

  it("wraps long text to at most two lines and uses the icon's room when there is no icon", function()
    -- recording stand-in: calls are logged per region, child regions are separate recorders
    local regions = {}
    local function recorder(kind)
      local r = { kind = kind, calls = {} }
      regions[#regions + 1] = r
      return setmetatable(r, { __index = function(_, name)
        if name == "CreateFontString" then return function() return recorder("FontString") end end
        if name == "CreateTexture" then return function() return recorder("Texture") end end
        if name == "CreateAnimationGroup" then return function() return recorder("AnimationGroup") end end
        if name == "CreateAnimation" then return function() return recorder("Animation") end end
        return function(_, ...)
          r.calls[#r.calls + 1] = { name = name, args = { ... } }
          return r
        end
      end })
    end
    local function last(r, name)
      for i = #r.calls, 1, -1 do
        if r.calls[i].name == name then return r.calls[i].args end
      end
    end
    local function anchorsSinceClear(r)
      local out = {}
      for _, c in ipairs(r.calls) do
        if c.name == "ClearAllPoints" then out = {} elseif c.name == "SetPoint" then out[#out + 1] = c.args end
      end
      return out
    end
    _G.UIParent = recorder("UIParent")
    _G.CreateFrame = function() return recorder("Frame") end
    _G.GrudgeForeverDB = {}
    wow.load(wowEnv, "UI/Banner.lua")

    wowEnv.Banner.Show("icon", "text")
    local text
    for _, r in ipairs(regions) do
      if r.kind == "FontString" then text = r end
    end
    assert.same({ 2 }, last(text, "SetMaxLines"))
    assert.same({ true }, last(text, "SetWordWrap"))
    local anchors = anchorsSinceClear(text)
    assert.equals("Texture", anchors[1][2].kind) -- next to the icon

    wowEnv.Banner.Show(nil, "text")
    anchors = anchorsSinceClear(text)
    assert.equals("LEFT", anchors[1][1])
    assert.is_number(anchors[1][2]) -- offset from the banner's own left edge
  end)
end)
