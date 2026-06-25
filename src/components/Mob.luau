--[[
	Mob — the creature component. A creator builds (or imports) any rigged Model with a Humanoid +
	PrimaryPart, tags it "Mob", and sets `MobType = "<id>"` to inherit health/speed/ranges/faction
	from a `SurvivorCore.Mobs` def (authored in code or no-code via the admin plugin). Per-instance
	attributes (Faction, Health, AggroRange, …) override the def for that one mob.

	On setup the node is handed to the server `Mobs` runtime (`Mobs.adopt`), which resolves its
	effective stats, sets the Humanoid health, and starts the AI FSM (idle/wander/chase/attack/flee).
	Combat damages it like any Humanoid; per-type juice (death fade, spawn cry) attaches via
	`SurvivorCore.Mobs.onReaction` — no core edits. This is the Builder-UI-drivable creature path
	(#11/#14): the attribute set below is the schema the admin plugin's Mobs editor writes.
]]

local Components = require(script.Parent)
local Mobs = require(script.Parent.Parent.systems.Mobs)

return Components.define({
	name = "Mob",
	tag = "Mob",
	attributes = {
		MobType = "", -- the Mobs def id to inherit from; blank = use the model's Name
		Faction = "", -- "hostile" | "passive" | "neutral"; blank = inherit the def (default "neutral")
		Health = 0, -- 0 = inherit the def (or 50)
		WalkSpeed = 0, -- 0 = inherit
		RunSpeed = 0, -- 0 = inherit
		AggroRange = 0, -- 0 = inherit / Config default
		LeashRange = 0, -- 0 = inherit / Config default
		AttackRange = 0, -- 0 = inherit / Config default
		AttackDamage = 0, -- 0 = inherit / Config default
		AttackCooldown = 0, -- 0 = inherit / Config default
		WanderRadius = 0, -- 0 = inherit / Config default
	},
	onSetup = function(instance, _values)
		-- The server Mobs runtime reads the instance attributes directly (one merge path:
		-- override attr › registry def › "Mobs" Config), so nothing to stash here — just adopt it.
		if instance:IsA("Model") then
			Mobs.adopt(instance)
		else
			warn(`[Mob] '{instance:GetFullName()}' must be a Model (Humanoid + PrimaryPart) to be a mob`)
		end
	end,
})
