--!nonstrict
--[[
	MovementConfig — tuning for the sprint / jump / energy system and its low-stat feedback.
	SHARED (server reads movement/energy; client reads audio/feedback). Defines the "Movement"
	Config section so games retune via `Config.override("Movement", { Energy = { ... } })`.

	Numbers + asset ids ported from The Counter Earth (its GameplayConfig + AssetIds) — proven,
	tuned values. Read the merged section with MovementConfig.get().
]]

local Config = require(script.Parent.Parent.foundation.Config)

local MovementConfig = {}

MovementConfig.SECTION = "Movement"

MovementConfig.DEFAULTS = {
	Energy = {
		Max = 100, -- matches the Energy stat's max in StatDefs
		SprintDrainPerSecond = 16,
		JumpCost = 10,
		RegenPerSecond = 14,
		RegenDelaySeconds = 0.75, -- regen waits this long after the last sprint/jump
		MinToJump = 10, -- can't jump below this much energy
	},
	Movement = {
		WalkSpeed = 16,
		SprintSpeed = 24,
		ExhaustedSpeed = 6, -- forced speed at 0 energy
		JumpPower = 80,
	},
	Health = {
		HeartbeatStartRatio = 0.4, -- heartbeat audio fades in below this fraction of health
	},
	Audio = {
		BreathingMaxVolume = 0.9,
		BreathingMinSpeed = 0.9,
		BreathingMaxSpeed = 1.5,
		HeartbeatMaxVolume = 1,
		HeartbeatMinSpeed = 0.9,
		HeartbeatMaxSpeed = 1.8,
	},
	-- Free default art (the engine ships these; override per game). "" disables a piece.
	Assets = {
		Vignette = "rbxassetid://117281807378470",
		Breathing = "rbxassetid://109256307915148",
		Heartbeat = "rbxassetid://90073835550134",
	},
}

-- Define the section once per Luau VM (server and client each require this module once).
Config.defineSection(MovementConfig.SECTION, MovementConfig.DEFAULTS)

-- The merged (defaults + overrides) Movement config table.
function MovementConfig.get(): any
	return Config.get(MovementConfig.SECTION) or MovementConfig.DEFAULTS
end

return MovementConfig
