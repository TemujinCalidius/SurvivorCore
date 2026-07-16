--!nonstrict
--[[
	Trade — server-authoritative player-to-player trading (issue #15). SERVER-ONLY.

	Two nearby players open a shared trade window, each stages loose backpack stacks into their
	side, and BOTH must confirm before anything moves. The swap is a single synchronous,
	dupe-proof commit.

	Safety model — staging is BY-REFERENCE, never escrow. While a trade is open the staged items
	stay in each owner's real inventory; a "basket" is just an { itemId -> qty } intent map. Real
	inventory mutation happens ONLY inside `commit`, in one no-yield critical section. So every
	abort (leave / death / walk out of range / cancel / timeout) needs zero item bookkeeping — the
	items never moved.

	Commit (both confirmed):
	  1. Re-validate both still HOLD their whole basket (Inventory.has) — zero mutations.
	  2. Pre-flight FIT on both receivers (Inventory.canAccept, accounting for each also shedding
	     its own basket) — zero mutations.
	  3. Escrow: Inventory.remove each basket from its owner (atomic; guaranteed by step 1).
	  4. Grant with Inventory.addUpTo (exact-count) — step 2 guarantees full grants.
	  5. Reconcile any residue back to the original owner (unreachable if canAccept is honest).
	Item count is conserved on every branch.

	Initiation: a "Trade" ProximityPrompt on each player's character; triggering it asks that player
	to trade with you (they Accept/Decline). Tuning: the "Trading" Config section. v1 trades loose
	backpack stacks only (worn gear/satchels reserved behind AllowEquippedItems). Started by
	SurvivorCore.start().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.Trade is server-only — booted by SurvivorCore.start()")

local Inventory = require(script.Parent.Inventory)
local Progression = require(script.Parent.Progression)
local Hooks = require(script.Parent.Parent.foundation.Hooks)
local EventBridge = require(script.Parent.Parent.foundation.EventBridge)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local TradingConfig = require(script.Parent.Parent.shared.TradingConfig)

local Trade = {}

local started = false

-- Both participants' keys point at the SAME session table; `sessions` lets the range loop iterate.
local activeTrade: { [Player]: any } = {}
local sessions: { any } = {}
local nextTradeId = 0

-- ── Small helpers ────────────────────────────────────────────────────────────

local function sanitizeItemId(value: any): string
	if type(value) ~= "string" then
		return ""
	end
	local s = string.sub(value, 1, 40)
	if s == "" or not string.match(s, "^[%w_%-%s]+$") then
		return ""
	end
	return s
end

local function basketToList(basket: { [string]: number }): { { itemId: string, qty: number } }
	local out = {}
	for itemId, qty in basket do
		if qty and qty > 0 then
			table.insert(out, { itemId = itemId, qty = qty })
		end
	end
	return out
end

local function hrpOf(player: Player): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

local function alive(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function maxDistance(): number
	return tonumber(TradingConfig.get().MaxDistance) or 16
end

local function inRange(a: Player, b: Player): boolean
	local ha, hb = hrpOf(a), hrpOf(b)
	if not ha or not hb then
		return false
	end
	return (ha.Position - hb.Position).Magnitude <= maxDistance() + 0.001
end

local function emit(event: string, player: Player, ctx: { [string]: any })
	ctx.player = player
	Hooks.run(event, ctx)
	EventBridge.fire(event, player, ctx)
end

local function notify(player: Player, title: string, body: string)
	if player and player.Parent then
		Remotes.event("Notify"):FireClient(player, { kind = "trade", title = title, body = body })
	end
end

-- ── Client state push (plain data — no Player/Instance refs) ──────────────────

-- The trade state oriented for one participant (mine/theirs swapped per side). `requested` splits
-- into "invite" (the invitee, who Accepts/Declines) and "waiting" (the requester).
local function stateFor(session: any, who: Player): { [string]: any }
	local isA = who == session.a
	local other = if isA then session.b else session.a
	local status = session.status
	if status == "requested" then
		status = if who == session.b then "invite" else "waiting"
	end
	return {
		tradeId = session.id,
		status = status,
		partner = other.Name,
		mine = basketToList(if isA then session.aBasket else session.bBasket),
		theirs = basketToList(if isA then session.bBasket else session.aBasket),
		myConfirm = if isA then session.aConfirm else session.bConfirm,
		theirConfirm = if isA then session.bConfirm else session.aConfirm,
		reason = session.reason,
	}
end

local function push(session: any)
	local remote = Remotes.event("TradeState")
	if session.a.Parent then
		remote:FireClient(session.a, stateFor(session, session.a))
	end
	if session.b.Parent then
		remote:FireClient(session.b, stateFor(session, session.b))
	end
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

local function dropSession(session: any)
	activeTrade[session.a] = nil
	activeTrade[session.b] = nil
	local idx = table.find(sessions, session)
	if idx then
		table.remove(sessions, idx)
	end
end

-- Idempotent teardown. Sends a terminal "cancelled" state so both windows close, then unregisters.
local function cancel(session: any, reason: string)
	if session.dead then
		return
	end
	session.dead = true
	session.status = "cancelled"
	session.reason = reason
	push(session)
	if reason ~= "cancelled" and reason ~= "declined" then
		local msg = ({
			timeout = "The trade request expired.",
			range = "You moved too far apart.",
			died = "A trader died.",
			left = "The other player left.",
		})[reason] or "Trade cancelled."
		notify(session.a, "Trade cancelled", msg)
		notify(session.b, "Trade cancelled", msg)
	end
	dropSession(session)
end

-- ── Atomic commit (the anti-dupe core) ─────────────────────────────────────────

local function refundEscrow(player: Player, escrow: { [string]: number })
	-- Restore exactly what we just removed; the room was freed a step ago with no yield between,
	-- so addUpTo restores in full.
	for itemId, qty in escrow do
		Inventory.addUpTo(player, itemId, qty)
	end
end

-- Returns (ok, reason). Runs synchronously with NO yield — nothing else can interleave and mutate
-- inventories mid-commit, so item count is conserved on every branch.
local function commit(session: any): (boolean, string?)
	local A, B = session.a, session.b

	-- Guard: both present, alive, still in range.
	if not (A.Parent and B.Parent and alive(A) and alive(B) and inRange(A, B)) then
		return false, "range"
	end

	-- STEP 1 — both still hold their whole basket. Zero mutations.
	for itemId, qty in session.aBasket do
		if not Inventory.has(A, itemId, qty) then
			return false, "shortfall"
		end
	end
	for itemId, qty in session.bBasket do
		if not Inventory.has(B, itemId, qty) then
			return false, "shortfall"
		end
	end

	-- STEP 2 — both receivers have room after shedding their own basket. Zero mutations.
	if not Inventory.canAccept(A, session.bBasket, { alsoRemoving = session.aBasket }) then
		return false, "full"
	end
	if not Inventory.canAccept(B, session.aBasket, { alsoRemoving = session.bBasket }) then
		return false, "full"
	end

	-- STEP 3 — escrow: remove each basket from its owner (atomic; guaranteed by step 1).
	local escrowA: { [string]: number } = {}
	for itemId, qty in session.aBasket do
		if Inventory.remove(A, itemId, qty) then
			escrowA[itemId] = qty
		else
			refundEscrow(A, escrowA)
			return false, "shortfall"
		end
	end
	local escrowB: { [string]: number } = {}
	for itemId, qty in session.bBasket do
		if Inventory.remove(B, itemId, qty) then
			escrowB[itemId] = qty
		else
			refundEscrow(A, escrowA)
			refundEscrow(B, escrowB)
			return false, "shortfall"
		end
	end

	-- STEP 4+5 — grant with the exact-count primitive; reconcile any residue back to its owner.
	-- Step 2 guarantees full grants, so the residue path is unreachable in practice (loud warn).
	for itemId, qty in escrowA do
		local granted = Inventory.addUpTo(B, itemId, qty)
		if granted < qty then
			local back = Inventory.addUpTo(A, itemId, qty - granted)
			if back < qty - granted then
				warn(`[SurvivorCore.Trade] residue lost: {qty - granted - back}x {itemId} (canAccept bug?)`)
			end
		end
	end
	for itemId, qty in escrowB do
		local granted = Inventory.addUpTo(A, itemId, qty)
		if granted < qty then
			local back = Inventory.addUpTo(B, itemId, qty - granted)
			if back < qty - granted then
				warn(`[SurvivorCore.Trade] residue lost: {qty - granted - back}x {itemId} (canAccept bug?)`)
			end
		end
	end

	return true
end

local function finalize(session: any)
	local A, B = session.a, session.b
	local aList = basketToList(session.aBasket)
	local bList = basketToList(session.bBasket)
	-- Fire once per player (Progression's resolver runs per real Player; both get trades_total++).
	emit("trade:completed", A, { partner = B.Name, gave = aList, got = bList })
	emit("trade:completed", B, { partner = A.Name, gave = bList, got = aList })
	notify(A, "Trade complete", `You traded with {B.Name}.`)
	notify(B, "Trade complete", `You traded with {A.Name}.`)
	session.status = "done"
	push(session)
	dropSession(session)
end

-- ── Internal ops (remotes AND the test harness call these with explicit Players) ──────────────

function Trade._startTrade(from: Player, target: Player)
	if typeof(from) ~= "Instance" or typeof(target) ~= "Instance" then
		return
	end
	if TradingConfig.get().Enabled == false then
		return
	end
	if from == target or not from.Parent or not target.Parent then
		return
	end
	if activeTrade[from] then
		notify(from, "Can't trade", "You're already in a trade.")
		return
	end
	if activeTrade[target] then
		notify(from, "Can't trade", `{target.Name} is already trading.`)
		return
	end
	if not (alive(from) and alive(target) and inRange(from, target)) then
		return
	end

	nextTradeId += 1
	local session = {
		id = tostring(nextTradeId),
		a = from, -- requester
		b = target, -- invitee
		status = "requested",
		aBasket = {},
		bBasket = {},
		aConfirm = false,
		bConfirm = false,
		dead = false,
	}
	activeTrade[from] = session
	activeTrade[target] = session
	table.insert(sessions, session)
	push(session)

	local timeout = math.max(1, tonumber(TradingConfig.get().RequestTimeoutSeconds) or 20)
	task.delay(timeout, function()
		if not session.dead and session.status == "requested" then
			cancel(session, "timeout")
		end
	end)
end

function Trade._respond(player: Player, accept: boolean)
	local session = activeTrade[player]
	if not session or session.dead or session.status ~= "requested" or player ~= session.b then
		return
	end
	if accept then
		if not (alive(session.a) and alive(session.b) and inRange(session.a, session.b)) then
			cancel(session, "range")
			return
		end
		session.status = "open"
		emit("trade:started", session.a, { partner = session.b.Name })
		emit("trade:started", session.b, { partner = session.a.Name })
		push(session)
	else
		cancel(session, "declined")
	end
end

local function resetConfirms(session: any)
	if TradingConfig.get().ResetConfirmOnChange ~= false then
		session.aConfirm = false
		session.bConfirm = false
	end
end

-- Stage from an inventory slot. The server resolves the itemId from the player's OWN slot (never
-- trusts a client-sent id) and clamps the quantity to what they actually hold.
function Trade._stage(player: Player, invSlot: any, qty: any)
	local session = activeTrade[player]
	if not session or session.dead or session.status ~= "open" then
		return
	end
	local slot = math.floor(tonumber(invSlot) or 0)
	if slot < 1 then
		return
	end
	local itemId = ""
	for _, e in Inventory.getSlots(player) do
		if e.slot == slot then
			itemId = e.itemId
			break
		end
	end
	if itemId == "" then
		return
	end
	local held = Inventory.getQty(player, itemId)
	local staged = math.clamp(math.floor(tonumber(qty) or 0), 0, held)
	local basket = if player == session.a then session.aBasket else session.bBasket
	if staged <= 0 then
		basket[itemId] = nil
	else
		basket[itemId] = staged
	end
	resetConfirms(session)
	push(session)
end

function Trade._unstage(player: Player, itemId: any, qty: any)
	local session = activeTrade[player]
	if not session or session.dead or session.status ~= "open" then
		return
	end
	local id = sanitizeItemId(itemId)
	if id == "" then
		return
	end
	local basket = if player == session.a then session.aBasket else session.bBasket
	if basket[id] == nil then
		return
	end
	local reduce = math.floor(tonumber(qty) or 0)
	if reduce <= 0 then
		basket[id] = nil
	else
		local n = basket[id] - reduce
		basket[id] = if n <= 0 then nil else n
	end
	resetConfirms(session)
	push(session)
end

function Trade._confirm(player: Player)
	local session = activeTrade[player]
	if not session or session.dead or session.status ~= "open" then
		return
	end
	if player == session.a then
		session.aConfirm = true
	elseif player == session.b then
		session.bConfirm = true
	else
		return
	end

	if session.aConfirm and session.bConfirm then
		session.status = "committing" -- re-entry latch; commit does not yield
		local ok, reason = commit(session)
		if ok then
			finalize(session)
		else
			session.status = "open"
			session.aConfirm = false
			session.bConfirm = false
			local msg = ({
				full = "Not enough room.",
				shortfall = "The offer changed — try again.",
				range = "You moved too far apart.",
			})[reason or ""] or "Trade failed."
			notify(session.a, "Trade failed", msg)
			notify(session.b, "Trade failed", msg)
			push(session)
		end
	else
		push(session)
	end
end

function Trade._cancel(player: Player)
	local session = activeTrade[player]
	if session then
		cancel(session, "cancelled")
	end
end

-- Testing accessor: the player's live session (or nil). Used by the demo conservation harness.
function Trade._activeFor(player: Player): any
	return activeTrade[player]
end

-- ── Initiation + character lifecycle ───────────────────────────────────────────

local function onCharacter(player: Player, character: Model)
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if hrp and hrp:IsA("BasePart") and TradingConfig.get().Enabled ~= false then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SC_TradePrompt"
		prompt.ActionText = "Trade"
		prompt.ObjectText = player.Name
		prompt.HoldDuration = 0.3
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = maxDistance()
		prompt.Parent = hrp
		prompt.Triggered:Connect(function(triggerer)
			Trade._startTrade(triggerer, player)
		end)
	end
	if humanoid then
		humanoid.Died:Once(function()
			local session = activeTrade[player]
			if session then
				cancel(session, "died")
			end
		end)
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

local function wireRemotes()
	Remotes.event("TradeRequest").OnServerEvent:Connect(function(player, targetUserId)
		local target = Players:GetPlayerByUserId(math.floor(tonumber(targetUserId) or -1))
		if target then
			Trade._startTrade(player, target)
		end
	end)
	Remotes.event("TradeRespond").OnServerEvent:Connect(function(player, accept)
		Trade._respond(player, accept == true)
	end)
	Remotes.event("TradeStage").OnServerEvent:Connect(function(player, invSlot, qty)
		Trade._stage(player, invSlot, qty)
	end)
	Remotes.event("TradeUnstage").OnServerEvent:Connect(function(player, itemId, qty)
		Trade._unstage(player, itemId, qty)
	end)
	Remotes.event("TradeConfirm").OnServerEvent:Connect(function(player)
		Trade._confirm(player)
	end)
	Remotes.event("TradeCancel").OnServerEvent:Connect(function(player)
		Trade._cancel(player)
	end)
end

function Trade.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	-- Completed trades flow into the shared progress stream → trades_total counter.
	Progression.map("trade:completed", function(_player, _data)
		return "trade", nil, 1
	end)

	Remotes.event("TradeState") -- eager S→C so clients can connect at startup
	wireRemotes()

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local session = activeTrade[player]
		if session then
			cancel(session, "left")
		end
	end)

	-- Throttled range watchdog: a trade auto-cancels if the pair walks apart.
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		if #sessions == 0 then
			return
		end
		accum += dt
		if accum < 0.25 then
			return
		end
		accum = 0
		for i = #sessions, 1, -1 do
			local s = sessions[i]
			if not s.dead and (s.status == "open" or s.status == "requested") and not inRange(s.a, s.b) then
				cancel(s, "range")
			end
		end
	end)
end

return Trade
