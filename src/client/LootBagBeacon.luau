--!nonstrict
--[[
	LootBagBeacon — client. Owner-only "your stuff is over there" juice (TCE port).

	When the server drops YOUR loot bag it fires `LootBagDropped` at you; this raises a tall golden
	beam + a soft ground ring + a point light over the bag — visible only to you (built locally).
	Everything cleans itself up when the bag despawns or empties. Booted by startClient().
]]

local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "SurvivorCore.LootBagBeacon is client-only — boot it via SurvivorCore.startClient()")

local Remotes = require(script.Parent.Parent.shared.Remotes)

local LootBagBeacon = {}

local started = false

local GOLD = Color3.fromRGB(255, 220, 80)

local function bagHost(bag: Instance): BasePart?
	if bag:IsA("BasePart") then
		return bag
	end
	return bag:FindFirstChildWhichIsA("BasePart")
end

local function buildBeacon(bag: Instance)
	local host = bagHost(bag)
	if not host then
		return
	end

	local beam = Instance.new("Part")
	beam.Name = "_LootBeacon"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = GOLD
	beam.Transparency = 0.35
	beam.Size = Vector3.new(0.8, 120, 0.8)
	beam.CFrame = CFrame.new(host.Position + Vector3.new(0, 60, 0))

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
	ring.CFrame = CFrame.new(host.Position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = beam

	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Brightness = 2.5
	light.Range = 18
	light.Parent = host

	beam.Parent = workspace

	-- Clean up when the bag goes away (looted empty or despawned).
	bag.Destroying:Connect(function()
		if beam.Parent then
			beam:Destroy()
		end
	end)
end

function LootBagBeacon.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	Remotes.event("LootBagDropped").OnClientEvent:Connect(function(bag, _lifetime)
		if typeof(bag) == "Instance" then
			buildBeacon(bag)
		end
	end)
end

return LootBagBeacon
