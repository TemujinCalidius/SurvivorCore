# Quests

The quest system ([`src/systems/Quests.luau`](../src/systems/Quests.luau)) gives players **goals**:
accept a quest, work its objectives, claim the reward. Progress is driven entirely by the events
the other systems already fire (gather / craft / kill / use), so a quest needs **zero wiring** —
register a def and the engine tracks it.

> Progress is **session-scoped** (Player attributes) — persistence (DataStore) is a future system.

## Defining a quest

In code (canonical, supports multiple objectives) or [no-code via the admin
plugin](content-authoring.md) (single-objective):

```lua
SurvivorCore.Quests.register({
    id = "gather_reeds",
    name = "Gather Reeds",
    description = "Pull 3 reeds from the bushes by the river.",
    objectives = {
        { type = "gather", target = "reed", count = 3 },  -- type: "gather"|"craft"|"kill"|"use"
    },
    rewards = { { item = "berry", count = 2 } },
    autoStart = true,       -- accepted automatically on join (or when `requires` completes)
    -- requires = "id",     -- single prerequisite (chains)
    -- turnIn = true,       -- must return to a QuestGiver to claim the reward
})
```

An objective's `target` is an item id (gather/craft/use) or a mob type (kill); **blank = any**
("slay 3 of anything"). The flat no-code shape (`objectiveType`/`objectiveTarget`/`objectiveCount`/
`rewardItem`/`rewardCount` attributes) is normalized to this at load — both behave identically.

## Lifecycle

**active** → objectives met → (**ready**, if `turnIn` or the inventory was full) → **done**.

- Progress comes from the [Progression](achievements.md#the-progression-stream) event stream.
- **Rewards are never lost:** if the inventory can't fit the reward, the quest parks in *ready* and
  the grant retries automatically whenever the inventory changes.
- Completing a quest fires the `quest:completed` hook + EventBridge event, shows a toast
  (config-gated), and **auto-starts** any `autoStart` quest that `requires` it — chains flow.

## Quest givers (no-code)

Tag any part/model **`QuestGiver`** (CollectionService) and set `Quest = "<quest id>"` — the engine
attaches a hold-**E** prompt that *accepts* the quest (or *turns it in* when its objectives are met
and it's a `turnIn` quest). The admin plugin's Quests editor drops one via **+ Quest giver**.

## Runtime API

`SurvivorCore.Quests` (registry always; runtime ops after `start()`):

| Function | Behavior |
|---|---|
| `accept(player, id) -> (ok, reason?)` | gates: unknown / done / active / `requires` / `MaxActive` |
| `complete(player, id) -> (ok, reason?)` | turn-in (or claim a met quest); `"full"` = no reward room |
| `abandon(player, id) -> ok` | drop an active quest (progress lost) |
| `getLog(player)` / `isActive` / `isCompleted` | read state |

Hooks (also on EventBridge): `quest:started` / `quest:progress` / `quest:completed` /
`quest:blocked` — ctx `{ player, questId, def?, index?, count?, reason? }`.

## The Quests tab & data

The menu's **Quests** tab (key **L**) renders Active (per-objective progress bars) / Ready /
Completed. Defs replicate via a JSON `SurvivorCoreQuestData` StringValue; per-player progress is the
`QuestLog` JSON Player attribute (`{ active = { [id] = { p = {…} } }, ready = {}, done = {} }`) —
both readable via [`src/shared/QuestData.luau`](../src/shared/QuestData.luau).

## Tuning

`Config.override("Quests", { MaxActive = 0 --[[0 = unlimited]], Toasts = true })`.

---

See also: [Achievements](achievements.md) · [No-code content](content-authoring.md) ·
[Extending](extending.md).
