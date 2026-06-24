--!nonstrict
--[[
	CraftingConfig — tuning for hand crafting (issue #4). Defines the "Crafting" Config section so
	games retune via `Config.override("Crafting", { ... })`. Read with CraftingConfig.get().
]]

local Config = require(script.Parent.Parent.foundation.Config)

local CraftingConfig = {}

CraftingConfig.SECTION = "Crafting"

CraftingConfig.DEFAULTS = {
	-- Craft channel time = BaseCraftTime + TimePerIngredient × (total ingredient units), clamped to
	-- MaxCraftTime — so more complex recipes take longer. A recipe may override with `craftTime`.
	BaseCraftTime = 0.6,
	TimePerIngredient = 0.5,
	MaxCraftTime = 8,
}

Config.defineSection(CraftingConfig.SECTION, CraftingConfig.DEFAULTS)

function CraftingConfig.get(): any
	return Config.get(CraftingConfig.SECTION) or CraftingConfig.DEFAULTS
end

return CraftingConfig
