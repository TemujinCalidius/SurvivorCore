--[[
	QuestGiver — the no-code quest board/NPC component.

	A creator builds ANY part/model (a signpost, a campfire NPC, a notice board), tags it
	"QuestGiver" (CollectionService), and sets `Quest = "<quest id>"`. The engine attaches a
	ProximityPrompt that routes through the server Quests runtime:
	  • quest not started  → hold E to ACCEPT it,
	  • objectives met on a turn-in quest → hold E to TURN IT IN and claim the reward,
	  • otherwise the prompt is a no-op (the runtime fires `quest:blocked` with a reason).

	The admin plugin's Quests editor drops one of these via "+ Quest giver". Placement is the
	creator's content; the engine ships no NPCs.
]]

local Components = require(script.Parent)
local Registries = require(script.Parent.Parent.registries)
local Quests = require(script.Parent.Parent.systems.Quests)
local QuestData = require(script.Parent.Parent.shared.QuestData)

return Components.define({
	name = "QuestGiver",
	tag = "QuestGiver",
	attributes = {
		Quest = "", -- the quest id this giver offers / accepts turn-ins for
	},
	onSetup = function(instance, values)
		local questId = tostring(values.Quest or "")
		if questId == "" then
			warn(`[QuestGiver] '{instance:GetFullName()}' has no Quest attribute`)
			return
		end

		local host = if instance:IsA("BasePart") then instance else instance:FindFirstChildWhichIsA("BasePart")
		if not host then
			warn(`[QuestGiver] '{instance:GetFullName()}' has no BasePart to host a prompt`)
			return
		end

		-- Display name from the registered def (normalized), falling back to the id.
		local raw = Registries.Quests.get(questId)
		local quest = raw and QuestData.normalize(raw)
		local questName = quest and quest.name or questId

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Quest"
		prompt.ObjectText = questName
		prompt.HoldDuration = 0.4
		prompt.RequiresLineOfSight = false
		prompt.Parent = host

		prompt.Triggered:Connect(function(player)
			-- Turn-in first (objectives met), else accept; the runtime re-validates everything.
			local ok = Quests.complete(player, questId)
			if not ok then
				Quests.accept(player, questId)
			end
		end)
	end,
})
