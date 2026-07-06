--!nonstrict
--[[
	LootBags — server. Death drops your things (issue #19, ported from The Counter Earth).

	On a player's death (config-gated): snapshot-and-clear the inventory — and, by default, WORN
	equipment too — via `Inventory.clearAll`, then spill it into an anchored loot bag at the death
	spot (ground-clamped raycast). The bag holds its contents as IntValue children (item id → qty),
	shows a floating countdown, and despawns after `LifetimeSeconds` with whatever's left. ANYONE
	may loot it: equipment restores to empty equip slots FIRST (a satchel re-grows your slots and
	weight cap before the stacks pour back in), then stacks grant via `Inventory.addUpTo` — partial
	pickups leave the remainder in the bag, so nothing is ever silently lost.

	Fires `player:died` (Hooks + EventBridge — AFTER the clear, so consumers see consistent state)
	plus `lootbag:dropped` / `lootbag:collected`, and maps `player:died` into the Progression
	stream ("death") so `deaths_total` counters/achievements work. The owner gets a `LootBagDropped`
	remote for the client-side beacon. Tuning: the "LootBags" Config section. Session-scoped.
	Started by SurvivorCore.start().
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.LootBags is server-only — booted by SurvivorCore.start()")

local Inventory = require(script.Parent.Inventory)
local Progression = require(script.Parent.Progression)
local Registries = require(script.Parent.Parent.registries)
local Hooks = require(script.Parent.Parent.foundation.Hooks)
local EventBridge = require(script.Parent.Parent.foundation.EventBridge)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local LootBagsConfig = require(script.Parent.Parent.shared.LootBagsConfig)

local LootBags = {}

local started = false
local looting: { [Player]: boolean } = {} -- re-entry guard per collector

-- Each owner's NEWEST bag — the one their beacon points at. Older bags coexist in the world on
-- their own timers; only the latest bag's fate may clear the owner's beacon (dying again mid
-- corpse-run re-points the beacon at the new bag, and the old bag's later despawn must not
-- touch it).
local latestBag: { [Player]: Instance } = {}

-- ── Bag construction ─────────────────────────────────────────────────────────

local function bagTemplate(): PVInstance?
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local content = ReplicatedStorage:FindFirstChild("SurvivorCoreContent")
	local tmpl = content and content:FindFirstChild("LootBag")
	if tmpl and tmpl:IsA("PVInstance") then
		return tmpl
	end
	return nil
end

local function buildPlaceholderBag(): BasePart
	local bag = Instance.new("Part")
	bag.Name = "LootBag"
	bag.Shape = Enum.PartType.Ball
	bag.Size = Vector3.new(1.6, 1.6, 1.6)
	bag.Color = Color3.fromRGB(120, 90, 55)
	bag.Material = Enum.Material.Fabric
	return bag
end

local function bagHost(bag: Instance): BasePart?
	if bag:IsA("BasePart") then
		return bag
	end
	return bag:FindFirstChildWhichIsA("BasePart")
end

-- Floating countdown label (server-built, HP-bar pattern — everyone sees it).
local function attachCountdown(bag: Instance, lifetime: number)
	local host = bagHost(bag)
	if not host then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "_LootBagTimer"
	gui.Adornee = host
	gui.Size = UDim2.fromOffset(90, 22)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.Parent = gui
	gui.Parent = bag

	task.spawn(function()
		local deadline = os.clock() + lifetime
		while bag.Parent and gui.Parent do
			local left = math.max(0, math.floor(deadline - os.clock()))
			label.Text = string.format("%d:%02d", left // 60, left % 60)
			label.TextColor3 = if left < 30
				then Color3.fromRGB(235, 90, 90)
				elseif left < 60 then Color3.fromRGB(240, 190, 80)
				else Color3.fromRGB(245, 245, 245)
			if left <= 0 then
				break
			end
			task.wait(1)
		end
	end)
end

-- ── Pickup ───────────────────────────────────────────────────────────────────

-- Grant the bag's contents to a collector: equipment first (Back first, so a satchel re-grows the
-- slot/weight caps), then stacks up-to-fit. Consumed IntValues shrink/vanish; the bag survives
-- with any remainder and is destroyed only when empty.
local function collect(bag: Instance, player: Player)
	if looting[player] then
		return
	end
	-- Dead players can't loot — the corpse falls right next to the bag, and a quick E while dead
	-- would scoop everything back before the respawn corpse-run even begins.
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	looting[player] = true

	local entries = {}
	for _, child in bag:GetChildren() do
		if child:IsA("IntValue") and child.Value > 0 then
			table.insert(entries, child)
		end
	end
	-- Equipment-restorable entries first, "back" slot before the rest.
	table.sort(entries, function(a, b)
		local da = Registries.Items.get(a.Name)
		local db = Registries.Items.get(b.Name)
		local ea = (da and typeof(da.equipment) == "table" and da.equipment.slot) or nil
		local eb = (db and typeof(db.equipment) == "table" and db.equipment.slot) or nil
		if (ea ~= nil) ~= (eb ~= nil) then
			return ea ~= nil
		end
		if ea and eb and (ea == "back") ~= (eb == "back") then
			return ea == "back"
		end
		return a.Name < b.Name
	end)

	local grantedAny = false
	for _, entry in entries do
		local def = Registries.Items.get(entry.Name)
		-- One unit may go straight onto an empty equip slot (the satchel path).
		if def and typeof(def.equipment) == "table" and entry.Value > 0 then
			if Inventory.restoreEquip(player, def.equipment.slot, entry.Name) then
				entry.Value -= 1
				grantedAny = true
			end
		end
		if entry.Value > 0 then
			local granted = Inventory.addUpTo(player, entry.Name, entry.Value)
			if granted > 0 then
				entry.Value -= granted
				grantedAny = true
			end
		end
		if entry.Value <= 0 then
			entry:Destroy()
		end
	end

	if grantedAny then
		local remaining = 0
		for _, child in bag:GetChildren() do
			if child:IsA("IntValue") and child.Value > 0 then
				remaining += 1
			end
		end
		local ctx = { player = player, bag = bag, emptied = remaining == 0 }
		Hooks.run("lootbag:collected", ctx)
		EventBridge.fire("lootbag:collected", player, { emptied = remaining == 0 })
		if remaining == 0 then
			bag:Destroy()
		end
	end
	looting[player] = nil
end

-- ── Death → bag ──────────────────────────────────────────────────────────────

local function dropBag(player: Player, position: Vector3)
	local cfg = LootBagsConfig.get()
	local snapshot = Inventory.clearAll(player, { equipment = cfg.DropEquipment ~= false })

	-- player:died fires AFTER the clear so hook/bus consumers (deaths counters, analytics) see
	-- consistent state — the inventory is already empty by the time anyone reacts.
	local dctx = { player = player, position = position }
	Hooks.run("player:died", dctx)
	EventBridge.fire("player:died", player, { position = position })

	local total = #snapshot.slots + #snapshot.equipment
	if total == 0 then
		return -- died empty-handed; no bag
	end

	-- The bag is a MODEL so it can be made stream-persistent for its owner: with the default
	-- StreamingEnabled place, respawning far from the death spot would otherwise evict the bag
	-- from the owner's client — it looked deleted (and killed the beacon) even though the server
	-- still had it.
	local tmpl = bagTemplate()
	local inner: Instance = if tmpl then tmpl:Clone() else buildPlaceholderBag()
	local bag: Model
	if inner:IsA("Model") then
		bag = inner
	else
		bag = Instance.new("Model")
		inner.Parent = bag
		if inner:IsA("BasePart") then
			bag.PrimaryPart = inner
		end
	end
	bag.Name = "LootBag"
	pcall(function()
		bag.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
		bag:AddPersistentPlayer(player)
	end)

	-- Aggregate contents as IntValue children (item id → qty), equipment included.
	local counts: { [string]: number } = {}
	for _, s in snapshot.slots do
		counts[s.itemId] = (counts[s.itemId] or 0) + s.qty
	end
	for _, e in snapshot.equipment do
		counts[e.itemId] = (counts[e.itemId] or 0) + 1
	end
	for itemId, qty in counts do
		local v = Instance.new("IntValue")
		v.Name = itemId
		v.Value = qty
		v.Parent = bag
	end

	-- Ground-clamp: a mid-air/water death still leaves a reachable, ANCHORED bag.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: any, bag }
	local hit = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -120, 0), params)
	local groundY = if hit then hit.Position.Y else position.Y;
	(bag :: PVInstance):PivotTo(CFrame.new(position.X, groundY + 1, position.Z))
	for _, p in bag:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
		end
	end
	local host = bagHost(bag)
	if host then
		host.Anchored = true
		host.CanCollide = false
	end

	bag:SetAttribute("_OwnerUserId", player.UserId)
	bag:SetAttribute("_SpawnTime", os.time())
	bag.Parent = Workspace

	local lifetime = tonumber(cfg.LifetimeSeconds) or 300
	if cfg.ShowCountdown ~= false then
		attachCountdown(bag, lifetime)
	end

	if host then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Loot"
		prompt.ObjectText = player.Name .. "'s bag"
		prompt.MaxActivationDistance = tonumber(cfg.InteractRange) or 8
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = host
		prompt.Triggered:Connect(function(collector)
			collect(bag, collector)
		end)
	end

	task.delay(lifetime, function()
		if bag.Parent then
			bag:Destroy()
		end
	end)

	local ctx = { player = player, bag = bag, position = position, items = total }
	Hooks.run("lootbag:dropped", ctx)
	EventBridge.fire("lootbag:dropped", player, { position = position, items = total })

	-- Owner-only client juice: beacon + "your things dropped" toast. The beacon payload is PLAIN
	-- DATA (position + lifetime) — no Instance reference, so there is no replication race and no
	-- streaming fragility; the client builds the beam at the position and keeps it until the bag
	-- is truly gone (the nil-fire below) or the lifetime lapses.
	local host2 = bagHost(bag)
	local beaconPos = if host2 then host2.Position else position
	latestBag[player] = bag
	if cfg.OwnerBeacon ~= false then
		Remotes.event("LootBagDropped"):FireClient(player, beaconPos, lifetime)
		bag.Destroying:Connect(function()
			-- Clear the owner's beacon ONLY if this is still their newest bag (an older bag
			-- despawning/emptying must not wipe the beacon that points at a newer one).
			if latestBag[player] == bag then
				latestBag[player] = nil
				if player.Parent then
					Remotes.event("LootBagDropped"):FireClient(player, nil)
				end
			end
		end)
	end
	Remotes.event("Notify"):FireClient(player, {
		kind = "death",
		title = "You died",
		body = "Your belongings dropped where you fell.",
	})
end

local function hookCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Once(function()
		local root = character:FindFirstChild("HumanoidRootPart")
		local position = root and root.Position or character:GetPivot().Position
		if LootBagsConfig.get().Enabled == false then
			-- Still announce the death for counters/analytics; inventory untouched.
			Hooks.run("player:died", { player = player, position = position })
			EventBridge.fire("player:died", player, { position = position })
			return
		end
		local ok, err = pcall(dropBag, player, position)
		if not ok then
			warn(`[SurvivorCore.LootBags] drop failed for {player.Name}: {tostring(err)}`)
		end
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		hookCharacter(player, character)
	end)
	if player.Character then
		task.spawn(hookCharacter, player, player.Character)
	end
end

function LootBags.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	-- Deaths flow into the shared progress stream → deaths_total counters/achievements.
	Progression.map("player:died", function(_player, _data)
		return "death", nil, 1
	end)

	Remotes.event("LootBagDropped") -- eager so clients can connect at startup

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		looting[player] = nil
		latestBag[player] = nil
	end)
end

return LootBags
