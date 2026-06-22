--!nonstrict
--[[
	SurvivalConsequences — server. The survival stats actually bite back.

	Each tick, for every living character:
	  • STARVING   (Hunger at max)  → drain Health
	  • DEHYDRATED (Thirst at max)  → drain Health
	  • POISONED   (Poison at max)  → drain Health
	  • BLED OUT   (Blood == 0)     → INSTANT death
	Health drains stack and reduce the character's real Humanoid health (so death + Roblox
	respawn happen naturally); bleeding out at 0 Blood kills outright.

	It also keeps the "Health" stat attribute in lockstep with the Humanoid (so the HUD Health
	bar reflects real damage), and on every (re)spawn resets all stats to their start values +
	clears modifiers — a fresh body, so injuries never carry across death or death-loop.

	(Energy-regen blocking while starving/dehydrated/fatigued lives in the Movement system,
	since that's where regen is applied.) Tuning: the "Consequences" Config section. Started by
	SurvivorCore.start().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(
	RunService:IsServer(),
	"SurvivorCore.SurvivalConsequences is server-only — require it via SurvivorCore.start()"
)

local SurvivalStats = require(script.Parent.SurvivalStats)
local ConsequenceConfig = require(script.Parent.Parent.shared.ConsequenceConfig)

local SurvivalConsequences = {}

local TICK_INTERVAL = 0.1 -- 10 Hz, matching the rest of the survival sim
local started = false

local humanoids: { [Player]: Humanoid } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

-- Release a player's previous-character connections (mirrors Movement; defensive even though
-- Roblox auto-disconnects on character destroy).
local function dropConnections(player: Player)
	local conns = connections[player]
	if conns then
		for _, conn in conns do
			conn:Disconnect()
		end
	end
	connections[player] = nil
end

local function isAtMax(player: Player, name: string): boolean
	local def = SurvivalStats.getDefinition(name)
	local value = SurvivalStats.getValue(player, name)
	return def ~= nil and value ~= nil and value >= def.max
end

local function syncHealth(player: Player, humanoid: Humanoid)
	-- Write to the Health stat's backing attribute (defaults to "Health"), so a custom
	-- `attribute` override still lands where the HUD reads it.
	local def = SurvivalStats.getDefinition("Health")
	local attr = (def and def.attribute) or "Health"
	player:SetAttribute(attr, math.max(0, math.round(humanoid.Health)))
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	dropConnections(player)

	-- Fresh body: clear injuries/afflictions + modifiers so nothing carries across death.
	SurvivalStats.resetPlayer(player)

	humanoids[player] = humanoid
	syncHealth(player, humanoid)
	connections[player] = {
		humanoid.HealthChanged:Connect(function()
			syncHealth(player, humanoid)
		end),
		humanoid.Died:Connect(function()
			if humanoids[player] == humanoid then
				humanoids[player] = nil
			end
		end),
	}
end

local function addPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		setupCharacter(player, player.Character)
	end
end

function SurvivalConsequences.start(_options: { [string]: any }?)
	assert(not started, "SurvivalConsequences.start() called twice")
	started = true

	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(function(player)
		humanoids[player] = nil
		dropConnections(player)
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		local step = accumulator
		accumulator = 0
		local drains = ConsequenceConfig.get().HealthDrainPerSecond

		for player, humanoid in humanoids do
			if humanoid.Parent == nil or humanoid.Health <= 0 then
				continue
			end

			-- Bled out: Blood empty (resource at 0) is INSTANT death — not a drain.
			local blood = SurvivalStats.getValue(player, "Blood")
			if blood ~= nil and blood <= 0 then
				humanoid.Health = 0
				continue
			end

			-- Otherwise, stacking per-second health drains from the survival needs.
			local perSecond = 0
			if isAtMax(player, "Hunger") then
				perSecond += drains.Starving
			end
			if isAtMax(player, "Thirst") then
				perSecond += drains.Dehydrated
			end
			-- Poison only drains health once it's maxed out (no partial-poison chip damage).
			if isAtMax(player, "Poison") then
				perSecond += drains.PoisonAtMax
			end

			if perSecond > 0 then
				humanoid:TakeDamage(perSecond * step)
			end
		end
	end)
end

return SurvivalConsequences
