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
local Schema = require(script.Parent.Schema)
local Mobs = require(script.Parent.Parent.systems.Mobs)

-- Attributes + their creator-facing help text live in the schema (the Studio plugin renders this
-- component's setup form from it).
local SCHEMA = Schema.COMPONENTS.Mob

return Components.define({
	name = SCHEMA.name,
	tag = SCHEMA.tag,
	display = SCHEMA.display,
	attributes = SCHEMA.attributes,
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
