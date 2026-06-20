--!nonstrict
--[[
	ConsequenceConfig — how survival stats hurt you when they hit their dangerous extreme.
	SHARED. Defines the "Consequences" Config section; retune via
	`Config.override("Consequences", { HealthDrainPerSecond = { Starving = 1 } })`.

	Health drains STACK (starving + poisoned + bleeding out all add up). Rates ported from
	The Counter Earth's StatsConfig. Energy-regen blocking (while starving / dehydrated /
	fatigued) is a hard gate, not a rate, so it lives in the Movement system.
]]

local Config = require(script.Parent.Parent.foundation.Config)

local ConsequenceConfig = {}

ConsequenceConfig.SECTION = "Consequences"

ConsequenceConfig.DEFAULTS = {
	-- Health (HP) drained per second while each condition holds. They add together, so being
	-- both starving AND dehydrated kills in half the time. (Bleeding out at 0 Blood is INSTANT
	-- death, handled directly in SurvivalConsequences — not a drain rate.)
	HealthDrainPerSecond = {
		Starving = 100 / (8 * 3600), -- Hunger at max → ~8h to die
		Dehydrated = 100 / (8 * 3600), -- Thirst at max → ~8h to die (both together → ~4h)
		PoisonAtMax = 1.0, -- ONLY at 100% poison (~1.7 min to die); no partial-poison chip damage
	},
	-- Default rate a bleed / poison SOURCE applies. Gameplay can pass a stronger/weaker rate per
	-- source (a deep cut vs a graze); these are the engine's sensible defaults.
	Affliction = {
		BleedRatePerSecond = 100 / 3600, -- Blood lost/s while bleeding → ~1h to bleed out from full
		PoisonRatePerSecond = 100 / 3600, -- Poison gained/s while poisoned → ~1h to reach 100%
	},
}

Config.defineSection(ConsequenceConfig.SECTION, ConsequenceConfig.DEFAULTS)

function ConsequenceConfig.get(): any
	return Config.get(ConsequenceConfig.SECTION) or ConsequenceConfig.DEFAULTS
end

return ConsequenceConfig
