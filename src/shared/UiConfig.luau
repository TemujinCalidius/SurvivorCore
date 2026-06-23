--!nonstrict
--[[
	UiConfig — tuning for the client UI layer (the tabbed menu, the hotbar, drag-drop).
	SHARED (defined on both sides so `Config.override("UI", …)` works pre-boot; only the
	client reads it). Defines the "UI" Config section.

	IMPORTANT: this theme styles only the ENGINE-BUILT primitives — the drag ghost, the
	zero-setup fallback UI, and the slot-selection highlight. The authored `SurvivalMenu` /
	`SurvivalHotbar` ScreenGui templates carry their own colours/fonts (restyle them in
	Studio); the binders never overwrite template styling from this config. The neutral
	palette here matches the shipped HUD template so the fallback looks consistent.

	Read the merged section with UiConfig.get().
]]

local Config = require(script.Parent.Parent.foundation.Config)

local UiConfig = {}

UiConfig.SECTION = "UI"

UiConfig.DEFAULTS = {
	-- Keybinds are KeyCode NAMES (resolved via Enum.KeyCode[name]); override with a string.
	Keybinds = {
		Menu = "Tab", -- toggles the menu (defaults to the Inventory tab)
		Character = "C",
		Codex = "K",
		Achievements = "J",
		Quests = "L",
	},

	-- Roblox's CoreGui owns some keys — notably Tab opens the built-in player roster, which
	-- swallows the keypress before any game script sees it. When the Menu keybind collides with
	-- such a key, the engine disables that core element so the key reaches the menu (the same way
	-- it already hides the default health bar + backpack). Set false to keep Roblox's stock
	-- player list — appropriate if you rebind Menu off Tab.
	ReclaimCoreKeys = true,

	-- The HUD lives in the top-left, where Roblox's chat also sits. By default the client moves
	-- the chat window (modern TextChatService) to the bottom-left so the two don't overlap.
	-- `Horizontal`/`Vertical` are Enum.HorizontalAlignment / Enum.VerticalAlignment names.
	-- Set `Reposition = false` to leave the chat wherever the player/game placed it.
	Chat = {
		Reposition = true,
		Horizontal = "Left",
		Vertical = "Bottom",
	},

	-- Palette mirrors assets/hud/SurvivalHud.model.json so engine-built UI is on-brand.
	Theme = {
		PanelColor = Color3.fromRGB(20, 23, 30),
		PanelTransparency = 0.25,
		SlotColor = Color3.fromRGB(28, 32, 42),
		CornerRadius = 10,
		StrokeColor = Color3.fromRGB(210, 220, 245),
		StrokeTransparency = 0.85,
		Text = Color3.fromRGB(245, 245, 245),
		TextSecondary = Color3.fromRGB(210, 220, 245),
		Accent = Color3.fromRGB(204, 166, 102), -- selection / active highlight
		Bad = Color3.fromRGB(200, 50, 50), -- over-weight / danger
		Ok = Color3.fromRGB(80, 195, 110),
		Font = Enum.Font.GothamMedium,
		FontBold = Enum.Font.GothamBold,
	},

	Inventory = {
		SlotSize = 64,
		SlotPadding = 6,
		Columns = 6,
	},

	Hotbar = {
		SlotSize = 58,
		SlotPadding = 6,
	},

	-- Cursor must move this many pixels before a press becomes a drag (vs a click). TCE value.
	DragThreshold = 8,

	-- ScreenGui layering. The HUD ships at DisplayOrder 2 and the vignette at 1, so the menu
	-- sits above both and the drag ghost above everything.
	DisplayOrder = {
		Menu = 5,
		Hotbar = 3,
		ClickOutside = 4,
		DragGhost = 100,
	},
}

-- Define the section once per Luau VM.
Config.defineSection(UiConfig.SECTION, UiConfig.DEFAULTS)

-- The merged (defaults + overrides) UI config table.
function UiConfig.get(): any
	return Config.get(UiConfig.SECTION) or UiConfig.DEFAULTS
end

return UiConfig
