--!nonstrict
--[[
	Remotes — the engine's RemoteEvent plumbing. SHARED (server + client).

	SurvivorCore is attribute-driven and has needed no RemoteEvents until now; the first
	is sprint intent (client → server). This keeps that contract in one place: the SERVER
	creates each named RemoteEvent under a `SurvivorCoreRemotes` folder in ReplicatedStorage;
	the CLIENT waits for it. Works for every distribution (Rojo source, demo, drop-in `.rbxm`)
	because the folder + events are created at runtime, not baked into the model.

		-- server: local remote = Remotes.event("SprintIntent"); remote.OnServerEvent:Connect(...)
		-- client: local remote = Remotes.event("SprintIntent"); remote:FireServer(true)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "SurvivorCoreRemotes"
local WAIT_TIMEOUT = 10

local function getFolder(): Instance
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing
	end
	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	assert(
		folder,
		`[SurvivorCore] Remotes folder '{FOLDER_NAME}' not found — is the server running SurvivorCore.start()?`
	)
	return folder
end

-- Get (server: create-if-absent) a named RemoteEvent. Idempotent.
function Remotes.event(name: string): RemoteEvent
	local folder = getFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if RunService:IsServer() then
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		return event
	end
	local event = folder:WaitForChild(name, WAIT_TIMEOUT)
	assert(event and event:IsA("RemoteEvent"), `[SurvivorCore] RemoteEvent '{name}' not found`)
	return event
end

return Remotes
