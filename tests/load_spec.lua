local wow = require("tests.helpers.wow")

-- Smoke test: loads the addon the way the client does (TOC order, one shared namespace) against
-- stub frames, then drives the main events through the addon's event frame.
describe("Addon load", function()
  local ADDON = "GrudgeForever"
  local ns, eventFrame

  local function readFile(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  local function unixPath(path)
    return (path:gsub("\\", "/"))
  end

  local function dirOf(path)
    return path:match("^(.*)/[^/]*$") or "."
  end

  -- Lua files referenced by an XML file, following <Include> recursively.
  local function xmlScripts(path, out)
    local dir = dirOf(path)
    for tag, file in readFile(path):gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
      local full = dir .. "/" .. unixPath(file)
      if tag == "Script" then
        out[#out + 1] = full
      elseif tag == "Include" then
        xmlScripts(full, out)
      end
    end
    return out
  end

  local function tocFiles()
    local files = {}
    for line in readFile(ADDON .. ".toc"):gmatch("[^\r\n]+") do
      line = line:match("^%s*(.-)%s*$")
      if line ~= "" and not line:find("^#") then files[#files + 1] = unixPath(line) end
    end
    return files
  end

  local function fire(event, ...)
    wow.fire(eventFrame, "OnEvent", event, ...)
  end

  -- compares without color codes
  local function chatContains(text)
    for _, line in ipairs(wow.chat) do
      line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      if line:find(text, 1, true) then return true end
    end
    return false
  end

  local function login()
    fire("ADDON_LOADED", ADDON)
    fire("PLAYER_LOGIN")
  end

  -- Loads every TOC file into a fresh namespace (a /reload keeps GrudgeForeverDB).
  local function loadAddon()
    wow.frames = {}
    ns = {}
    for _, path in ipairs(tocFiles()) do
      if path:match("%.xml$") then
        -- embedded libraries run as plain Lua; the addon's namespace is not theirs
        for _, script in ipairs(xmlScripts(path, {})) do assert(loadfile(script))() end
      else
        wow.load(ns, path)
      end
    end
    eventFrame = wow.frameFor("ADDON_LOADED")
  end

  before_each(function()
    wow.reset()
    wow.installUI()
    wow.units.player = { name = "Jaina", surname = "Proudmoore", player = true, faction = "Alliance" }
    loadAddon()
  end)

  it("loads every TOC file and listens for ADDON_LOADED", function()
    assert.is_table(ns.Core)
    assert.is_not_nil(eventFrame)
  end)

  it("describes the addon for the Forever client in English and German", function()
    local toc = "\n" .. readFile(ADDON .. ".toc")
    assert.truthy(toc:find("\n## Interface: 16001\n", 1, true))
    -- Like Questie and Chatify: no game-type filter, which can hide the addon from the list.
    assert.is_nil(toc:find("LoadGameType", 1, true))
    local notes = toc:match("\n## Notes: ([^\n]+)")
    local notesDe = toc:match("\n## Notes%-deDE: ([^\n]+)")
    assert.truthy(notes and notes:find("KOS", 1, true) and notes:find("guild", 1, true))
    assert.truthy(notesDe and notesDe:find("KOS", 1, true) and notesDe:find("Gilde", 1, true))
    assert.is_nil(notes:lower():find("friend", 1, true))
  end)

  it("has every text in both locales and the reworded sound and preview labels", function()
    local en = wow.newNs().L
    -- the German file run on its own, recording what it sets
    wow.locale = "deDE"
    local de = {}
    wow.load({ L = setmetatable({}, { __newindex = function(_, k, v) de[k] = v end }) }, "Locales/deDE.lua")
    local missing = {}
    for key in pairs(en) do
      if de[key] == nil then missing[#missing + 1] = key end
    end
    table.sort(missing)
    assert.same({}, missing)
    assert.equals("Minimap ping", en["OPT_SOUND_MAPPING"])
    assert.equals("Preview", en["OPT_TEST"])
    assert.equals("Minimap-Ping", de["OPT_SOUND_MAPPING"])
    assert.equals("Vorschau", de["OPT_TEST"])
    assert.is_nil(rawget(en, "ADDON_NOTES"))
    assert.is_nil(de["ADDON_NOTES"])
  end)

  it("sets up saved variables, settings and slash commands when loaded", function()
    fire("ADDON_LOADED", "SomeOtherAddon")
    assert.is_nil(GrudgeForeverDB)
    fire("ADDON_LOADED", ADDON)
    assert.is_table(GrudgeForeverDB)
    assert.equals("auto", GrudgeForeverDB.settings.syncMode)
    assert.equals("/gf", SLASH_GRUDGEFOREVER1)
    assert.equals("/grudgeforever", SLASH_GRUDGEFOREVER2)
    assert.is_function(SlashCmdList.GRUDGEFOREVER)
  end)

  it("runs the main events without errors", function()
    wow.inGuild = true
    wow.guildName = "Die Gilde"
    wow.roster = { "Jaina Proudmoore", "Thrall-Earthson" }
    login()
    fire("GUILD_ROSTER_UPDATE", true)
    fire("PLAYER_GUILD_UPDATE", "player")
    fire("CHAT_MSG_WHISPER", "hi", "Thrall Earthson")
    fire("PARTY_INVITE_REQUEST", "Thrall Earthson")
    wow.units.party1 = { name = "Thrall", surname = "Earthson", player = true, faction = "Alliance" }
    wow.group = { raid = false, size = 2 }
    fire("GROUP_ROSTER_UPDATE")
    wow.units.target = { name = "Garrosh", surname = "Hellscream", player = true, faction = "Horde" }
    fire("PLAYER_TARGET_CHANGED")
    fire("UPDATE_MOUSEOVER_UNIT")
    fire("NAME_PLATE_UNIT_ADDED", "target")
    wow.group = nil
    fire("GROUP_ROSTER_UPDATE")
    for _, ticker in ipairs(wow.tickers) do ticker.fn() end
    wow.runTimers()
    assert.equals("Die Gilde", ns.Core.store:GetCurrentGuild())
    assert.equals("Jaina Proudmoore", ns.Core.store:GetCurrentChar())
    assert.is_true(wow.rosterRequests > 0)
  end)

  it("prints a warning when a listed player whispers", function()
    login()
    ns.Core.store:AddOrUpdate("friendly", "Thrall Earthson", "pöbelt")
    fire("CHAT_MSG_WHISPER", "hi", "Thrall-Earthson")
    assert.is_true(chatContains("WARNING: Blacklisted player Thrall Earthson is whispering you! Reason: pöbelt"))
    assert.equals(1, #wow.sounds)
  end)

  it("warns about a listed enemy that comes into sight", function()
    login()
    ns.Core.store:AddOrUpdate("enemy", "Garrosh Hellscream", "gankt")
    wow.units.nameplate1 = { name = "Garrosh", surname = "Hellscream", player = true, faction = "Horde" }
    fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    assert.is_true(chatContains("WARNING: KOS target Garrosh Hellscream is nearby! Reason: gankt"))
  end)

  it("warns once about a listed player in the group, but not about the own character", function()
    login()
    ns.Core.store:AddOrUpdate("friendly", "Thrall Earthson", "afk")
    ns.Core.store:AddOrUpdate("friendly", "Jaina Proudmoore", "me")
    wow.units.raid1 = wow.units.player
    wow.units.raid2 = { name = "Thrall", surname = "Earthson", player = true, faction = "Alliance" }
    wow.group = { raid = true, size = 2 }
    fire("GROUP_ROSTER_UPDATE")
    fire("GROUP_ROSTER_UPDATE")
    local hits = 0
    for _, line in ipairs(wow.chat) do
      if line:find("is in your group", 1, true) then hits = hits + 1 end
    end
    assert.equals(1, hits)
    assert.is_false(chatContains("Jaina Proudmoore is in your group"))
  end)

  it("keeps the guild cache while the guild name is still loading at login", function()
    _G.GrudgeForeverDB = {
      myChars = { ["jaina proudmoore"] = { name = "Jaina Proudmoore", guild = "Die Gilde", lastSeen = 1 },
                  ["alt twink"] = { name = "Alt Twink", guild = "Alte Gilde", lastSeen = 1 } },
      guilds = { ["Die Gilde"] = { owners = {} }, ["Alte Gilde"] = { owners = {} } },
    }
    wow.inGuild = true
    login()
    assert.is_table(GrudgeForeverDB.guilds["Die Gilde"])
    -- the character and its last known guild are there right away, so lookups see that guild's data
    assert.equals("Jaina Proudmoore", ns.Core.store:GetCurrentChar())
    assert.equals("Die Gilde", ns.Core.store:GetCurrentGuild())

    wow.guildName = "Die Gilde"
    fire("GUILD_ROSTER_UPDATE")
    assert.equals("Die Gilde", ns.Core.store:GetCurrentGuild())
    assert.is_table(GrudgeForeverDB.guilds["Die Gilde"])
    assert.is_table(GrudgeForeverDB.guilds["Alte Gilde"])
  end)

  it("sends nothing until the guild is resolved, then switches to the new guild", function()
    _G.GrudgeForeverDB = {
      myChars = { ["jaina proudmoore"] = { name = "Jaina Proudmoore", guild = "Die Gilde", lastSeen = 1 } },
      guilds = { ["Die Gilde"] = { owners = {} } },
    }
    wow.inGuild = true
    login()
    local send = spy.on(ns.Core.transport, "Send")
    ns.Core.Change(function(store) store:AddOrUpdate("enemy", "Thrall Earthson", "x") end)
    SlashCmdList.GRUDGEFOREVER("sync")
    assert.is_true(chatContains(ns.L["SYNC_NO_GUILD"]))
    wow.runTimers()
    assert.spy(send).was_not_called()

    -- the character changed guilds while logged out
    wow.guildName = "Neue Gilde"
    fire("PLAYER_GUILD_UPDATE", "player")
    assert.equals("Neue Gilde", ns.Core.store:GetCurrentGuild())
    assert.is_nil(GrudgeForeverDB.guilds["Die Gilde"])
  end)

  it("drops the guild cache of a guild the character left", function()
    _G.GrudgeForeverDB = {
      myChars = { ["jaina proudmoore"] = { name = "Jaina Proudmoore", guild = "Die Gilde", lastSeen = 1 } },
      guilds = { ["Die Gilde"] = { owners = {} } },
    }
    wow.inGuild = false
    login()
    assert.is_nil(ns.Core.store:GetCurrentGuild())
    assert.is_nil(GrudgeForeverDB.guilds["Die Gilde"])
  end)

  it("says hello once on the first roster update, complete or not", function()
    wow.inGuild = true
    wow.guildName = "Die Gilde"
    login()
    local sent = spy.on(ns.Core.transport, "Send")
    wow.roster = { "Jaina Proudmoore", wow.secret("Thrall Earthson") }
    fire("GUILD_ROSTER_UPDATE")
    assert.spy(sent).was_called(1)
    assert.equals("H", sent.calls[1].vals[2].t)
    wow.roster = { "Jaina Proudmoore", "Thrall Earthson" }
    fire("GUILD_ROSTER_UPDATE")
    wow.runTimers()
    assert.spy(sent).was_called(1)
  end)

  it("says hello after a while when no roster update arrives", function()
    wow.inGuild = true
    wow.guildName = "Die Gilde"
    login()
    local sent = spy.on(ns.Core.transport, "Send")
    assert.spy(sent).was_not_called()
    wow.runTimers()
    assert.spy(sent).was_called(1)
    assert.equals("H", sent.calls[1].vals[2].t)
  end)

  it("says no hello while the guild name is unknown", function()
    wow.inGuild = true
    login()
    local sent = spy.on(ns.Core.transport, "Send")
    wow.roster = { "Jaina Proudmoore" }
    fire("GUILD_ROSTER_UPDATE")
    wow.runTimers()
    assert.spy(sent).was_not_called()
    wow.guildName = "Die Gilde"
    fire("GUILD_ROSTER_UPDATE")
    assert.spy(sent).was_called(1)
  end)

  it("says hello when the sync mode is switched to automatic in the options", function()
    local radios = {}
    _G.Settings = {
      RegisterCanvasLayoutCategory = function() return wow.proxy() end,
      RegisterAddOnCategory = function() end,
    }
    local createFrame = CreateFrame
    _G.CreateFrame = function(kind, ...)
      local frame = createFrame(kind, ...)
      if kind == "DropdownButton" then
        rawset(frame, "SetupMenu", function(_, build)
          build(nil, { CreateRadio = function(_, _, _, select, value)
            radios[#radios + 1] = { value = value, select = select }
          end })
        end)
      end
      return frame
    end
    wow.inGuild = true
    wow.guildName = "Die Gilde"
    _G.GrudgeForeverDB = { settings = { syncMode = "manual" } }
    login()
    fire("GUILD_ROSTER_UPDATE")
    local sent = spy.on(ns.Core.transport, "Send")
    for _, radio in ipairs(radios) do
      if radio.value == "auto" then radio.select("auto") end
    end
    assert.equals("auto", GrudgeForeverDB.settings.syncMode)
    assert.spy(sent).was_called(1)
    assert.equals("H", sent.calls[1].vals[2].t)
  end)

  it("works without the guild roster API and without PlaySoundFile", function()
    _G.GetGuildRosterInfo = nil
    _G.PlaySoundFile = nil
    wow.inGuild = true
    wow.guildName = "Die Gilde"
    login()
    local sent = spy.on(ns.Core.transport, "Send")
    assert.has_no.errors(function() fire("GUILD_ROSTER_UPDATE") end)
    assert.spy(sent).was_called(1)

    LibStub("LibSharedMedia-3.0"):Register("sound", "GF Test", "Sound\\gf-test.ogg")
    GrudgeForeverDB.settings.lists.enemy.sound = "GF Test"
    assert.has_no.errors(function() ns.Core.TestAlert("enemy") end)
    assert.is_true(chatContains(ns.L["TEST_REASON"]))
  end)

  it("shows the minimap button through the embedded LibDBIcon", function()
    login()
    assert.is_true(LibStub("LibDBIcon-1.0"):IsRegistered("GrudgeForever"))
    assert.same({ hide = false }, GrudgeForeverDB.settings.minimap)
  end)

  it("puts a player the user ignores on the Blacklist", function()
    local ignoredNames = {}
    _G.C_FriendList = {
      AddOrDelIgnore = function(name) ignoredNames[name] = not ignoredNames[name] end,
      IsOnIgnoredList = function(name) return ignoredNames[name] == true end,
    }
    _G.hooksecurefunc = function(t, key, fn)
      local orig = t[key]
      t[key] = function(...)
        orig(...)
        fn(...)
      end
    end
    login()
    C_FriendList.AddOrDelIgnore("Spitz-Ohr")
    fire("IGNORELIST_UPDATE")
    local entry = ns.Core.store:GetOwnEntry("friendly", "Spitz Ohr")
    assert.equals("IgnoreList Import", entry.reason)
    assert.is_true(chatContains(ns.L["IGNORE_ADDED"]:format("Spitz Ohr")))
  end)

  it("hints at disabled enemy nameplates once per account", function()
    wow.cvars.nameplateShowEnemies = false
    login()
    assert.is_true(chatContains(ns.L["HINT_NAMEPLATES"]))

    wow.chat = {}
    loadAddon()
    login()
    assert.is_false(chatContains(ns.L["HINT_NAMEPLATES"]))
  end)

  it("does not hint while enemy nameplates are on", function()
    wow.cvars.nameplateShowEnemies = true
    login()
    assert.is_false(chatContains(ns.L["HINT_NAMEPLATES"]))
  end)

  it("plays a test alert from the options panel without a cooldown", function()
    login()
    ns.Core.TestAlert("enemy")
    ns.Core.TestAlert("enemy")
    assert.equals(2, #wow.sounds)
    assert.is_true(chatContains(ns.L["TEST_REASON"]))
  end)

  it("runs every slash command without errors", function()
    wow.inGuild = true
    wow.guildName = "Die Gilde"
    login()
    local run = SlashCmdList.GRUDGEFOREVER
    for _, line in ipairs({ "", "", "help", "add Thrall Earthson pöbelt", "add", "remove", "export", "import",
                            "debug", "debug", "config", "frobnicate" }) do
      run(line)
    end
    assert.is_true(chatContains(ns.L["HELP_HEADER"]))
    assert.is_true(chatContains(ns.L["SLASH_NO_TARGET"]))
  end)

  it("deletes own entries and syncs via /gf remove", function()
    login()
    ns.Core.store:AddOrUpdate("enemy", "Thrall Earthson", "x")
    SlashCmdList.GRUDGEFOREVER("remove Thrall-Earthson")
    assert.same({}, ns.Core.store:Lookup("Thrall Earthson"))
    assert.is_true(chatContains("Thrall Earthson"))
  end)

  it("reports the manual sync state via /gf sync", function()
    login()
    SlashCmdList.GRUDGEFOREVER("sync")
    assert.is_true(chatContains(ns.L["SYNC_NO_GUILD"]))

    GrudgeForeverDB.settings.syncMode = "off"
    SlashCmdList.GRUDGEFOREVER("sync")
    assert.is_true(chatContains(ns.L["SYNC_OFF"]))
  end)

  it("starts a manual sync and then reports the cooldown", function()
    wow.inGuild = true
    wow.guildName = "Die Gilde"
    login()
    SlashCmdList.GRUDGEFOREVER("sync")
    assert.is_true(chatContains(ns.L["SYNC_STARTED"]))
    wow.now = wow.now + 100
    SlashCmdList.GRUDGEFOREVER("sync")
    assert.is_true(chatContains(ns.L["SYNC_COOLDOWN"]:format(200)))
  end)

  describe("main window", function()
    local initializer, items

    local function frameNamed(name)
      for _, frame in ipairs(wow.frames) do
        if frame:GetName() == name then return frame end
      end
    end

    local function buttonLabeled(text)
      for _, frame in ipairs(wow.frames) do
        if frame:GetText() == text and frame:GetScript("OnClick") then return frame end
      end
    end

    -- Builds one stub row per list item through the view's initializer.
    local function rows()
      local out = {}
      for i, item in ipairs(items) do
        out[i] = wow.proxy()
        initializer(out[i], item)
      end
      return out
    end

    before_each(function()
      _G.CreateScrollBoxListLinearView = function()
        local view = wow.proxy()
        view.SetElementInitializer = function(_, _, fn) initializer = fn end
        return view
      end
      _G.CreateDataProvider = function(list)
        items = list
        return wow.proxy()
      end
      wow.inGuild = true
      wow.guildName = "Die Gilde"
      login()
      local store = ns.Core.store
      store:AddOrUpdate("friendly", "Thrall Earthson", "pöbelt")
      store:ApplyDelta({ o = "aaaaaaaaaaaaaaaa", rev = 2, base = 0, lastChar = "Arthas Menethil", chars = {}, e = {
        { key = "thrall earthson", name = "Thrall Earthson", list = "friendly", reason = "afk",
          created = 1, updated = 2, rev = 1, deleted = false },
        { key = "sylvanas windrunner", name = "Sylvanas Windrunner", list = "friendly", reason = "ninja",
          created = 1, updated = 2, rev = 2, deleted = false },
      } })
    end)

    it("lists one row per player and expands a player into its entries", function()
      SlashCmdList.GRUDGEFOREVER("")
      assert.is_true(frameNamed("GrudgeForeverMainWindow"):IsShown())
      assert.equals(2, #items)
      local list = rows()
      wow.fire(list[2], "OnClick") -- Thrall Earthson: own + foreign entry
      assert.equals(4, #items)
      rows()
    end)

    it("adopts a foreign entry and mutes a player listed only by others", function()
      SlashCmdList.GRUDGEFOREVER("")
      wow.fire(rows()[1], "OnClick") -- Sylvanas Windrunner, only a foreign entry
      wow.fire(buttonLabeled(ns.L["MENU_MUTE"]), "OnClick")
      assert.is_true(ns.Core.store:IsMuted("friendly", "Sylvanas Windrunner"))
      wow.fire(buttonLabeled(ns.L["MENU_UNMUTE"]), "OnClick")
      assert.is_false(ns.Core.store:IsMuted("friendly", "Sylvanas Windrunner"))

      local send = spy.on(ns.Core.transport, "Send")
      wow.fire(buttonLabeled(ns.L["MW_ADOPT"]), "OnClick")
      assert.is_true(ns.Core.store:Lookup("Sylvanas Windrunner", "friendly")[1].isOwn)
      assert.spy(send).was_called(1)
      assert.is_true(chatContains(ns.L["MW_ADOPTED"]:format(1)))
    end)

    it("escapes pipes in names, reasons and creators from other players", function()
      ns.Core.store:ApplyDelta({ o = "bbbbbbbbbbbbbbbb", rev = 1, base = 0, lastChar = "Ev|cffil Guy", chars = {}, e = {
        { key = "a|hb c", name = "A|Hb C", list = "friendly", reason = "x|Ty", origin = "O|r P",
          created = 1, updated = 2, rev = 1, deleted = false },
      } })
      SlashCmdList.GRUDGEFOREVER("")
      local list = rows()
      local cells = list[1].cells
      assert.equals("A||Hb C", cells[1]:GetText())
      assert.equals("x||Ty", cells[2]:GetText())
      assert.truthy(cells[3]:GetText():find("Ev||cffil Guy", 1, true))
      assert.truthy(cells[3]:GetText():find("O||r P", 1, true))
      wow.fire(list[1], "OnClick")
      assert.is_not_nil(buttonLabeled(ns.L["MW_ADOPT_ALL"]:format("Ev||cffil Guy")))
    end)

    it("filters by name", function()
      SlashCmdList.GRUDGEFOREVER("")
      local search
      for _, frame in ipairs(wow.frames) do
        if frame:GetScript("OnTextChanged") then search = frame end
      end
      search:SetText("sylv")
      wow.fire(search, "OnTextChanged")
      assert.equals(1, #items)
      assert.equals("sylvanas windrunner", items[1].key)
    end)

    -- The edit dialog is created after the main window, so its buttons come last.
    local function lastButtonLabeled(text)
      local found
      for _, frame in ipairs(wow.frames) do
        if frame:GetText() == text and frame:GetScript("OnClick") then found = frame end
      end
      return found
    end

    it("deletes the edited own entry from the edit dialog after confirming", function()
      local popup
      _G.StaticPopup_Show = function(which, text, _, data) popup = { which = which, text = text, data = data } end
      SlashCmdList.GRUDGEFOREVER("")
      wow.fire(rows()[2], "OnClick") -- Thrall Earthson, own entry
      wow.fire(buttonLabeled(ns.L["MW_EDIT"]), "OnClick")
      local dialog = frameNamed("GrudgeForeverEditDialog")
      local delete = lastButtonLabeled(ns.L["MW_DELETE"])
      assert.is_true(delete:IsShown())

      wow.fire(delete, "OnClick")
      assert.equals("GRUDGEFOREVER_DELETE", popup.which)
      assert.equals("Thrall Earthson", popup.text)
      StaticPopupDialogs[popup.which].OnAccept(nil, popup.data)
      local entry = ns.Core.store:GetOwnEntry("friendly", "Thrall Earthson")
      assert.is_true(entry == nil or entry.deleted)
      assert.is_false(dialog:IsShown())

      wow.fire(buttonLabeled(ns.L["MW_ADD"]), "OnClick")
      assert.is_true(dialog:IsShown())
      assert.is_false(delete:IsShown())
    end)

    it("locks the list choice when the dialog opens with a fixed list", function()
      ns.UI.EditDialog.Open("Jaina Proudmoore", "friendly", nil, nil, true)
      local dialog = frameNamed("GrudgeForeverEditDialog")
      assert.is_false(dialog.list:IsEnabled())
      ns.UI.EditDialog.Open("Jaina Proudmoore", "friendly")
      assert.is_true(dialog.list:IsEnabled())
    end)

    it("opens the settings from the gear button", function()
      local opened = spy.on(ns.OptionsPanel, "Open")
      SlashCmdList.GRUDGEFOREVER("")
      wow.fire(frameNamed("GrudgeForeverMainWindowOptions"), "OnClick")
      assert.spy(opened).was_called(1)
    end)

    it("opens the edit, export and import dialogs from its buttons", function()
      SlashCmdList.GRUDGEFOREVER("")
      wow.fire(rows()[2], "OnClick")
      wow.fire(buttonLabeled(ns.L["MW_EDIT"]), "OnClick")
      assert.is_true(frameNamed("GrudgeForeverEditDialog"):IsShown())
      wow.fire(buttonLabeled(ns.L["MW_ADD"]), "OnClick")
      wow.fire(buttonLabeled(ns.L["MW_EXPORT"]), "OnClick")
      assert.is_true(frameNamed("GrudgeForeverTextDialog"):IsShown())
      wow.fire(buttonLabeled(ns.L["MW_IMPORT"]), "OnClick")
    end)
  end)
end)
