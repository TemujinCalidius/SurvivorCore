--[[
	Registry — the shared lifecycle behind every content registry: register a def,
	validate it, index it by a key, and query it. Returns a plain table of functions
	so the public API is dot-callable: SurvivorCore.Items.register({ ... }).

		local Items = Registry.new("Items", { keyField = "id" })
		Items.register({ id = "reed", name = "Reed" })
		Items.get("reed")
]]

local Registry = {}

export type Options = {
	keyField: string?, -- unique id field (default "id")
	validate: ((def: any) -> (boolean, string?))?,
}

function Registry.new(name: string, options: Options?)
	local opts = options or {}
	local keyField = opts.keyField or "id"
	local validate = opts.validate

	local byId: { [any]: any } = {}
	local all: { any } = {}

	local self = {}
	self.name = name

	function self.register(def: any): any
		local key = def[keyField]
		assert(key ~= nil, `[{name}] def is missing key field '{keyField}'`)
		assert(byId[key] == nil, `[{name}] '{tostring(key)}' is already registered`)
		if validate then
			local ok, err = validate(def)
			assert(ok, `[{name}] '{tostring(key)}' is invalid: {err or "?"}`)
		end
		byId[key] = def
		table.insert(all, def)
		return def
	end

	function self.registerMany(defs: { any })
		for _, def in defs do
			self.register(def)
		end
	end

	function self.get(key: any): any
		return byId[key]
	end

	function self.getAll(): { any }
		return all
	end

	function self.query(predicate: (def: any) -> boolean): { any }
		local out = {}
		for _, def in all do
			if predicate(def) then
				table.insert(out, def)
			end
		end
		return out
	end

	return self
end

return Registry
