--!nonstrict
--[[
	SurvivorCore HUD loader. Ships into StarterPlayerScripts (mounted by the demo,
	cloned by SurvivorCore.start()/installHud() for drop-in consumers). It just boots
	the client HUD; all logic lives in the engine module so it stays versioned.
	Editing or restyling the HUD is done on the `SurvivalHud` ScreenGui in StarterGui —
	never here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SurvivorCore = require(ReplicatedStorage:WaitForChild("SurvivorCore"))
SurvivorCore.startClient()
