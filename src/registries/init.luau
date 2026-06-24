--[[
	The content registry family. Each is an empty registry the game populates at startup;
	the engine ships zero concrete items/recipes/lore/ids.

	NOTE: Crafting and cooking are ONE registry — `station` ("hand", "campfire", ...) is
	just a routing tag, per the boundary-map decision.
]]

local Registry = require(script.Parent.foundation.Registry)

local Registries = {}

Registries.Items = Registry.new("Items", { keyField = "id" })
Registries.Recipes = Registry.new("Recipes", { keyField = "id" })
-- A gatherable-resource def: what a tagged Gatherable node *is*. Separate from the inventory
-- item it yields. Fields: { id, item, hp, requireTool, yieldMin, yieldMax }.
Registries.Resources = Registry.new("Resources", { keyField = "id" })
Registries.Stats = Registry.new("Stats", { keyField = "name" })
Registries.Achievements = Registry.new("Achievements", { keyField = "key" })
Registries.Codex = Registry.new("Codex", { keyField = "id" })
Registries.Appearance = Registry.new("Appearance", { keyField = "id" })
Registries.Mobs = Registry.new("Mobs", { keyField = "id" })

-- Documented alias: Stats.defineStat(model) == Stats.register(model)
Registries.Stats.defineStat = Registries.Stats.register

-- Convenience: all recipes for a given station.
function Registries.Recipes.forStation(station: string)
	return Registries.Recipes.query(function(r)
		return r.station == station
	end)
end

return Registries
