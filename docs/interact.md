# Player interact window

> 📹 **Demo:** [the interact window + player trading](https://makertube.net/w/sJmS6L15jRmwxhQCE4Zgmi)

Walk up to another player and a **"[E] Interact"** badge appears over *their* head. Press **E** (or
tap the badge) to open an **interact window** showing that player's name and survival stats, plus a
list of **actions** — **Trade** ships built-in; games add their own
([`src/client/PlayerInteract.luau`](../src/client/PlayerInteract.luau), ported from The Counter
Earth).

This is the front door for player-to-player interaction. It replaced an earlier per-character
proximity prompt that (wrongly) showed on your *own* character — the interact target is chosen by a
client-side **nearest-other-player** scan, so the affordance can never point at you.

## Targeting

- A throttled scan picks the **nearest other player within range** (`Trading.MaxDistance`, default 16
  studs) and floats the badge over their head. It never considers the local player.
- Light hysteresis keeps the badge from flickering between two players who are the same distance away.
- The badge (and any open window) clears when you walk away, when the target leaves or dies, or while
  you're already in a trade.

## Actions API

Actions are a small **client-side registry**, so a game (or a future engine system) can add its own
interactions. Trade is registered by the engine as the first entry.

```lua
local SurvivorCore = require(ReplicatedStorage.SurvivorCore)

SurvivorCore.Interact.addAction({
    id = "wave",              -- unique; re-adding the same id replaces it
    label = "Wave",
    order = 50,               -- sort key (lower = earlier); default 100
    enabled = function(ctx)   -- optional; return false to hide the button
        return true
    end,
    onActivate = function(ctx)
        -- ctx = { target: Player, targetUserId: number, distance: number, close: () -> () }
        Remotes.event("Wave"):FireServer(ctx.targetUserId)
        ctx.close()           -- hide the interact window
    end,
})
```

The built-in **Trade** action simply fires the `TradeRequest` remote with the target's `UserId`; the
server (`Trade._startTrade`) validates everything and the [trade flow](trading.md) takes over.

## Config

The scan reuses the **`Trading.MaxDistance`** setting, and the interact key is
**`UI.Keybinds.Interact`** (default `"E"`) — both editable no-code in SurvivorCore Studio (Engine
Config → *Trading* / *UI & theme*) or via `Config.override`.

---

See also: [Trading](trading.md) · [Survival stats](survival-stats.md) · [Extending](extending.md).
