--!nonstrict
--[[
	RespawnCamera — client. Ported from The Counter Earth's RespawnCameraFix.

	When a character is replaced (respawn, or a game assigning player.Character directly), Roblox's
	camera can stay subject-locked to the destroyed body. On every CharacterAdded, re-point
	CameraSubject at the new Humanoid and restore the Custom camera type. Harmless when the default
	behavior already did the right thing. Booted by SurvivorCore.startClient().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

assert(RunService:IsClient(), "SurvivorCore.RespawnCamera is client-only — boot it via SurvivorCore.startClient()")

local RespawnCamera = {}

local started = false
local player = Players.LocalPlayer

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraSubject = humanoid
		camera.CameraType = Enum.CameraType.Custom
	end
end

function RespawnCamera.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return RespawnCamera
