--[[
	Reactions — per-resource-type gather "juice" hooks.

	Global `Hooks.on("gather:hit", …)` fire for EVERY gatherable. Reactions instead bind behavior to
	ONE resource type, so a creator can make `"oak_tree"` shake + drop leaves on each hit and rez a
	stump + fell the trunk on depletion, while `"reed"` just sways — without filtering inside a
	global handler. The harvesting path dispatches these alongside the global Hooks.

		SurvivorCore.Gather.onReaction("oak_tree", "depleted", function(ctx)
			-- ctx = { instance, player, resource, item, position, granted?, hpLeft? }
			rezStumpAndFell(ctx.instance, ctx.position) -- creator content; engine ships none
		end)

	`event` is the gather event without the "gather:" prefix: "hit" | "depleted" | "blocked".
	Handlers run via task.spawn (a throwing reaction can't break the harvest). Registration is safe
	any time; reactions typically run server-side so part tweens / model swaps replicate.
]]

local Reactions = {}

-- handlers[resourceId][event] = { fn, ... }
local handlers: { [string]: { [string]: { (ctx: any) -> () } } } = {}

-- Register a reaction for a resource type + event. Returns an unsubscribe function.
function Reactions.on(resourceId: string, event: string, fn: (ctx: any) -> ()): () -> ()
	assert(type(resourceId) == "string" and resourceId ~= "", "Reactions.on: resourceId must be a non-empty string")
	assert(type(event) == "string" and event ~= "", "Reactions.on: event must be a non-empty string")
	assert(type(fn) == "function", "Reactions.on: fn must be a function")

	local byEvent = handlers[resourceId]
	if not byEvent then
		byEvent = {}
		handlers[resourceId] = byEvent
	end
	local list = byEvent[event]
	if not list then
		list = {}
		byEvent[event] = list
	end
	table.insert(list, fn)

	return function()
		local i = table.find(list, fn)
		if i then
			table.remove(list, i)
		end
	end
end

-- Dispatch a reaction event for a resource type. No-op when nothing is registered.
function Reactions.run(resourceId: string?, event: string, ctx: any)
	if resourceId == nil then
		return
	end
	local byEvent = handlers[resourceId]
	local list = byEvent and byEvent[event]
	if not list then
		return
	end
	for _, fn in list do
		task.spawn(fn, ctx)
	end
end

return Reactions
