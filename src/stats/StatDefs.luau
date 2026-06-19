--[[
	StatDefs — the survival-stat roster the engine ships with, and the one-time
	install that registers it. SHARED: safe to require on server and client.

	Each stat is a single signed-rate model: `ratePerSecond` moves the raw value
	toward `max` (positive) or `0` (negative). `invert` affects ONLY HUD display /
	warnings — an inverted bar shows the *healthy* amount (full = good), so a stat
	that rises to be bad (Hunger 0→100) renders as a bar that depletes.

	Owners retune without code via the Studio `SurvivalStatsConfig` instance;
	developers may instead `Config.override("SurvivalStats", { ... })`. See StatConfig.
]]

local Config = require(script.Parent.Parent.foundation.Config)
local Registries = require(script.Parent.Parent.registries)

export type StatDef = {
	name: string,
	start: number,
	max: number,
	ratePerSecond: number, -- signed: + rises toward max, - falls toward 0
	invert: boolean, -- display only: true => bar full = healthy (value 0 = full)
	warnAt: number, -- warn when the displayed bar drops below this percent (0-100)
	display: boolean, -- show in the HUD by default
	attribute: string, -- Player attribute name (defaults to `name`)
}

local StatDefs = {}

-- Reach `max` (from 0) in N minutes — readable way to express drift rates.
local function perMinutes(minutes: number): number
	return 100 / (minutes * 60)
end

-- The shipped defaults. Numbers ported from The Counter Earth; content-free.
-- Hunger/Thirst/Fatigue/Poison start at 0 and rise toward 100 = bad (invert = true,
-- so their bars deplete). Blood starts full and 0 = death. Health/Energy are
-- display-only in this build (drain/regen + consequences arrive with #5/#6).
StatDefs.DEFAULTS = {
	{ name = "Health", start = 100, max = 100, ratePerSecond = 0, invert = false, warnAt = 25, display = true },
	{ name = "Energy", start = 100, max = 100, ratePerSecond = 0, invert = false, warnAt = 25, display = true },
	{
		name = "Hunger",
		start = 0,
		max = 100,
		ratePerSecond = perMinutes(30),
		invert = true,
		warnAt = 25,
		display = true,
	},
	{
		name = "Thirst",
		start = 0,
		max = 100,
		ratePerSecond = perMinutes(20),
		invert = true,
		warnAt = 25,
		display = true,
	},
	{
		name = "Fatigue",
		start = 0,
		max = 100,
		ratePerSecond = perMinutes(60),
		invert = true,
		warnAt = 25,
		display = true,
	},
	{ name = "Poison", start = 0, max = 100, ratePerSecond = 0, invert = true, warnAt = 25, display = true },
	{ name = "Blood", start = 100, max = 100, ratePerSecond = 0, invert = false, warnAt = 25, display = true },
}

local installed = false

-- Register each default stat into the Stats registry and define the tunable
-- `SurvivalStats` Config section. Idempotent per Luau VM (server and client each
-- install once). Called eagerly at require time so `Config.override("SurvivalStats", …)`
-- works any time before `start()`.
function StatDefs.install()
	if installed then
		return
	end
	installed = true

	local section = {}
	for _, def in StatDefs.DEFAULTS do
		section[def.name] = {
			start = def.start,
			max = def.max,
			ratePerSecond = def.ratePerSecond,
			invert = def.invert,
			warnAt = def.warnAt,
			display = def.display,
		}
		Registries.Stats.register({
			name = def.name,
			start = def.start,
			max = def.max,
			ratePerSecond = def.ratePerSecond,
			invert = def.invert,
			warnAt = def.warnAt,
			display = def.display,
			attribute = def.name,
		})
	end
	Config.defineSection("SurvivalStats", section)
end

StatDefs.install()

return StatDefs
