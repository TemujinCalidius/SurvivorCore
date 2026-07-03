--!nonstrict
--[[
	QuestsConfig — tuning for the quest system (issue #10). SHARED (the server runtime enforces the
	limits; the client tab only renders). Defines the "Quests" Config section so games retune via
	`Config.override("Quests", { ... })`. Read the merged section with QuestsConfig.get().
]]

local Config = require(script.Parent.Parent.foundation.Config)

local QuestsConfig = {}

QuestsConfig.SECTION = "Quests"

QuestsConfig.DEFAULTS = {
	MaxActive = 0, -- max quests a player can have active at once; 0 = unlimited
	Toasts = true, -- show a toast notification when a quest completes
}

Config.defineSection(QuestsConfig.SECTION, QuestsConfig.DEFAULTS)

function QuestsConfig.get(): any
	return Config.get(QuestsConfig.SECTION) or QuestsConfig.DEFAULTS
end

return QuestsConfig
