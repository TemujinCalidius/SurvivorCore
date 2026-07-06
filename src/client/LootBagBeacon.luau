--!nonstrict
--[[
	LootBagBeacon — client. Owner-only "your stuff is over there" juice (TCE port).

	The server fires `LootBagDropped` at the owner with a POSITION + lifetime (plain data — immune
	to instance-replication races and streaming eviction); this raises a tall golden beam + ground
	ring + light there, visible only to this player. It clears when the server signals the bag is
	truly gone (a nil fire: looted empty or expired) or when the lifetime lapses — NOT when the
	bag's replica streams out, which is what used to kill the beacon on respawn. Booted by
	startClient().
]]

local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "SurvivorCore.LootBagBeacon is client-only — boot it via SurvivorCore.startClient()")

local Remotes = require(script.Parent.Parent.shared.Remotes)

local LootBagBeacon = {}

local started = false

local GOLD = Color3.fromRGB(255, 220, 80)

local currentBeam: BasePart? = nil
local currentToken = 0 -- invalidates stale lifetime timers when a new bag drops

local function clearBeacon()
	currentToken += 1
	if currentBeam and currentBeam.Parent then
		currentBeam:Destroy()
	end
	currentBeam = nil
end

local function buildBeacon(position: Vector3, lifetime: number)
	clearBeacon()
	local token = currentToken

	local beam = Instance.new("Part")
	beam.Name = "_LootBeacon"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = GOLD
	beam.Transparency = 0.35
	beam.Size = Vector3.new(0.8, 120, 0.8)
	beam.CFrame = CFrame.new(position + Vector3.new(0, 60, 0))

	local ring = Instance.new("Part")
	ring.Name = "_LootBeaconRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = GOLD
	ring.Transparency = 0.55
	ring.Size = Vector3.new(0.2, 5, 5)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = beam

	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Brightness = 2.5
	light.Range = 18
	light.Parent = beam

	beam.Parent = workspace
	currentBeam = beam

	-- Fallback cleanup at lifetime (the server's nil-fire normally clears it first).
	task.delay(math.max(1, lifetime), function()
		if token == currentToken and currentBeam == beam then
			clearBeacon()
		end
	end)
end

function LootBagBeacon.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	Remotes.event("LootBagDropped").OnClientEvent:Connect(function(position, lifetime)
		if typeof(position) == "Vector3" then
			buildBeacon(position, tonumber(lifetime) or 300)
		else
			clearBeacon() -- nil = the bag is truly gone (looted empty or expired)
		end
	end)
end

return LootBagBeacon
