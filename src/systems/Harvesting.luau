--!nonstrict
--[[
	Harvesting — server. The single, authoritative hit resolver for gatherable nodes, shared by
	BOTH interaction paths: the hold-E ProximityPrompt (Gatherable calls in) and tool-swing
	(client click → HarvestSwing remote → here). This is SurvivorCore's first client-input →
	RemoteEvent → server-validation pipeline, deliberately shaped so combat can reuse it.

	Per hit: resolve the node's resource → roll yield (min..max) → try to grant it (BLOCK the hit,
	no HP loss, if the inventory is full — matches the proven TCE behavior) → decrement HP → fire
	`gather:hit` + the per-type reaction; on depletion fire `gather:depleted` + reaction and destroy
	(unless the node opts out via DestroyOnDeplete=false, so a creator can rez a stump/fell a trunk).
	Rejected swings fire `gather:blocked`. Started by SurvivorCore.start(). Tuning: "Harvesting".
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.Harvesting is server-only — require it via SurvivorCore.start()")

local Inventory = require(script.Parent.Inventory)
local Reactions = require(script.Parent.Parent.foundation.Reactions)
local Hooks = require(script.Parent.Parent.foundation.Hooks)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local HarvestingConfig = require(script.Parent.Parent.shared.HarvestingConfig)

local Harvesting = {}

local GATHERABLE_TAG = "Gatherable"
local started = false

local lastHit: { [Player]: number } = {}

-- Resolved per-node state (written by Gatherable.onSetup from the resource def + overrides).
local function readNode(node: Instance)
	return {
		resource = node:GetAttribute("_Resource"),
		item = tostring(node:GetAttribute("_ItemId") or ""),
		requireTool = tostring(node:GetAttribute("_RequireTool") or ""),
		yieldMin = math.floor(tonumber(node:GetAttribute("_YieldMin")) or 1),
		yieldMax = math.floor(tonumber(node:GetAttribute("_YieldMax")) or 1),
		destroyOnDeplete = node:GetAttribute("_DestroyOnDeplete") ~= false,
		hp = tonumber(node:GetAttribute("_HP")) or 0,
	}
end

local function nodePosition(node: Instance): Vector3?
	if node:IsA("PVInstance") then
		return node:GetPivot().Position
	end
	return nil
end

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

-- The equipped tool's type ("axe"), from the native Tool's ToolType attribute (fallback Name).
local function equippedToolType(player: Player): string?
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end
	local t = tool:GetAttribute("ToolType")
	return if typeof(t) == "string" and t ~= "" then t else tool.Name
end

local function hasLineOfSight(root: BasePart, node: Instance, target: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance, node }
	local origin = root.Position
	local result = Workspace:Raycast(origin, target - origin, params)
	return result == nil -- nothing between the player and the node
end

local function fireResult(player: Player, payload: { [string]: any })
	Remotes.event("HarvestResult"):FireClient(player, payload)
end

local function fireBlocked(player: Player, node: Instance, resource: any, reason: string)
	local ctx = { instance = node, player = player, resource = resource, reason = reason }
	Hooks.run("gather:blocked", ctx)
	Reactions.run(resource, "blocked", ctx)
	fireResult(player, { ok = false, reason = reason, resource = resource })
end

local HP_BAR_NAME = "_HarvestHP"

local function nodeAdornee(node: Instance): BasePart?
	if node:IsA("BasePart") then
		return node
	end
	return node:FindFirstChildWhichIsA("BasePart")
end

-- A small floating "HP left" bar above a node while it's being harvested, so the player can see
-- progress. Server-built (everyone nearby sees it), config-gated, auto-fades after a few idle
-- seconds. Removed on depletion (and destroyed with the node if it's destroyed).
local function updateHealthBar(node: Instance, hpLeft: number, maxHp: number)
	if not HarvestingConfig.get().ShowHealthBar then
		return
	end
	local adornee = nodeAdornee(node)
	if not adornee then
		return
	end
	local gui = node:FindFirstChild(HP_BAR_NAME)
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = HP_BAR_NAME
		gui.Adornee = adornee
		gui.Size = UDim2.fromOffset(110, 16)
		-- Sit a little above the node's top for short nodes, but cap the height for tall ones (a
		-- 14-stud tree shouldn't put its bar 16 studs up, above the canopy and out of view).
		local aboveBase = math.min(adornee.Size.Y + 1.5, 8)
		gui.StudsOffset = Vector3.new(0, aboveBase - adornee.Size.Y / 2, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 60
		local bg = Instance.new("Frame")
		bg.Name = "BG"
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
		bg.BackgroundTransparency = 0.3
		bg.BorderSizePixel = 0
		bg.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = bg
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(90, 200, 110)
		fill.BorderSizePixel = 0
		fill.Parent = bg
		local fc = Instance.new("UICorner")
		fc.CornerRadius = UDim.new(0, 4)
		fc.Parent = fill
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 12
		label.Parent = gui
		gui.Parent = node
	end
	local ratio = if maxHp > 0 then math.clamp(hpLeft / maxHp, 0, 1) else 0
	local bg = gui:FindFirstChild("BG")
	local fill = bg and bg:FindFirstChild("Fill")
	if fill then
		(fill :: Frame).Size = UDim2.fromScale(ratio, 1)
	end
	local label = gui:FindFirstChild("Label")
	if label then
		(label :: TextLabel).Text = `{hpLeft} / {maxHp}`
	end

	-- Debounced fade-out: remove the bar after a few idle seconds (a newer hit cancels this).
	local token = (tonumber(node:GetAttribute("_HPBarToken")) or 0) + 1
	node:SetAttribute("_HPBarToken", token)
	task.delay(4, function()
		if node.Parent and node:GetAttribute("_HPBarToken") == token then
			local g = node:FindFirstChild(HP_BAR_NAME)
			if g then
				g:Destroy()
			end
		end
	end)
end

local function removeHealthBar(node: Instance)
	local g = node:FindFirstChild(HP_BAR_NAME)
	if g then
		g:Destroy()
	end
end

-- Resolve one harvest interaction. `mode` is "prompt" (proximity already enforced) or "tool"
-- (range + line-of-sight enforced here). Returns true if a hit landed.
function Harvesting.tryHarvest(node: Instance, player: Player, mode: string): boolean
	if not node or not node.Parent or not CollectionService:HasTag(node, GATHERABLE_TAG) then
		return false
	end
	if not isAlive(player) then
		return false
	end

	local info = readNode(node)
	if info.hp <= 0 then
		return false -- already depleted (mid-destroy)
	end

	-- Tool gate (both modes; this is also the prompt-path "requireTool" precursor).
	if info.requireTool ~= "" then
		local toolType = equippedToolType(player)
		if toolType ~= info.requireTool then
			fireBlocked(player, node, info.resource, "tool")
			return false
		end
	end

	-- Range + line-of-sight (tool mode; the ProximityPrompt already guarantees these for prompts).
	local pos = nodePosition(node)
	local root = playerRoot(player)
	if mode == "tool" then
		if not pos or not root then
			return false
		end
		local cfg = HarvestingConfig.get()
		if (root.Position - pos).Magnitude > (tonumber(cfg.SwingRange) or 12) then
			return false -- out of range; silent (client pre-check should have caught it)
		end
		if cfg.RequireLineOfSight and not hasLineOfSight(root, node, pos) then
			return false
		end
	end

	-- Per-player cooldown (anti-spam for both paths).
	local now = os.clock()
	local cooldown = tonumber(HarvestingConfig.get().SwingCooldown) or 0.45
	if lastHit[player] and now - lastHit[player] < cooldown then
		return false
	end

	-- Roll + grant the yield BEFORE spending HP. If the inventory can't take it, block the hit so
	-- nothing is lost and the node isn't wasted (proven TCE behavior).
	local amount = info.yieldMax > info.yieldMin and math.random(info.yieldMin, info.yieldMax) or info.yieldMin
	amount = math.max(0, amount)
	if info.item ~= "" and amount > 0 then
		if not Inventory.add(player, info.item, amount) then
			fireBlocked(player, node, info.resource, "full")
			return false
		end
	end

	lastHit[player] = now
	local hp = info.hp - 1
	node:SetAttribute("_HP", hp)
	updateHealthBar(node, math.max(0, hp), tonumber(node:GetAttribute("_MaxHP")) or info.hp)

	local ctx = {
		instance = node,
		player = player,
		resource = info.resource,
		item = info.item,
		granted = amount,
		hpLeft = hp,
		position = pos,
	}
	Hooks.run("gather:hit", ctx)
	Reactions.run(info.resource, "hit", ctx)
	fireResult(player, { ok = true, resource = info.resource, granted = amount, hpLeft = hp })

	if hp <= 0 then
		local dctx = {
			instance = node,
			player = player,
			resource = info.resource,
			item = info.item,
			position = pos,
		}
		Hooks.run("gather:depleted", dctx)
		Reactions.run(info.resource, "depleted", dctx)
		removeHealthBar(node)
		if info.destroyOnDeplete then
			node:Destroy()
		end
	end
	return true
end

function Harvesting.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	-- Create HarvestResult eagerly (server→client feedback) so clients can connect at startup,
	-- not only after the first harvest fires it.
	Remotes.event("HarvestResult")

	-- Tool-swing: the client sends the node it clicked; the server re-validates everything.
	Remotes.event("HarvestSwing").OnServerEvent:Connect(function(player, node)
		if typeof(node) == "Instance" then
			Harvesting.tryHarvest(node, player, "tool")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
	end)
end

return Harvesting
