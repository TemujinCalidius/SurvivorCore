--!nonstrict
--[[
	Inventory — the server-authoritative inventory data layer. SERVER-ONLY.

	A slots + carry-weight model (ported from The Counter Earth): every player has a number
	of inventory slots and a carry-weight limit; equipping a backpack raises BOTH. Items stack
	(up to the item def's `stack`) and carry weight. All state lives in auto-replicating Player
	Attributes (see InventoryTypes for the schema) — no read RemoteEvents, exactly like the
	survival stats. Clients request mutations through validated write RemoteEvents.

	What it owns:
	  • add / remove / move / swap / split across inventory slots (weight- and stack-checked).
	  • A 9-slot quick-use hotbar (pin / unpin / reorder / use; auto-pin on pickup).
	  • Equipment slots (head/top/pants/shoes/back/quiver). `back` is the backpack slot and
	    recomputes capacity; the rest are display + occupancy only (a future EquipEffects layer
	    can apply attribute modifiers via the `inventory:changed` hook).
	  • Consumables: using one applies its `onConsume` deltas via the stat-effects layer
	    (SurvivalStats.adjust) and fires the `item:use` hook.

	Runtime API is surfaced on SurvivorCore.Inventory after start() (it acts on live players).
	Tuning: the "Inventory" Config section. Started by SurvivorCore.start().

	DEFERRED (documented seams, not built): dropping items to the world / loot bags (#19),
	physical Tool instances + equip-to-swing (#1), durability, spoilage, the 2D backpack grid.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.Inventory is server-only — require it via SurvivorCore.start()")

local Registries = require(script.Parent.Parent.registries)
local SurvivalStats = require(script.Parent.SurvivalStats)
local InventoryConfig = require(script.Parent.Parent.shared.InventoryConfig)
local InventoryTypes = require(script.Parent.Parent.shared.InventoryTypes)
local ItemData = require(script.Parent.Parent.shared.ItemData)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local Hooks = require(script.Parent.Parent.foundation.Hooks)

local Items = Registries.Items

local Inventory = {}

local started = false

-- Cached config (defaults here are a safety net; start() overwrites from the Config section).
local BASE_POCKET_SLOTS = 5
local BASE_POCKET_WEIGHT = 5
local HOTBAR_SIZE = 9
local USE_COOLDOWN = 2.0
local AUTO_HOTBAR_CATEGORIES: { [string]: boolean } = {}

-- Per-player consume cooldown (os.clock timestamps); cleared on PlayerRemoving.
local lastUse: { [Player]: number } = {}

-- ── Item-def accessors (defs are free-form on the Items registry) ──────────

local function readDef(itemId: string): any
	if itemId == "" then
		return nil
	end
	return Items.get(itemId)
end

local function stackMax(def: any): number
	local s = def and tonumber(def.stack)
	return if s and s >= 1 then math.floor(s) else 1
end

local function weightOf(def: any): number
	local w = def and tonumber(def.weight)
	return if w and w > 0 then w else 0
end

-- ── Input sanitising ──────────────────────────────────────────────────────

local function sanitizeItemId(value: any): string
	if type(value) ~= "string" then
		return ""
	end
	local s = string.sub(value, 1, 40)
	if s == "" or not string.match(s, "^[%w_%-%s]+$") then
		return ""
	end
	return s
end

local function toSlot(value: any): number
	return math.floor(tonumber(value) or 0)
end

-- ── Slot helpers (mirror InventoryTypes attribute schema) ──────────────────

local function getMaxSlots(player: Player): number
	return math.max(1, math.floor(tonumber(player:GetAttribute(InventoryTypes.MAX_SLOTS_ATTR)) or BASE_POCKET_SLOTS))
end

local function getSlotItemId(player: Player, n: number): string
	return sanitizeItemId(player:GetAttribute(InventoryTypes.invSlotAttr(n)) or "")
end

local function getSlotQty(player: Player, n: number): number
	return math.max(0, math.floor(tonumber(player:GetAttribute(InventoryTypes.invQtyAttr(n))) or 0))
end

local function setSlot(player: Player, n: number, itemId: string, qty: number)
	if qty <= 0 then
		player:SetAttribute(InventoryTypes.invSlotAttr(n), nil)
		player:SetAttribute(InventoryTypes.invQtyAttr(n), nil)
	else
		player:SetAttribute(InventoryTypes.invSlotAttr(n), itemId)
		player:SetAttribute(InventoryTypes.invQtyAttr(n), math.floor(qty + 0.5))
	end
end

local function getTotalQty(player: Player, itemId: string): number
	local total = 0
	for n = 1, getMaxSlots(player) do
		if getSlotItemId(player, n) == itemId then
			total += getSlotQty(player, n)
		end
	end
	return total
end

-- ── Weight ─────────────────────────────────────────────────────────────────

local function computeWeight(player: Player): number
	local total = 0
	for n = 1, getMaxSlots(player) do
		local itemId = getSlotItemId(player, n)
		if itemId ~= "" then
			total += weightOf(readDef(itemId)) * getSlotQty(player, n)
		end
	end
	return total
end

local function refreshWeight(player: Player)
	player:SetAttribute(InventoryTypes.CARRY_WEIGHT_ATTR, math.floor(computeWeight(player) * 100 + 0.5) / 100)
end

-- ── Backpack capacity recompute ─────────────────────────────────────────────

local function recalcBackpackCapacity(player: Player)
	local equipped = player:GetAttribute(InventoryTypes.equipSlotAttr(InventoryTypes.BACK_SLOT))
	if type(equipped) == "string" and equipped ~= "" then
		local def = readDef(equipped)
		if def and def.backpack then
			player:SetAttribute(InventoryTypes.MAX_SLOTS_ATTR, BASE_POCKET_SLOTS + (tonumber(def.backpack.slots) or 0))
			player:SetAttribute(
				InventoryTypes.MAX_CARRY_WEIGHT_ATTR,
				BASE_POCKET_WEIGHT + (tonumber(def.backpack.maxWeight) or 0)
			)
			return
		end
	end
	player:SetAttribute(InventoryTypes.MAX_SLOTS_ATTR, BASE_POCKET_SLOTS)
	player:SetAttribute(InventoryTypes.MAX_CARRY_WEIGHT_ATTR, BASE_POCKET_WEIGHT)
end

-- ── Hooks ────────────────────────────────────────────────────────────────────

local function fireChanged(player: Player, kind: string, extra: { [string]: any }?)
	local payload: { [string]: any } = { player = player, kind = kind }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	Hooks.run("inventory:changed", payload)
end

-- ── Add / Remove (weight-checked; partial-then-empty fill; LIFO removal) ────

local function addQty(player: Player, itemId: string, amount: number): boolean
	local def = readDef(itemId)
	if not def then
		return false
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return false
	end

	local maxWeight = tonumber(player:GetAttribute(InventoryTypes.MAX_CARRY_WEIGHT_ATTR)) or BASE_POCKET_WEIGHT
	if computeWeight(player) + weightOf(def) * amount > maxWeight + 0.001 then
		return false
	end

	local maxSlots = getMaxSlots(player)
	local cap = stackMax(def)
	local remaining = amount

	-- Fill partial stacks first.
	for n = 1, maxSlots do
		if remaining <= 0 then
			break
		end
		if getSlotItemId(player, n) == itemId then
			local qty = getSlotQty(player, n)
			local canAdd = math.min(remaining, cap - qty)
			if canAdd > 0 then
				setSlot(player, n, itemId, qty + canAdd)
				remaining -= canAdd
			end
		end
	end

	-- Then empty slots.
	for n = 1, maxSlots do
		if remaining <= 0 then
			break
		end
		if getSlotItemId(player, n) == "" then
			local take = math.min(remaining, cap)
			setSlot(player, n, itemId, take)
			remaining -= take
		end
	end

	refreshWeight(player)
	return remaining == 0
end

local function removeQty(player: Player, itemId: string, amount: number): boolean
	amount = math.floor(amount)
	if amount <= 0 then
		return false
	end
	if getTotalQty(player, itemId) < amount then
		return false
	end

	local remaining = amount
	for n = getMaxSlots(player), 1, -1 do
		if remaining <= 0 then
			break
		end
		if getSlotItemId(player, n) == itemId then
			local qty = getSlotQty(player, n)
			local take = math.min(remaining, qty)
			setSlot(player, n, itemId, qty - take)
			remaining -= take
		end
	end

	refreshWeight(player)
	return true
end

-- ── Hotbar helpers ───────────────────────────────────────────────────────────

local function findFreeHotbarSlot(player: Player): number?
	for slot = 1, HOTBAR_SIZE do
		local v = player:GetAttribute(InventoryTypes.hotbarSlotAttr(slot))
		if type(v) ~= "string" or v == "" then
			return slot
		end
	end
	return nil
end

local function isAutoHotbarEligible(def: any): boolean
	if not def then
		return false
	end
	if def.onConsume then
		return true
	end
	return type(def.category) == "string" and AUTO_HOTBAR_CATEGORIES[def.category] == true
end

-- Auto-pin a freshly picked-up, hotbar-eligible item to the smallest free hotbar slot, so
-- quick-use items are reachable without opening the menu (the "ground pickup → quick slot" rule).
local function tryAutoHotbar(player: Player, itemId: string)
	local def = readDef(itemId)
	if not isAutoHotbarEligible(def) then
		return
	end
	for slot = 1, HOTBAR_SIZE do
		if player:GetAttribute(InventoryTypes.hotbarSlotAttr(slot)) == itemId then
			return -- already pinned somewhere
		end
	end
	local freeSlot = findFreeHotbarSlot(player)
	if freeSlot then
		player:SetAttribute(InventoryTypes.hotbarSlotAttr(freeSlot), itemId)
	end
end

-- Clear hotbar pins whose item no longer exists anywhere in inventory. Pass `onlyItemId` to scope
-- the sweep to pins for that ONE item — so removing/consuming item X never clears an unrelated pin Y
-- (e.g. a hotbar-pinned weapon with no inventory stack). nil sweeps every pin.
local function cleanOrphanedHotbarPins(player: Player, onlyItemId: string?)
	for slot = 1, HOTBAR_SIZE do
		local pinned = tostring(player:GetAttribute(InventoryTypes.hotbarSlotAttr(slot)) or "")
		local consider = pinned ~= "" and (onlyItemId == nil or pinned == onlyItemId)
		if consider and getTotalQty(player, pinned) == 0 then
			player:SetAttribute(InventoryTypes.hotbarSlotAttr(slot), nil)
			if math.floor(tonumber(player:GetAttribute(InventoryTypes.HOTBAR_EQUIPPED_ATTR)) or 0) == slot then
				player:SetAttribute(InventoryTypes.HOTBAR_EQUIPPED_ATTR, nil)
			end
		end
	end
end

-- ── Consume ───────────────────────────────────────────────────────────────────

local function consume(player: Player, itemId: string, slot: number?): boolean
	local def = readDef(itemId)
	if not def or not def.onConsume then
		return false
	end

	local now = os.clock()
	if lastUse[player] and now - lastUse[player] < USE_COOLDOWN then
		return false
	end
	lastUse[player] = now

	-- Decrement first (authoritative) so a double-fire can't double-apply effects.
	if not removeQty(player, itemId, 1) then
		return false
	end

	-- Apply every onConsume entry through the stat-effects layer. Keys are stat names; values
	-- are signed deltas (afflictions rise toward 100=bad, so feeding is e.g. Hunger = -15).
	for statName, delta in def.onConsume do
		if type(statName) == "string" and type(delta) == "number" then
			SurvivalStats.adjust(player, statName, delta)
		end
	end

	cleanOrphanedHotbarPins(player, itemId)
	-- Every successful consume fires item:use — the seam for eat animations, sounds, or
	-- modifier logic (e.g. Stats.removeModifier to stop an ongoing poison tick).
	Hooks.run("item:use", { player = player, itemId = itemId, def = def, slot = slot })
	fireChanged(player, "use", { itemId = itemId })
	return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Public API (surfaced on SurvivorCore.Inventory after start; acts on live players)
-- ═══════════════════════════════════════════════════════════════════════════

-- Add `amount` of an item; weight-checked. Returns true only if ALL were placed. Auto-pins
-- hotbar-eligible items. This is the pickup path (gather grants, demo pickups, etc.).
function Inventory.add(player: Player, itemId: string, amount: number?): boolean
	local id = sanitizeItemId(itemId)
	if id == "" then
		return false
	end
	local ok = addQty(player, id, math.max(1, math.floor(tonumber(amount) or 1)))
	if getTotalQty(player, id) > 0 then
		tryAutoHotbar(player, id)
	end
	fireChanged(player, "add", { itemId = id })
	return ok
end

-- Remove `amount` of an item (LIFO across slots). Returns false if the player has fewer.
function Inventory.remove(player: Player, itemId: string, amount: number?): boolean
	local id = sanitizeItemId(itemId)
	if id == "" then
		return false
	end
	local ok = removeQty(player, id, math.max(1, math.floor(tonumber(amount) or 1)))
	if ok then
		cleanOrphanedHotbarPins(player, id)
		fireChanged(player, "remove", { itemId = id })
	end
	return ok
end

function Inventory.getQty(player: Player, itemId: string): number
	return getTotalQty(player, sanitizeItemId(itemId))
end

function Inventory.has(player: Player, itemId: string, amount: number?): boolean
	return getTotalQty(player, sanitizeItemId(itemId)) >= math.max(1, math.floor(tonumber(amount) or 1))
end

-- A read-only snapshot of the occupied slots (for tools / tests / custom UIs).
function Inventory.getSlots(player: Player): { { slot: number, itemId: string, qty: number } }
	local out = {}
	for n = 1, getMaxSlots(player) do
		local id = getSlotItemId(player, n)
		if id ~= "" then
			table.insert(out, { slot = n, itemId = id, qty = getSlotQty(player, n) })
		end
	end
	return out
end

-- Move/merge/swap two inventory slots (the drag-and-drop primitive). Same item → merge up to
-- the stack cap (overflow stays in the source); different (or one empty) → swap.
function Inventory.move(player: Player, fromSlot: number, destSlot: number): boolean
	local maxSlots = getMaxSlots(player)
	local a, b = toSlot(fromSlot), toSlot(destSlot)
	if a < 1 or a > maxSlots or b < 1 or b > maxSlots or a == b then
		return false
	end

	local itemA, qtyA = getSlotItemId(player, a), getSlotQty(player, a)
	local itemB, qtyB = getSlotItemId(player, b), getSlotQty(player, b)

	if itemA ~= "" and itemA == itemB then
		local cap = stackMax(readDef(itemA))
		local transfer = math.min(qtyA, cap - qtyB)
		if transfer > 0 then
			setSlot(player, b, itemB, qtyB + transfer)
			setSlot(player, a, itemA, qtyA - transfer)
		end
	else
		setSlot(player, a, itemB, qtyB)
		setSlot(player, b, itemA, qtyA)
	end

	refreshWeight(player)
	fireChanged(player, "move")
	return true
end

-- Documented alias (the issue lists both names; one implementation).
Inventory.swap = Inventory.move

-- Split `qty` off a slot into the first free slot. `1 <= qty < slotQty`; needs a free slot.
function Inventory.split(player: Player, slot: number, qty: number): boolean
	local maxSlots = getMaxSlots(player)
	local s = toSlot(slot)
	if s < 1 or s > maxSlots then
		return false
	end
	local itemId = getSlotItemId(player, s)
	if itemId == "" then
		return false
	end
	local slotQty = getSlotQty(player, s)
	local splitQty = toSlot(qty)
	if splitQty < 1 or splitQty >= slotQty then
		return false
	end

	local freeSlot: number? = nil
	for n = 1, maxSlots do
		if n ~= s and getSlotItemId(player, n) == "" then
			freeSlot = n
			break
		end
	end
	if not freeSlot then
		return false
	end

	setSlot(player, s, itemId, slotQty - splitQty)
	setSlot(player, freeSlot, itemId, splitQty)
	fireChanged(player, "split")
	return true
end

-- Equip the item in inventory slot `invSlot` into its equipment slot. The item dictates its
-- slot (via def.equipment.slot, or `back` for a def with a backpack table); an explicit
-- equipSlotName must match. `back` recomputes capacity.
function Inventory.equip(player: Player, invSlot: number, equipSlotName: string?): boolean
	local maxSlots = getMaxSlots(player)
	local s = toSlot(invSlot)
	if s < 1 or s > maxSlots then
		return false
	end
	local itemId = getSlotItemId(player, s)
	if itemId == "" then
		return false
	end
	local def = readDef(itemId)
	if not def then
		return false
	end

	-- Resolve the slot the item declares.
	local resolved: string? = nil
	if def.equipment and type(def.equipment.slot) == "string" then
		resolved = string.lower(def.equipment.slot)
	elseif def.backpack then
		resolved = InventoryTypes.BACK_SLOT
	end
	if not resolved or not InventoryTypes.isEquipSlot(resolved) then
		return false
	end
	if equipSlotName ~= nil and string.lower(equipSlotName) ~= resolved then
		return false -- can't force an item into a slot it doesn't declare
	end
	if resolved == InventoryTypes.BACK_SLOT and not def.backpack then
		return false
	end

	local attr = InventoryTypes.equipSlotAttr(resolved)
	local current = player:GetAttribute(attr)
	if type(current) == "string" and current ~= "" then
		return false -- slot occupied
	end

	setSlot(player, s, "", 0)
	player:SetAttribute(attr, itemId)
	if resolved == InventoryTypes.BACK_SLOT then
		recalcBackpackCapacity(player)
	end
	refreshWeight(player)
	-- TODO (EquipEffects): a future layer subscribes to inventory:changed{kind="equip"} and
	-- applies an item's attribute modifiers (armor → defense, etc.) via Stats.addModifier.
	fireChanged(player, "equip", { equipSlot = resolved, itemId = itemId })
	return true
end

-- Return an equipped item to inventory. `back` enforces the unequip rules. Returns
-- (false, reason) on rejection so the caller can surface a message.
function Inventory.unequip(player: Player, equipSlotName: string): (boolean, string?)
	if type(equipSlotName) ~= "string" or not InventoryTypes.isEquipSlot(equipSlotName) then
		return false, "Unknown equipment slot"
	end
	local slotName = string.lower(equipSlotName)
	local attr = InventoryTypes.equipSlotAttr(slotName)
	local equipped = player:GetAttribute(attr)
	if type(equipped) ~= "string" or equipped == "" then
		return false, "Nothing equipped"
	end

	if slotName == InventoryTypes.BACK_SLOT then
		local def = readDef(equipped)
		local bpSlots = (def and def.backpack and tonumber(def.backpack.slots)) or 0
		-- The backpack-granted slots must be empty (they vanish when capacity shrinks).
		for n = BASE_POCKET_SLOTS + 1, BASE_POCKET_SLOTS + bpSlots do
			if getSlotItemId(player, n) ~= "" then
				return false, "Empty backpack slots first"
			end
		end
		-- A pocket slot must be free to hold the satchel itself.
		local hasFree = false
		for n = 1, BASE_POCKET_SLOTS do
			if getSlotItemId(player, n) == "" then
				hasFree = true
				break
			end
		end
		if not hasFree then
			return false, "No free inventory slot"
		end
		player:SetAttribute(attr, nil)
		recalcBackpackCapacity(player)
		addQty(player, equipped, 1)
	else
		local hasFree = false
		for n = 1, getMaxSlots(player) do
			if getSlotItemId(player, n) == "" then
				hasFree = true
				break
			end
		end
		if not hasFree then
			return false, "No free inventory slot"
		end
		player:SetAttribute(attr, nil)
		addQty(player, equipped, 1)
	end

	refreshWeight(player)
	fireChanged(player, "unequip", { equipSlot = slotName, itemId = equipped })
	return true
end

-- Pin (itemId present, must exist in inventory) or unpin (nil) a hotbar slot.
function Inventory.setHotbar(player: Player, hotbarSlot: number, itemId: string?): boolean
	local slot = toSlot(hotbarSlot)
	if slot < 1 or slot > HOTBAR_SIZE then
		return false
	end
	local attr = InventoryTypes.hotbarSlotAttr(slot)

	if itemId == nil then
		-- Unpin.
		if tostring(player:GetAttribute(attr) or "") == "" then
			return false
		end
		player:SetAttribute(attr, nil)
		if math.floor(tonumber(player:GetAttribute(InventoryTypes.HOTBAR_EQUIPPED_ATTR)) or 0) == slot then
			player:SetAttribute(InventoryTypes.HOTBAR_EQUIPPED_ATTR, nil)
		end
		fireChanged(player, "hotbar")
		return true
	end

	-- Pin: no category gate — an explicit drag to the hotbar is always allowed.
	local id = sanitizeItemId(itemId)
	if id == "" or not readDef(id) or getTotalQty(player, id) < 1 then
		return false
	end
	player:SetAttribute(attr, id)
	fireChanged(player, "hotbar")
	return true
end

-- Reorder two hotbar slots, keeping the active-slot pointer accurate.
function Inventory.swapHotbar(player: Player, slotA: number, slotB: number): boolean
	local a, b = toSlot(slotA), toSlot(slotB)
	if a < 1 or a > HOTBAR_SIZE or b < 1 or b > HOTBAR_SIZE or a == b then
		return false
	end
	local attrA, attrB = InventoryTypes.hotbarSlotAttr(a), InventoryTypes.hotbarSlotAttr(b)
	local itemA = tostring(player:GetAttribute(attrA) or "")
	local itemB = tostring(player:GetAttribute(attrB) or "")
	player:SetAttribute(attrA, itemB ~= "" and itemB or nil)
	player:SetAttribute(attrB, itemA ~= "" and itemA or nil)

	local equipped = math.floor(tonumber(player:GetAttribute(InventoryTypes.HOTBAR_EQUIPPED_ATTR)) or 0)
	if equipped == a then
		player:SetAttribute(InventoryTypes.HOTBAR_EQUIPPED_ATTR, b)
	elseif equipped == b then
		player:SetAttribute(InventoryTypes.HOTBAR_EQUIPPED_ATTR, a)
	end
	fireChanged(player, "hotbar")
	return true
end

-- Use an item. Pass a hotbar slot index (sets the active slot + uses that pin) or an itemId.
function Inventory.useSlot(player: Player, hotbarSlotOrItemId: number | string): boolean
	if type(hotbarSlotOrItemId) == "number" then
		local slot = toSlot(hotbarSlotOrItemId)
		if slot < 1 or slot > HOTBAR_SIZE then
			return false
		end
		player:SetAttribute(InventoryTypes.HOTBAR_EQUIPPED_ATTR, slot)
		local itemId = tostring(player:GetAttribute(InventoryTypes.hotbarSlotAttr(slot)) or "")
		if itemId == "" then
			return false
		end
		return consume(player, sanitizeItemId(itemId), nil)
	end
	return consume(player, sanitizeItemId(hotbarSlotOrItemId), nil)
end

-- ── Per-player lifecycle ───────────────────────────────────────────────────

local function initPlayer(player: Player)
	if player:GetAttribute(InventoryTypes.MAX_SLOTS_ATTR) == nil then
		player:SetAttribute(InventoryTypes.MAX_SLOTS_ATTR, BASE_POCKET_SLOTS)
	end
	if player:GetAttribute(InventoryTypes.MAX_CARRY_WEIGHT_ATTR) == nil then
		player:SetAttribute(InventoryTypes.MAX_CARRY_WEIGHT_ATTR, BASE_POCKET_WEIGHT)
	end
	if player:GetAttribute(InventoryTypes.CARRY_WEIGHT_ATTR) == nil then
		player:SetAttribute(InventoryTypes.CARRY_WEIGHT_ATTR, 0)
	end

	-- Recompute weight on out-of-band slot writes; recompute capacity if the backpack changes
	-- (future-proofs a DataStore restore that sets EquipSlot_Back after init).
	player.AttributeChanged:Connect(function(attrName)
		if string.sub(attrName, 1, 8) == "InvSlot_" or string.sub(attrName, 1, 7) == "InvQty_" then
			refreshWeight(player)
		elseif attrName == InventoryTypes.equipSlotAttr(InventoryTypes.BACK_SLOT) then
			recalcBackpackCapacity(player)
			refreshWeight(player)
		end
	end)

	task.defer(function()
		if player.Parent then
			recalcBackpackCapacity(player)
			refreshWeight(player)
		end
	end)
end

-- ── Remote handlers (validated client → server requests) ────────────────────

local function wireRemotes()
	Remotes.event("InventorySwapSlots").OnServerEvent:Connect(function(player, slotA, slotB)
		Inventory.move(player, slotA, slotB)
	end)
	Remotes.event("InventorySplitStack").OnServerEvent:Connect(function(player, slot, qty)
		Inventory.split(player, slot, qty)
	end)
	Remotes.event("InventoryUseItem").OnServerEvent:Connect(function(player, invSlot)
		local maxSlots = getMaxSlots(player)
		local s = toSlot(invSlot)
		if s < 1 or s > maxSlots then
			return
		end
		consume(player, getSlotItemId(player, s), s)
	end)
	Remotes.event("InventoryEquip").OnServerEvent:Connect(function(player, invSlot, equipSlotName)
		Inventory.equip(player, invSlot, type(equipSlotName) == "string" and equipSlotName or nil)
	end)
	Remotes.event("InventoryUnequip").OnServerEvent:Connect(function(player, equipSlotName)
		if type(equipSlotName) == "string" then
			Inventory.unequip(player, equipSlotName)
		end
	end)
	Remotes.event("InventorySetHotbar").OnServerEvent:Connect(function(player, hotbarSlot, itemId)
		Inventory.setHotbar(player, hotbarSlot, type(itemId) == "string" and itemId or nil)
	end)
	Remotes.event("InventorySwapHotbar").OnServerEvent:Connect(function(player, slotA, slotB)
		Inventory.swapHotbar(player, slotA, slotB)
	end)
	Remotes.event("InventoryUseHotbar").OnServerEvent:Connect(function(player, hotbarSlot)
		Inventory.useSlot(player, toSlot(hotbarSlot))
	end)
end

function Inventory.start(_options: { [string]: any }?)
	assert(not started, "Inventory.start() called twice")
	started = true

	local cfg = InventoryConfig.get()
	BASE_POCKET_SLOTS = math.max(1, math.floor(tonumber(cfg.BasePocketSlots) or 5))
	BASE_POCKET_WEIGHT = math.max(0, tonumber(cfg.BasePocketWeight) or 5)
	HOTBAR_SIZE = math.max(1, math.floor(tonumber(cfg.HotbarSize) or 9))
	USE_COOLDOWN = math.max(0, tonumber(cfg.UseCooldownSeconds) or 2.0)
	AUTO_HOTBAR_CATEGORIES = {}
	for _, category in cfg.AutoHotbarCategories or {} do
		if type(category) == "string" then
			AUTO_HOTBAR_CATEGORIES[category] = true
		end
	end

	-- Replicate item display data (name/icon/stack/…) so client UI can render items the game
	-- registered server-side. Games should register items before SurvivorCore.start().
	ItemData.publish(Items.getAll())

	for _, player in Players:GetPlayers() do
		initPlayer(player)
	end
	Players.PlayerAdded:Connect(initPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)

	wireRemotes()
end

return Inventory
