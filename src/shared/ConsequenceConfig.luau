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
	-- Health (HP) drained per second while each condition holds. They add together.
	HealthDrainPerSecond = {
		Starving = 0.5, -- Hunger at max
		Dehydrated = 1.0, -- Thirst at max (worse than hunger)
		BledOut = 3.0, -- Blood empty (0) — bleeding out, kills fast
		PoisonAtMax = 2.0, -- at 100% poison; scales linearly with the poison level
	},
}

Config.defineSection(ConsequenceConfig.SECTION, ConsequenceConfig.DEFAULTS)

function ConsequenceConfig.get(): any
	return Config.get(ConsequenceConfig.SECTION) or ConsequenceConfig.DEFAULTS
end

return ConsequenceConfig
