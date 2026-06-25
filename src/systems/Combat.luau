--!nonstrict
--[[
	Combat — server. Server-authoritative melee + ranged (#12), reusing the v0.4.0 client-input →
	RemoteEvent → server-validated-hit pipeline (the same shape as Harvesting). The client only
	REQUESTS an attack; the server validates everything and decides the hit. NEVER trusts the client.

	A weapon is just an Item with a `toolType` (so the hotbar→Tool bridge equips it) plus flat
	`weapon*` fields: `weaponKind` ("melee" | "bow"), `weaponDamage`, `weaponRange`, `weaponCooldown`,
	and for bows `weaponDrawTime`, `weaponProjectileSpeed`, `weaponMaxRange`, `weaponAmmo`. Flat
	attributes so a weapon is fully no-code-authorable (the admin plugin's Weapons editor writes them).

	Targets are anything with a Humanoid: engine `Mobs` (damaged via `Mobs.damage`, so the FSM gets
	attribution + a `mob:hit` reaction) and — when `Config "Combat".FriendlyFire` is on — other
	players. The kill-event schema is designed ONCE here:

		combat:hit  { attacker, victim, weapon, source, damage, victimHpLeft }
		combat:kill { attacker, victim, weapon, source }      -- source = "melee" | "bow"

	fired via BOTH `Hooks` (engine extension) and `EventBridge` (analytics/quests/achievements), and
	replacing TCE's overlapping zombie_killed / animal_killed / pvp_kill / bow_kill / spear_kill.
	Tuning: the "Combat" Config section. Started by SurvivorCore.start().
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.Combat is server-only — require it via SurvivorCore.start()")

local Registries = require(script.Parent.Parent.registries)
local Mobs = require(script.Parent.Mobs)
local Inventory = require(script.Parent.Inventory)
local Hooks = require(script.Parent.Parent.foundation.Hooks)
local EventBridge = require(script.Parent.Parent.foundation.EventBridge)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local CombatConfig = require(script.Parent.Parent.shared.CombatConfig)

local Combat = {}

local started = false
local lastSwing: { [Player]: number } = {}
local drawStart: { [Player]: number } = {}

local function playerRoot(player: Player): BasePart?
	local char = player.Character
	if not char then
		return nil
	end
	return (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart) :: BasePart?
end

local function isAlive(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- The def for the player's equipped weapon (the held engine Tool's _ItemId → Items registry), or nil
-- if they're not holding a weapon of the wanted kind.
local function equippedWeapon(player: Player, wantKind: string): (any?, string?)
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not tool then
		return nil, nil
	end
	local itemId = tostring(tool:GetAttribute("_ItemId") or tool.Name)
	local def = Registries.Items.get(itemId)
	if not def then
		return nil, nil
	end
	local kind = tostring(def.weaponKind or "")
	if kind ~= wantKind then
		return nil, nil
	end
	return def, itemId
end

-- A clear raycast from one point to another, ignoring the attacker + target instances.
local function clearShot(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(from, to - from, params)
	return result == nil
end

-- The fired hooks/events for a landed hit (and a kill, if the victim died). Designed once, here.
local function fireHit(
	attacker: Player,
	victim: Instance,
	weapon: string,
	source: string,
	damage: number,
	hum: Humanoid
)
	local hpLeft = math.max(0, hum.Health)
	local ctx = {
		attacker = attacker,
		victim = victim,
		weapon = weapon,
		source = source,
		damage = damage,
		victimHpLeft = hpLeft,
	}
	Hooks.run("combat:hit", ctx)
	EventBridge.fire("combat:hit", attacker, { victim = victim, weapon = weapon, source = source, damage = damage })
	if hum.Health <= 0 then
		local kctx = { attacker = attacker, victim = victim, weapon = weapon, source = source }
		Hooks.run("combat:kill", kctx)
		EventBridge.fire("combat:kill", attacker, { victim = victim, weapon = weapon, source = source })
	end
end

-- Apply combat damage to a victim model. Mobs route through Mobs.damage (attribution + reaction);
-- a player victim takes Humanoid damage directly (which syncs to their survival Health HUD).
local function applyDamage(
	attacker: Player,
	model: Model,
	hum: Humanoid,
	damage: number,
	weapon: string,
	source: string
)
	if Mobs.isMob(model) then
		Mobs.damage(model, damage, attacker)
	else
		hum:TakeDamage(damage)
	end
	fireHit(attacker, model, weapon, source, damage, hum)
end

local function fireResult(player: Player, payload: { [string]: any })
	Remotes.event("CombatResult"):FireClient(player, payload)
end

-- ===== Melee =================================================================

-- Find the nearest valid melee target (mob, or another player if FriendlyFire) within range + LoS.
local function findMeleeTarget(attacker: Player, range: number): (Humanoid?, Model?)
	local aroot = playerRoot(attacker)
	if not aroot then
		return nil, nil
	end
	local origin = aroot.Position
	local achar = attacker.Character :: any
	local cfg = CombatConfig.get()

	local bestHum, bestModel, bestDist = nil, nil, range

	local function consider(model: Model)
		local hum = model:FindFirstChildOfClass("Humanoid")
		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if not hum or hum.Health <= 0 or not root then
			return
		end
		local d = (root.Position - origin).Magnitude
		if d > bestDist then
			return
		end
		if cfg.RequireLineOfSight and not clearShot(origin, root.Position, { achar, model }) then
			return
		end
		bestHum, bestModel, bestDist = hum, model, d
	end

	for _, model in Mobs.getActive() do
		consider(model)
	end
	if cfg.FriendlyFire then
		for _, other in Players:GetPlayers() do
			if other ~= attacker and other.Character then
				consider(other.Character)
			end
		end
	end
	return bestHum, bestModel
end

local function onMeleeSwing(player: Player)
	if not isAlive(player) then
		return
	end
	local def, itemId = equippedWeapon(player, "melee")
	if not def then
		return
	end

	local cfg = CombatConfig.get()
	local cooldown = tonumber(def.weaponCooldown) or tonumber(cfg.MeleeCooldown) or 0.6
	local now = os.clock()
	if lastSwing[player] and now - lastSwing[player] < cooldown then
		return
	end
	lastSwing[player] = now

	local range = tonumber(def.weaponRange) or tonumber(cfg.MeleeRange) or 8
	local damage = tonumber(def.weaponDamage) or 10
	local hum, model = findMeleeTarget(player, range)
	if hum and model then
		applyDamage(player, model, hum, damage, itemId, "melee")
		fireResult(player, { ok = true, source = "melee", hit = true })
	else
		fireResult(player, { ok = true, source = "melee", hit = false })
	end
end

-- ===== Ranged (bow) ==========================================================

-- Per-shot arrow modifiers from the ammo item def (or neutral defaults for an ammo-free bow).
-- ammoDamage / ammoSpeed scale the bow's values; ammoDrop scales gravity (heavier arrow = more
-- curve/drop); ammoRange caps the flight independently. This is what makes arrow TYPES differ.
local function arrowMods(ammoId: string)
	local d = ammoId ~= "" and Registries.Items.get(ammoId) or nil
	return {
		damage = (d and tonumber(d.ammoDamage)) or 1, -- damage multiplier
		speed = (d and tonumber(d.ammoSpeed)) or 0, -- speed multiplier; 0 = use bow speed as-is
		drop = (d and tonumber(d.ammoDrop)) or 1, -- gravity multiplier (curve); >1 drops faster
		range = (d and tonumber(d.ammoRange)) or 0, -- max studs; 0 = use bow/Config default
	}
end

-- Step a gravity-affected projectile via short raycasts. Returns the first Humanoid hit, its model,
-- the impact point, and a downsampled `path` of waypoints along the ARC (origin → impact) so the
-- client can render the curving flight that the server actually computed (no client-side guessing).
local function simulateArrow(
	origin: Vector3,
	dir: Vector3,
	speed: number,
	gravity: number,
	maxRange: number,
	ignore: { Instance }
): (Humanoid?, Model?, Vector3, { Vector3 })
	local step = math.max(1, tonumber(CombatConfig.get().Bow.StepSize) or 4)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local path: { Vector3 } = { origin }
	local waypointEvery = 10 -- studs between recorded visual waypoints
	local lastRecord = 0
	local pos = origin
	local vel = dir.Unit * math.max(1, speed)
	local g = Vector3.new(0, -gravity, 0)
	local traveled = 0
	while traveled < maxRange do
		local dt = step / math.max(1, speed)
		local nextPos = pos + vel * dt + 0.5 * g * dt * dt
		vel = vel + g * dt
		local seg = nextPos - pos
		local result = Workspace:Raycast(pos, seg, params)
		if result then
			local model = result.Instance:FindFirstAncestorWhichIsA("Model")
			local hum = model and model:FindFirstChildOfClass("Humanoid")
			table.insert(path, result.Position)
			return hum, model, result.Position, path
		end
		pos = nextPos
		traveled += seg.Magnitude
		if traveled - lastRecord >= waypointEvery then
			table.insert(path, pos)
			lastRecord = traveled
		end
	end
	table.insert(path, pos)
	return nil, nil, pos, path
end

-- `targetPoint` is the world point the client's crosshair (camera-centre ray) is aimed at; the
-- server recomputes the true fire direction from the bow's own origin, eliminating shoulder-camera
-- parallax and any client direction spoofing.
local function onBowRelease(player: Player, targetPoint: any, _clientAlpha: any)
	if not isAlive(player) or typeof(targetPoint) ~= "Vector3" then
		drawStart[player] = nil
		return
	end
	local def, itemId = equippedWeapon(player, "bow")
	if not def then
		drawStart[player] = nil
		return
	end
	local aroot = playerRoot(player)
	if not aroot then
		drawStart[player] = nil
		return
	end

	-- Server-timed draw (anti-cheat): how long the player actually held, clamped to the draw time.
	local cfg = CombatConfig.get()
	local drawTime = math.max(0.01, tonumber(def.weaponDrawTime) or 1)
	local held = drawStart[player] and (os.clock() - drawStart[player]) or 0
	drawStart[player] = nil
	local alpha = math.clamp(held / drawTime, 0, 1)

	-- Consume ammo if the bow requires it (arrows must be in the inventory).
	local ammo = tostring(def.weaponAmmo or "")
	if ammo ~= "" then
		if not Inventory.remove(player, ammo, 1) then
			fireResult(player, { ok = false, source = "bow", reason = "ammo" })
			return
		end
	end

	-- Combine BOW stats (pullback: base speed/damage/draw) with ARROW stats (weight→drop, damage,
	-- range, speed) and the draw strength.
	local mods = arrowMods(ammo)
	local drawScale = tonumber(cfg.Bow.MinDrawDamageMult) or 0.3
	drawScale = drawScale + (1 - drawScale) * alpha
	local baseSpeed = tonumber(def.weaponProjectileSpeed) or tonumber(cfg.Bow.ProjectileSpeed) or 180
	local speed = (mods.speed > 0 and baseSpeed * mods.speed or baseSpeed) * drawScale
	local gravity = (tonumber(cfg.Bow.Gravity) or 80) * mods.drop
	local maxRange = (mods.range > 0 and mods.range)
		or tonumber(def.weaponMaxRange)
		or tonumber(cfg.Bow.MaxRange)
		or 300
	local damage = (tonumber(def.weaponDamage) or 10) * mods.damage * drawScale

	local origin = aroot.Position + Vector3.new(0, 1.5, 0)
	local dir = targetPoint - origin
	if dir.Magnitude < 0.01 then
		dir = aroot.CFrame.LookVector
	end
	local hum, model, _hitPos, path =
		simulateArrow(origin, dir.Unit, speed, gravity, maxRange, { player.Character :: any })

	local hit = false
	if hum and model and hum.Health > 0 then
		-- Don't let an arrow damage the shooter; friendly-fire still gated for player victims.
		local victimPlayer = Players:GetPlayerFromCharacter(model)
		local allowed = Mobs.isMob(model) or (victimPlayer ~= nil and victimPlayer ~= player and cfg.FriendlyFire)
		if allowed then
			applyDamage(player, model, hum, damage, itemId, "bow")
			hit = true
		end
	end
	-- `path` is the arc (origin → impact) so the client renders the curving flight, not a straight line.
	fireResult(player, { ok = true, source = "bow", hit = hit, path = path })
end

function Combat.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	-- Eager so clients can connect at startup (server→client feedback).
	Remotes.event("CombatResult")

	Remotes.event("CombatSwing").OnServerEvent:Connect(function(player)
		onMeleeSwing(player)
	end)
	Remotes.event("BowDraw").OnServerEvent:Connect(function(player)
		drawStart[player] = os.clock()
	end)
	Remotes.event("BowRelease").OnServerEvent:Connect(function(player, targetPoint, clientAlpha)
		onBowRelease(player, targetPoint, clientAlpha)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		drawStart[player] = nil
	end)
end

return Combat
