--[[
	Gatherable — the flagship creator-owned component.

	A creator builds ANY part/mesh, tags it "Gatherable", and EITHER:
	  • points it at a named resource def — `Resource = "oak_tree"` — inheriting item/hp/tool/yield
	    from `SurvivorCore.Resources` (authored in code or no-code via the admin plugin); or
	  • sets raw attributes per node: `ItemId`, `HP`, `RequireTool`, `YieldMin`/`YieldMax`
	    (or legacy single `Yield`). Raw attributes override the resource def.

	Interaction is auto-derived: a node that needs a tool (`RequireTool`) is click-to-swing; a
	bare-hand node is a hold-E ProximityPrompt. Set `Interaction` ("prompt"/"tool") to force it.
	Both paths route every hit through the server `Harvesting` resolver (validation, per-hit yield,
	HP, depletion). Per-type juice (shake, fell, stump) attaches via `SurvivorCore.Gather.onReaction`
	— no core edits. Set `DestroyOnDeplete = false` to keep the node so a reaction can transform it.
]]

local Components = require(script.Parent)
local Registries = require(script.Parent.Parent.registries)
local Harvesting = require(script.Parent.Parent.systems.Harvesting)

-- Resolve the node's effective values from its resource def (if any) + per-node overrides.
local function resolve(values: { [string]: any })
	local def = nil
	if values.Resource ~= "" then
		def = Registries.Resources.get(values.Resource)
	end

	local item = values.ItemId ~= "" and values.ItemId or (def and def.item) or ""
	local hp = values.HP > 0 and values.HP or (def and tonumber(def.hp)) or 3
	local requireTool = values.RequireTool ~= "" and values.RequireTool or (def and def.requireTool) or ""

	-- Yield: explicit Min/Max win; else legacy single Yield; else the resource def; else 1.
	local yMin, yMax
	if values.YieldMin > 0 or values.YieldMax > 0 then
		yMin, yMax = values.YieldMin, values.YieldMax
	elseif values.Yield > 0 then
		yMin, yMax = values.Yield, values.Yield
	elseif def then
		yMin, yMax = tonumber(def.yieldMin) or 1, tonumber(def.yieldMax) or 1
	else
		yMin, yMax = 1, 1
	end
	if yMin <= 0 then
		yMin = 1
	end
	if yMax < yMin then
		yMax = yMin
	end

	local interaction = values.Interaction
	if interaction ~= "prompt" and interaction ~= "tool" then
		interaction = if requireTool ~= "" then "tool" else "prompt" -- "auto"
	end

	return {
		resource = values.Resource ~= "" and values.Resource or nil,
		item = item,
		hp = hp,
		requireTool = requireTool,
		yieldMin = yMin,
		yieldMax = yMax,
		interaction = interaction,
		destroyOnDeplete = values.DestroyOnDeplete,
	}
end

return Components.define({
	name = "Gatherable",
	tag = "Gatherable",
	attributes = {
		Resource = "", -- named resource def to inherit from (optional)
		ItemId = "", -- override / bare-hand item id
		Yield = 0, -- legacy single per-hit yield (use YieldMin/Max for a range)
		YieldMin = 0,
		YieldMax = 0,
		HP = 0, -- 0 = inherit from the resource def (or default 3)
		RequireTool = "", -- tool type needed (e.g. "axe"); "" = bare-hand
		Interaction = "auto", -- "auto" | "prompt" | "tool"
		DestroyOnDeplete = true, -- false keeps the node for a reaction to transform (stump/fell)
	},
	onSetup = function(instance, values)
		local r = resolve(values)

		-- Stash the resolved values so the server Harvesting resolver reads one source of truth.
		instance:SetAttribute("_Resource", r.resource)
		instance:SetAttribute("_ItemId", r.item)
		instance:SetAttribute("_RequireTool", r.requireTool)
		instance:SetAttribute("_YieldMin", r.yieldMin)
		instance:SetAttribute("_YieldMax", r.yieldMax)
		instance:SetAttribute("_DestroyOnDeplete", r.destroyOnDeplete)
		instance:SetAttribute("_HP", r.hp)
		instance:SetAttribute("_MaxHP", r.hp) -- for the floating "HP left" bar's ratio

		if r.interaction == "tool" then
			return -- click-to-swing: the client ToolHarvest controller + HarvestSwing remote drive it
		end

		-- Bare-hand: a hold-E ProximityPrompt routed through the same server resolver.
		local host = if instance:IsA("BasePart") then instance else instance:FindFirstChildWhichIsA("BasePart")
		if not host then
			warn(`[Gatherable] '{instance:GetFullName()}' has no BasePart to host a prompt`)
			return
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Gather"
		prompt.ObjectText = r.resource or (r.item ~= "" and r.item) or "Resource"
		prompt.HoldDuration = 0.4
		prompt.RequiresLineOfSight = false
		prompt.Parent = host

		prompt.Triggered:Connect(function(player)
			Harvesting.tryHarvest(instance, player, "prompt")
		end)
	end,
})
