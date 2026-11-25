local wow = require("tests.helpers.wow")

local function plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

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
        -- text: the whole banner as one line (head and reason line joined), to compare with the chat
        banner = function(icon, head, detail)
          calls.banner[#calls.banner + 1] = {
            icon = icon, head = head, detail = detail, text = detail and (head .. " " .. detail) or head,
          }
        end,
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
      assert.equals("|cffffffffThrall Earthson|r " .. ns.L["TRIGGER_WHISPER"] .. ": x||ry (|cff8fb7e0Ev||cffil|r)",
        calls.banner[1].text)
      assert.truthy(calls.chat[1]:find("x||ry", 1, true))
      assert.truthy(calls.chat[1]:find("Ev||cffil", 1, true))
    end)
  end)

  describe("SplitAtReason", function()
    it("splits before the sentence that holds the reason", function()
      assert.same({ "{list} {name} {trigger}!", "Reason: {reason} (by {by})" },
        { ns.Alerts.SplitAtReason("{list} {name} {trigger}! Reason: {reason} (by {by})") })
    end)

    it("knows the German alias", function()
      assert.same({ "{liste} {name} {anlass}!", "Grund: {grund} (von {von})" },
        { ns.Alerts.SplitAtReason("{liste} {name} {anlass}! Grund: {grund} (von {von})") })
    end)

    it("splits right before the reason when no sentence ends before it", function()
      assert.same({ "{name} {trigger}:", "{reason} ({by})" },
        { ns.Alerts.SplitAtReason("{name} {trigger}: {reason} ({by})") })
    end)

    it("does not split without a reason or when the reason comes first", function()
      assert.same({ "{list} {name}" }, { ns.Alerts.SplitAtReason("{list} {name}") })
      assert.same({ "{reason} - {name}" }, { ns.Alerts.SplitAtReason("{reason} - {name}") })
      assert.same({ "Reason: {reason}" }, { ns.Alerts.SplitAtReason("Reason: {reason}") })
    end)
  end)

  describe("chat colors", function()
    local function one() return { match("Jaina", "pöbelt") } end

    it("wraps filled values in their color and leaves others plain", function()
      local text = ns.Alerts.Render("{name}: {reason} ({by})", { name = "A", reason = "r|x", by = "B" },
        { name = "ffffd100", reason = "ffffffff" })
      assert.equals("|cffffd100A|r: |cffffffffr||x|r (B)", text)
    end)

    it("colors the player name and matches the banner text", function()
      settings.lists.friendly.chat = true
      assert.is_true(alerts:Fire("friendly", "Thrall Earthson", one(), "group"))
      local line = calls.chat[1]
      assert.truthy(line:find("|cffffffffThrall Earthson|r", 1, true))
      assert.equals(plain(calls.banner[1].text), plain(line))
    end)

    it("uses the journal palette for the chat colors", function()
      assert.same({ list = "ffff6a4a", name = "ffffffff", reason = "ffe8dcc2", by = "ff8fb7e0" }, ns.Alerts.CHAT_COLORS)
    end)

    it("fills the list label and reads like the default sentence", function()
      settings.lists.friendly.chat = true
      settings.lists.friendly.text = ns.L["DEFAULT_TEXT"]
      assert.is_true(alerts:Fire("friendly", "Spitz Ohr", { match("Sacricola Umbrae", "Blabla") }, "group"))
      assert.equals("Blacklisted player Spitz Ohr is in your group! Reason: Blabla (by Sacricola Umbrae)",
        plain(calls.banner[1].text))
      assert.equals(plain(calls.banner[1].text), plain(calls.chat[1]))
    end)

    it("puts the reason's sentence on its own banner line and keeps the chat in one line", function()
      settings.lists.friendly.chat = true
      settings.lists.friendly.text = ns.L["DEFAULT_TEXT"]
      assert.is_true(alerts:Fire("friendly", "Spitz Ohr", { match("Sacricola Umbrae", "Blabla") }, "group"))
      assert.equals("Blacklisted player Spitz Ohr is in your group!", plain(calls.banner[1].head))
      assert.equals("Reason: Blabla (by Sacricola Umbrae)", plain(calls.banner[1].detail))
      assert.equals("Blacklisted player Spitz Ohr is in your group! Reason: Blabla (by Sacricola Umbrae)",
        plain(calls.chat[1]))
    end)

    it("keeps a banner without a reason placeholder in one line", function()
      settings.lists.enemy.text = "{list} {name}"
      assert.is_true(alerts:Fire("enemy", "Garrosh Hellscream", one(), "sight"))
      assert.is_nil(calls.banner[1].detail)
    end)

    it("labels enemies as KOS targets, also through the German alias", function()
      settings.lists.enemy.text = "{liste} {name}"
      assert.is_true(alerts:Fire("enemy", "Garrosh Hellscream", one(), "sight"))
      assert.equals(ns.L["ALERT_LIST_ENEMY"] .. " Garrosh Hellscream", plain(calls.banner[1].text))
    end)
  end)

  describe("banner colors", function()
    it("colors the list, name and by in the banner text", function()
      local banner = ns.Alerts.Compose("friendly", { text = "{list} {name} ({by})" }, { name = "A", by = "B" })
      assert.truthy(banner:find("|cffffffffA|r", 1, true))
      assert.truthy(banner:find("|cff8fb7e0B|r", 1, true))
      assert.truthy(banner:find("|cffff6a4a" .. ns.L["ALERT_LIST_FRIENDLY"] .. "|r", 1, true))
    end)

    it("keeps pipes in a remote reason escaped in the banner", function()
      local banner = ns.Alerts.Compose("friendly", { text = "{reason}" }, { reason = "r|x" })
      assert.equals("r||x", banner)
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
      assert.equals("Thrall Earthson is whispering you: pöbelt (Jaina)", plain(calls.banner[1].text))
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
        plain(calls.banner[1].text))
    end)

    it("localizes trigger text and default template in German", function()
      wow.locale = "deDE"
      ns = wow.newNs()
      wow.load(ns, "Core/Names.lua", "Core/Alerts.lua")
      settings.lists.friendly.text = ""
      local a = ns.Alerts.New({
        settings = function() return settings end, now = function() return clock end,
        out = { banner = function(_, head, detail)
          calls.banner[#calls.banner + 1] = { head = head, detail = detail }
        end },
      })
      a:Fire("friendly", "Thrall Earthson", one(), "group")
      assert.equals("Blacklist-Spieler Thrall Earthson ist in deiner Gruppe!", plain(calls.banner[1].head))
      assert.equals("Grund: pöbelt (von Jaina)", plain(calls.banner[1].detail))
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
      assert.equals("Thrall Earthson is whispering you: pöbelt (Jaina)",
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
    wow.load(wowEnv, "UI/Skin.lua", "UI/Banner.lua")
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
    wow.load(wowEnv, "UI/Skin.lua", "UI/Banner.lua")
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

  -- Recording stand-in: calls are logged per region, child regions are separate recorders.
  local regions
  local function recorder(kind)
    local r = { kind = kind, calls = {}, children = {} }
    regions[#regions + 1] = r
    return setmetatable(r, { __index = function(_, name)
      if name == "CreateFontString" then return function() return recorder("FontString") end end
      if name == "CreateTexture" then return function() return recorder("Texture") end end
      if name == "CreateAnimationGroup" then return function() return recorder("AnimationGroup") end end
      if name == "CreateAnimation" then
        return function(_, type)
          local child = recorder("Animation")
          child.type = type
          r.children[#r.children + 1] = child
          return child
        end
      end
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
  local function count(r, name)
    local n = 0
    for _, c in ipairs(r.calls) do
      if c.name == name then n = n + 1 end
    end
    return n
  end
  local function anchorsSinceClear(r)
    local out = {}
    for _, c in ipairs(r.calls) do
      if c.name == "ClearAllPoints" then out = {} elseif c.name == "SetPoint" then out[#out + 1] = c.args end
    end
    return out
  end
  -- The animation group whose Alpha child fades from `from`.
  local function groupFading(from)
    for _, r in ipairs(regions) do
      if r.kind == "AnimationGroup" then
        for _, child in ipairs(r.children) do
          local a = last(child, "SetFromAlpha")
          if child.type == "Alpha" and a and a[1] == from then return r end
        end
      end
    end
  end
  local function fontStrings()
    local out = {}
    for _, r in ipairs(regions) do
      if r.kind == "FontString" then out[#out + 1] = r end
    end
    return out
  end
  -- Which of the given calls came last.
  local function lastOf(r, names)
    for i = #r.calls, 1, -1 do
      for _, name in ipairs(names) do
        if r.calls[i].name == name then return name end
      end
    end
  end
  local function setupRecorders()
    regions = {}
    _G.UIParent = recorder("UIParent")
    _G.CreateFrame = function() return recorder("Frame") end
    _G.GrudgeForeverDB = {}
    wow.load(wowEnv, "UI/Skin.lua", "UI/Banner.lua")
  end

  it("wraps long text to at most two lines and uses the icon's room when there is no icon", function()
    setupRecorders()
    wowEnv.Banner.Show("icon", "text")
    local text = fontStrings()[1]
    assert.same({ 2 }, last(text, "SetMaxLines"))
    assert.same({ true }, last(text, "SetWordWrap"))
    local anchors = anchorsSinceClear(text)
    assert.equals("Texture", anchors[1][2].kind) -- next to the icon

    wowEnv.Banner.Show(nil, "text")
    anchors = anchorsSinceClear(text)
    assert.equals("LEFT", anchors[1][1])
    assert.is_number(anchors[1][2]) -- offset from the banner's own left edge
  end)

  it("shows the reason on its own line below the text and hides it without one", function()
    setupRecorders()
    wowEnv.Banner.Show("icon", "head", "Reason: long reason")
    local title, detail = fontStrings()[1], fontStrings()[2]
    local frame
    for _, r in ipairs(regions) do
      if r.kind == "Frame" then frame = r; break end
    end
    assert.same({ "Reason: long reason" }, last(detail, "SetText"))
    assert.equals("Show", lastOf(detail, { "Show", "Hide" }))
    assert.same({ true }, last(detail, "SetWordWrap"))
    assert.same({ 2 }, last(detail, "SetMaxLines"))
    assert.equals(title, anchorsSinceClear(detail)[1][2]) -- right below the text
    assert.is_true(last(frame, "SetHeight")[1] >= 70)

    wowEnv.Banner.Show("icon", "head")
    assert.equals("Hide", lastOf(detail, { "Show", "Hide" }))
    assert.equals(70, last(frame, "SetHeight")[1])
  end)

  it("plays the intro animation on every show", function()
    setupRecorders()
    wowEnv.Banner.Show("icon", "one")
    wowEnv.Banner.Show("icon", "two")
    local intro = groupFading(0)
    assert.is_not_nil(intro)
    assert.equals(2, count(intro, "Play"))
    assert.is_true(count(intro, "Stop") >= 2)
  end)

  it("a second alert keeps the banner up after the first one's timer", function()
    setupRecorders()
    wowEnv.Banner.Show("icon", "A")
    wowEnv.Banner.Show("icon", "B")
    assert.equals(2, #wow.timers)
    local fade = groupFading(1)
    assert.is_not_nil(fade)
    wow.timers[1].fn() -- A's timer is stale
    assert.equals(0, count(fade, "Play"))
    wow.timers[2].fn()
    assert.equals(1, count(fade, "Play"))
  end)

  describe("intro lift", function()
    local function script(r, name)
      for i = #r.calls, 1, -1 do
        if r.calls[i].name == "SetScript" and r.calls[i].args[1] == name then return r.calls[i].args[2] end
      end
    end
    local function bannerFrame()
      for _, r in ipairs(regions) do
        if r.kind == "Frame" then return r end
      end
    end
    local function restY(frame)
      local anchors = anchorsSinceClear(frame)
      return anchors[#anchors][5]
    end

    before_each(setupRecorders)

    it("anchors 12px above the rest position and settles on finish", function()
      wowEnv.Banner.Show("icon", "x")
      local frame = bannerFrame()
      assert.equals(-138, restY(frame))
      script(groupFading(0), "OnFinished")()
      assert.equals(-150, restY(frame))
    end)

    it("settles on stop and uses the saved position as rest", function()
      GrudgeForeverDB.settings = { banner = { point = "CENTER", x = 5, y = 20 } }
      wowEnv.Banner.Show("icon", "x")
      local frame = bannerFrame()
      assert.equals(32, restY(frame))
      script(groupFading(0), "OnStop")()
      assert.equals(20, restY(frame))
    end)

    it("resets to the rest anchor when a drag starts", function()
      wowEnv.Banner.SetLocked(false) -- placeholder, lifted
      local frame = bannerFrame()
      assert.equals(-138, restY(frame))
      script(frame, "OnDragStart")(frame)
      assert.equals(-150, restY(frame))
    end)

    it("never changes the saved position by showing", function()
      local saved = { point = "CENTER", x = 5, y = 20 }
      GrudgeForeverDB.settings = { banner = saved }
      wowEnv.Banner.Show("icon", "x")
      wowEnv.Banner.Show("icon", "y")
      assert.equals(saved, GrudgeForeverDB.settings.banner)
      assert.same({ point = "CENTER", x = 5, y = 20 }, saved)
    end)

    it("stops the intro when the position is reset", function()
      wowEnv.Banner.Show("icon", "x")
      local intro = groupFading(0)
      local before = count(intro, "Stop")
      wowEnv.Banner.ResetPosition()
      assert.equals(before + 1, count(intro, "Stop"))
    end)
  end)
end)
