--!nonstrict
--[[
	DEMO ONLY — a row of interactable parts to exercise the survival systems by hand.

	Each part has a ProximityPrompt (walk up, press E) that calls a SurvivorCore stat API on
	the triggering player — a live demonstration of the effects layer:
	  DAMAGE   → real Humanoid damage (death + Roblox respawn)
	  FEED     → Hunger down            DRINK   → Thirst down
	  POISON   → start Poison ticking   ANTIDOTE → stop it
	  BLEED    → start Blood draining    BANDAGE → stop it

	This is demo scaffolding, not engine code — it shows how a game would drive the API.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SurvivorCore = require(ReplicatedStorage:WaitForChild("SurvivorCore"))

local POISON_SOURCE = "TestStation:poison"
local BLEED_SOURCE = "TestStation:bleed"

local function stats()
	return SurvivorCore.Stats
end

local STATIONS = {
	{
		label = "DAMAGE -25 HP",
		color = Color3.fromRGB(200, 60, 60),
		action = function(_player, humanoid)
			if humanoid then
				humanoid:TakeDamage(25) -- repeated hits → death → Roblox respawn
			end
		end,
	},
	{
		label = "FEED  (Hunger -40)",
		color = Color3.fromRGB(225, 150, 60),
		action = function(player)
			stats().adjust(player, "Hunger", -40)
		end,
	},
	{
		label = "DRINK  (Thirst -40)",
		color = Color3.fromRGB(70, 140, 220),
		action = function(player)
			stats().adjust(player, "Thirst", -40)
		end,
	},
	{
		label = "POISON  (start)",
		color = Color3.fromRGB(120, 190, 70),
		action = function(player)
			stats().adjust(player, "Poison", 5)
			stats().addModifier(player, "Poison", { ratePerSecond = 8, source = POISON_SOURCE })
		end,
	},
	{
		label = "ANTIDOTE  (stop poison)",
		color = Color3.fromRGB(190, 235, 170),
		action = function(player)
			stats().removeModifier(player, "Poison", POISON_SOURCE)
		end,
	},
	{
		label = "BLEED  (start)",
		color = Color3.fromRGB(130, 20, 20),
		action = function(player)
			stats().addModifier(player, "Blood", { ratePerSecond = -6, source = BLEED_SOURCE })
		end,
	},
	{
		label = "BANDAGE  (stop bleed)",
		color = Color3.fromRGB(235, 235, 235),
		action = function(player)
			stats().removeModifier(player, "Blood", BLEED_SOURCE)
		end,
	},
}

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function buildStation(def: any, position: Vector3)
	local part = Instance.new("Part")
	part.Name = "TestStation"
	part.Size = Vector3.new(3, 3, 3)
	part.Anchored = true
	part.Color = def.color
	part.Material = Enum.Material.SmoothPlastic
	part.Position = position
	part.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 44)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = def.label
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Use"
	prompt.ObjectText = def.label
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		if typeof(stats().adjust) ~= "function" then
			warn("[SurvivorCore demo] stat runtime not ready — has SurvivorCore.start() run?")
			return
		end
		def.action(player, humanoidOf(player))
	end)
end

-- Mirror the live Humanoid's health into the "Health" stat attribute so the HUD Health bar
-- tracks damage and resets on respawn. Demo scaffolding — an engine-level Health↔Humanoid
-- sync is part of the consequence-system follow-on (see the respawn/loot issue).
local function bindHealth(player: Player)
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		local function sync()
			player:SetAttribute("Health", math.max(0, math.round(humanoid.Health)))
		end
		sync()
		humanoid.HealthChanged:Connect(sync)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

local BASE = Vector3.new(0, 4, -16)
for i, def in STATIONS do
	local x = (i - (#STATIONS + 1) / 2) * 4
	buildStation(def, BASE + Vector3.new(x, 0, 0))
end

for _, player in Players:GetPlayers() do
	bindHealth(player)
end
Players.PlayerAdded:Connect(bindHealth)
