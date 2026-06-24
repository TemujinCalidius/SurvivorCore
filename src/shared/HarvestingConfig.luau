--!nonstrict
--[[
	HarvestingConfig — tuning for tool-swing harvesting (issue #1). SHARED (the server validates
	swings; the client uses the range for its target pre-check). Defines the "Harvesting" Config
	section so games retune via `Config.override("Harvesting", { ... })`.

	Read the merged section with HarvestingConfig.get().
]]

local Config = require(script.Parent.Parent.foundation.Config)

local HarvestingConfig = {}

HarvestingConfig.SECTION = "Harvesting"

HarvestingConfig.DEFAULTS = {
	SwingRange = 12, -- studs; max player→node distance for a tool swing (server-validated)
	SwingCooldown = 0.45, -- seconds between accepted hits per player (anti-spam)
	RequireLineOfSight = true, -- raycast player→node; blocks swings through walls
	ShowHealthBar = true, -- a floating "HP left" bar above a node while it's being harvested
}

Config.defineSection(HarvestingConfig.SECTION, HarvestingConfig.DEFAULTS)

function HarvestingConfig.get(): any
	return Config.get(HarvestingConfig.SECTION) or HarvestingConfig.DEFAULTS
end

return HarvestingConfig
