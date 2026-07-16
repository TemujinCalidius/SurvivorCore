--!nonstrict
--[[
	SpawnHelpers — the "Add to World" branch logic, moved verbatim out of the plugin main. Drops a
	tagged, def-linked instance in front of the camera and selects it — the no-code bridge between
	an editor entry and the world:
	  Resources → a Part tagged "Gatherable" with Resource = id.
	  Mobs      → a placeholder rig Model tagged "Mob" with MobType = id.
	  Quests    → a quest-giver post tagged "QuestGiver" with Quest = id.
	  Weapons   → a starter Tool (Handle + ToolType/WeaponKind) to model the equipped look on.
]]

local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local SpawnHelpers = {}

local function spawnPosition(): Vector3
	local cam = Workspace.CurrentCamera
	return if cam then cam.CFrame.Position + cam.CFrame.LookVector * 16 else Vector3.new(0, 5, 0)
end

-- A minimal placeholder mob rig (Model + HumanoidRootPart + Humanoid + head), tagged "Mob" with the
-- MobType set — exactly what the engine adopts at play. The creator swaps in their own rig later.
local function buildMobRig(id: string): Model
	local model = Instance.new("Model")
	model.Name = id
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 3, 1)
	rootPart.Color = Color3.fromRGB(150, 60, 60)
	rootPart.Anchored = false
	rootPart.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Color = rootPart.Color
	head.CanCollide = false
	head.Massless = true
	head.CFrame = rootPart.CFrame * CFrame.new(0, 2, 0)
	head.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = head
	weld.Parent = rootPart
	local hum = Instance.new("Humanoid")
	hum.Parent = model
	model.PrimaryPart = rootPart
	return model
end

function SpawnHelpers.spawn(ContentAdmin: any, catKey: string, id: string): Instance
	if catKey == "Mobs" then
		local model = buildMobRig(id)
		model:SetAttribute("MobType", id)
		model:PivotTo(CFrame.new(spawnPosition()))
		CollectionService:AddTag(model, "Mob")
		model.Parent = Workspace
		Selection:Set({ model })
		return model
	end
	if catKey == "Quests" then
		-- Drop a quest-giver post: tag + Quest attribute is exactly what the engine reads. The
		-- creator swaps in their own NPC/notice-board model later (tag it and set Quest).
		local post = Instance.new("Part")
		post.Name = id .. "_giver"
		post.Size = Vector3.new(1, 5, 1)
		post.Anchored = true
		post.Color = Color3.fromRGB(120, 170, 255)
		post.Material = Enum.Material.Wood
		post.Position = spawnPosition()
		post:SetAttribute("Quest", id)
		CollectionService:AddTag(post, "QuestGiver")
		post.Parent = Workspace
		Selection:Set({ post })
		return post
	end
	if catKey == "Weapons" then
		-- Drop a starter Tool you can model the look on. It carries the weapon's ToolType /
		-- WeaponKind so it's recognisable; move it under ReplicatedStorage.SurvivorCoreContent.Tools
		-- (named by this id) to make it the equipped look the hotbar clones.
		local node = ContentAdmin.getNode("Weapons", id)
		local tool = Instance.new("Tool")
		tool.Name = id
		tool.RequiresHandle = true
		tool.CanBeDropped = false
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.5, 3, 0.5)
		handle.Color = Color3.fromRGB(120, 90, 60)
		handle.Anchored = true
		handle.Position = spawnPosition()
		handle.Parent = tool
		for _, attr in { "toolType", "weaponKind" } do
			local v = node and node:GetAttribute(attr)
			if typeof(v) == "string" and v ~= "" then
				tool:SetAttribute(attr == "toolType" and "ToolType" or "WeaponKind", v)
			end
		end
		tool.Parent = Workspace
		Selection:Set({ tool })
		return tool
	end
	local part = Instance.new("Part")
	part.Name = id
	part.Size = Vector3.new(4, 4, 4)
	part.Anchored = true
	part.Position = spawnPosition()
	part:SetAttribute("Resource", id)
	CollectionService:AddTag(part, "Gatherable")
	part.Parent = Workspace
	Selection:Set({ part })
	return part
end

return SpawnHelpers
