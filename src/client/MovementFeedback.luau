--!nonstrict
--[[
	MovementFeedback — client sprint input + low-stat feedback. CLIENT-ONLY.

	Ported from The Counter Earth's HudController. Two jobs:
	  • SPRINT INPUT — hold Left/Right Shift to sprint; fires the `SprintIntent` RemoteEvent
	    (the server is authoritative for speed + energy). Releases on key-up / focus loss.
	  • LOW-STAT FEEDBACK — a full-screen vignette + breathing loop that intensify as Energy
	    drops, and a heartbeat loop that fades in below HeartbeatStartRatio of health. All
	    driven by reading the replicated Energy attribute + the character's Humanoid health,
	    smoothed each frame.

	Booted by SurvivorCore.startClient(). Tuning + asset ids come from MovementConfig.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

assert(RunService:IsClient(), "SurvivorCore.MovementFeedback is client-only — boot it via SurvivorCore.startClient()")

local MovementConfig = require(script.Parent.Parent.shared.MovementConfig)
local Remotes = require(script.Parent.Parent.shared.Remotes)

local MovementFeedback = {}

local started = false

-- Frame-rate-independent approach toward a target (the TCE `smooth` helper).
local function smooth(current: number, target: number, speed: number, dt: number): number
	return current + (target - current) * math.clamp(dt * speed, 0, 1)
end

local function makeLoopedSound(name: string, soundId: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = 0
	sound.PlaybackSpeed = 1
	sound.Parent = SoundService
	if soundId ~= "" then
		sound:Play()
	end
	return sound
end

function MovementFeedback.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local cfg = MovementConfig.get()

	-- --- Sprint input → server -------------------------------------------------
	local sprintRemote = Remotes.event("SprintIntent")
	local sprintHeld = false
	local function setSprint(value: boolean)
		if sprintHeld == value then
			return
		end
		sprintHeld = value
		sprintRemote:FireServer(value)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			setSprint(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			setSprint(false)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		setSprint(false)
	end)

	-- --- Vignette overlay ------------------------------------------------------
	local playerGui = player:WaitForChild("PlayerGui")
	local vignetteGui = Instance.new("ScreenGui")
	vignetteGui.Name = "SurvivorCoreVignette"
	vignetteGui.ResetOnSpawn = false
	vignetteGui.IgnoreGuiInset = true
	vignetteGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	vignetteGui.DisplayOrder = 1
	vignetteGui.Parent = playerGui

	local vignette = Instance.new("ImageLabel")
	vignette.Name = "EnergyVignette"
	vignette.BackgroundTransparency = 1
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.Image = cfg.Assets.Vignette
	vignette.ImageColor3 = Color3.fromRGB(255, 255, 255)
	vignette.ImageTransparency = 1
	vignette.ScaleType = Enum.ScaleType.Stretch
	vignette.Visible = cfg.Assets.Vignette ~= ""
	vignette.Parent = vignetteGui

	-- --- Breathing + heartbeat loops -------------------------------------------
	local breathing = makeLoopedSound("SurvivorCoreBreathing", cfg.Assets.Breathing)
	local heartbeat = makeLoopedSound("SurvivorCoreHeartbeat", cfg.Assets.Heartbeat)

	RunService.RenderStepped:Connect(function(dt)
		local energy = player:GetAttribute("Energy")
		if typeof(energy) ~= "number" then
			energy = 0
		end
		local maxEnergy = cfg.Energy.Max
		if typeof(maxEnergy) ~= "number" or maxEnergy <= 0 then
			maxEnergy = 100
		end
		local energyRatio = math.clamp(energy / maxEnergy, 0, 1)

		-- Health from the live character Humanoid (the real health bar).
		local healthRatio, alive = 1, false
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.MaxHealth > 0 then
			healthRatio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			alive = humanoid.Health > 0
		end

		-- Vignette: intensifies as energy drops.
		if vignette.Visible then
			local intensity = math.clamp(1 - energyRatio, 0, 1) ^ 1.2
			vignette.ImageTransparency = smooth(vignette.ImageTransparency, 1 - (intensity * 0.9), 5, dt)
		end

		-- Breathing: tracks low energy.
		local breathingIntensity = math.clamp(1 - energyRatio, 0, 1)
		breathing.Volume = smooth(breathing.Volume, breathingIntensity * cfg.Audio.BreathingMaxVolume, 5, dt)
		breathing.PlaybackSpeed = smooth(
			breathing.PlaybackSpeed,
			cfg.Audio.BreathingMinSpeed
				+ (cfg.Audio.BreathingMaxSpeed - cfg.Audio.BreathingMinSpeed) * breathingIntensity,
			5,
			dt
		)

		-- Heartbeat: fades in below HeartbeatStartRatio of health.
		local heartbeatStart = math.clamp(cfg.Health.HeartbeatStartRatio, 0.05, 1)
		local heartbeatIntensity = 0
		if alive and healthRatio < heartbeatStart then
			heartbeatIntensity = math.clamp((heartbeatStart - healthRatio) / heartbeatStart, 0, 1)
		end
		heartbeat.Volume = smooth(heartbeat.Volume, heartbeatIntensity * cfg.Audio.HeartbeatMaxVolume, 7, dt)
		heartbeat.PlaybackSpeed = smooth(
			heartbeat.PlaybackSpeed,
			cfg.Audio.HeartbeatMinSpeed
				+ (cfg.Audio.HeartbeatMaxSpeed - cfg.Audio.HeartbeatMinSpeed) * heartbeatIntensity,
			7,
			dt
		)
	end)
end

return MovementFeedback
