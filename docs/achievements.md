# Achievements

> 📹 **Demo:** [quests, achievements & the no-code editors in action](https://makertube.net/w/uSGJ2MHEFjSSKxMiJBJ6Y5)

The achievement system ([`src/systems/Achievements.luau`](../src/systems/Achievements.luau)) tracks
**milestones**: always-on counters that unlock a badge (once) when they cross a threshold — with a
toast and an Achievements menu tab. The architecture is ported from The Counter Earth's proven
achievement service, made content-free.

> Progress is **session-scoped** (Player attributes) — persistence (DataStore) is a future system.

## Defining an achievement

Defs are **flat** — the same shape in code and [no-code](content-authoring.md):

```lua
SurvivorCore.Achievements.register({
    key = "husk_slayer",
    name = "Husk Slayer",
    description = "Slay 3 husks.",
    counter = "kills_husk",   -- which counter unlocks it (see the catalogue below)
    threshold = 3,
    -- icon = "rbxassetid://…",
})
```

## The Progression stream

One shared layer ([`src/systems/Progression.luau`](../src/systems/Progression.luau)) subscribes to
the EventBridge and translates gameplay events into `(player, kind, target, amount)` progress —
consumed by **both** achievements (counters) and [quests](quests.md) (objectives). Built-in:

| Event | kind | target | amount |
|---|---|---|---|
| `gather:hit` | `gather` | the item id | amount granted |
| `craft:end` | `craft` | the output item id | output count |
| `mob:died` (with a killer) | `kill` | the mob type | 1 |
| `item:use` | `use` | the item id | 1 |
| `quest:completed` | `quest` | the quest id | 1 |

### Counter catalogue (the naming rule)

Every progress tick bumps `"<kind>s_total"` and `"<kind>s_<target>"`:

`gathers_total` · `gathers_reed` · `crafts_total` · `crafts_reed_basket` · `kills_total` ·
`kills_husk` · `uses_total` · `uses_berry` · `quests_total` · `quests_<questId>` — author any
achievement against any of these, no code.

### Custom events & counters (code)

```lua
-- Teach the stream a game event (then author achievements against boss counters):
SurvivorCore.Progression.map("myGame:bossDown", function(player, data)
    return "kill", data.bossId, 1
end)

-- Or bump a bespoke counter / award directly:
SurvivorCore.Achievements.addCount(player, "shrines_visited", 1)
SurvivorCore.Achievements.award(player, "secret_cave")
```

## Runtime API

`SurvivorCore.Achievements` (registry always; runtime ops after `start()`): `award(player, key)`,
`addCount(player, counterId, n?)`, `isUnlocked(player, key)`, `getState(player)`. Unlocks fire the
`achievement:unlocked` hook + EventBridge event and a toast (config-gated).

## The Achievements tab & data

The menu's **Achievements** tab (key **J**) lists every def with a progress bar toward its
threshold; unlocked rows go gold. Defs replicate via `SurvivorCoreAchievementData`; per-player state
is the `AchievementState` JSON attribute (`{ c = { [counter] = n }, u = { [key] = true } }`) — both
readable via [`src/shared/AchievementData.luau`](../src/shared/AchievementData.luau).

## Tuning

`Config.override("Achievements", { Toasts = true })`.

---

See also: [Quests](quests.md) · [No-code content](content-authoring.md) · [Extending](extending.md).
