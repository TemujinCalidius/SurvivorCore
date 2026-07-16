--!nonstrict
--[[
	TradeUi — client. The player-to-player trade window (issue #15).

	NOT a menu tab: a transient, server-driven surface with its own ScreenGui (built on demand, the
	Toasts idiom). The server pushes a plain-data `TradeState` and this renders it:
	  • "invite"  → an incoming request with Accept / Decline (the invitee).
	  • "waiting" → "waiting for <partner>…" + Cancel (the requester).
	  • "open"    → two columns (your offer / their offer), each side's confirm state, Confirm/Cancel.
	  • "cancelled" / "done" → the window closes (a toast explains why).

	Staging is drag-to-offer: drag a slot out of the inventory grid onto the "Your offer" column and
	the server stages that item (cross-ScreenGui drag via DragDrop). Each staged row has −/+ steppers
	and a remove button. Both sides must Confirm; the server does the atomic swap. `mine` renders
	from the pushed list; `theirs` is built manually (SlotGrid reads only the local player).
	Styled from the UI Config Theme. Booted by SurvivorCore.startClient().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "SurvivorCore.TradeUi is client-only — boot it via SurvivorCore.startClient()")

local Remotes = require(script.Parent.Parent.shared.Remotes)
local UiConfig = require(script.Parent.Parent.shared.UiConfig)
local InventoryTypes = require(script.Parent.Parent.shared.InventoryTypes)
local ItemData = require(script.Parent.Parent.shared.ItemData)
local SlotGrid = require(script.Parent.SlotGrid)
local DragDrop = require(script.Parent.DragDrop)
local PanelManager = require(script.Parent.PanelManager)

local TradeUi = {}

local started = false
local localPlayer = Players.LocalPlayer

local root: Frame? = nil
local body: Frame? = nil
local offerZone: Frame? = nil -- the "Your offer" column; the drag drop-zone
local lastStatus: string? = nil

-- ── Theme helpers ──────────────────────────────────────────────────────────────

local function theme(): any
	return UiConfig.get().Theme or {}
end

local function corner(inst: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function label(props: { [string]: any }): TextLabel
	local t = theme()
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = props.color or t.Text or Color3.fromRGB(235, 238, 245)
	l.Font = props.font or t.Font or Enum.Font.GothamMedium
	l.TextSize = props.size or 13
	l.TextXAlignment = props.align or Enum.TextXAlignment.Left
	l.Text = props.text or ""
	l.Size = props.size2 or UDim2.new(1, 0, 0, 20)
	if props.pos then
		l.Position = props.pos
	end
	l.TextTruncate = Enum.TextTruncate.AtEnd
	return l
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

-- ── Inventory lookups (for staging qty from local attributes) ────────────────

local function slotHolding(itemId: string): number?
	local maxN = math.floor(tonumber(localPlayer:GetAttribute(InventoryTypes.MAX_SLOTS_ATTR)) or 0)
	for n = 1, maxN do
		if localPlayer:GetAttribute(InventoryTypes.invSlotAttr(n)) == itemId then
			return n
		end
	end
	return nil
end

-- ── GUI scaffold ────────────────────────────────────────────────────────────

local function ensureGui(): Frame?
	if root and root.Parent then
		return root
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local t = theme()

	local gui = Instance.new("ScreenGui")
	gui.Name = "SurvivorCoreTrade"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90 -- above the menu + toasts
	gui.Enabled = true

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -20, 0.5, 0) -- right side, leaving the centred menu reachable
	panel.Size = UDim2.fromOffset(380, 400)
	panel.BackgroundColor3 = t.PanelColor or Color3.fromRGB(20, 23, 30)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Active = true -- sink input
	panel.Visible = false
	corner(panel, tonumber(t.CornerRadius) or 10)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = panel

	local head = label({
		text = "Trade",
		font = t.FontBold or Enum.Font.GothamBold,
		size = 16,
		color = t.Accent or Color3.fromRGB(204, 166, 102),
		size2 = UDim2.new(1, 0, 0, 22),
	})
	head.Name = "Head"
	head.Parent = panel

	local content = Instance.new("Frame")
	content.Name = "Body"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(0, 28)
	content.Size = UDim2.new(1, 0, 1, -28)
	content.Parent = panel

	panel.Parent = gui
	gui.Parent = playerGui
	root = panel
	body = content
	return panel
end

local function clearBody()
	if not body then
		return
	end
	for _, c in body:GetChildren() do
		c:Destroy()
	end
	offerZone = nil
end

-- ── Item rows ─────────────────────────────────────────────────────────────────

-- One offer row. `mineControls` adds −/+/✕ (for the local player's editable side).
local function offerRow(entry: any, mineControls: boolean): Frame
	local t = theme()
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 28)
	row.BackgroundColor3 = t.SlotColor or Color3.fromRGB(30, 34, 44)
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	corner(row, 6)

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.fromOffset(20, 20)
	icon.Position = UDim2.fromOffset(4, 4)
	icon.BackgroundTransparency = 1
	icon.Image = SlotGrid.resolveItemIcon(entry.itemId)
	icon.Parent = row

	local def = ItemData.get(entry.itemId)
	local name = (def and def.name) or entry.itemId
	local nameLabel = label({
		text = name,
		size2 = UDim2.new(1, if mineControls then -140 else -70, 1, 0),
		pos = UDim2.fromOffset(30, 0),
	})
	nameLabel.Parent = row

	local qtyLabel = label({
		text = `×{entry.qty}`,
		align = Enum.TextXAlignment.Right,
		color = t.TextSecondary or Color3.fromRGB(200, 205, 215),
		size2 = UDim2.fromOffset(40, 28),
		pos = UDim2.new(1, if mineControls then -108 else -44, 0, 0),
	})
	qtyLabel.Parent = row

	if mineControls then
		local minus = button("−", t.SlotColor or Color3.fromRGB(48, 54, 68))
		minus.Size = UDim2.fromOffset(24, 20)
		minus.Position = UDim2.new(1, -66, 0.5, -10)
		minus.Parent = row
		minus.MouseButton1Click:Connect(function()
			local slot = slotHolding(entry.itemId)
			if entry.qty <= 1 or not slot then
				Remotes.event("TradeUnstage"):FireServer(entry.itemId)
			else
				Remotes.event("TradeStage"):FireServer(slot, entry.qty - 1)
			end
		end)

		local plus = button("+", t.SlotColor or Color3.fromRGB(48, 54, 68))
		plus.Size = UDim2.fromOffset(24, 20)
		plus.Position = UDim2.new(1, -38, 0.5, -10)
		plus.Parent = row
		plus.MouseButton1Click:Connect(function()
			local slot = slotHolding(entry.itemId)
			if slot then
				Remotes.event("TradeStage"):FireServer(slot, entry.qty + 1)
			end
		end)

		local remove = button("✕", Color3.fromRGB(120, 60, 60))
		remove.Size = UDim2.fromOffset(20, 20)
		remove.Position = UDim2.new(1, -12, 0.5, -10)
		remove.AnchorPoint = Vector2.new(1, 0.5)
		remove.Parent = row
		remove.MouseButton1Click:Connect(function()
			Remotes.event("TradeUnstage"):FireServer(entry.itemId)
		end)
	end

	return row
end

-- A scrolling column of offer rows.
local function offerColumn(title: string, entries: { any }, mineControls: boolean, confirmed: boolean): Frame
	local t = theme()
	local col = Instance.new("Frame")
	col.BackgroundTransparency = 1

	local heading = label({
		text = title,
		font = t.FontBold or Enum.Font.GothamBold,
		size = 13,
		color = if confirmed
			then (t.Ok or Color3.fromRGB(120, 200, 120))
			else (t.TextSecondary or Color3.fromRGB(200, 205, 215)),
		size2 = UDim2.new(1, 0, 0, 18),
	})
	heading.Parent = col

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(0, 22)
	list.Size = UDim2.new(1, 0, 1, -22)
	list.BackgroundColor3 = t.PanelColor or Color3.fromRGB(20, 23, 30)
	list.BackgroundTransparency = 0.5
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Active = true
	corner(list, 6)
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 4)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	local lp = Instance.new("UIPadding")
	lp.PaddingTop = UDim.new(0, 4)
	lp.PaddingBottom = UDim.new(0, 4)
	lp.PaddingLeft = UDim.new(0, 4)
	lp.PaddingRight = UDim.new(0, 4)
	lp.Parent = list

	if #entries == 0 then
		local hint = label({
			text = if mineControls then "Drag items here" else "Nothing yet",
			color = t.TextSecondary or Color3.fromRGB(150, 160, 180),
			size = 12,
			align = Enum.TextXAlignment.Center,
			size2 = UDim2.new(1, 0, 0, 24),
		})
		hint.Parent = list
	else
		for i, entry in entries do
			local r = offerRow(entry, mineControls)
			r.LayoutOrder = i
			r.Parent = list
		end
	end

	list.Parent = col
	return col
end

-- ── State views ────────────────────────────────────────────────────────────────

local function buildInvite(state: any)
	local t = theme()
	local msg = label({
		text = `{state.partner} wants to trade with you.`,
		size2 = UDim2.new(1, 0, 0, 40),
		size = 14,
	})
	msg.TextWrapped = true
	msg.Parent = body

	local accept = button("Accept", t.Accent or Color3.fromRGB(120, 170, 90))
	accept.Size = UDim2.new(0.5, -6, 0, 34)
	accept.Position = UDim2.fromOffset(0, 56)
	accept.Parent = body
	accept.MouseButton1Click:Connect(function()
		Remotes.event("TradeRespond"):FireServer(true)
	end)

	local decline = button("Decline", Color3.fromRGB(90, 60, 60))
	decline.Size = UDim2.new(0.5, -6, 0, 34)
	decline.Position = UDim2.new(0.5, 6, 0, 56)
	decline.Parent = body
	decline.MouseButton1Click:Connect(function()
		Remotes.event("TradeRespond"):FireServer(false)
	end)
end

local function buildWaiting(state: any)
	local msg = label({
		text = `Waiting for {state.partner} to accept…`,
		size2 = UDim2.new(1, 0, 0, 40),
		size = 14,
	})
	msg.TextWrapped = true
	msg.Parent = body

	local cancel = button("Cancel", Color3.fromRGB(90, 60, 60))
	cancel.Size = UDim2.new(1, 0, 0, 34)
	cancel.Position = UDim2.fromOffset(0, 56)
	cancel.Parent = body
	cancel.MouseButton1Click:Connect(function()
		Remotes.event("TradeCancel"):FireServer()
	end)
end

local function buildOpen(state: any)
	local t = theme()

	local mineCol = offerColumn("You offer", state.mine or {}, true, state.myConfirm == true)
	mineCol.Position = UDim2.fromOffset(0, 0)
	mineCol.Size = UDim2.new(0.5, -6, 1, -84)
	mineCol.Parent = body
	offerZone = mineCol

	local theirsTitle = if state.theirConfirm then `{state.partner} ✓` else `{state.partner} offers`
	local theirsCol = offerColumn(theirsTitle, state.theirs or {}, false, state.theirConfirm == true)
	theirsCol.Position = UDim2.new(0.5, 6, 0, 0)
	theirsCol.Size = UDim2.new(0.5, -6, 1, -84)
	theirsCol.Parent = body

	-- Footer: status line + Confirm + Cancel.
	local statusLabel = label({
		text = if state.myConfirm
			then "You confirmed — waiting for your partner…"
			else "Stage items, then Confirm. Both must confirm.",
		color = t.TextSecondary or Color3.fromRGB(200, 205, 215),
		size = 12,
		size2 = UDim2.new(1, 0, 0, 18),
		pos = UDim2.new(0, 0, 1, -76),
	})
	statusLabel.Parent = body

	local confirm = button(
		if state.myConfirm then "✓ Confirmed" else "Confirm",
		if state.myConfirm
			then (t.SlotColor or Color3.fromRGB(60, 66, 80))
			else (t.Accent or Color3.fromRGB(120, 170, 90))
	)
	confirm.Size = UDim2.new(0.5, -6, 0, 34)
	confirm.Position = UDim2.new(0, 0, 1, -34)
	confirm.Parent = body
	confirm.MouseButton1Click:Connect(function()
		if not state.myConfirm then
			Remotes.event("TradeConfirm"):FireServer()
		end
	end)

	local cancel = button("Cancel", Color3.fromRGB(90, 60, 60))
	cancel.Size = UDim2.new(0.5, -6, 0, 34)
	cancel.Position = UDim2.new(0.5, 6, 1, -34)
	cancel.Parent = body
	cancel.MouseButton1Click:Connect(function()
		Remotes.event("TradeCancel"):FireServer()
	end)
end

-- ── Render ─────────────────────────────────────────────────────────────────────

local function render(state: any)
	local panel = ensureGui()
	if not panel then
		return
	end

	local status = state and state.status
	if not status or status == "cancelled" or status == "done" then
		panel.Visible = false
		clearBody()
		lastStatus = status
		return
	end

	panel.Visible = true
	clearBody()
	if status == "invite" then
		buildInvite(state)
	elseif status == "waiting" then
		buildWaiting(state)
	elseif status == "open" then
		buildOpen(state)
		-- Pop the inventory menu open on entering a trade so items are draggable.
		if lastStatus ~= "open" then
			pcall(function()
				PanelManager.open("inventory")
			end)
		end
	end
	lastStatus = status
end

function TradeUi.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	-- Drag-to-stage: dropping an inventory slot onto the "Your offer" column stages that item.
	-- Registered once; hit-tests the live offer zone. Stages the whole held amount (clamped by the
	-- server); the row steppers then trim it.
	DragDrop.addTarget({
		hitTest = function(pos)
			return root ~= nil and root.Visible and offerZone ~= nil and DragDrop.hitTestGui(offerZone, pos)
		end,
		onDrop = function(payload, _pos)
			if payload and payload.kind == "invSlot" and offerZone then
				Remotes.event("TradeStage"):FireServer(payload.slot, 9999) -- server clamps to held
			end
		end,
	})

	Remotes.event("TradeState").OnClientEvent:Connect(function(state)
		render(state)
	end)
end

return TradeUi
