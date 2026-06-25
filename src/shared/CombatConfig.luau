--!nonstrict
--[[
	CombatConfig — tuning for combat (issue #12). SHARED (the server validates every hit; the client
	uses MeleeRange for its target pre-check and the Bow values for the draw meter). Defines the
	"Combat" Config section so games retune via `Config.override("Combat", { ... })`.

	Per-weapon values (damage, range, cooldown, draw time) live on the weapon ITEM def as flat
	`weapon*` attributes and override these — these are the fallbacks when a weapon leaves a field
	unset. Read the merged section with CombatConfig.get().
]]

local Config = require(script.Parent.Parent.foundation.Config)

local CombatConfig = {}

CombatConfig.SECTION = "Combat"

CombatConfig.DEFAULTS = {
	MeleeRange = 8, -- studs; fallback melee reach when a weapon has no weaponRange (server-validated)
	MeleeCooldown = 0.6, -- seconds between accepted melee swings per player (anti-spam fallback)
	RequireLineOfSight = true, -- raycast attacker→target; blocks melee hits through walls
	FriendlyFire = false, -- false = players can't damage other players (mobs are always damageable)
	Bow = {
		Gravity = 80, -- studs/s² pulling the arrow down (arc); 0 = flat shot
		ProjectileSpeed = 180, -- studs/s at full draw (fallback when a bow has no weaponProjectileSpeed)
		MaxRange = 300, -- studs the server simulates a projectile before giving up
		MinDrawDamageMult = 0.3, -- damage multiplier at zero draw; scales up to 1.0 at full draw
		StepSize = 4, -- studs per raycast step when simulating the arc (smaller = more precise, costlier)
	},
}

Config.defineSection(CombatConfig.SECTION, CombatConfig.DEFAULTS)

function CombatConfig.get(): any
	return Config.get(CombatConfig.SECTION) or CombatConfig.DEFAULTS
end

return CombatConfig
