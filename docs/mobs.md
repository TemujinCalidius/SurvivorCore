# Mobs & AI

> 📹 **Demo:** [creating mobs & fleeing hunt-NPCs, plus combat and the admin plugin](https://makertube.net/w/tyn8JEMG3CaMbTXid8osdU)

The **mob & AI engine** ([`src/systems/Mobs.luau`](../src/systems/Mobs.luau)) is the shared,
content-free creature substrate that combat (#12), animals (#13) and monsters (#14) all build on.

The key idea: **a mob is a Humanoid.** Concretely, a mob is a `Model` tagged **`Mob`** that contains
a `Humanoid` and a `PrimaryPart` (its `HumanoidRootPart`). Because of that, a mob is damaged, healed
and killed *exactly* like a player — `Humanoid:TakeDamage`, `Humanoid.Health`, `Humanoid.Died` — so
[combat](combat.md) has **one** code path for players and mobs, and there are no bespoke "mob HP"
systems to keep in sync.

> The engine ships **zero** creatures. You supply the rigged model (or let the engine build a blocky
> placeholder), the `Mobs` def (stats), and the death/spawn juice via reactions.

## Defining a mob type

A mob's stats come from a **`Mobs` registry def** — in code or [no-code via the admin
plugin](content-authoring.md):

```lua
SurvivorCore.Mobs.register({
    id = "husk",
    faction = "hostile",   -- "hostile" | "passive" | "neutral"  (picks the AI profile)
    health = 60,
    walkSpeed = 5,         -- idle/wander speed
    runSpeed = 15,         -- chase / flee speed
    aggroRange = 40,       -- how close a player must be to be noticed (hostile) or fled from (passive)
    leashRange = 70,       -- studs from spawn before a chaser gives up and returns
    attackRange = 6,       -- melee reach of the mob's own attack (hostile)
    attackDamage = 8,
    attackCooldown = 1.5,
})
```

Anything you leave out falls back to the **`Mobs` Config** defaults (see Tuning). Every field also
has a Config default, so a minimal def is just `{ id, faction }`.

## The behavior profile is data

The FSM is one state machine; `faction` selects how it behaves — you don't subclass or script it:

| Faction | Behavior |
|---|---|
| `hostile` | idle/wander near spawn → **chase** a player in `aggroRange` (with line-of-sight) → **attack** within `attackRange` → **return** to spawn if it's dragged past `leashRange`. |
| `passive` | idle/wander → **flee** from a player who comes within `aggroRange` (or who strikes it). |
| `neutral` | idle/wander only; **flees briefly** when struck. |

## Placing a mob in the world

Two ways, and they coexist:

**1. Tag a model (no-code).** Build/import any rigged Model with a Humanoid + PrimaryPart, tag it
**`Mob`** (CollectionService), and set one attribute:

| Attribute | Meaning |
|---|---|
| `MobType` | the `Mobs` def id to inherit from (e.g. `"husk"`); blank = the model's `Name` |

Per-instance attributes (`Faction`, `Health`, `WalkSpeed`, `RunSpeed`, `AggroRange`, `LeashRange`,
`AttackRange`, `AttackDamage`, `AttackCooldown`, `WanderRadius`) **override** the def for that one
mob. (The admin plugin's **Mobs** editor writes the def and its **+ Add to World** button drops a
tagged placeholder rig for you.)

**2. Spawn from code** (`SurvivorCore.Mobs`, available after `start()`):

| Function | Behavior |
|---|---|
| `spawn(mobType, cframe, opts?) -> Model` | clone a creator template (`SurvivorCoreContent.MobModels.<mobType>`) or build a placeholder, tag + adopt it. `opts.respawn = true` re-spawns it on death after `opts.respawnSeconds` (default Config). |
| `adopt(model)` | bring an existing tagged Model under AI control (idempotent). |
| `damage(model, amount, source?)` | apply damage to a mob (combat uses this; records the attacker + fires `mob:hit`). |
| `getActive() -> { Model }` · `isMob(model) -> bool` | the live roster / a membership test. |

```lua
SurvivorCore.Mobs.spawn("husk", CFrame.new(40, 5, 20), { respawn = true })
```

## Reactions (the juice)

Global `Hooks.on("mob:died", …)` fire for every mob. For behavior tied to **one** mob type, use the
reaction API — no core edits:

```lua
SurvivorCore.Mobs.onReaction("husk", "died", function(ctx)
    -- ctx = { instance, mobType, killer?, position? }
    fadeCorpse(ctx.instance) -- creator content; the engine just removes the body after CorpseSeconds
end)
```

Events: `"spawned"` · `"hit"` · `"attack"` (the mob hit a player) · `"died"`. Anims/sounds are
content-free — register them in `Assets` under `MobAnims` / `MobSounds`, keyed `mobType.."_"..state`
(e.g. `husk_attack`); the FSM plays them if present.

## Tuning

`Config.override("Mobs", { TickRate = 0.2, DefaultAggroRange = 40, DefaultLeashRange = 60,
DefaultAttackRange = 6, DefaultAttackDamage = 8, DefaultAttackCooldown = 1.5, RequireLineOfSight =
true, RespawnSeconds = 30, CorpseSeconds = 5 })` — these are the fallbacks a def (or per-mob
attribute) overrides.

## Out of scope (for now)

Pathfinding (mobs walk straight via `Humanoid:MoveTo` — open terrain), butchering carcasses into
yields (#13), and spawn-zone scattering (#16) are follow-ups that build on this substrate. Combat
(#12) is its first consumer — see [combat.md](combat.md).
