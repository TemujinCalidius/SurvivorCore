--!nonstrict
--[[
	QuestsUi — the Quests tab. CLIENT-ONLY.

	Fills the menu's scaffolded "quests" tab (PanelManager adopts the authored placeholder) with
	the player's quest log, rendered from the replicated quest defs (QuestData) + the QuestLog
	Player attribute the server runtime writes:
	  • Active — name, description, one line + progress bar per objective ("2/3 Reed"),
	  • Ready — objectives met, awaiting turn-in (or inventory room) — accented,
	  • Completed — dimmed history.
	Re-renders whenever QuestLog changes. Themed from the "UI" Config section.
	Booted by SurvivorCore.startClient() (after PanelManager).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "SurvivorCore.QuestsUi is client-only")

local ItemData = require(script.Parent.Parent.shared.ItemData)
local QuestData = require(script.Parent.Parent.shared.QuestData)
local UiConfig = require(script.Parent.Parent.shared.UiConfig)
local PanelManager = require(script.Parent.PanelManager)

local QuestsUi = {}

local started = false
local localPlayer = Players.LocalPlayer

local function itemName(itemId: string): string
	local def = ItemData.get(itemId)
	return (def and def.name) or itemId
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function objectiveText(obj: any, have: number): string
	local target = if obj.target ~= "" then itemName(obj.target) else "any"
	local verb = ({ gather = "Gather", craft = "Craft", kill = "Slay", use = "Use" })[obj.type] or obj.type
	return `{verb} {target} — {math.min(have, obj.count)}/{obj.count}`
end

local function rewardsText(quest: any): string
	if #quest.rewards == 0 then
		return ""
	end
	local parts = {}
	for _, r in quest.rewards do
		table.insert(parts, `{r.count}× {itemName(r.item)}`)
	end
	return "Reward: " .. table.concat(parts, ", ")
end

local function buildQuests(content: Instance)
	local theme = UiConfig.get().Theme

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "QuestList"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Active = true -- sink clicks so the menu's click-outside overlay doesn't close the menu
	scroll.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function addHeader(text: string)
		local h = Instance.new("TextLabel")
		h.BackgroundTransparency = 1
		h.Size = UDim2.new(1, -8, 0, 24)
		h.Font = theme.FontBold or Enum.Font.GothamBold
		h.TextSize = 13
		h.TextXAlignment = Enum.TextXAlignment.Left
		h.TextColor3 = theme.TextSecondary or Color3.fromRGB(200, 205, 215)
		h.Text = text
		h.LayoutOrder = nextOrder()
		h.Parent = scroll
	end

	-- One quest card. `state` = "active" | "ready" | "done"; progress only for active.
	local function addCard(quest: any, state: string, progress: { number }?)
		local objLines = if state == "active" then #quest.objectives else 0
		local rewardLine = if rewardsText(quest) ~= "" then 1 else 0
		local descLine = if quest.description then 1 else 0
		local height = 34 + descLine * 18 + objLines * 22 + rewardLine * 18

		local card = Instance.new("Frame")
		card.Name = "Quest_" .. quest.id
		card.Size = UDim2.new(1, -8, 0, height)
		card.BackgroundColor3 = theme.SlotColor or theme.PanelColor or Color3.fromRGB(30, 34, 44)
		card.BackgroundTransparency = 0.15
		card.BorderSizePixel = 0
		card.LayoutOrder = nextOrder()
		card.Parent = scroll
		corner(card, theme.CornerRadius or 8)

		local dim = if state == "done" then 0.45 else 0

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, -110, 0, 22)
		name.Position = UDim2.fromOffset(12, 7)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Font = theme.FontBold or Enum.Font.GothamBold
		name.TextSize = 15
		name.TextColor3 = theme.Text or Color3.fromRGB(245, 245, 245)
		name.TextTransparency = dim
		name.Text = quest.name
		name.Parent = card

		local badgeText, badgeColor
		if state == "ready" then
			badgeText, badgeColor =
				if quest.turnIn then "TURN IN" else "READY", theme.Accent or Color3.fromRGB(120, 170, 255)
		elseif state == "done" then
			badgeText, badgeColor = "DONE", Color3.fromRGB(110, 190, 130)
		end
		if badgeText then
			local badge = Instance.new("TextLabel")
			badge.BackgroundTransparency = 1
			badge.Size = UDim2.fromOffset(90, 22)
			badge.Position = UDim2.new(1, -98, 0, 7)
			badge.TextXAlignment = Enum.TextXAlignment.Right
			badge.Font = theme.FontBold or Enum.Font.GothamBold
			badge.TextSize = 12
			badge.TextColor3 = badgeColor
			badge.Text = badgeText
			badge.Parent = card
		end

		local y = 29
		if quest.description then
			local desc = Instance.new("TextLabel")
			desc.BackgroundTransparency = 1
			desc.Size = UDim2.new(1, -24, 0, 16)
			desc.Position = UDim2.fromOffset(12, y)
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextTruncate = Enum.TextTruncate.AtEnd
			desc.Font = theme.Font or Enum.Font.Gotham
			desc.TextSize = 12
			desc.TextColor3 = theme.TextSecondary or Color3.fromRGB(200, 205, 215)
			desc.TextTransparency = dim
			desc.Text = quest.description
			desc.Parent = card
			y += 18
		end

		if state == "active" and progress then
			for i, obj in quest.objectives do
				local have = tonumber(progress[i]) or 0
				local line = Instance.new("TextLabel")
				line.BackgroundTransparency = 1
				line.Size = UDim2.new(1, -140, 0, 18)
				line.Position = UDim2.fromOffset(12, y)
				line.TextXAlignment = Enum.TextXAlignment.Left
				line.Font = theme.Font or Enum.Font.Gotham
				line.TextSize = 13
				line.TextColor3 = if have >= obj.count
					then Color3.fromRGB(110, 190, 130)
					else (theme.Text or Color3.fromRGB(245, 245, 245))
				line.Text = objectiveText(obj, have)
				line.Parent = card

				-- Thin progress bar to the right of the line.
				local track = Instance.new("Frame")
				track.Size = UDim2.fromOffset(110, 6)
				track.Position = UDim2.new(1, -122, 0, y + 6)
				track.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
				track.BorderSizePixel = 0
				track.Parent = card
				corner(track, 3)
				local fill = Instance.new("Frame")
				fill.Size = UDim2.fromScale(math.clamp(have / obj.count, 0, 1), 1)
				fill.BackgroundColor3 = if have >= obj.count
					then Color3.fromRGB(110, 190, 130)
					else (theme.Accent or Color3.fromRGB(120, 170, 255))
				fill.BorderSizePixel = 0
				fill.Parent = track
				corner(fill, 3)

				y += 22
			end
		end

		local rt = rewardsText(quest)
		if rt ~= "" then
			local reward = Instance.new("TextLabel")
			reward.BackgroundTransparency = 1
			reward.Size = UDim2.new(1, -24, 0, 16)
			reward.Position = UDim2.fromOffset(12, y)
			reward.TextXAlignment = Enum.TextXAlignment.Left
			reward.Font = theme.Font or Enum.Font.Gotham
			reward.TextSize = 12
			reward.TextColor3 = Color3.fromRGB(240, 190, 80)
			reward.TextTransparency = dim
			reward.Text = rt
			reward.Parent = card
		end
	end

	local function render()
		order = 0
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local quests = QuestData.getAll()
		local log = QuestData.decodeLog(localPlayer)

		local activeList, readyList, doneList = {}, {}, {}
		for _, q in quests do
			if log.active[q.id] then
				table.insert(activeList, q)
			elseif log.ready[q.id] then
				table.insert(readyList, q)
			elseif log.done[q.id] then
				table.insert(doneList, q)
			end
		end

		if #activeList + #readyList + #doneList == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 40)
			empty.Font = theme.Font or Enum.Font.Gotham
			empty.TextSize = 14
			empty.TextColor3 = theme.TextSecondary or Color3.fromRGB(200, 205, 215)
			empty.Text = "No quests yet — explore the world."
			empty.LayoutOrder = 1
			empty.Parent = scroll
			return
		end

		if #readyList > 0 then
			addHeader("READY")
			for _, q in readyList do
				addCard(q, "ready")
			end
		end
		if #activeList > 0 then
			addHeader("ACTIVE")
			for _, q in activeList do
				local entry = log.active[q.id]
				addCard(q, "active", entry and entry.p)
			end
		end
		if #doneList > 0 then
			addHeader("COMPLETED")
			for _, q in doneList do
				addCard(q, "done")
			end
		end
	end

	render()
	localPlayer:GetAttributeChangedSignal(QuestData.LOG_ATTR):Connect(render)
end

function QuestsUi.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	PanelManager.registerPanel({
		id = "quests",
		title = "Quests",
		order = 5,
		build = buildQuests,
	})
end

return QuestsUi
