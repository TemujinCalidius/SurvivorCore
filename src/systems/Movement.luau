--!nonstrict
--[[
	Movement — server-side sprinting, jumping and energy. SERVER-ONLY.

	Ported from The Counter Earth's PlayerStateService. The client sends sprint intent over the
	`SprintIntent` RemoteEvent; the server is authoritative:
	  • While sprinting AND moving AND energy > 0 → drain energy, set WalkSpeed = SprintSpeed.
	  • At 0 energy → forced to ExhaustedSpeed (can't sprint until it recovers).
	  • Idle for RegenDelaySeconds after the last exertion → energy regenerates.
	  • Jumps cost energy and are gated below MinToJump (JumpPower drops to 0).
	Energy is the engine's "Energy" stat (a Player Attribute) written through the stat-effects
	layer (Stats.adjust), so it replicates to the HUD with no extra RemoteEvents.

	Tuning lives in MovementConfig ("Movement" Config section). Started by SurvivorCore.start().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.Movement is server-only — require it via SurvivorCore.start()")

local MovementConfig = require(script.Parent.Parent.shared.MovementConfig)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local SurvivalStats = require(script.Parent.SurvivalStats)

local Movement = {}

local TICK_INTERVAL = 0.1 -- 10 Hz: energy + walk-speed updates (jumps are event-driven)
local JUMP_DRAIN_THROTTLE = 0.15 -- seconds; jumps fire several Humanoid signals at once
local MOVING_MAGNITUDE = 0.05

local started = false

type State = {
	humanoid: Humanoid?,
	sprintRequested: boolean,
	lastEnergyUseTime: number,
	lastJumpDrainTime: number,
	currentWalkSpeed: number,
	jumpEnabled: boolean,
	connections: { RBXScriptConnection },
}

local states: { [Player]: State } = {}

local function cfg(): any
	return MovementConfig.get()
end

local function energyOf(player: Player): number
	return SurvivalStats.getValue(player, "Energy") or 0
end

-- Energy refuses to regenerate while a survival need is at its dangerous extreme: starving
-- (Hunger maxed), dehydrated (Thirst maxed) or fully fatigued (Fatigue maxed) — this overrides
-- the normal post-exertion regen, so a depleted player stays depleted until they recover.
local function regenBlocked(player: Player): boolean
	local function atMax(name: string): boolean
		local def = SurvivalStats.getDefinition(name)
		local value = SurvivalStats.getValue(player, name)
		return def ~= nil and value ~= nil and value >= def.max
	end
	return atMax("Hunger") or atMax("Thirst") or atMax("Fatigue")
end

local function setWalkSpeed(state: State, speed: number)
	local humanoid = state.humanoid
	if not humanoid then
		return
	end
	if state.currentWalkSpeed ~= speed or humanoid.WalkSpeed ~= speed then
		state.currentWalkSpeed = speed
		humanoid.WalkSpeed = speed
	end
end

local function setJumpEnabled(state: State, enabled: boolean, jumpPower: number)
	local humanoid = state.humanoid
	if not humanoid then
		return
	end
	local desired = if enabled then jumpPower else 0
	if state.jumpEnabled ~= enabled or humanoid.JumpPower ~= desired then
		state.jumpEnabled = enabled
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
		humanoid.UseJumpPower = true
		humanoid.JumpPower = desired
		if not enabled and humanoid.Jump then
			humanoid.Jump = false
		end
	end
end

-- A jump fires Humanoid.Jump + Jumping + StateChanged at once, so throttle the energy cost.
local function drainJumpEnergy(player: Player, state: State)
	local c = cfg()
	local now = os.clock()
	if now - state.lastJumpDrainTime < JUMP_DRAIN_THROTTLE then
		return
	end
	state.lastJumpDrainTime = now
	if energyOf(player) < c.Energy.MinToJump then
		setJumpEnabled(state, false, c.Movement.JumpPower)
		local humanoid = state.humanoid
		if humanoid and humanoid.Jump then
			humanoid.Jump = false
		end
		return
	end
	SurvivalStats.adjust(player, "Energy", -c.Energy.JumpCost)
	state.lastEnergyUseTime = now
end

local function setupCharacter(player: Player, character: Model)
	local state = states[player]
	if not state then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	for _, conn in state.connections do
		conn:Disconnect()
	end
	table.clear(state.connections)

	local c = cfg()
	state.humanoid = humanoid
	state.currentWalkSpeed = c.Movement.WalkSpeed
	state.jumpEnabled = true
	state.lastEnergyUseTime = os.clock()
	state.lastJumpDrainTime = 0

	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = c.Movement.WalkSpeed
	humanoid.JumpPower = c.Movement.JumpPower
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

	table.insert(
		state.connections,
		humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
			if humanoid.Jump then
				drainJumpEnergy(player, state)
			end
		end)
	)
	table.insert(
		state.connections,
		humanoid.Jumping:Connect(function(isJumping)
			if isJumping then
				drainJumpEnergy(player, state)
			end
		end)
	)
	table.insert(
		state.connections,
		humanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Jumping then
				drainJumpEnergy(player, state)
			end
		end)
	)
end

local function addPlayer(player: Player)
	states[player] = {
		humanoid = nil,
		sprintRequested = false,
		lastEnergyUseTime = os.clock(),
		lastJumpDrainTime = 0,
		currentWalkSpeed = cfg().Movement.WalkSpeed,
		jumpEnabled = true,
		connections = {},
	}
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		setupCharacter(player, player.Character)
	end
end

local function removePlayer(player: Player)
	local state = states[player]
	if state then
		for _, conn in state.connections do
			conn:Disconnect()
		end
	end
	states[player] = nil
end

function Movement.start(_options: { [string]: any }?)
	assert(not started, "Movement.start() called twice")
	started = true

	local sprintRemote = Remotes.event("SprintIntent")
	sprintRemote.OnServerEvent:Connect(function(player, wantsToSprint)
		if typeof(wantsToSprint) ~= "boolean" then
			return -- ignore malformed client input
		end
		local state = states[player]
		if state then
			state.sprintRequested = wantsToSprint
		end
	end)

	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		local step = accumulator
		accumulator = 0
		local c = cfg()

		for player, state in states do
			local humanoid = state.humanoid
			if not humanoid or humanoid.Parent == nil or humanoid.Health <= 0 then
				continue
			end

			local moving = humanoid.MoveDirection.Magnitude > MOVING_MAGNITUDE
			local swimming = humanoid:GetState() == Enum.HumanoidStateType.Swimming
			local energy = energyOf(player)
			local shouldSprint = state.sprintRequested and moving and energy > 0

			if shouldSprint then
				SurvivalStats.adjust(player, "Energy", -c.Energy.SprintDrainPerSecond * step)
				state.lastEnergyUseTime = os.clock()
			elseif
				not moving
				and not swimming
				and not regenBlocked(player)
				and os.clock() - state.lastEnergyUseTime >= c.Energy.RegenDelaySeconds
			then
				SurvivalStats.adjust(player, "Energy", c.Energy.RegenPerSecond * step)
			end

			-- Jump gate: no jump below MinToJump (drop JumpPower to 0).
			setJumpEnabled(state, energy >= c.Energy.MinToJump, c.Movement.JumpPower)

			-- Movement speed reflects energy state.
			if energy <= 0 then
				setWalkSpeed(state, c.Movement.ExhaustedSpeed)
			elseif shouldSprint then
				setWalkSpeed(state, c.Movement.SprintSpeed)
			else
				setWalkSpeed(state, c.Movement.WalkSpeed)
			end
		end
	end)
end

return Movement
