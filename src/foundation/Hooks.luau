--[[
	Hooks — lifecycle extension points. Where EventBridge is "something happened",
	Hooks is "the engine is about to / just did X — creators, do your thing here".

		Hooks.on("craft:start", function(ctx) ctx.station:lightFire() end)
		Hooks.on("craft:end",   function(ctx) ringBell(ctx.station) end)
		-- inside the engine:
		Hooks.run("craft:start", { station = station, recipe = recipe, player = player })

	This is how game-specific flourish (tree-felling physics, station VFX, custom drops)
	stays OUT of the engine while remaining first-class.
]]

local Hooks = {}

type Hook = (...any) -> ()

local hooks: { [string]: { Hook } } = {}

function Hooks.on(name: string, callback: Hook): () -> ()
	hooks[name] = hooks[name] or {}
	table.insert(hooks[name], callback)
	return function()
		local list = hooks[name]
		local i = list and table.find(list, callback)
		if i then
			table.remove(list, i)
		end
	end
end

function Hooks.run(name: string, ...)
	local list = hooks[name]
	if not list then
		return
	end
	for _, cb in list do
		task.spawn(cb, ...)
	end
end

return Hooks
