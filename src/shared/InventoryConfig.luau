--!nonstrict
--[[
	InventoryConfig — tuning for the inventory data layer (slots + carry-weight model).
	SHARED (the server system reads it; client UI reads HotbarSize / EquipSlots for layout).
	Defines the "Inventory" Config section so games retune via
	`Config.override("Inventory", { BasePocketSlots = 8 })`.

	Numbers ported from The Counter Earth (its GameplayConfig.Inventory + InventoryService
	constants) — proven values. Read the merged section with InventoryConfig.get().
]]

local Config = require(script.Parent.Parent.foundation.Config)

local InventoryConfig = {}

InventoryConfig.SECTION = "Inventory"

InventoryConfig.DEFAULTS = {
	-- Carrying capacity with no backpack equipped. A backpack adds to BOTH.
	BasePocketSlots = 5, -- TCE GameplayConfig.Inventory.PocketSlots
	BasePocketWeight = 5, -- kg; TCE BasePocketWeight

	-- Quick-use hotbar. 9 maps to the number keys 1-9 (and the 9 HotbarSlot{n} attributes).
	HotbarSize = 9, -- TCE HOTBAR_SIZE

	-- Anti-spam guard on consuming items (seconds between uses, per player).
	UseCooldownSeconds = 2.0, -- TCE EAT_COOLDOWN

	-- The equipment slots a character sheet exposes. `back` is special — it accepts the
	-- backpack (recomputes capacity); the rest are generic single-item slots.
	EquipSlots = { "head", "top", "pants", "shoes", "back", "quiver" },

	-- Picking up an item of these categories (or anything with an `onConsume`) auto-pins it
	-- to the smallest free hotbar slot, so quick-use items are reachable without opening the menu.
	AutoHotbarCategories = { "tool", "weapon", "placeable", "consumable" },
}

-- Define the section once per Luau VM (server and client each require this module once).
Config.defineSection(InventoryConfig.SECTION, InventoryConfig.DEFAULTS)

-- The merged (defaults + overrides) Inventory config table.
function InventoryConfig.get(): any
	return Config.get(InventoryConfig.SECTION) or InventoryConfig.DEFAULTS
end

return InventoryConfig
