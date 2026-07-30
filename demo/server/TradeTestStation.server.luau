--!nonstrict
--[[
	TradeTestStation — DEMO harness for player trading (issue #15). Not engine code.

	Trading needs two players, so it can't be driven from a single-client playtest. This script
	drives the internal `SurvivorCore.Trade._*` API with two REAL players and asserts ITEM
	CONSERVATION — merge(A,B) before == merge(A,B) after — across the tricky paths.

	Run it in a 2-player local server (Studio → Test → Start, 2 players), then have either player
	chat `/tradetest`. Results print to the Server output. It can also be invoked from a server
	command bar / MCP as `_G.SurvivorCoreTradeTest()`.

	It seeds each player's inventory before every scenario, so it overwrites their items — a test
	tool, not something to leave enabled in a shipping game.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SurvivorCore = require(ReplicatedStorage:WaitForChild("SurvivorCore"))

-- ── inventory helpers (direct attribute seeding — deterministic setup) ─────────

local function clearSlots(player: Player)
	for n = 1, 40 do
		player:SetAttribute("InvSlot_" .. n, nil)
		player:SetAttribute("InvQty_" .. n, nil)
	end
end

local function seed(player: Player, entries: { { itemId: string, slot: number, qty: number } })
	clearSlots(player)
	for _, e in entries do
		player:SetAttribute("InvSlot_" .. e.slot, e.itemId)
		player:SetAttribute("InvQty_" .. e.slot, e.qty)
	end
end

-- itemId -> total qty across all of a player's slots.
local function snap(player: Player): { [string]: number }
	local out = {}
	for _, s in SurvivorCore.Inventory.getSlots(player) do
		out[s.itemId] = (out[s.itemId] or 0) + s.qty
	end
	return out
end

local function mergeCounts(a: { [string]: number }, b: { [string]: number }): { [string]: number }
	local out = {}
	for k, v in a do
		out[k] = (out[k] or 0) + v
	end
	for k, v in b do
		out[k] = (out[k] or 0) + v
	end
	return out
end

local function sameCounts(a: { [string]: number }, b: { [string]: number }): boolean
	for k, v in a do
		if (b[k] or 0) ~= v then
			return false
		end
	end
	for k, v in b do
		if (a[k] or 0) ~= v then
			return false
		end
	end
	return true
end

local function slotOf(player: Player, itemId: string): number?
	for _, s in SurvivorCore.Inventory.getSlots(player) do
		if s.itemId == itemId then
			return s.slot
		end
	end
	return nil
end

-- ── scenario driver ────────────────────────────────────────────────────────────

local passed, failed = 0, 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
		print(`  ✓ {name}`)
	else
		failed += 1
		warn(`  ✗ {name}{if detail then " — " .. detail else ""}`)
	end
end

-- Open a trade, stage each side by itemId, both confirm. Returns after the (synchronous) commit.
local function runTrade(A: Player, B: Player, aStage: { [string]: number }, bStage: { [string]: number })
	SurvivorCore.Trade._startTrade(A, B)
	SurvivorCore.Trade._respond(B, true)
	for itemId, qty in aStage do
		local slot = slotOf(A, itemId)
		if slot then
			SurvivorCore.Trade._stage(A, slot, qty)
		end
	end
	for itemId, qty in bStage do
		local slot = slotOf(B, itemId)
		if slot then
			SurvivorCore.Trade._stage(B, slot, qty)
		end
	end
	SurvivorCore.Trade._confirm(A)
	SurvivorCore.Trade._confirm(B)
end

local function runSuite()
	local players = Players:GetPlayers()
	if #players < 2 then
		warn("[TradeTest] need two players in the server — Start a 2-player local server.")
		return
	end
	local A, B = players[1], players[2]
	passed, failed = 0, 0
	print(`[TradeTest] A={A.Name}  B={B.Name}`)

	-- 1. Happy-path swap: A gives reed×10, B gives berry×5.
	do
		seed(A, { { itemId = "reed", slot = 1, qty = 10 } })
		seed(B, { { itemId = "berry", slot = 1, qty = 5 } })
		local before = mergeCounts(snap(A), snap(B))
		runTrade(A, B, { reed = 10 }, { berry = 5 })
		local a1, b1 = snap(A), snap(B)
		check("happy swap: conserved", sameCounts(before, mergeCounts(a1, b1)))
		check("happy swap: A got berries", (a1.berry or 0) == 5 and (a1.reed or 0) == 0)
		check("happy swap: B got reeds", (b1.reed or 0) == 10 and (b1.berry or 0) == 0)
		check("happy swap: session cleared", SurvivorCore.Trade._activeFor(A) == nil)
	end

	-- 2. Receiver-full refund: B has no free slots, so A's offer can't land. Nothing moves.
	do
		local full = {}
		for n = 1, 5 do -- base pocket slots
			table.insert(full, { itemId = "berry", slot = n, qty = 1 })
		end
		seed(A, { { itemId = "reed", slot = 1, qty = 3 } })
		seed(B, full)
		local a0, b0 = snap(A), snap(B)
		runTrade(A, B, { reed = 3 }, {}) -- A offers, B offers nothing → B has no room
		local a1, b1 = snap(A), snap(B)
		check("receiver-full: A unchanged", sameCounts(a0, a1))
		check("receiver-full: B unchanged", sameCounts(b0, b1))
		SurvivorCore.Trade._cancel(A) -- trade reopened on failure; close it
	end

	-- 3. Stage-more-than-held clamps to what the player actually holds.
	do
		seed(A, { { itemId = "reed", slot = 1, qty = 4 } })
		seed(B, { { itemId = "berry", slot = 1, qty = 2 } })
		SurvivorCore.Trade._startTrade(A, B)
		SurvivorCore.Trade._respond(B, true)
		SurvivorCore.Trade._stage(A, 1, 999) -- ask for 999, hold 4
		SurvivorCore.Trade._stage(B, 1, 2)
		local before = mergeCounts(snap(A), snap(B))
		SurvivorCore.Trade._confirm(A)
		SurvivorCore.Trade._confirm(B)
		local a1, b1 = snap(A), snap(B)
		check("stage clamp: conserved", sameCounts(before, mergeCounts(a1, b1)))
		check("stage clamp: only 4 reeds moved", (b1.reed or 0) == 4)
	end

	-- 4. Cancel mid-trade leaves both inventories untouched (staging never escrows).
	do
		seed(A, { { itemId = "reed", slot = 1, qty = 6 } })
		seed(B, { { itemId = "berry", slot = 1, qty = 6 } })
		local a0, b0 = snap(A), snap(B)
		SurvivorCore.Trade._startTrade(A, B)
		SurvivorCore.Trade._respond(B, true)
		SurvivorCore.Trade._stage(A, 1, 6)
		SurvivorCore.Trade._stage(B, 1, 6)
		SurvivorCore.Trade._cancel(A)
		check("cancel mid-trade: A unchanged", sameCounts(a0, snap(A)))
		check("cancel mid-trade: B unchanged", sameCounts(b0, snap(B)))
		check("cancel mid-trade: session gone", SurvivorCore.Trade._activeFor(A) == nil)
	end

	print(`[TradeTest] done — {passed} passed, {failed} failed.`)
end

-- selene: allow(global_usage)
_G.SurvivorCoreTradeTest = runSuite -- so a command bar / MCP can invoke the suite directly

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		local trimmed = string.gsub(message, "%s+", "")
		if string.lower(trimmed) == "/tradetest" then
			runSuite()
		end
	end)
end)
