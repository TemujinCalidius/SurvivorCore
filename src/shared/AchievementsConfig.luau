--!nonstrict
--[[
	AchievementsConfig — tuning for the achievements system. SHARED. Defines the "Achievements"
	Config section so games retune via `Config.override("Achievements", { ... })`. Read the merged
	section with AchievementsConfig.get().
]]

local Config = require(script.Parent.Parent.foundation.Config)

local AchievementsConfig = {}

AchievementsConfig.SECTION = "Achievements"

AchievementsConfig.DEFAULTS = {
	Toasts = true, -- show a toast notification when an achievement unlocks
}

Config.defineSection(AchievementsConfig.SECTION, AchievementsConfig.DEFAULTS)

function AchievementsConfig.get(): any
	return Config.get(AchievementsConfig.SECTION) or AchievementsConfig.DEFAULTS
end

return AchievementsConfig
