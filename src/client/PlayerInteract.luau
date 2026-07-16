--!nonstrict
--[[
	PlayerInteract — client. Walk-up player interaction (ported from The Counter Earth's inspect
	window). CLIENT-ONLY.

	Get close to another player and a "[E] Interact" billboard appears over THEIR head (never your
	own). Pressing the interact key (or tapping the billboard) opens an interact window showing that
	player's name + survival stats and a list of ACTIONS. "Trade" is the first built-in action; games
	add more with `SurvivorCore.Interact.addAction{…}`.

	This replaces the old per-character server ProximityPrompt (which wrongly showed on your own
	character). Targeting is a throttled nearest-other-in-range scan — self is skipped in the loop,
	so the affordance can never point at you. The "Trade" action just fires the existing
	`TradeRequest` remote; the server (`Trade._startTrade`) does all the validation, and the existing
	invite/Accept flow (TradeUi) takes over. Booted by SurvivorCore.startClient().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

assert(RunService:IsClient(), "SurvivorCore.PlayerInteract is client-only — boot via SurvivorCore.startClient()")

local Remotes = require(script.Parent.Parent.shared.Remotes)
local UiConfig = require(script.Parent.Parent.shared.UiConfig)
local TradingConfig = require(script.Parent.Parent.shared.TradingConfig)
local StatConfig = require(script.Parent.Parent.stats.StatConfig)

local PlayerInteract = {}

local started = false
local localPlayer = Players.LocalPlayer

local SCAN_INTERVAL = 0.2
local SWITCH_MARGIN = 1.5 -- hysteresis: a new target must be this much closer to steal focus

local currentTarget: Player? = nil
local tradeActive = false -- suppress interaction while a trade window is up

-- ── action registry (buffered; addAction works before or after start) ─────────
local actions: { any } = {}

-- spec = { id, label, order?, icon?, enabled?(ctx)->bool, onActivate(ctx) }
-- ctx  = { target, targetUserId, distance, close }
function PlayerInteract.addAction(spec: any)
	assert(
		type(spec) == "table" and type(spec.id) == "string" and type(spec.onActivate) == "function",
		"Interact.addAction: spec needs { id: string, onActivate: function, … }"
	)
	for i, a in actions do
		if a.id == spec.id then
			actions[i] = spec -- replace-by-id, so a game can override a built-in
			return
		end
	end
	table.insert(actions, spec)
end

-- ── theme helpers (same idiom as TradeUi) ──────────────────────────────────────

local function theme(): any
	return UiConfig.get().Theme or {}
end

local function corner(inst: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function button(text: string, bg: Color3): TextButton
	local t = theme()
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Text = text
	b.Font = t.FontBold or Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = t.Text or Color3.fromRGB(245, 245, 245)
	b.BackgroundColor3 = bg
	b.BorderSizePixel = 0
	corner(b, tonumber(t.CornerRadius) or 8)
	return b
end

-- ── the interact window ────────────────────────────────────────────────────────

local windowPanel: Frame? = nil
local windowBody: Frame? = nil
local savedMouseBehavior: Enum.MouseBehavior? = nil

local function ensureWindow(): Frame?
	if windowPanel and windowPanel.Parent then
		return windowPanel
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local t = theme()

	local gui = Instance.new("ScreenGui")
	gui.Name = "SurvivorCoreInteract"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 70 -- below TradeUi (90), above menu/HUD
	gui.Enabled = true

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(320, 300)
	panel.BackgroundColor3 = t.PanelColor or Color3.fromRGB(20, 23, 30)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	corner(panel, tonumber(t.CornerRadius) or 10)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = panel

	local close = button("✕", Color3.fromRGB(90, 60, 60))
	close.Size = UDim2.fromOffset(24, 24)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Parent = panel
	close.MouseButton1Click:Connect(function()
		PlayerInteract.closeWindow()
	end)

	local content = Instance.new("Frame")
	content.Name = "Body"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(0, 28)
	content.Size = UDim2.new(1, 0, 1, -28)
	content.Parent = panel

	panel.Parent = gui
	gui.Parent = playerGui
	windowPanel = panel
	windowBody = content
	return panel
end

-- One stat bar row for the target (read from replicated Player attributes).
local function statRow(def: any, target: Player, order: number): Frame
	local t = theme()
	local attr = def.attribute or def.name
	local value = tonumber(target:GetAttribute(attr))
	local max = tonumber(def.max) or 100
	local ratio = if value and max > 0 then math.clamp(value / max, 0, 1) else 0
	local fillRatio = if def.invert then 1 - ratio else ratio

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order

	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(0.34, 1)
	name.BackgroundTransparency = 1
	name.Text = def.name
	name.TextColor3 = t.TextSecondary or Color3.fromRGB(200, 205, 215)
	name.Font = t.Font or Enum.Font.GothamMedium
	name.TextSize = 12
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local track = Instance.new("Frame")
	track.Size = UDim2.new(0.66, -40, 0, 8)
	track.Position = UDim2.new(0.34, 0, 0.5, -4)
	track.BackgroundColor3 = t.SlotColor or Color3.fromRGB(28, 32, 42)
	track.BorderSizePixel = 0
	corner(track, 4)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(fillRatio, 1)
	fill.BackgroundColor3 = if def.dangerHigh
		then Color3.fromRGB(200, 90, 80)
		else (t.Ok or Color3.fromRGB(120, 190, 120))
	fill.BorderSizePixel = 0
	corner(fill, 4)
	fill.Parent = track
	track.Parent = row

	local val = Instance.new("TextLabel")
	val.Size = UDim2.fromOffset(38, 22)
	val.Position = UDim2.new(1, -38, 0, 0)
	val.BackgroundTransparency = 1
	val.Text = if value then tostring(math.floor(value)) else "—"
	val.TextColor3 = t.Text or Color3.fromRGB(235, 238, 245)
	val.Font = t.Font or Enum.Font.GothamMedium
	val.TextSize = 12
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Parent = row

	return row
end

local function renderWindow(target: Player)
	local panel = ensureWindow()
	if not panel or not windowBody then
		return
	end
	for _, c in windowBody:GetChildren() do
		c:Destroy()
	end
	local t = theme()

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -28, 0, 24)
	header.BackgroundTransparency = 1
	header.Text = target.DisplayName
	header.TextColor3 = t.Accent or Color3.fromRGB(204, 166, 102)
	header.Font = t.FontBold or Enum.Font.GothamBold
	header.TextSize = 18
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextTruncate = Enum.TextTruncate.AtEnd
	header.Parent = windowBody

	-- Stat bars (only stats flagged for display; new stats appear automatically).
	local statsHolder = Instance.new("Frame")
	statsHolder.BackgroundTransparency = 1
	statsHolder.Position = UDim2.fromOffset(0, 30)
	statsHolder.Size = UDim2.new(1, 0, 1, -74)
	local sl = Instance.new("UIListLayout")
	sl.Padding = UDim.new(0, 3)
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Parent = statsHolder
	local order = 0
	for _, def in StatConfig.resolve().stats do
		if def.display ~= false then
			order += 1
			statRow(def, target, order).Parent = statsHolder
		end
	end
	statsHolder.Parent = windowBody

	-- Action buttons (registry, sorted, enable-filtered).
	local ctx = {
		target = target,
		targetUserId = target.UserId,
		distance = 0,
		close = function()
			PlayerInteract.closeWindow()
		end,
	}
	local hrp = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	local lhrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	if hrp and lhrp then
		ctx.distance = (hrp.Position - lhrp.Position).Magnitude
	end

	local shown = {}
	for _, a in actions do
		if not a.enabled or a.enabled(ctx) then
			table.insert(shown, a)
		end
	end
	table.sort(shown, function(a, b)
		return (tonumber(a.order) or 100) < (tonumber(b.order) or 100)
	end)

	local actionRow = Instance.new("Frame")
	actionRow.BackgroundTransparency = 1
	actionRow.Position = UDim2.new(0, 0, 1, -34)
	actionRow.Size = UDim2.new(1, 0, 0, 34)
	local al = Instance.new("UIListLayout")
	al.FillDirection = Enum.FillDirection.Horizontal
	al.Padding = UDim.new(0, 6)
	al.Parent = actionRow
	if #shown == 0 then
		local none = Instance.new("TextLabel")
		none.Size = UDim2.fromScale(1, 1)
		none.BackgroundTransparency = 1
		none.Text = "No actions available"
		none.TextColor3 = t.TextSecondary or Color3.fromRGB(150, 160, 180)
		none.Font = t.Font or Enum.Font.GothamMedium
		none.TextSize = 13
		none.Parent = actionRow
	else
		local w = 1 / #shown
		for i, a in shown do
			local b = button(a.label or a.id, t.Accent or Color3.fromRGB(120, 170, 90))
			b.Size = UDim2.new(w, -6, 1, 0)
			b.LayoutOrder = i
			b.Parent = actionRow
			b.MouseButton1Click:Connect(function()
				local ok, err = pcall(a.onActivate, ctx)
				if not ok then
					warn(`[SurvivorCore.Interact] action '{a.id}' errored: {tostring(err)}`)
				end
			end)
		end
	end
	actionRow.Parent = windowBody
end

function PlayerInteract.openWindow(target: Player)
	if not target or target == localPlayer or not target.Parent then
		return
	end
	local panel = ensureWindow()
	if not panel then
		return
	end
	renderWindow(target)
	panel.Visible = true
	-- Free the cursor so the buttons are clickable (first person locks it centred).
	if savedMouseBehavior == nil then
		savedMouseBehavior = UserInputService.MouseBehavior
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

function PlayerInteract.closeWindow()
	if windowPanel then
		windowPanel.Visible = false
	end
	if savedMouseBehavior ~= nil then
		UserInputService.MouseBehavior = savedMouseBehavior
		savedMouseBehavior = nil
	end
end

local function windowOpen(): boolean
	return windowPanel ~= nil and windowPanel.Visible
end

-- ── the billboard affordance ────────────────────────────────────────────────────

local billboard: BillboardGui? = nil

local function ensureBillboard(): BillboardGui?
	if billboard and billboard.Parent then
		return billboard
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local t = theme()
	local bb = Instance.new("BillboardGui")
	bb.Name = "SurvivorCoreInteractPrompt"
	bb.Size = UDim2.fromOffset(150, 30)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 60
	bb.Enabled = false

	local btn = Instance.new("TextButton")
	btn.Name = "Btn"
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundColor3 = t.PanelColor or Color3.fromRGB(20, 23, 30)
	btn.BackgroundTransparency = 0.2
	btn.AutoButtonColor = true
	btn.Text = ""
	btn.Font = t.FontBold or Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextColor3 = t.Text or Color3.fromRGB(235, 238, 245)
	corner(btn, tonumber(t.CornerRadius) or 8)
	btn.Parent = bb
	btn.MouseButton1Click:Connect(function()
		if currentTarget then
			PlayerInteract.openWindow(currentTarget)
		end
	end)

	bb.Parent = playerGui
	billboard = bb
	return bb
end

local function setTarget(target: Player?)
	currentTarget = target
	local bb = ensureBillboard()
	if not bb then
		return
	end
	if target and target.Character then
		local head = target.Character:FindFirstChild("Head") or target.Character:FindFirstChild("HumanoidRootPart")
		bb.Adornee = head
		local btn = bb:FindFirstChild("Btn")
		if btn and btn:IsA("TextButton") then
			btn.Text = `[E] Interact — {target.DisplayName}`
		end
		bb.Enabled = head ~= nil and not tradeActive
	else
		bb.Adornee = nil
		bb.Enabled = false
	end
end

-- ── scan ─────────────────────────────────────────────────────────────────────

local function localHRP(): BasePart?
	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

local function targetValid(target: Player?, myPos: Vector3, maxDist: number): boolean
	if not target or target == localPlayer or not target.Parent then
		return false
	end
	local char = target.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return false
	end
	return (hrp.Position - myPos).Magnitude <= maxDist
end

local function scan()
	if tradeActive then
		if currentTarget then
			setTarget(nil)
		end
		if windowOpen() then
			PlayerInteract.closeWindow()
		end
		return
	end
	local myHRP = localHRP()
	if not myHRP then
		if currentTarget then
			setTarget(nil)
			PlayerInteract.closeWindow()
		end
		return
	end
	local maxDist = tonumber(TradingConfig.get().MaxDistance) or 16

	-- Nearest OTHER player in range (self skipped → never targets you).
	local bestPlayer, bestDist = nil, math.huge
	for _, plr in Players:GetPlayers() do
		if plr ~= localPlayer and plr.Character then
			local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local d = (hrp.Position - myHRP.Position).Magnitude
				if d <= maxDist and d < bestDist then
					bestPlayer, bestDist = plr, d
				end
			end
		end
	end

	-- Keep the current target unless it's invalid or a new one is meaningfully closer (hysteresis).
	local cur = currentTarget
	if cur and targetValid(cur, myHRP.Position, maxDist) then
		local curChar = cur.Character
		local curHRP = curChar and curChar:FindFirstChild("HumanoidRootPart")
		local curDist = if curHRP then (curHRP.Position - myHRP.Position).Magnitude else math.huge
		if bestPlayer and bestPlayer ~= cur and bestDist < curDist - SWITCH_MARGIN then
			setTarget(bestPlayer)
		end
	else
		setTarget(bestPlayer)
		-- If the open window's subject vanished/left range, close it.
		if windowOpen() and not (currentTarget and targetValid(currentTarget, myHRP.Position, maxDist)) then
			PlayerInteract.closeWindow()
		end
	end
end

-- ── input ───────────────────────────────────────────────────────────────────────

local function interactKeyCode(): Enum.KeyCode
	local name = (UiConfig.get().Keybinds or {}).Interact or "E"
	local ok, kc = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok and typeof(kc) == "EnumItem" then
		return kc :: Enum.KeyCode
	end
	return Enum.KeyCode.E
end

function PlayerInteract.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	-- Built-in Trade action: fire the existing request remote; the server validates and the
	-- invite/Accept flow (TradeUi) takes over.
	PlayerInteract.addAction({
		id = "trade",
		label = "Trade",
		order = 10,
		enabled = function(ctx)
			return TradingConfig.get().Enabled ~= false
				and ctx.distance <= (tonumber(TradingConfig.get().MaxDistance) or 16)
		end,
		onActivate = function(ctx)
			Remotes.event("TradeRequest"):FireServer(ctx.targetUserId)
			ctx.close()
		end,
	})

	-- Suppress interaction while a trade window is up; reopen scanning when it closes.
	Remotes.event("TradeState").OnClientEvent:Connect(function(state)
		local status = state and state.status
		tradeActive = status ~= nil and status ~= "cancelled" and status ~= "done"
		if tradeActive then
			PlayerInteract.closeWindow()
			setTarget(nil)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or tradeActive then
			return
		end
		if input.KeyCode == interactKeyCode() and currentTarget then
			if windowOpen() then
				PlayerInteract.closeWindow()
			else
				PlayerInteract.openWindow(currentTarget)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(plr)
		if plr == currentTarget then
			setTarget(nil)
			PlayerInteract.closeWindow()
		end
	end)

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < SCAN_INTERVAL then
			return
		end
		accum = 0
		scan()
	end)
end

return PlayerInteract
