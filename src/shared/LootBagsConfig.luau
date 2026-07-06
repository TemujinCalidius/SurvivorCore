--!nonstrict
--[[
	LootBagsConfig — tuning for death loot bags (issue #19). SHARED. Defines the "LootBags" Config
	section so games retune via `Config.override("LootBags", { ... })`. Read the merged section
	with LootBagsConfig.get().
]]

local Config = require(script.Parent.Parent.foundation.Config)

local LootBagsConfig = {}

LootBagsConfig.SECTION = "LootBags"

LootBagsConfig.DEFAULTS = {
	Enabled = true, -- false = nothing drops on death (inventory persists through death)
	DropEquipment = true, -- also drop WORN equipment (hat/satchel/…); false = only carried items
	LifetimeSeconds = 300, -- how long a bag lingers before despawning (with whatever's left in it)
	InteractRange = 8, -- studs; the bag's ProximityPrompt activation distance
	ShowCountdown = true, -- a floating "time left" label above the bag (everyone sees it)
	OwnerBeacon = true, -- a tall golden beam over the bag, visible ONLY to its owner
}

Config.defineSection(LootBagsConfig.SECTION, LootBagsConfig.DEFAULTS)

function LootBagsConfig.get(): any
	return Config.get(LootBagsConfig.SECTION) or LootBagsConfig.DEFAULTS
end

return LootBagsConfig
