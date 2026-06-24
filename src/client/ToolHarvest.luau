--!nonstrict
--[[
	ToolHarvest — client. Tool-swing input for harvesting. CLIENT-ONLY.

	When the player holds a Tool and clicks, find the Gatherable under the cursor within range and
	ask the server to harvest it (the server re-validates everything — never trust this). Optional
	feedback: a registered swing animation (Assets "ToolAnims" by toolType) and a result sound
	(Assets "HarvestSounds"); the node's own reactions (shake/fell) run server-side. Booted by
	SurvivorCore.startClient().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

assert(RunService:IsClient(), "SurvivorCore.ToolHarvest is client-only — boot it via SurvivorCore.startClient()")

local Assets = require(script.Parent.Parent.foundation.Assets)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local HarvestingConfig = require(script.Parent.Parent.shared.HarvestingConfig)

local ToolHarvest = {}

local GATHERABLE_TAG = "Gatherable"
local started = false

local player = Players.LocalPlayer

local function findGatherableUnderMouse(): Instance?
	local target = player:GetMouse().Target
	local node: Instance? = target
	while node do
		if CollectionService:HasTag(node, GATHERABLE_TAG) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function inRange(node: Instance): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not node:IsA("PVInstance") then
		return false
	end
	local range = tonumber(HarvestingConfig.get().SwingRange) or 12
	return (root.Position - node:GetPivot().Position).Magnitude <= range
end

local function playSwing(tool: Tool)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local toolType = tostring(tool:GetAttribute("ToolType") or tool.Name)
	local animId = Assets.tryGet("ToolAnims", toolType)
	if animId == "" then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track:Play()
	end
end

local function onActivated(tool: Tool)
	local node = findGatherableUnderMouse()
	if not node or not inRange(node) then
		return
	end
	playSwing(tool)
	Remotes.event("HarvestSwing"):FireServer(node)
end

local function bindTool(tool: Instance)
	if tool:IsA("Tool") then
		tool.Activated:Connect(function()
			onActivated(tool :: Tool)
		end)
	end
end

local function watchCharacter(char: Model)
	for _, child in char:GetChildren() do
		bindTool(child)
	end
	char.ChildAdded:Connect(bindTool)
end

function ToolHarvest.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	-- Optional: a short "thunk" on a successful/blocked swing (content-free; skipped if unset).
	Remotes.event("HarvestResult").OnClientEvent:Connect(function(result)
		local key = if result and result.ok then "hit" else "blocked"
		local soundId = Assets.tryGet("HarvestSounds", key)
		if soundId ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = soundId
			sound.Parent = SoundService
			sound:Play()
			sound.Ended:Once(function()
				sound:Destroy()
			end)
		end
	end)
end

return ToolHarvest
