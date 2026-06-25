--!nonstrict
--[[
	Mobs — server. The shared mob & AI engine (issue #17): the substrate combat (#12), animals (#13)
	and monsters (#14) all build on. A "mob" is the engine's unified, content-free creature contract:

		a Model, tagged "Mob", containing a Humanoid + a PrimaryPart (HumanoidRootPart).

	Because a mob IS a Humanoid, combat damages it EXACTLY like a player (`Humanoid:TakeDamage`),
	its health IS `Humanoid.Health`, and its death IS `Humanoid.Died` — one code path for players and
	mobs. The engine ships ZERO creature content; a creator supplies the rigged model (or the engine
	builds a minimal blocky placeholder), the `Mobs` registry def (health/speed/ranges/faction), and
	the death/spawn juice via `SurvivorCore.Mobs.onReaction`.

	A reusable FSM drives behavior, with the profile chosen by DATA (the def's `faction`):
	  • "hostile" → idle/wander → chase (line-of-sight + leash) → attack → return on leash break.
	  • "passive" → idle/wander → flee from a near (or attacking) player.
	  • "neutral" → idle/wander only; flees when struck.

	One shared scheduler ticks every active mob at `Config "Mobs".TickRate`. Movement is idiomatic
	`Humanoid:MoveTo` (a creator's rig walks/animates naturally; PathfindingService is a future
	enhancement). Tuning: the "Mobs" Config section. Started by SurvivorCore.start().
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.Mobs is server-only — require it via SurvivorCore.start()")

local Registries = require(script.Parent.Parent.registries)
local Reactions = require(script.Parent.Parent.foundation.Reactions)
local Hooks = require(script.Parent.Parent.foundation.Hooks)
local EventBridge = require(script.Parent.Parent.foundation.EventBridge)
local Assets = require(script.Parent.Parent.foundation.Assets)
local MobsConfig = require(script.Parent.Parent.shared.MobsConfig)

local Mobs = {}

local MOB_TAG = "Mob"
local BOUND_ATTR = "_MobBound"
local started = false
local schedulerRunning = false

-- model -> live AI state. The shared scheduler iterates this every tick.
local activeMobs: { [Model]: any } = {}

-- A non-empty number/string attribute, else nil — so "" / 0 fall through to the def / config default.
local function attrOr(model: Instance, name: string): any
	local v = model:GetAttribute(name)
	if v == nil or v == "" or v == 0 then
		return nil
	end
	return v
end

-- Resolve a mob's effective fields: per-instance override attribute › registry def › "Mobs" Config.
-- One merge path, shared by tagged in-world mobs (the `Mob` component) and `Mobs.spawn` alike.
local function resolveMob(model: Model)
	local mobType = tostring(model:GetAttribute("MobType") or model:GetAttribute("_MobType") or model.Name)
	local def = Registries.Mobs.get(mobType) or {}
	local cfg = MobsConfig.get()

	local faction = tostring(attrOr(model, "Faction") or def.faction or "neutral")
	if faction ~= "hostile" and faction ~= "passive" and faction ~= "neutral" then
		faction = "neutral"
	end

	local function num(attr: string, defField: string, cfgField: string): number
		return tonumber(attrOr(model, attr)) or tonumber(def[defField]) or tonumber(cfg[cfgField]) or 0
	end

	return {
		mobType = mobType,
		faction = faction,
		health = tonumber(attrOr(model, "Health")) or tonumber(def.health) or 50,
		walkSpeed = tonumber(attrOr(model, "WalkSpeed")) or tonumber(def.walkSpeed) or 6,
		runSpeed = tonumber(attrOr(model, "RunSpeed")) or tonumber(def.runSpeed) or 14,
		aggroRange = num("AggroRange", "aggroRange", "DefaultAggroRange"),
		leashRange = num("LeashRange", "leashRange", "DefaultLeashRange"),
		attackRange = num("AttackRange", "attackRange", "DefaultAttackRange"),
		attackDamage = num("AttackDamage", "attackDamage", "DefaultAttackDamage"),
		attackCooldown = num("AttackCooldown", "attackCooldown", "DefaultAttackCooldown"),
		wanderRadius = num("WanderRadius", "wanderRadius", "DefaultWanderRadius"),
	}
end

-- A minimal, content-free placeholder rig: one upright block (the HumanoidRootPart) + a Humanoid,
-- so the default mob walks via MoveTo with no creator model. Real games supply their own rigged
-- model template under ReplicatedStorage.SurvivorCoreContent.MobModels.<mobType>.
local function buildDefaultRig(name: string, faction: string): Model
	local model = Instance.new("Model")
	model.Name = name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 3, 1)
	root.Color = if faction == "hostile" then Color3.fromRGB(150, 60, 60) else Color3.fromRGB(120, 130, 90)
	root.Material = Enum.Material.SmoothPlastic
	root.Parent = model

	-- A small "head" for personality (welded, no collision, massless so it doesn't affect movement).
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Color = root.Color
	head.CanCollide = false
	head.Massless = true
	head.CFrame = root.CFrame * CFrame.new(0, 2, 0)
	head.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	local hum = Instance.new("Humanoid")
	hum.Parent = model

	model.PrimaryPart = root
	return model
end

local function mobRoot(model: Model): BasePart?
	return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The nearest LIVE player within `maxDist` of a point (and their root). Mobs only target players.
local function nearestPlayer(pos: Vector3, maxDist: number): (Player?, number, BasePart?)
	local best, bestDist, bestRoot = nil, maxDist, nil
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 and root then
			local d = (root.Position - pos).Magnitude
			if d <= bestDist then
				best, bestDist, bestRoot = player, d, root
			end
		end
	end
	return best, bestDist, bestRoot
end

-- Clear sight from the mob to a target part (raycast, ignoring the mob's own model + the target char).
local function hasLineOfSight(from: BasePart, mobModel: Model, targetRoot: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { mobModel, targetRoot.Parent :: Instance }
	local origin = from.Position
	local result = Workspace:Raycast(origin, (targetRoot.Position - origin), params)
	return result == nil
end

local function moveTo(s: any, pos: Vector3, speed: number)
	if s.humanoid.WalkSpeed ~= speed then
		s.humanoid.WalkSpeed = speed
	end
	s.humanoid:MoveTo(pos)
end

-- Pick a fresh wander destination near spawn (used while idle/unaggroed).
local function wanderPoint(s: any): Vector3
	local r = s.wanderRadius
	local off = Vector3.new(math.random(-r, r), 0, math.random(-r, r))
	return s.spawnPos + off
end

local function playMobAnim(s: any, state: string)
	local animId = Assets.tryGet("MobAnims", s.mobType .. "_" .. state)
	if animId == "" then
		return
	end
	local animator = s.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
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

-- A hostile mob lands a hit on a player: damage the player's Humanoid (lethal — it syncs to the
-- survival Health HUD), respecting the per-mob attack cooldown. Fires `mob:attack`.
local function tryAttack(s: any, target: Player, targetRoot: BasePart)
	local now = os.clock()
	if now - (s.lastAttack or 0) < s.attackCooldown then
		return
	end
	s.lastAttack = now
	playMobAnim(s, "attack")
	local hum = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum:TakeDamage(s.attackDamage)
	end
	local ctx = {
		instance = s.model,
		mobType = s.mobType,
		player = target,
		damage = s.attackDamage,
		position = targetRoot.Position,
	}
	Hooks.run("mob:attack", ctx)
	Reactions.run(s.mobType, "attack", ctx)
	EventBridge.fire("mob:attack", target, { mob = s.model, mobType = s.mobType, damage = s.attackDamage })
end

-- One FSM tick for one mob. Behavior profile is chosen by faction (data), not by subclassing.
local function step(s: any)
	local root = mobRoot(s.model)
	if not root then
		return
	end
	local pos = root.Position
	local player, dist, targetRoot = nearestPlayer(pos, math.max(s.aggroRange, 1))

	if s.faction == "hostile" then
		local seesPlayer = player ~= nil
			and (not s.requireLoS or hasLineOfSight(root, s.model, targetRoot))
			and (pos - s.spawnPos).Magnitude <= s.leashRange

		if seesPlayer then
			s.current = "chase"
			if dist <= s.attackRange then
				moveTo(s, pos, s.walkSpeed) -- stop closing; hold position and swing
				tryAttack(s, player, targetRoot)
			else
				moveTo(s, targetRoot.Position, s.runSpeed)
			end
			return
		end

		-- No valid target: if we wandered off chasing, walk back to spawn; otherwise idle/wander.
		if (pos - s.spawnPos).Magnitude > s.wanderRadius + 2 and s.current == "chase" then
			s.current = "return"
		end
	elseif s.faction == "passive" then
		local threatened = player ~= nil and (dist <= s.aggroRange or os.clock() < (s.fleeUntil or 0))
		if threatened then
			s.current = "flee"
			local away = (pos - targetRoot.Position)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
			moveTo(s, pos + away * 16, s.runSpeed)
			return
		end
	else
		-- neutral: flee briefly only if recently struck, else just wander.
		if os.clock() < (s.fleeUntil or 0) and targetRoot then
			local away = (pos - targetRoot.Position)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
			moveTo(s, pos + away * 12, s.runSpeed)
			return
		end
	end

	-- Idle / wander / return-to-spawn fallback (shared by every faction when not engaged).
	if s.current == "return" then
		moveTo(s, s.spawnPos, s.walkSpeed)
		if (pos - s.spawnPos).Magnitude < 4 then
			s.current = "idle"
		end
		return
	end

	if os.clock() >= (s.wanderUntil or 0) then
		if s.current == "wander" then
			s.current = "idle"
			s.wanderUntil = os.clock() + math.random(2, 5)
		else
			s.current = "wander"
			s.wanderUntil = os.clock() + math.random(3, 6)
			moveTo(s, wanderPoint(s), s.walkSpeed)
		end
	end
end

-- The mob died: fire the lifecycle (Hooks + per-type Reactions + EventBridge), let a death reaction
-- transform the body, then clean up — and respawn if requested.
local function onDied(s: any)
	if s.dead then
		return
	end
	s.dead = true
	s.current = "dead"
	activeMobs[s.model] = nil

	local root = mobRoot(s.model)
	local ctx = {
		instance = s.model,
		mobType = s.mobType,
		killer = s.lastDamageBy,
		position = root and root.Position or nil,
	}
	Hooks.run("mob:died", ctx)
	Reactions.run(s.mobType, "died", ctx)
	EventBridge.fire("mob:died", s.lastDamageBy, { mob = s.model, mobType = s.mobType })

	local corpse = tonumber(MobsConfig.get().CorpseSeconds) or 5
	local model = s.model
	task.delay(corpse, function()
		if model and model.Parent then
			model:Destroy()
		end
	end)

	if s.respawn and s.respawnSeconds > 0 and s.spawnCFrame then
		local mobType, cf, seconds, respawn = s.mobType, s.spawnCFrame, s.respawnSeconds, true
		task.delay(seconds, function()
			Mobs.spawn(mobType, cf, { respawn = respawn, respawnSeconds = seconds })
		end)
	end
end

-- One shared scheduler ticks every active mob. Started lazily on the first adopt (so the engine
-- works whether mobs are placed in-world before start() or spawned after it).
local function ensureScheduler()
	if schedulerRunning then
		return
	end
	schedulerRunning = true
	task.spawn(function()
		while true do
			local tickRate = tonumber(MobsConfig.get().TickRate) or 0.2
			task.wait(tickRate)
			for model, s in activeMobs do
				if model.Parent and not s.dead then
					local ok, err = pcall(step, s)
					if not ok then
						warn(`[SurvivorCore.Mobs] '{s.mobType}' AI error: {tostring(err)}`)
					end
				elseif not model.Parent then
					activeMobs[model] = nil
				end
			end
		end
	end)
end

-- Bring a Model (tagged "Mob", with a Humanoid + PrimaryPart) under engine AI control. Idempotent —
-- safe to call from both the `Mob` component's onSetup and `Mobs.spawn`. Returns the live state.
function Mobs.adopt(model: Model): any?
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	if model:GetAttribute(BOUND_ATTR) then
		return activeMobs[model]
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = mobRoot(model)
	if not hum or not root then
		warn(`[SurvivorCore.Mobs] '{model:GetFullName()}' needs a Humanoid + PrimaryPart to be a mob`)
		return nil
	end

	local r = resolveMob(model)
	hum.MaxHealth = r.health
	hum.Health = r.health
	hum.WalkSpeed = r.walkSpeed

	local s: any = {
		model = model,
		humanoid = hum,
		mobType = r.mobType,
		faction = r.faction,
		walkSpeed = r.walkSpeed,
		runSpeed = r.runSpeed,
		aggroRange = r.aggroRange,
		leashRange = r.leashRange,
		attackRange = r.attackRange,
		attackDamage = r.attackDamage,
		attackCooldown = r.attackCooldown,
		wanderRadius = r.wanderRadius,
		requireLoS = MobsConfig.get().RequireLineOfSight ~= false,
		spawnPos = root.Position,
		spawnCFrame = model:GetPivot(),
		current = "idle",
		lastAttack = 0,
		lastDamageBy = nil,
		dead = false,
		respawn = false,
		respawnSeconds = tonumber(MobsConfig.get().RespawnSeconds) or 0,
	}

	model:SetAttribute(BOUND_ATTR, true)
	model:SetAttribute("_MobType", r.mobType)
	activeMobs[model] = s
	ensureScheduler()

	hum.Died:Once(function()
		onDied(s)
	end)

	local ctx = { instance = model, mobType = r.mobType, position = root.Position }
	Hooks.run("mob:spawned", ctx)
	Reactions.run(r.mobType, "spawned", ctx)
	return s
end

-- Spawn a mob of `mobType` at a CFrame. Clones a creator template
-- (ReplicatedStorage.SurvivorCoreContent.MobModels.<mobType>) if present, else builds a placeholder.
-- opts.respawn = true re-spawns it (after opts.respawnSeconds, default config) when it dies.
function Mobs.spawn(mobType: string, cframe: CFrame, opts: { [string]: any }?): Model?
	local o: { [string]: any } = opts or {}
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local content = ReplicatedStorage:FindFirstChild("SurvivorCoreContent")
	local models = content and content:FindFirstChild("MobModels")
	local template = models and models:FindFirstChild(mobType)

	local def = Registries.Mobs.get(mobType) or {}
	local faction = tostring(def.faction or "neutral")

	local model: Model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = buildDefaultRig(mobType, faction)
	end
	model.Name = mobType
	model:SetAttribute("MobType", mobType)
	model:PivotTo(cframe)
	CollectionService:AddTag(model, MOB_TAG)
	model.Parent = Workspace

	local s = Mobs.adopt(model)
	if s then
		s.respawn = o.respawn == true
		s.respawnSeconds = tonumber(o.respawnSeconds) or s.respawnSeconds
		s.spawnCFrame = cframe
	end
	return model
end

-- Apply combat (or scripted) damage to a mob: damage its Humanoid (death is handled by Humanoid.Died)
-- and record the attacker for kill attribution + the `mob:hit` reaction. Called by the Combat system.
function Mobs.damage(model: Model, amount: number, source: Player?): boolean
	local s = activeMobs[model]
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	if s then
		s.lastDamageBy = source
		-- A struck passive/neutral mob flees for a few seconds even if the player then backs off.
		s.fleeUntil = os.clock() + 5
		local ctx = {
			instance = model,
			mobType = s.mobType,
			player = source,
			damage = amount,
			hpLeft = math.max(0, hum.Health - amount),
		}
		Hooks.run("mob:hit", ctx)
		Reactions.run(s.mobType, "hit", ctx)
	end
	hum:TakeDamage(amount)
	return true
end

-- True if an instance is (part of) a live engine mob — used by Combat target selection.
function Mobs.isMob(model: Instance?): boolean
	return model ~= nil and model:IsA("Model") and activeMobs[model] ~= nil
end

function Mobs.getActive(): { Model }
	local out = {}
	for model in activeMobs do
		table.insert(out, model)
	end
	return out
end

function Mobs.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true
	ensureScheduler()
end

return Mobs
