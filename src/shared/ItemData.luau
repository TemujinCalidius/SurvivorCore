--!nonstrict
--[[
	ItemData — replicates item *display data* from the server to clients. SHARED.

	The content registries (`SurvivorCore.Items`) are populated per Luau VM: a game registers
	items in server code, so the client's copy of the registry is empty. The UI still needs each
	item's name / icon / stack / equip slot / consumable flag to render. Rather than make games
	register items twice, the engine serialises the display fields of every registered item into
	a single replicated StringValue at start(); the client reads it back.

	This keeps the engine content-free (it ships no items) and the register-from-code model intact
	(register once, server-side) while the UI "just works".

		-- server (engine, at start): ItemData.publish(SurvivorCore.Items.getAll())
		-- client (engine UI):        local def = ItemData.get("berry")  -> { id, name, icon, … }

	Only DISPLAY fields cross the wire — never gameplay logic. The server stays authoritative for
	weight/consume/equip; the client copy is for rendering only.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemData = {}

local HOLDER_NAME = "SurvivorCoreItemData"

export type DisplayDef = {
	id: string,
	name: string,
	description: string?,
	icon: string?,
	stack: number,
	category: string?,
	equipSlot: string?, -- the slot this item equips into (incl. "back" for backpacks)
	consumable: boolean, -- has an onConsume effect (drives the UI's "Use" affordance)
}

local function toDisplay(def: any): DisplayDef
	local stack = tonumber(def.stack)
	return {
		id = def.id,
		name = if typeof(def.name) == "string" then def.name else def.id,
		description = if typeof(def.description) == "string" then def.description else nil,
		icon = if typeof(def.icon) == "string" and def.icon ~= "" then def.icon else nil,
		stack = if stack and stack >= 1 then math.floor(stack) else 1,
		category = if typeof(def.category) == "string" then def.category else nil,
		equipSlot = if def.equipment and typeof(def.equipment.slot) == "string"
			then string.lower(def.equipment.slot)
			elseif def.backpack then "back"
			else nil,
		consumable = def.onConsume ~= nil,
	}
end

-- ── Server: serialise + replicate ──────────────────────────────────────────

-- Publish the display data for a list of item defs (SurvivorCore.Items.getAll()). Idempotent;
-- call again to re-publish after registering more items.
function ItemData.publish(defs: { any })
	local out = {}
	for _, def in defs do
		if def and def.id then
			table.insert(out, toDisplay(def))
		end
	end
	local holder = ReplicatedStorage:FindFirstChild(HOLDER_NAME)
	if not holder then
		holder = Instance.new("StringValue")
		holder.Name = HOLDER_NAME
		holder.Parent = ReplicatedStorage
	end
	holder.Value = HttpService:JSONEncode(out)
end

-- ── Client: read + cache ────────────────────────────────────────────────────

local cache: { [string]: DisplayDef }? = nil
local watching = false

local function rebuild(): { [string]: DisplayDef }
	local result: { [string]: DisplayDef } = {}
	local holder = ReplicatedStorage:WaitForChild(HOLDER_NAME, 10)
	if holder and holder:IsA("StringValue") and holder.Value ~= "" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(holder.Value)
		end)
		if ok and typeof(decoded) == "table" then
			for _, d in decoded do
				if typeof(d) == "table" and typeof(d.id) == "string" then
					result[d.id] = d
				end
			end
		end
		if not watching then
			watching = true
			holder:GetPropertyChangedSignal("Value"):Connect(function()
				cache = nil -- invalidate; next get() re-decodes
			end)
		end
	end
	return result
end

local function ensureCache(): { [string]: DisplayDef }
	local c = cache
	if not c then
		c = rebuild()
		cache = c
	end
	return c
end

-- The replicated display def for an item, or nil if unknown.
function ItemData.get(itemId: string): DisplayDef?
	if typeof(itemId) ~= "string" or itemId == "" then
		return nil
	end
	return ensureCache()[itemId]
end

return ItemData
