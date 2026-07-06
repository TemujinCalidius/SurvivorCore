# Death, loot bags & respawn

When a player dies, SurvivorCore drops their belongings into a **loot bag** at the spot they fell
([`src/systems/LootBags.luau`](../src/systems/LootBags.luau), ported from The Counter Earth). The
survival stakes system: get back to your bag before it's gone — or before someone else does.

## What happens on death

1. The inventory — and, by default, **worn equipment** too — is snapshotted and cleared
   (`Inventory.clearAll`; ordering is capacity-safe, so satchel-granted slots never lose items).
2. `player:died` fires (Hooks + EventBridge, ctx `{ player, position }`) — **after** the clear, so
   consumers see consistent state. The Progression stream maps it to a `death`, so
   **`deaths_total`** counters and achievements work out of the box.
3. An **anchored** bag spawns at the death spot (ground-clamped by raycast — mid-air and water
   deaths stay reachable), holding the contents as `IntValue` children (item id → count). A
   floating **countdown** shows everyone how long it has left; the **owner** also gets a tall
   golden **beacon** (client-side, only they see it) and a "You died" toast.
4. After `LifetimeSeconds` the bag despawns with whatever is still inside.

## Looting

**Anyone** may loot a bag (hold nothing — the prompt is instant). Pickup is loss-proof:

- **Equipment restores first** (the Back slot before the rest) straight onto empty equip slots —
  so a dropped satchel re-grows your slot count and weight cap *before* the stacks pour back in.
- Stacks then grant **up to what fits** (`Inventory.addUpTo`); anything that doesn't fit **stays in
  the bag** for another trip. The bag is destroyed only when it's empty.

## Configuration

```lua
Config.override("LootBags", {
    Enabled = true,           -- false = nothing drops (inventory persists through death)
    DropEquipment = true,     -- false = worn gear survives death; only carried items drop
    LifetimeSeconds = 300,
    InteractRange = 8,
    ShowCountdown = true,
    OwnerBeacon = true,
})
```

A creator-styled bag replaces the placeholder by adding a model named **`LootBag`** under
`ReplicatedStorage.SurvivorCoreContent`.

## Respawn camera

[`src/client/RespawnCamera.luau`](../src/client/RespawnCamera.luau) re-points `CameraSubject` at
the new Humanoid on every respawn (a TCE fix for the camera lingering on the old body). Survival
stats already reset per fresh body via [SurvivalConsequences](survival-stats.md).

## Hooks & events

| Event | Payload |
|---|---|
| `player:died` | `{ player, position }` |
| `lootbag:dropped` | `{ player, bag, position, items }` |
| `lootbag:collected` | `{ player, bag, emptied }` |

All three also cross the EventBridge. Progress is **session-scoped** — persistence (DataStore) is
a future system.

---

See also: [Mobs & hunting](mobs.md) · [Inventory](inventory.md) · [Combat](combat.md).
