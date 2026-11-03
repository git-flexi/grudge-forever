std = "lua51"
exclude_files = { "Libs/**", ".luarocks/**" }
max_line_length = 120
-- every addon file starts with `local ADDON, ns = ...`; ADDON is often unused
ignore = { "211/ADDON" }

-- WoW APIs used by the addon (later tasks extend this list)
read_globals = {
  "issecretvalue", "UnitExists", "UnitIsPlayer", "UnitName", "UnitFactionGroup",
  "GetLocale", "GetServerTime", "C_Timer", "C_ChatInfo", "IsInGuild", "LibStub",
  "CreateFrame", "UIParent",
}

-- the single addon-owned global
globals = { "GrudgeForeverDB" }

files["tests/**"] = {
  std = "+busted",
  -- the test helper installs WoW stubs as globals
  globals = {
    "issecretvalue", "UnitExists", "UnitIsPlayer", "UnitName", "UnitFactionGroup",
    "GetLocale", "GetServerTime", "C_Timer", "C_ChatInfo", "IsInGuild", "LibStub",
    "CreateFrame", "UIParent", "GrudgeForeverDB",
  },
}
