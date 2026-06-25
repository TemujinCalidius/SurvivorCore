--!nonstrict
--[[
	MobsConfig — tuning for the mob & AI engine (issue #17). SHARED (the server runs the FSM; the
	client never needs it today, but it lives in shared like the other config sections). Defines the
	"Mobs" Config section so games retune via `Config.override("Mobs", { ... })`.

	These are ENGINE-WIDE defaults. Per-mob-type values (health, ranges, damage) live on the Mobs
	registry def / the `Mob` component's attributes and override these — these only apply when a mob
	leaves a field unset. Read the merged section with MobsConfig.get().
]]

local Config = require(script.Parent.Parent.foundation.Config)

local MobsConfig = {}

MobsConfig.SECTION = "Mobs"

MobsConfig.DEFAULTS = {
	TickRate = 0.2, -- seconds between AI ticks per mob (the FSM cadence)
	DefaultAggroRange = 40, -- studs; how close a player must be for a hostile mob to notice (or a passive to flee)
	DefaultLeashRange = 60, -- studs from spawn; past this a chasing mob gives up and returns
	DefaultAttackRange = 6, -- studs; melee reach of a hostile mob's attack
	DefaultAttackDamage = 8, -- HP per landed mob attack
	DefaultAttackCooldown = 1.5, -- seconds between a mob's attacks
	DefaultWanderRadius = 12, -- studs around spawn a mob idles/wanders within
	RequireLineOfSight = true, -- a hostile mob must see a player (raycast) to aggro
	RespawnSeconds = 30, -- default respawn delay for mobs spawned with respawn = true (0 = no respawn)
	CorpseSeconds = 5, -- how long a dead mob's body lingers before it's removed (a death reaction can fade it)
}

Config.defineSection(MobsConfig.SECTION, MobsConfig.DEFAULTS)

function MobsConfig.get(): any
	return Config.get(MobsConfig.SECTION) or MobsConfig.DEFAULTS
end

return MobsConfig
