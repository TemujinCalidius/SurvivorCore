--[[
	StatDefs — the survival-stat roster the engine ships with, and the one-time
	install that registers it. SHARED: safe to require on server and client.

	Each stat is a single signed-rate model: `ratePerSecond` moves the raw value
	toward `max` (positive) or `0` (negative). The HUD bar shows the RAW value by
	default (empty at 0), so an affliction like Hunger/Poison fills UP as it worsens.
	`dangerHigh` says which end is bad (so the warn color triggers correctly); the
	optional `invert` flips the fill direction for a depleting-resource look.

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
	dangerHigh: boolean, -- which end is bad: true => high value (afflictions), false => low (resources)
	invert: boolean, -- display only: true => bar shows 1 - value/max (depletes). Default false (bar = value).
	warnAt: number, -- warn within this percent of the dangerous end (0-100)
	display: boolean, -- show in the HUD by default
	attribute: string, -- Player attribute name (defaults to `name`)
	icon: string?, -- HUD icon asset id; engine ships free default icons (overridable per stat)
	valueFormat: string?, -- HUD numeric readout: "fraction" | "percent" | "value" | "none"
}

local StatDefs = {}

-- Reach `max` (from 0) in N minutes — readable way to express drift rates.
local function perMinutes(minutes: number): number
	return 100 / (minutes * 60)
end

-- The shipped defaults. Numbers + default icons ported from The Counter Earth.
-- Hunger/Thirst/Fatigue/Poison start at 0 and rise toward 100 = bad (`dangerHigh = true`,
-- so their bars fill up as they worsen). Health/Energy/Blood are resources (`dangerHigh =
-- false`: 0 = bad). Health/Energy are display-only here (drain/regen + consequences = #5/#6).
StatDefs.DEFAULTS = {
	{
		name = "Health",
		start = 100,
		max = 100,
		ratePerSecond = 0,
		dangerHigh = false,
		invert = false,
		warnAt = 25,
		display = true,
		icon = "rbxassetid://88514622686548",
	},
	{
		name = "Energy",
		start = 100,
		max = 100,
		ratePerSecond = 0,
		dangerHigh = false,
		invert = false,
		warnAt = 25,
		display = true,
		icon = "rbxassetid://129856164091801",
	},
	{
		name = "Hunger",
		start = 0,
		max = 100,
		ratePerSecond = perMinutes(30),
		dangerHigh = true,
		invert = false,
		warnAt = 25,
		display = true,
		icon = "rbxassetid://138699077112926",
	},
	{
		name = "Thirst",
		start = 0,
		max = 100,
		ratePerSecond = perMinutes(20),
		dangerHigh = true,
		invert = false,
		warnAt = 25,
		display = true,
		icon = "rbxassetid://124374881225649",
	},
	{
		name = "Fatigue",
		start = 0,
		max = 100,
		ratePerSecond = perMinutes(60),
		dangerHigh = true,
		invert = false,
		warnAt = 25,
		display = true,
		icon = "rbxassetid://102789813187589",
	},
	{
		name = "Poison",
		start = 0,
		max = 100,
		ratePerSecond = 0,
		dangerHigh = true,
		invert = false,
		warnAt = 25,
		display = true,
		icon = "rbxassetid://86406240258610",
	},
	{
		name = "Blood",
		start = 100,
		max = 100,
		ratePerSecond = 0,
		dangerHigh = false,
		invert = false,
		warnAt = 25,
		display = true,
		icon = "rbxassetid://139788071928396",
	},
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
			dangerHigh = def.dangerHigh,
			invert = def.invert,
			warnAt = def.warnAt,
			display = def.display,
			icon = def.icon or "", -- engine ships a default icon; owners override via config/Assets
			valueFormat = def.valueFormat or "fraction",
		}
		Registries.Stats.register({
			name = def.name,
			start = def.start,
			max = def.max,
			ratePerSecond = def.ratePerSecond,
			dangerHigh = def.dangerHigh,
			invert = def.invert,
			warnAt = def.warnAt,
			display = def.display,
			attribute = def.name,
			icon = def.icon or "",
			valueFormat = def.valueFormat or "fraction",
		})
	end
	Config.defineSection("SurvivalStats", section)
end

StatDefs.install()

return StatDefs
