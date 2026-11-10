std = "lua51"
exclude_files = { "Libs/**", ".luarocks/**" }
max_line_length = 120
-- every addon file starts with `local ADDON, ns = ...`; ADDON is often unused
ignore = { "211/ADDON" }

-- WoW APIs used by the addon
read_globals = {
  "issecretvalue", "UnitExists", "UnitIsPlayer", "UnitName", "UnitFactionGroup",
  "GetLocale", "GetServerTime", "C_Timer", "C_ChatInfo", "IsInGuild", "LibStub",
  "CreateFrame", "UIParent", "TooltipDataProcessor", "Enum", "Menu", "Settings",
  "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "C_GuildInfo", "GetCVarBool",
  "IsInGroup", "IsInRaid", "GetNumGroupMembers", "PlaySound", "PlaySoundFile", "DEFAULT_CHAT_FRAME", "date",
  "ButtonFrameTemplate_HidePortrait", "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab",
  "PanelTemplates_EnableTab", "PanelTemplates_DisableTab",
  "CreateScrollBoxListLinearView", "CreateDataProvider", "ScrollUtil", "ScrollBoxConstants", "StaticPopup_Show",
  "geterrorhandler", "C_FriendList", "hooksecurefunc", "GameTooltip", "C_AddOns",
}

-- addon-owned globals, plus client tables the addon registers into
globals = {
  "GrudgeForeverDB", "SLASH_GRUDGEFOREVER1", "SLASH_GRUDGEFOREVER2", "SlashCmdList",
  "StaticPopupDialogs", "UISpecialFrames",
}

files["tests/**"] = {
  std = "+busted",
  -- the test helper installs WoW stubs as globals
  globals = {
    "issecretvalue", "UnitExists", "UnitIsPlayer", "UnitName", "UnitFactionGroup",
    "GetLocale", "GetServerTime", "C_Timer", "C_ChatInfo", "IsInGuild", "LibStub",
    "CreateFrame", "UIParent", "GrudgeForeverDB", "TooltipDataProcessor", "Enum", "Menu",
    "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "C_GuildInfo", "GetCVarBool",
    "IsInGroup", "IsInRaid", "GetNumGroupMembers", "PlaySound", "PlaySoundFile", "DEFAULT_CHAT_FRAME",
    "SlashCmdList", "SLASH_GRUDGEFOREVER1", "SLASH_GRUDGEFOREVER2", "date",
    "hooksecurefunc", "securecallfunction", "GetTime", "GetFramerate", "ChatThrottleLib", "C_UIFileAsset",
    "ButtonFrameTemplate_HidePortrait", "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab",
  "PanelTemplates_EnableTab", "PanelTemplates_DisableTab",
    "CreateScrollBoxListLinearView", "CreateDataProvider", "ScrollUtil", "ScrollBoxConstants",
    "StaticPopupDialogs", "StaticPopup_Show", "UISpecialFrames", "geterrorhandler", "Settings",
    "C_FriendList", "Minimap", "C_AddOns",
  },
}
