--!nonstrict
--[[
	DEMO ONLY — assigns the demo's generated survival-stat icons to the HUD.

	The engine ships ZERO asset ids (content-free); a real game does this for its own art.
	Setting a bar/counter's `Icon` attribute makes the HUD binder render it (the binder
	re-renders when `Icon` changes, so timing doesn't matter). These are flat, game-agnostic
	icons generated for the demo via 3D AI Studio (Gemini 3 Pro).
]]

local Players = game:GetService("Players")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local ICONS: { [string]: string } = {
	Health = "rbxassetid://88514622686548",
	Energy = "rbxassetid://129856164091801",
	Hunger = "rbxassetid://138699077112926",
	Thirst = "rbxassetid://124374881225649",
	Fatigue = "rbxassetid://102789813187589",
	Blood = "rbxassetid://139788071928396",
	Poison = "rbxassetid://86406240258610",
	Credits = "rbxassetid://137051934393677",
}

local function apply(hud: Instance)
	for _, descendant in hud:GetDescendants() do
		local key = descendant:GetAttribute("Stat") or descendant:GetAttribute("Counter")
		if typeof(key) == "string" and ICONS[key] and ICONS[key] ~= "" then
			descendant:SetAttribute("Icon", ICONS[key])
		end
	end
end

local hud = playerGui:WaitForChild("SurvivalHud", 10)
if hud then
	apply(hud)
end
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "SurvivalHud" then
		task.wait(0.2)
		apply(child)
	end
end)
