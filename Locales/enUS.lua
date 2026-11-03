local ADDON, ns = ...

-- Missing keys return the key itself, so untranslated strings stay readable.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

L["ADDON_TITLE"] = "GrudgeForever"
L["ADDON_NOTES"] = "Keep a list of players you hold a grudge against, and friends you like - shared with your friends."

L["TRIGGER_WHISPER"] = "is whispering you"
L["TRIGGER_INVITE"] = "is inviting you"
L["TRIGGER_GROUP"] = "is in your group"
L["TRIGGER_SIGHT"] = "is nearby"
L["DEFAULT_TEXT"] = "{name} {trigger}! {reason} (by {by})"
L["BANNER_PLACEHOLDER"] = "Drag to move the warning banner"
L["DEBUG_PREFIX"] = "[GrudgeForever debug]"

L["LIST_FRIENDLY"] = "Blacklist"
L["LIST_ENEMY"] = "KOS"
L["TOOLTIP_HEADER"] = "GrudgeForever (%s)"
L["TOOLTIP_BY"] = "by %s"
L["TOOLTIP_ADOPTED_FROM"] = "adopted from %s"
L["TOOLTIP_MORE"] = "+%d more"
L["TOOLTIP_MUTED"] = "muted"
L["MENU_ADD"] = "Add to GrudgeForever..."
L["MENU_EDIT"] = "Edit GrudgeForever entry..."
L["MENU_MUTE"] = "Mute"
L["MENU_UNMUTE"] = "Unmute"
