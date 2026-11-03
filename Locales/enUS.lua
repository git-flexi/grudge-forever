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
