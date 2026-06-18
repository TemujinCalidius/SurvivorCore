--[[
	Config — engine ships default tuning per section; games override via deep merge.

		Config.defineSection("Energy", { DrainPerSecond = 16, RegenPerSecond = 14 })
		Config.override("Energy", { DrainPerSecond = 10 })   -- game tweak
		Config.get("Energy.DrainPerSecond")                  -- 10
]]

local Config = {}

local sections: { [string]: any } = {}

local function deepCopy(t: any): any
	if typeof(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in t do
		c[k] = deepCopy(v)
	end
	return c
end

local function deepMerge(base: any, over: any)
	for k, v in over do
		if typeof(v) == "table" and typeof(base[k]) == "table" then
			deepMerge(base[k], v)
		else
			base[k] = deepCopy(v)
		end
	end
end

-- Engine code calls this to declare a section with its default values.
function Config.defineSection(name: string, defaults: { [string]: any })
	assert(sections[name] == nil, `Config section '{name}' already defined`)
	sections[name] = deepCopy(defaults)
end

-- Game code calls this to override engine defaults.
function Config.override(name: string, overrides: { [string]: any })
	assert(sections[name] ~= nil, `Config section '{name}' not defined`)
	deepMerge(sections[name], overrides)
end

-- Dotted lookup: Config.get("Energy.DrainPerSecond")
function Config.get(path: string): any
	local node: any = sections
	for part in string.gmatch(path, "[^.]+") do
		if typeof(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

return Config
