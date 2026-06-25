--!nonstrict
--[[
	CombatInput — client. The input half of combat (#12). CLIENT-ONLY.

	Routes by the EQUIPPED weapon's `WeaponKind` attribute (stamped on the held Tool by the ToolEquip
	bridge), so it coexists with ToolHarvest — a given item is a harvest tool OR a weapon, never both:
	  • melee → left-click asks the server to swing (CombatSwing); the server picks + validates target.
	  • bow → a TCE-style aiming flow: HOLD right-click to AIM (over-the-shoulder camera + FOV zoom +
	    a crosshair and a charge ring); HOLD left-click to DRAW (the ring fills/greens up); RELEASE to
	    FIRE along the crosshair (camera-centre ray → a world target point). The server simulates the
	    arrow's gravity arc authoritatively and sends back the arc PATH; this only renders the cosmetic
	    arrow flying along that exact curve. Arrows must be in the inventory (the server consumes one).

	Never authoritative — the server re-validates and decides every hit. Booted by startClient().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

assert(RunService:IsClient(), "SurvivorCore.CombatInput is client-only — boot it via SurvivorCore.startClient()")

local Assets = require(script.Parent.Parent.foundation.Assets)
local Remotes = require(script.Parent.Parent.shared.Remotes)

local CombatInput = {}

local started = false
local player = Players.LocalPlayer

-- Aim/draw state (bow only).
local aiming = false
local drawing = false
local drawT0 = 0
local drawTime = 1
local drawTool: Tool? = nil
local savedFov: number? = nil

-- The currently held engine weapon Tool (or nil). A weapon carries a "WeaponKind" attribute.
local function equippedWeapon(): (Tool?, string?)
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not tool or not tool:IsA("Tool") then
		return nil, nil
	end
	local kind = tool:GetAttribute("WeaponKind")
	if typeof(kind) ~= "string" or kind == "" then
		return nil, nil
	end
	return tool, kind
end

local function humanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- ===== Aim reticle UI (crosshair + charge ring) ==============================

local aimGui: ScreenGui? = nil
local function ensureAimGui(): ScreenGui?
	if aimGui and aimGui.Parent then
		return aimGui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatAimGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Enabled = false

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(22, 22)
	ring.BackgroundTransparency = 1
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(255, 200, 100)
	stroke.Transparency = 0.1
	stroke.Parent = ring
	ring.Parent = gui

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(4, 4)
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dot.BorderSizePixel = 0
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	dot.Parent = gui

	gui.Parent = playerGui
	aimGui = gui
	return gui
end

-- Drive the charge ring from the current draw alpha (0..1): grows + recolours yellow→green.
local function setRing(alpha: number?)
	local gui = aimGui
	if not gui then
		return
	end
	local ring = gui:FindFirstChild("Ring") :: Frame
	if not ring then
		return
	end
	local a = math.clamp(alpha or 0, 0, 1)
	local size = 22 + 22 * a
	ring.Size = UDim2.fromOffset(size, size)
	local stroke = ring:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Color3.fromRGB(255, 200, 100):Lerp(Color3.fromRGB(120, 230, 140), a)
	end
end

local function flashNoAmmo()
	local gui = aimGui
	local dot = gui and gui:FindFirstChild("Dot") :: Frame
	if not dot then
		return
	end
	dot.BackgroundColor3 = Color3.fromRGB(235, 90, 90)
	task.delay(0.4, function()
		if dot.Parent then
			dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		end
	end)
end

-- ===== Aim mode (right-click) ================================================

local function enterAim(tool: Tool)
	if aiming then
		return
	end
	aiming = true
	drawTool = tool
	local gui = ensureAimGui()
	if gui then
		gui.Enabled = true
		setRing(0)
	end
	local cam = Workspace.CurrentCamera
	if cam then
		savedFov = cam.FieldOfView
		TweenService
			:Create(
				cam,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad),
				{ FieldOfView = math.max(40, cam.FieldOfView - 12) }
			)
			:Play()
	end
	local hum = humanoid()
	if hum then
		TweenService:Create(hum, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { CameraOffset = Vector3.new(2, 0.5, 0) })
			:Play()
	end
end

local function exitAim()
	if not aiming then
		return
	end
	aiming = false
	drawing = false
	drawTool = nil
	if aimGui then
		aimGui.Enabled = false
	end
	local cam = Workspace.CurrentCamera
	if cam and savedFov then
		TweenService:Create(cam, TweenInfo.new(0.2), { FieldOfView = savedFov }):Play()
	end
	savedFov = nil
	local hum = humanoid()
	if hum then
		TweenService:Create(hum, TweenInfo.new(0.2), { CameraOffset = Vector3.zero }):Play()
	end
end

-- ===== Draw + fire (left-click while aiming) =================================

local function startDraw(tool: Tool)
	if drawing then
		return
	end
	drawing = true
	drawTool = tool
	drawT0 = os.clock()
	drawTime = math.max(0.05, tonumber(tool:GetAttribute("WeaponDrawTime")) or 1)
	Remotes.event("BowDraw"):FireServer()
	setRing(0)
end

-- The world point the crosshair (camera centre) is over — the server fires from the bow toward it.
local function aimTargetPoint(): Vector3
	local cam = Workspace.CurrentCamera
	local vp = cam.ViewportSize
	local ray = cam:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: any }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	return result and result.Position or (ray.Origin + ray.Direction * 500)
end

local function fireBow()
	if not drawing then
		return
	end
	drawing = false
	local tool = equippedWeapon()
	if tool and tool == drawTool then
		local alpha = math.clamp((os.clock() - drawT0) / drawTime, 0, 1)
		Remotes.event("BowRelease"):FireServer(aimTargetPoint(), alpha)
	end
	setRing(0)
end

-- ===== Melee (left-click) ====================================================

local function playSwing(tool: Tool)
	local hum = humanoid()
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local toolType = tostring(tool:GetAttribute("ToolType") or tool.Name)
	local animId = Assets.tryGet("WeaponAnims", toolType)
	if animId == "" then
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

-- ===== Input routing =========================================================

local function primaryDown()
	local tool, kind = equippedWeapon()
	if not tool then
		return
	end
	if kind == "melee" then
		playSwing(tool)
		Remotes.event("CombatSwing"):FireServer()
	elseif kind == "bow" and aiming then
		startDraw(tool)
	end
end

local function primaryUp()
	if drawing then
		fireBow()
	end
end

local function secondaryDown()
	local tool, kind = equippedWeapon()
	if tool and kind == "bow" then
		enterAim(tool)
	end
end

local function secondaryUp()
	if aiming then
		exitAim()
	end
end

-- ===== Cosmetic arrow flying the server's arc ================================

-- Cumulative arc-length sampler over the server-sent path, so the arrow follows the real curve.
local function buildSampler(path: { Vector3 })
	local cum = { 0 }
	for i = 2, #path do
		cum[i] = cum[i - 1] + (path[i] - path[i - 1]).Magnitude
	end
	local total = cum[#path]
	return total,
		function(frac: number): (Vector3, Vector3)
			local target = math.clamp(frac, 0, 1) * total
			for i = 2, #path do
				if cum[i] >= target then
					local seg = cum[i] - cum[i - 1]
					local f = if seg > 1e-4 then (target - cum[i - 1]) / seg else 0
					local p0, p1 = path[i - 1], path[i]
					return p0:Lerp(p1, f), (p1 - p0).Unit
				end
			end
			local n = #path
			return path[n], (path[n] - path[n - 1]).Unit
		end
end

local function showArrowPath(path: { Vector3 })
	if not path or #path < 2 then
		return
	end
	local total, sample = buildSampler(path)
	if total < 0.1 then
		return
	end
	local flight = math.clamp(total / 180, 0.08, 1.2)

	local arrow = Instance.new("Part")
	arrow.Size = Vector3.new(0.14, 0.14, 1.6)
	arrow.Color = Color3.fromRGB(220, 210, 180)
	arrow.Material = Enum.Material.Wood
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	local p0, d0 = sample(0)
	arrow.CFrame = CFrame.lookAt(p0, p0 + d0)
	arrow.Parent = Workspace

	task.spawn(function()
		local t0 = os.clock()
		while arrow.Parent do
			local frac = (os.clock() - t0) / flight
			if frac >= 1 then
				break
			end
			local pos, dir = sample(frac)
			arrow.CFrame = CFrame.lookAt(pos, pos + dir)
			RunService.RenderStepped:Wait()
		end
		if arrow.Parent then
			local pos, dir = sample(1)
			arrow.CFrame = CFrame.lookAt(pos, pos + dir)
			task.delay(1.5, function()
				if arrow.Parent then
					arrow:Destroy()
				end
			end)
		end
	end)
end

function CombatInput.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			primaryDown()
		elseif t == Enum.UserInputType.MouseButton2 then
			secondaryDown()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			primaryUp()
		elseif t == Enum.UserInputType.MouseButton2 then
			secondaryUp()
		end
	end)

	-- Fill the charge ring while drawing.
	RunService.RenderStepped:Connect(function()
		if drawing then
			setRing((os.clock() - drawT0) / drawTime)
		end
	end)

	-- Drop aim state if the character/weapon goes away.
	player.CharacterAdded:Connect(function()
		aiming, drawing, drawTool, savedFov = false, false, nil, nil
		if aimGui then
			aimGui.Enabled = false
		end
	end)

	Remotes.event("CombatResult").OnClientEvent:Connect(function(result)
		if not result then
			return
		end
		if result.source == "bow" then
			if result.reason == "ammo" then
				flashNoAmmo()
			elseif result.path then
				showArrowPath(result.path)
			end
		end
		local key = if result.hit then "hit" else "miss"
		local soundId = Assets.tryGet("CombatSounds", key)
		if soundId ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = soundId
			sound.Parent = SoundService
			sound:Play()
			sound.Ended:Once(function()
				sound:Destroy()
			end)
		end
	end)
end

return CombatInput
