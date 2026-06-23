--!nonstrict
--[[
	DragDrop — a generic drag-and-drop primitive for the UI. CLIENT-ONLY.

	Ported from The Counter Earth's inventory drag logic, generalised so it isn't tied to the
	inventory. A press that moves past a threshold becomes a drag: a ghost follows the cursor in
	a top-most IgnoreGuiInset overlay (so it tracks exactly and floats above every panel), and on
	release the first registered target whose rectangle contains the cursor receives the drop.

	Targets hit-test by AbsolutePosition/AbsoluteSize, which works ACROSS ScreenGuis — that's how
	an item dragged from the menu drops onto the hotbar (a separate ScreenGui).

		DragDrop.beginDrag({ icon = "rbxassetid://…", label = "AXE", data = {...} })  -- on press
		DragDrop.addTarget({ hitTest = function(pos) … end, onDrop = function(payload, pos) … end })
		if DragDrop.didDrag() then return end  -- in a slot's Activated, to ignore the click

	Booted by SurvivorCore.startClient() (via the binders that require it). Tuning: "UI" config.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

assert(RunService:IsClient(), "SurvivorCore.DragDrop is client-only")

local UiConfig = require(script.Parent.Parent.shared.UiConfig)

local DragDrop = {}

local GHOST_SIZE = 56

local localPlayer = Players.LocalPlayer
local started = false

local overlay: ScreenGui? = nil
local targets: { any } = {}

local armed = false
local dragging = false
local dragStart = Vector2.zero
local payload: any = nil
local ghost: Frame? = nil
local dragEndedThisFrame = false

local function isClickOrTap(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function ensureOverlay(): ScreenGui
	if overlay then
		return overlay
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SurvivorCoreDragOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = UiConfig.get().DisplayOrder.DragGhost
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	overlay = gui
	return gui
end

local function makeGhost(pos: Vector2): Frame
	local theme = UiConfig.get().Theme
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(GHOST_SIZE, GHOST_SIZE)
	frame.Position = UDim2.fromOffset(pos.X - GHOST_SIZE / 2, pos.Y - GHOST_SIZE / 2)
	frame.BackgroundColor3 = theme.SlotColor
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.ZIndex = 100

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = theme.Accent
	stroke.Thickness = 2
	stroke.Parent = frame

	if typeof(payload.icon) == "string" and payload.icon ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(0.8, 0.8)
		img.Position = UDim2.fromScale(0.1, 0.1)
		img.BackgroundTransparency = 1
		img.Image = payload.icon
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = 101
		img.Parent = frame
	else
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = tostring(payload.label or "?")
		label.TextColor3 = theme.TextSecondary
		label.Font = theme.FontBold
		label.TextSize = 12
		label.ZIndex = 101
		label.Parent = frame
	end

	frame.Parent = ensureOverlay()
	return frame
end

local function cleanup()
	armed = false
	dragging = false
	payload = nil
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
end

-- True if a GuiObject is on screen and the point is inside its rectangle. Cross-ScreenGui safe.
function DragDrop.hitTestGui(gui: GuiObject?, pos: Vector2): boolean
	if not gui or not gui.Visible then
		return false
	end
	local ap, as = gui.AbsolutePosition, gui.AbsoluteSize
	if as.X <= 0 or as.Y <= 0 then
		return false
	end
	return pos.X >= ap.X and pos.X <= ap.X + as.X and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
end

-- Register a drop target. Targets are tried in registration order; the first whose hitTest
-- returns true gets the drop. (Register more specific targets — slots, hotbar — before any
-- catch-all.)
function DragDrop.addTarget(target: any)
	table.insert(targets, target)
end

-- Begin a potential drag. The ghost is not shown until the cursor passes the drag threshold,
-- so a plain click never spawns a ghost. `data` (any field) is handed to the drop target.
function DragDrop.beginDrag(spec: any)
	payload = spec
	armed = true
	dragging = false
	dragStart = UserInputService:GetMouseLocation()
end

-- True for the frame in which a drag just ended — call it at the top of a slot's Activated
-- handler so the drag's mouse-up isn't also treated as a click.
function DragDrop.didDrag(): boolean
	return dragEndedThisFrame
end

function DragDrop.isDragging(): boolean
	return dragging
end

function DragDrop.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	local threshold = tonumber(UiConfig.get().DragThreshold) or 8

	-- Promote an armed press to a real drag and track the ghost from a per-frame poll of the
	-- cursor — NOT UserInputService.InputChanged. The inventory grid is a ScrollingFrame, which
	-- swallows held-mouse MouseMovement events (so an InputChanged-based threshold never trips);
	-- polling GetMouseLocation each frame is immune to that and serves touch identically.
	RunService.RenderStepped:Connect(function()
		if not armed then
			return
		end
		local pos = UserInputService:GetMouseLocation()
		if not dragging and (pos - dragStart).Magnitude > threshold then
			dragging = true
			ghost = makeGhost(pos)
		end
		if dragging and ghost then
			ghost.Position = UDim2.fromOffset(pos.X - GHOST_SIZE / 2, pos.Y - GHOST_SIZE / 2)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not armed or not isClickOrTap(input) then
			return
		end
		local wasDragging = dragging
		local dropped = payload
		-- GetMouseLocation() is in true-screen pixels, but our menu/hotbar ScreenGuis respect the
		-- GUI inset, so their slots' AbsolutePosition sits ~36px below it. Subtract the inset so the
		-- drop hit-test lines up with where the slots actually are. (The ghost stays raw — its
		-- overlay is IgnoreGuiInset, so it keeps tracking the cursor exactly.)
		local pos = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		cleanup()
		if wasDragging then
			dragEndedThisFrame = true
			task.defer(function()
				dragEndedThisFrame = false
			end)
			for _, target in targets do
				if target.hitTest(pos) then
					target.onDrop(dropped, pos)
					break
				end
			end
		end
	end)
end

return DragDrop
