# Player trading

Two survivors standing near each other can **trade items** face-to-face
([`src/systems/Trade.luau`](../src/systems/Trade.luau), issue #15). The swap is fully
server-authoritative and **dupe-proof**: nothing moves until both players confirm, and even then it
moves in one atomic step that can never create or destroy an item.

## How a trade goes

1. **Start it.** Walk up to another player — an **"[E] Interact"** badge appears over *their* head.
   Press **E** (or tap it) to open the [interact window](interact.md), then choose **Trade**. They
   get an **Accept / Decline** request; the requester waits.
2. **Stage your offer.** Once open, both players see the trade window: *your offer* and *their
   offer* side by side, with **your backpack listed underneath** — click a row to offer one, or
   **All** for the whole stack. (You can also drag straight from the inventory grid if you have the
   menu open.) The **−/+** steppers on a staged row set the quantity and **✕** removes it. Changing
   either offer **clears both confirms** (so nobody can confirm and then swap the goods out from
   under you). Drag the window by its **header** to move it out of the way.
3. **Confirm.** Both players press **Confirm**. The instant both are confirmed, the server runs the
   atomic swap and the items change hands.

Either side can **Cancel** at any time. A trade also auto-cancels if a trader **dies**, **leaves**,
or **walks out of range** (see `MaxDistance`), and a pending request expires after
`RequestTimeoutSeconds`.

## Why it can't dupe

Staging is **by reference, not escrow** — while the window is open your items stay in your
inventory; the "offer" is just a list of intentions. Real inventory changes happen only in the
commit, in one synchronous step:

1. Re-check both players still **hold** everything they offered.
2. Pre-check both players have **room** for what they're about to receive
   (`Inventory.canAccept`, weight + free slots, accounting for what each is giving away).
3. Remove both offers, grant them to the other side with the exact-count primitive
   (`Inventory.addUpTo`), and refund anything that somehow doesn't fit.

Because the whole commit runs without yielding, nothing else can slip in between the steps — the
item count is conserved on every path. If a receiver turns out to be full, the trade simply reopens
with a "not enough room" notice and nothing is lost.

## What can be traded

**v1: loose backpack stacks only.** Worn equipment and satchels aren't tradeable yet — they change
carry capacity, which needs extra care. Flip `AllowEquippedItems` on when that lands.

## Configuration

```lua
Config.override("Trading", {
    Enabled = true,            -- false = trading off (the prompt never appears)
    MaxDistance = 16,          -- studs; how close to open AND keep a trade
    RequestTimeoutSeconds = 20,
    ResetConfirmOnChange = true, -- a staging change clears both confirms
    AllowEquippedItems = false,  -- reserved: trade worn gear/satchels too
})
```

All of these are also editable no-code in **SurvivorCore Studio** (Engine Config → *Trading*).

## Hooks & events

| Event | Payload |
|---|---|
| `trade:started` | `{ player, partner }` — fired once per player when both accept |
| `trade:completed` | `{ player, partner, gave, got }` — fired once per player on a successful swap |

Both also cross the EventBridge, and `trade:completed` feeds the Progression stream as a **`trade`**
counter (`trades_total`), so quests and achievements can reward trading out of the box. Progress is
**session-scoped** — persistence (DataStore) is a future system.

---

See also: [Inventory](inventory.md) · [Loot bags](loot-bags.md) · [Extending](extending.md).
