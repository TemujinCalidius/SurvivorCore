--!nonstrict
--[[
	PanelManager — the tabbed-menu framework. CLIENT-ONLY.

	SurvivorCore ships ONE menu ScreenGui ("SurvivalMenu") whose tabs (Inventory, Character,
	Codex, …) are authored as marked frames inside it — the same template+binder model as the
	HUD. This manager discovers those tabs by attribute, owns the open/close + tab-switch state,
	the menu keybind, the click-outside overlay, and the open/close animation. It drives state
	only; the template owns all styling.

	Template attribute conventions (set in Studio; the binder never restyles):
	  • The animated panel frame: a child named "Root" (falls back to the first GuiObject child).
	  • A tab button:  GuiButton with `InventoryTab` = <id> (e.g. "inventory"). Optional `Selected`
	    child shown while that tab is active.
	  • A tab's content: GuiObject with `TabContent` = <id> (matched to the button by id).
	  • A close button (optional): GuiButton with `MenuClose` = true.
	  • For code-registered tabs: containers marked `TabBar` = true and `TabContentHost` = true.

	Public API (re-exported on SurvivorCore.UI):
	  • registerPanel({ id, title, icon?, order?, build? }) — add a tab from code; `build(frame)`
	    fills its (empty) content once. Safe to call before start() (buffered).
	  • open(id?) / close() / toggle(id?) — id defaults to the current/Inventory tab.

	Booted by SurvivorCore.startClient(). Tuning: the "UI" Config section.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

assert(RunService:IsClient(), "SurvivorCore.PanelManager is client-only — boot it via SurvivorCore.startClient()")

local UiConfig = require(script.Parent.Parent.shared.UiConfig)

local PanelManager = {}

local MENU_NAME = "SurvivalMenu"
local DEFAULT_TAB = "inventory"
local OPEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local started = false
local localPlayer = Players.LocalPlayer
local playerGui: Instance? = nil

local menuGui: ScreenGui? = nil
local menuRoot: GuiObject? = nil
local tabs: { [string]: GuiButton } = {} -- id -> tab button
local contents: { [string]: GuiObject } = {} -- id -> content frame
local activeTab: string? = nil
local menuOpen = false

-- Code-registered panels buffered until the menu is bound.
local pendingPanels: { any } = {}
local registered: { [string]: boolean } = {}

local mouseOverrideConn: RBXScriptConnection? = nil
local clickOutsideOverlay: ScreenGui? = nil

-- ── Mouse unlock (fights first-person re-lock, like TCE) ───────────────────

local function startMouseOverride()
	if mouseOverrideConn then
		return
	end
	mouseOverrideConn = RunService.RenderStepped:Connect(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
end

local function stopMouseOverride()
	if mouseOverrideConn then
		mouseOverrideConn:Disconnect()
		mouseOverrideConn = nil
	end
	if localPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
		UserInputService.MouseIconEnabled = false
	end
end

-- ── Click-outside overlay ──────────────────────────────────────────────────

local function showClickOutside()
	if clickOutsideOverlay or not playerGui then
		return
	end
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "SurvivorCorePanelClickOutside"
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = UiConfig.get().DisplayOrder.ClickOutside
	overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local btn = Instance.new("TextButton")
	btn.Name = "Overlay"
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Parent = overlay
	btn.Activated:Connect(function()
		PanelManager.close()
	end)

	overlay.Parent = playerGui
	clickOutsideOverlay = overlay
end

local function hideClickOutside()
	if clickOutsideOverlay then
		clickOutsideOverlay:Destroy()
		clickOutsideOverlay = nil
	end
end

-- ── Animation (scale + optional CanvasGroup fade), ported from TCE ─────────

local function animateOpen(frame: GuiObject)
	local target = frame.Size
	frame.Size = UDim2.new(target.X.Scale * 0.95, target.X.Offset * 0.95, target.Y.Scale * 0.95, target.Y.Offset * 0.95)
	if frame:IsA("CanvasGroup") then
		frame.GroupTransparency = 1
		TweenService:Create(frame, OPEN_INFO, { Size = target, GroupTransparency = 0 }):Play()
	else
		TweenService:Create(frame, OPEN_INFO, { Size = target }):Play()
	end
end

local function animateClose(frame: GuiObject, callback: () -> ())
	local current = frame.Size
	local small =
		UDim2.new(current.X.Scale * 0.95, current.X.Offset * 0.95, current.Y.Scale * 0.95, current.Y.Offset * 0.95)
	local tween
	if frame:IsA("CanvasGroup") then
		tween = TweenService:Create(frame, CLOSE_INFO, { Size = small, GroupTransparency = 1 })
	else
		tween = TweenService:Create(frame, CLOSE_INFO, { Size = small })
	end
	tween.Completed:Once(function()
		frame.Size = current
		callback()
	end)
	tween:Play()
end

-- ── Tab switching ──────────────────────────────────────────────────────────

function PanelManager.showTab(id: string)
	if not contents[id] then
		return
	end
	activeTab = id
	for tabId, content in contents do
		content.Visible = tabId == id
	end
	for tabId, button in tabs do
		local selected = button:FindFirstChild("Selected")
		if selected and selected:IsA("GuiObject") then
			selected.Visible = tabId == id
		end
	end
end

-- ── Open / close / toggle ───────────────────────────────────────────────────

function PanelManager.open(id: string?)
	if not menuGui or not menuRoot then
		return
	end
	local target = id or activeTab or DEFAULT_TAB
	if not contents[target] then
		-- Fall back to any tab so the menu is never blank.
		target = next(contents) :: string
		if not target then
			return
		end
	end
	menuOpen = true
	menuGui.Enabled = true
	PanelManager.showTab(target)
	animateOpen(menuRoot)
	startMouseOverride()
	showClickOutside()
end

function PanelManager.close()
	if not menuOpen or not menuGui or not menuRoot then
		return
	end
	menuOpen = false
	local gui = menuGui
	animateClose(menuRoot, function()
		gui.Enabled = false
	end)
	stopMouseOverride()
	hideClickOutside()
end

function PanelManager.toggle(id: string?)
	if not menuGui then
		return
	end
	if menuOpen then
		if id and activeTab ~= id then
			PanelManager.showTab(id)
		else
			PanelManager.close()
		end
	else
		PanelManager.open(id)
	end
end

function PanelManager.isOpen(): boolean
	return menuOpen
end

-- ── Tab discovery + wiring ───────────────────────────────────────────────────

-- Resize tab buttons so they always fit the TabBar, however many there are (authored +
-- code-registered like Crafting). Each takes an equal share; the 6px offset leaves room for the
-- UIListLayout's padding so the row never overflows the bar.
local function fitTabs()
	local n = 0
	for _ in tabs do
		n += 1
	end
	if n == 0 then
		return
	end
	for _, button in tabs do
		button.Size = UDim2.new(1 / n, -6, 1, 0)
		button.AutomaticSize = Enum.AutomaticSize.None
	end
end

local function wireTabButton(id: string, button: GuiButton)
	tabs[id] = button
	registered[id] = true
	button.Activated:Connect(function()
		PanelManager.showTab(id)
	end)
	fitTabs()
end

local function bindContent(id: string, frame: GuiObject)
	contents[id] = frame
	frame.Visible = false
end

-- Create a tab from code: clone an authored tab button for styling (or build a plain one),
-- add an empty content frame, and let the caller fill it once.
local function realizePanel(spec: any)
	if not menuGui or registered[spec.id] then
		return
	end
	local host = menuGui:FindFirstChild("TabContentHost", true)
		or (menuRoot and menuRoot:FindFirstChild("Content"))
		or menuRoot
	local bar = menuGui:FindFirstChild("TabBar", true)
	if not host then
		return
	end

	-- Content frame.
	local content = Instance.new("Frame")
	content.Name = spec.id
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content:SetAttribute("TabContent", spec.id)
	content.Parent = host
	bindContent(spec.id, content)
	if typeof(spec.build) == "function" then
		task.spawn(spec.build, content)
	end

	-- Tab button: clone an existing one to inherit styling, else build a minimal button.
	if bar then
		local templateButton: GuiButton? = nil
		for _, b in tabs do
			templateButton = b
			break
		end
		local button: GuiButton
		if templateButton then
			button = templateButton:Clone()
			button:SetAttribute("InventoryTab", spec.id)
			local label = button:FindFirstChildWhichIsA("TextLabel") or (button:IsA("TextButton") and button)
			if label and spec.title then
				label.Text = spec.title
			end
		else
			local tb = Instance.new("TextButton")
			tb.Size = UDim2.fromOffset(96, 28)
			tb.Text = spec.title or spec.id
			tb:SetAttribute("InventoryTab", spec.id)
			button = tb
		end
		if spec.order then
			button.LayoutOrder = spec.order
		end
		button.Parent = bar
		wireTabButton(spec.id, button)
	end
end

local function bindMenu(gui: ScreenGui)
	if menuGui == gui then
		return
	end
	menuGui = gui
	menuRoot = (gui:FindFirstChild("Root") or gui:FindFirstChildWhichIsA("GuiObject")) :: any
	gui.Enabled = false

	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") then
			local tabId = d:GetAttribute("InventoryTab")
			local contentId = d:GetAttribute("TabContent")
			if typeof(tabId) == "string" and tabId ~= "" and d:IsA("GuiButton") then
				wireTabButton(tabId, d)
			end
			if typeof(contentId) == "string" and contentId ~= "" then
				bindContent(contentId, d)
			end
			if d:GetAttribute("MenuClose") ~= nil and d:IsA("GuiButton") then
				d.Activated:Connect(function()
					PanelManager.close()
				end)
			end
		end
	end

	-- Default the active tab so the first open isn't blank.
	if contents[DEFAULT_TAB] then
		activeTab = DEFAULT_TAB
	else
		activeTab = next(contents) :: string?
	end

	-- Flush any panels registered before the menu existed.
	local pending = pendingPanels
	pendingPanels = {}
	for _, spec in pending do
		realizePanel(spec)
	end
end

-- ── Public registration (buffered until the menu binds) ────────────────────

function PanelManager.registerPanel(spec: any)
	assert(typeof(spec) == "table" and typeof(spec.id) == "string", "registerPanel: spec.id (string) is required")
	if menuGui then
		realizePanel(spec)
	else
		table.insert(pendingPanels, spec)
	end
end

-- ── Keybinds ────────────────────────────────────────────────────────────────

local function resolveKey(name: any): Enum.KeyCode?
	if typeof(name) ~= "string" or name == "" then
		return nil
	end
	local ok, key = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok and typeof(key) == "EnumItem" then
		return key :: Enum.KeyCode
	end
	return nil
end

-- Some keys are owned by Roblox CoreGui (Tab opens the player roster) and never reach a game
-- listener — the press arrives with gameProcessed == true. ContextActionService can't out-rank
-- CoreGui, so the only reliable fix is to disable the colliding core element. We do that only
-- when the configured Menu key actually collides (today just Tab), and only if ReclaimCoreKeys
-- is on. Same pcall retry loop the Hotbar/HUD use to survive late CoreGui init + respawns.
local CORE_KEY_COLLISIONS: { [Enum.KeyCode]: Enum.CoreGuiType } = {
	[Enum.KeyCode.Tab] = Enum.CoreGuiType.PlayerList,
}

local function reclaimCoreKey(menuKey: Enum.KeyCode?)
	if not menuKey or not UiConfig.get().ReclaimCoreKeys then
		return
	end
	local coreType = CORE_KEY_COLLISIONS[menuKey]
	if not coreType then
		return
	end
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(coreType, false)
			end)
			if ok then
				break
			end
			task.wait(0.2)
		end
	end)
end

local function wireKeybinds()
	local binds = UiConfig.get().Keybinds or {}
	-- Values are a tab id (string) or `false` (the menu-toggle sentinel, no specific tab).
	local map: { [Enum.KeyCode]: string | boolean } = {}
	local menuKey = resolveKey(binds.Menu)
	if menuKey then
		map[menuKey] = false
		reclaimCoreKey(menuKey) -- free Tab (etc.) from CoreGui so our handler sees it
	end
	for tabName, keyName in
		{ Character = binds.Character, Codex = binds.Codex, Achievements = binds.Achievements, Quests = binds.Quests }
	do
		local key = resolveKey(keyName)
		if key then
			map[key] = string.lower(tabName)
		end
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return -- never toggle the menu while the user is typing
		end
		local entry = map[input.KeyCode]
		if entry == false then
			PanelManager.toggle(nil) -- the menu-toggle key (no specific tab)
		elseif typeof(entry) == "string" then
			PanelManager.toggle(entry)
		end
	end)
end

-- The engine draws its HUD in the top-left, where Roblox's chat also sits. Move the chat
-- (TextChatService) out from under it — to the bottom-left by default — so they don't overlap.
-- Alignment is config-driven; opt out with Config.override("UI", { Chat = { Reposition = false } }).
local function repositionChat()
	local chat = UiConfig.get().Chat
	if not chat or not chat.Reposition then
		return
	end
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return -- legacy chat has no ChatWindowConfiguration to move
	end
	task.spawn(function()
		local config = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
			or TextChatService:WaitForChild("ChatWindowConfiguration", 5)
		if not config then
			return
		end
		local h = (Enum.HorizontalAlignment :: any)[chat.Horizontal or "Left"]
		local v = (Enum.VerticalAlignment :: any)[chat.Vertical or "Bottom"]
		if typeof(h) == "EnumItem" then
			(config :: any).HorizontalAlignment = h
		end
		if typeof(v) == "EnumItem" then
			(config :: any).VerticalAlignment = v
		end
	end)
end

function PanelManager.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	playerGui = localPlayer:WaitForChild("PlayerGui")
	repositionChat()

	local existing = (playerGui :: Instance):FindFirstChild(MENU_NAME)
	if existing and existing:IsA("ScreenGui") then
		bindMenu(existing)
	end -- Bind the menu whenever it arrives (StarterGui copy on spawn, or the fallback builder).
	(playerGui :: Instance).ChildAdded:Connect(function(child)
		if child.Name == MENU_NAME and child:IsA("ScreenGui") then
			bindMenu(child)
		end
	end)

	wireKeybinds()
end

return PanelManager
