--[[
	EventBridge — the engine's event bus. Systems fire semantic events; anything
	(achievements, quests, analytics, an external webhook) can subscribe with zero
	changes to the firing code.

		local disconnect = EventBridge.onFire(function(eventType, player, data) ... end)
		EventBridge.fire("animal_killed", player, { species = "deer" })
]]

local EventBridge = {}

type Listener = (eventType: string, player: Player?, data: { [string]: any }) -> ()

local listeners: { Listener } = {}

function EventBridge.onFire(callback: Listener): () -> ()
	table.insert(listeners, callback)
	return function()
		local i = table.find(listeners, callback)
		if i then
			table.remove(listeners, i)
		end
	end
end

function EventBridge.fire(eventType: string, player: Player?, data: { [string]: any }?)
	local payload = data or {}
	for _, cb in listeners do
		task.spawn(cb, eventType, player, payload)
	end
	-- TODO (extraction): optional HTTP forwarding + batched queue, endpoint from Config.
end

return EventBridge
