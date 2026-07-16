--!nonstrict
--[[
	TradingConfig — tuning for player-to-player trading (issue #15). SHARED. Defines the "Trading"
	Config section so games retune via `Config.override("Trading", { ... })`. Read the merged
	section with TradingConfig.get(). Also exposed in the no-code SurvivorCore Studio editor.
]]

local Config = require(script.Parent.Parent.foundation.Config)

local TradingConfig = {}

TradingConfig.SECTION = "Trading"

TradingConfig.DEFAULTS = {
	Enabled = true, -- false = trading is off (the "Trade" prompt never appears)
	MaxDistance = 16, -- studs; how close two players must be to open AND keep a trade open
	RequestTimeoutSeconds = 20, -- a pending trade invite auto-declines after this
	ResetConfirmOnChange = true, -- changing either basket clears BOTH confirms (anti-bait)
	AllowEquippedItems = false, -- v1: only loose backpack stacks trade; worn gear/satchels stay put
}

Config.defineSection(TradingConfig.SECTION, TradingConfig.DEFAULTS)

function TradingConfig.get(): any
	return Config.get(TradingConfig.SECTION) or TradingConfig.DEFAULTS
end

return TradingConfig
