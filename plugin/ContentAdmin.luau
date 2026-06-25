--!nonstrict
--[[
	ContentAdmin — the pure LOGIC layer of the no-code content builder (Items + Gatherable
	resources). NO Studio widget / `plugin` global / ChangeHistoryService, so it's requirable and
	testable headlessly. The UI (ContentAdminUi) + plugin main are thin layers over this.

	Unlike the stat editor (which writes DELTAS over engine defaults), content is entirely
	owner-created: each item/resource is a `Configuration` child under
	`ReplicatedStorage.SurvivorCoreContent.{Items,Resources}`, named by its id, with its fields as
	attributes. The engine's `Registry.loadFromFolder` reads exactly this at start() — so what the
	plugin writes here, the runtime registers, with no code. Field attribute names are the def field
	names (name/stack/…) the loader copies verbatim.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContentAdmin = {}

ContentAdmin.ROOT_NAME = "SurvivorCoreContent"

export type FieldSpec = { attr: string, kind: string, label: string, default: any, placeholder: string? }
export type Category = { folder: string, keyLabel: string, title: string, fields: { FieldSpec } }

-- The two builders. `attr` are the lowercase def field names the engine loader reads.
ContentAdmin.CATEGORIES = {
	Items = {
		folder = "Items",
		title = "Items",
		keyLabel = "New item id",
		fields = {
			{ attr = "name", kind = "string", label = "Name", default = "" },
			{ attr = "stack", kind = "number", label = "Max stack", default = 1 },
			{ attr = "weight", kind = "number", label = "Weight", default = 0 },
			{
				attr = "category",
				kind = "string",
				label = "Category",
				default = "",
				placeholder = "material / tool / consumable",
			},
			{ attr = "toolType", kind = "string", label = "Tool type", default = "", placeholder = "axe (tools only)" },
			{ attr = "icon", kind = "string", label = "Icon", default = "", placeholder = "rbxassetid://…" },
			{ attr = "description", kind = "string", label = "Description", default = "" },
		},
	},
	Weapons = {
		-- Weapons ARE items (category = "weapon"), but live in their own SurvivorCoreContent.Weapons
		-- folder so this editor never collides with the Items editor; the engine loads it into the
		-- Items registry at start(). `toolType` lets the hotbar equip it; the `weapon*` fields are the
		-- flat stats the Combat system reads.
		folder = "Weapons",
		title = "Weapons",
		keyLabel = "New weapon id",
		fields = {
			{ attr = "name", kind = "string", label = "Name", default = "" },
			{ attr = "category", kind = "string", label = "Category", default = "weapon" },
			{
				attr = "toolType",
				kind = "string",
				label = "Tool type",
				default = "",
				placeholder = "sword / bow (required to equip)",
			},
			{ attr = "weaponKind", kind = "string", label = "Kind", default = "melee", placeholder = "melee / bow" },
			{ attr = "weaponDamage", kind = "number", label = "Damage", default = 10 },
			{ attr = "weaponRange", kind = "number", label = "Range (melee)", default = 8 },
			{ attr = "weaponCooldown", kind = "number", label = "Cooldown", default = 0.6 },
			{ attr = "weaponDrawTime", kind = "number", label = "Draw time (bow)", default = 1 },
			{ attr = "weaponProjectileSpeed", kind = "number", label = "Arrow speed (bow)", default = 180 },
			{
				attr = "weaponMaxRange",
				kind = "number",
				label = "Max range (bow)",
				default = 0,
				placeholder = "0 = engine default",
			},
			{
				attr = "weaponAmmo",
				kind = "string",
				label = "Ammo item (bow)",
				default = "",
				placeholder = "an arrow id; blank = none",
			},
			{ attr = "stack", kind = "number", label = "Max stack", default = 1 },
			{ attr = "weight", kind = "number", label = "Weight", default = 1 },
			{ attr = "icon", kind = "string", label = "Icon", default = "", placeholder = "rbxassetid://…" },
		},
	},
	Arrows = {
		-- Arrows ARE items (category = "ammo"), in their own SurvivorCoreContent.Arrows folder (loaded
		-- into the Items registry). A bow's `weaponAmmo` points at one of these ids; the shot combines
		-- the bow's pullback with the arrow's weight/damage/range. Different arrow types = different
		-- ballistics.
		folder = "Arrows",
		title = "Arrows / Ammo",
		keyLabel = "New arrow id",
		fields = {
			{ attr = "name", kind = "string", label = "Name", default = "" },
			{ attr = "category", kind = "string", label = "Category", default = "ammo" },
			{
				attr = "ammoDamage",
				kind = "number",
				label = "Damage ×",
				default = 1,
				placeholder = "1.0 = bow base; 1.2 = +20%",
			},
			{
				attr = "ammoDrop",
				kind = "number",
				label = "Drop / curve ×",
				default = 1,
				placeholder = "1.0 = normal; heavier = more arc",
			},
			{
				attr = "ammoRange",
				kind = "number",
				label = "Max range",
				default = 0,
				placeholder = "studs; 0 = bow default",
			},
			{
				attr = "ammoSpeed",
				kind = "number",
				label = "Speed ×",
				default = 0,
				placeholder = "0 = bow speed; 1.2 = faster",
			},
			{ attr = "weight", kind = "number", label = "Carry weight", default = 0.05 },
			{ attr = "stack", kind = "number", label = "Max stack", default = 32 },
			{ attr = "icon", kind = "string", label = "Icon", default = "", placeholder = "rbxassetid://…" },
			{ attr = "description", kind = "string", label = "Description", default = "" },
		},
	},
	Resources = {
		folder = "Resources",
		title = "Gatherables",
		keyLabel = "New resource id",
		fields = {
			{ attr = "item", kind = "string", label = "Yields item", default = "", placeholder = "an item id" },
			{ attr = "hp", kind = "number", label = "HP / gathers", default = 3 },
			{
				attr = "requireTool",
				kind = "string",
				label = "Tool required",
				default = "",
				placeholder = "axe (blank = bare hand)",
			},
			{ attr = "yieldMin", kind = "number", label = "Yield min", default = 1 },
			{ attr = "yieldMax", kind = "number", label = "Yield max", default = 1 },
		},
	},
	Mobs = {
		folder = "Mobs",
		title = "Mobs",
		keyLabel = "New mob id",
		fields = {
			{
				attr = "faction",
				kind = "string",
				label = "Faction",
				default = "hostile",
				placeholder = "hostile / passive / neutral",
			},
			{ attr = "health", kind = "number", label = "Health", default = 50 },
			{ attr = "walkSpeed", kind = "number", label = "Walk speed", default = 6 },
			{ attr = "runSpeed", kind = "number", label = "Run speed", default = 14 },
			{ attr = "aggroRange", kind = "number", label = "Aggro range", default = 40 },
			{ attr = "leashRange", kind = "number", label = "Leash range", default = 60 },
			{ attr = "attackRange", kind = "number", label = "Attack range", default = 6 },
			{ attr = "attackDamage", kind = "number", label = "Attack damage", default = 8 },
			{ attr = "attackCooldown", kind = "number", label = "Attack cooldown", default = 1.5 },
		},
	},
} :: { [string]: Category }

-- Render order for the UI.
ContentAdmin.ORDER = { "Items", "Weapons", "Arrows", "Resources", "Mobs" }

-- ids are lowercase alphanumeric + underscore (matches how content is referenced everywhere).
function ContentAdmin.sanitizeId(raw: any): string
	return (string.gsub(string.lower(tostring(raw or "")), "[^%w_]", ""))
end

function ContentAdmin.getRoot(): Instance?
	return ReplicatedStorage:FindFirstChild(ContentAdmin.ROOT_NAME)
end

function ContentAdmin.getCategoryFolder(catKey: string): Instance?
	local cat = ContentAdmin.CATEGORIES[catKey]
	local root = ContentAdmin.getRoot()
	return root and cat and root:FindFirstChild(cat.folder) or nil
end

-- Find-or-create the SurvivorCoreContent/<folder> path. Only called from the write path.
function ContentAdmin.ensureFolder(catKey: string): Instance
	local cat = ContentAdmin.CATEGORIES[catKey]
	local root = ContentAdmin.getRoot()
	if not root then
		root = Instance.new("Folder")
		root.Name = ContentAdmin.ROOT_NAME
		root.Parent = ReplicatedStorage
	end
	local folder = root:FindFirstChild(cat.folder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = cat.folder
		folder.Parent = root
	end
	return folder
end

function ContentAdmin.list(catKey: string): { string }
	local out = {}
	local folder = ContentAdmin.getCategoryFolder(catKey)
	if folder then
		for _, child in folder:GetChildren() do
			table.insert(out, child.Name)
		end
		table.sort(out)
	end
	return out
end

function ContentAdmin.getNode(catKey: string, id: string): Instance?
	local folder = ContentAdmin.getCategoryFolder(catKey)
	return folder and folder:FindFirstChild(id) or nil
end

local function coerce(kind: string, raw: any): (boolean, any, string?)
	if kind == "number" then
		local n = tonumber(raw)
		if n == nil then
			return false, nil, "not a number"
		end
		return true, n, nil
	elseif kind == "boolean" then
		if typeof(raw) == "boolean" then
			return true, raw, nil
		end
		return true, raw == "true", nil
	end
	return true, tostring(raw), nil
end
ContentAdmin.coerce = coerce

-- Create a new entry, seeding every field to its default so the loader sees a complete def.
function ContentAdmin.create(catKey: string, rawId: any): (boolean, string)
	local cat = ContentAdmin.CATEGORIES[catKey]
	if not cat then
		return false, "unknown category"
	end
	local id = ContentAdmin.sanitizeId(rawId)
	if id == "" then
		return false, "Enter a valid id (letters, numbers, _)."
	end
	local folder = ContentAdmin.ensureFolder(catKey)
	if folder:FindFirstChild(id) then
		return false, `'{id}' already exists.`
	end
	local node = Instance.new("Configuration")
	node.Name = id
	for _, f in cat.fields do
		node:SetAttribute(f.attr, f.default)
	end
	node.Parent = folder
	return true, id
end

function ContentAdmin.delete(catKey: string, id: string)
	local node = ContentAdmin.getNode(catKey, id)
	if node then
		node:Destroy()
	end
end

-- The attribute value for a field (or its default if unset/no node).
function ContentAdmin.read(catKey: string, id: string, field: FieldSpec): any
	local node = ContentAdmin.getNode(catKey, id)
	local v = node and node:GetAttribute(field.attr)
	if v == nil then
		return field.default
	end
	return v
end

-- Write a field (full value — content is owner-owned, not a delta over an engine default).
function ContentAdmin.set(catKey: string, id: string, field: FieldSpec, raw: any): (boolean, string?)
	local node = ContentAdmin.getNode(catKey, id)
	if not node then
		return false, "missing entry"
	end
	local ok, value, err = coerce(field.kind, raw)
	if not ok then
		return false, err
	end
	node:SetAttribute(field.attr, value)
	return true, nil
end

return ContentAdmin
