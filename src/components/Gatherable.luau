--[[
	Gatherable — the flagship creator-owned component.

	A creator builds ANY part/mesh, tags it "Gatherable", and sets attributes:
	  • ItemId (string) — what it yields
	  • Yield  (number) — amount per full harvest
	  • HP     (number) — interactions to deplete

	No engine-side content needed: the creator owns the object. Advanced behavior
	(custom drops, VFX, falling physics) attaches via Hooks rather than editing core.
]]

local Components = require(script.Parent)
local Hooks = require(script.Parent.Parent.foundation.Hooks)

return Components.define({
	name = "Gatherable",
	tag = "Gatherable",
	attributes = {
		ItemId = "unknown",
		Yield = 1,
		HP = 3,
	},
	onSetup = function(instance, values)
		instance:SetAttribute("_HP", values.HP)

		local host = if instance:IsA("BasePart") then instance else instance:FindFirstChildWhichIsA("BasePart")
		if not host then
			warn(`[Gatherable] '{instance:GetFullName()}' has no BasePart to host a prompt`)
			return
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Gather"
		prompt.ObjectText = tostring(values.ItemId)
		prompt.HoldDuration = 0.4
		prompt.Parent = host

		prompt.Triggered:Connect(function(player)
			local hp = (instance:GetAttribute("_HP") or 1) - 1
			instance:SetAttribute("_HP", hp)

			-- The Inventory system grants `values.Yield` of `values.ItemId` by subscribing to
			-- the "gather:depleted" hook below (kept here as a hook, not a direct call, to avoid
			-- a require cycle and to let any system observe gathers). "gather:hit" fires per
			-- interaction for games that want per-hit yield or swing feedback.
			Hooks.run("gather:hit", { instance = instance, player = player, values = values, hpLeft = hp })

			if hp <= 0 then
				Hooks.run("gather:depleted", { instance = instance, player = player, values = values })
				instance:Destroy()
			end
		end)
	end,
})
