local ADDON, ns = ...

-- /gf and /grudgeforever: a pure parser plus the command handlers. Handlers reach the running
-- addon through ns.Core (set up at login), so this file loads before Core.lua.
local Const, L, Names = ns.Const, ns.L, ns.Names

local Slash = {}

local COMMANDS = {
  toggle = true, add = true, remove = true, sync = true, export = true, import = true,
  debug = true, config = true, help = true,
}

local LISTS = { Const.LIST_FRIENDLY, Const.LIST_ENEMY }
local LIST_KEYS = { [Const.LIST_FRIENDLY] = "LIST_FRIENDLY", [Const.LIST_ENEMY] = "LIST_ENEMY" }

local HELP_KEYS = {
  "HELP_TOGGLE", "HELP_ADD", "HELP_REMOVE", "HELP_SYNC", "HELP_EXPORT", "HELP_IMPORT", "HELP_DEBUG", "HELP_CONFIG",
}

-- Splits "First Surname rest" / "First-Surname rest" into name and rest. A hyphenated first
-- token is a full name on its own; otherwise the name is the first two tokens.
local function splitName(text)
  local first, rest = text:match("^(%S+)%s*(.-)$")
  if not first then return nil, "" end
  if first:find("-", 1, true) then return first, rest end
  local second, after = rest:match("^(%S+)%s*(.-)$")
  if not second then return first, "" end
  return first .. " " .. second, after
end

-- Returns cmd, args. Empty input toggles the window, unknown commands show the help.
function Slash.Parse(msg)
  if type(msg) ~= "string" then msg = "" end
  local word, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  if word == "" then return "toggle", {} end
  local cmd = word:lower()
  if not COMMANDS[cmd] then return "help", {} end

  local args = {}
  if cmd == "add" or cmd == "remove" then
    local name, reason = splitName(rest)
    args.name = name
    if cmd == "add" and reason ~= "" then args.reason = reason end
  end
  return cmd, args
end

-- Handlers ---------------------------------------------------------------------

local handlers = {}

function handlers.toggle()
  ns.UI.MainWindow.Toggle()
end

-- Without a name the target is used, and its faction picks the list.
function handlers.add(args)
  local Core = ns.Core
  local name, list = args.name, nil
  if not name then
    name = Names.FromUnit("target")
    if not name then return Core.Print(L["SLASH_NO_TARGET"]) end
    list = ns.UnitMenu.IsOtherFaction("target") and Const.LIST_ENEMY or Const.LIST_FRIENDLY
  end
  if not Names.Normalize(name) then return Core.Print(L["ERR_INVALID_NAME"]) end
  ns.UI.EditDialog.Open(Names.Display(name), list, nil, args.reason)
end

-- Deletes the own entries for the player on both lists.
function handlers.remove(args)
  local Core = ns.Core
  local name = args.name or Names.FromUnit("target")
  if not name then return Core.Print(L["SLASH_NO_TARGET"]) end
  local display = Names.Display(name)
  if not display then return Core.Print(L["ERR_INVALID_NAME"]) end

  local removed = {}
  Core.Change(function(store)
    for _, list in ipairs(LISTS) do
      if store:Delete(list, display) then removed[#removed + 1] = L[LIST_KEYS[list]] end
    end
  end)
  if #removed > 0 then
    Core.Print(L["SLASH_REMOVED"]:format(display, table.concat(removed, ", ")))
  else
    Core.Print(L["SLASH_NOT_FOUND"]:format(display))
  end
end

function handlers.sync()
  ns.Core.ManualSync()
end

function handlers.export()
  ns.UI.TextDialog.Open("export")
end

function handlers.import()
  ns.UI.TextDialog.Open("import")
end

function handlers.debug()
  local settings = ns.Core.sv.settings
  settings.debug = not settings.debug
  ns.Core.Print(settings.debug and L["DEBUG_ON"] or L["DEBUG_OFF"])
end

function handlers.config()
  ns.OptionsPanel.Open()
end

function handlers.help()
  local Core = ns.Core
  Core.Print(L["HELP_HEADER"])
  for _, key in ipairs(HELP_KEYS) do Core.Print(L[key]) end
end

-- Runs one command line; does nothing until the addon is running.
function Slash.Run(msg)
  if not (ns.Core and ns.Core.ready) then return end
  local cmd, args = Slash.Parse(msg)
  handlers[cmd](args)
end

function Slash.Register()
  SLASH_GRUDGEFOREVER1 = "/gf"
  SLASH_GRUDGEFOREVER2 = "/grudgeforever"
  SlashCmdList.GRUDGEFOREVER = Slash.Run
end

ns.Slash = Slash
