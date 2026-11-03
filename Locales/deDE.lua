local ADDON, ns = ...

if GetLocale() ~= "deDE" then return end

local L = ns.L

L["ADDON_TITLE"] = "GrudgeForever"
L["ADDON_NOTES"] = "Führe eine Liste von Spielern, denen du grollst, "
  .. "und von Freunden, die du magst - geteilt mit deinen Freunden."
L["TRIGGER_WHISPER"] = "flüstert dir"
L["TRIGGER_INVITE"] = "lädt dich ein"
L["TRIGGER_GROUP"] = "ist in deiner Gruppe"
L["TRIGGER_SIGHT"] = "ist in Sicht"
L["DEFAULT_TEXT"] = "{name} {anlass}! {grund} (von {von})"
L["BANNER_PLACEHOLDER"] = "Ziehen, um das Warnbanner zu verschieben"
L["DEBUG_PREFIX"] = "[GrudgeForever Diagnose]"
