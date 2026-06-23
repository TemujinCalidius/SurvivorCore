--[[
	InventoryTypes — the shared inventory schema. SHARED, logic-free (pure functions only).

	The single source of truth for how inventory state maps onto Player Attributes, so the
	server system (which writes them) and the client binders (which read them) never drift.
	The server stores everything as auto-replicating Player Attributes — no read RemoteEvents —
	exactly like the survival stats. Slots are flat scalar pairs (InvSlot_N / InvQty_N) rather
	than one serialized table, so the UI gets a granular change signal per slot.
]]

local InventoryTypes = {}

-- A stack occupying one inventory slot.
export type ItemStack = {
	itemId: string,
	qty: number,
}

-- The inventory fields the engine reads off an item def (all optional but `id`). Defs stay
-- free-form on the Items registry; this just documents what the inventory layer consumes.
export type ItemDef = {
	id: string,
	name: string?,
	stack: number?, -- max stack size (defaults to 1)
	weight: number?, -- per-unit carry weight (defaults to 0)
	category: string?,
	icon: string?,
	onConsume: { [string]: number }?, -- statName -> signed delta passed to Stats.adjust
	equipment: { slot: string }?, -- head/top/pants/shoes/back/quiver
	backpack: { slots: number, maxWeight: number }?, -- only on `back` items
}

-- Canonical equipment slot identifiers (lowercase), matching item-def `equipment.slot` and
-- the Inventory config's EquipSlots. `back` is the backpack slot (recomputes capacity).
InventoryTypes.EQUIP_SLOTS = { "head", "top", "pants", "shoes", "back", "quiver" }
InventoryTypes.BACK_SLOT = "back"

-- Player-attribute names that don't vary per slot.
InventoryTypes.MAX_SLOTS_ATTR = "MaxInvSlots"
InventoryTypes.CARRY_WEIGHT_ATTR = "CarryWeight"
InventoryTypes.MAX_CARRY_WEIGHT_ATTR = "MaxCarryWeight"
InventoryTypes.HOTBAR_EQUIPPED_ATTR = "HotbarEquippedSlot"

-- Per-slot attribute names. Slot indices are 1-based.
function InventoryTypes.invSlotAttr(slot: number): string
	return "InvSlot_" .. slot
end

function InventoryTypes.invQtyAttr(slot: number): string
	return "InvQty_" .. slot
end

function InventoryTypes.hotbarSlotAttr(slot: number): string
	return "HotbarSlot" .. slot
end

-- Normalize an equip-slot identifier ("head", "Head", "HEAD") to the attribute name
-- "EquipSlot_Head", so templates and item defs can use any casing.
function InventoryTypes.equipSlotAttr(name: string): string
	local lower = string.lower(name)
	local titled = string.upper(string.sub(lower, 1, 1)) .. string.sub(lower, 2)
	return "EquipSlot_" .. titled
end

-- True if `name` (any casing) is a recognised equipment slot.
function InventoryTypes.isEquipSlot(name: string): boolean
	local lower = string.lower(name)
	for _, slot in InventoryTypes.EQUIP_SLOTS do
		if slot == lower then
			return true
		end
	end
	return false
end

return InventoryTypes
