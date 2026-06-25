# Combat (melee + ranged)

> 📹 **Demo:** [melee hits, bows & arrows, and creating weapons/ammo/mobs in the admin plugin](https://makertube.net/w/tyn8JEMG3CaMbTXid8osdU)

Combat ([`src/systems/Combat.luau`](../src/systems/Combat.luau)) is **server-authoritative** and
reuses the v0.4.0 **client-input → RemoteEvent → server-validated-hit** pipeline (the same shape as
[harvesting](harvesting.md)). The client only *requests* an attack; the server validates everything —
equipped weapon, range, line-of-sight, cooldown — and decides the hit. It never trusts the client.

Targets are anything with a `Humanoid`: engine [mobs](mobs.md) (always damageable) and, when
`Config "Combat".FriendlyFire` is on, other players. Damage flows through `Humanoid:TakeDamage`, so a
player victim's **survival Health HUD updates with no extra wiring** and death/respawn is clean.

## Weapons are items

A weapon is just an **`Items` def** with `category = "weapon"`, a `toolType` (so the hotbar→Tool
bridge equips it as a real `Tool`), and flat `weapon*` fields. Flat attributes keep weapons fully
[no-code-authorable](content-authoring.md) (the admin plugin's **Weapons** editor writes exactly
these):

```lua
SurvivorCore.Items.register({
    id = "wood_club",
    name = "Wooden Club",
    category = "weapon",
    toolType = "club",        -- lets the hotbar equip it
    weaponKind = "melee",     -- "melee" | "bow"
    weaponDamage = 20,
    weaponRange = 8,          -- melee reach (server-validated)
    weaponCooldown = 0.6,
})

SurvivorCore.Items.register({
    id = "short_bow",
    name = "Short Bow",
    category = "weapon",
    toolType = "bow",
    weaponKind = "bow",
    weaponDamage = 34,            -- base; multiplied by the arrow's ammoDamage and the draw
    weaponDrawTime = 1,           -- seconds to a full-power draw (the bow's "pullback")
    weaponProjectileSpeed = 200,
    weaponMaxRange = 260,         -- studs (fallback if the arrow sets no ammoRange)
    weaponAmmo = "arrow",         -- the arrow id consumed per shot ("" = no ammo)
})
```

## Melee

Equip a melee weapon from the hotbar and **click**. The client
([`CombatInput`](../src/client/CombatInput.luau)) asks the server to swing; the server finds the
nearest valid target within `weaponRange` (falling back to `Combat.MeleeRange`) with line-of-sight
and applies `weaponDamage`. A registered swing animation (`Assets "WeaponAnims"` by `toolType`) plays
client-side.

## Ranged (bow) — the aiming flow

Bows use a TCE-style two-button aim ([`CombatInput`](../src/client/CombatInput.luau)):

1. **Hold right-click to aim** — the camera shifts over-the-shoulder (`Humanoid.CameraOffset`) and
   zooms (FOV), and a **crosshair + charge ring** appear.
2. **Hold left-click to draw** — the ring fills and greens up over `weaponDrawTime`.
3. **Release left-click to fire** along the crosshair; **release right-click** exits aim.

The client sends the **world point under the crosshair** (a camera-centre ray); the server recomputes
the true direction from the bow's own muzzle (killing shoulder-camera parallax and any spoofed
direction), times the draw itself (anti-cheat), consumes one `weaponAmmo` arrow from the inventory
(**no arrows → no shot**), and **simulates the arrow authoritatively** — a gravity arc stepped as
short raycasts. It sends back the arc's **path**, and the client flies a cosmetic arrow along that
exact curve. The melee and bow paths route by the equipped Tool's `WeaponKind`, so they coexist with
harvesting without ever double-firing.

## Arrows — configurable, weighted ammo

An **arrow is its own item** (`category = "ammo"`), authored in code or via the admin **Arrows / Ammo**
editor — so a game can ship many arrow types with different ballistics. A shot **combines the bow's
pullback with the arrow's stats** and the draw strength:

| Arrow field | Effect |
|---|---|
| `ammoDamage` | × the bow's `weaponDamage` (e.g. `1.4` = +40%) |
| `ammoDrop` | × gravity — **the curve**; heavier arrows (`> 1`) arc steeply and fall short |
| `ammoRange` | caps the flight in studs (`0` = use the bow's `weaponMaxRange`) |
| `ammoSpeed` | × the bow's projectile speed (`0` = use the bow's speed) |
| `weight` | carry weight per arrow (the inventory cost of ammo) |

```lua
SurvivorCore.Items.register({
    id = "heavy_arrow", name = "Heavy Arrow", category = "ammo",
    weight = 0.12, stack = 16,
    ammoDamage = 1.4,   -- hits harder
    ammoDrop = 2,       -- doubles gravity → a pronounced arc
    ammoSpeed = 0.85,   -- a touch slower
    ammoRange = 140,    -- short effective range
})
```

Final shot = `damage = weaponDamage × ammoDamage × draw`, `speed = (bow speed × ammoSpeed) × draw`,
`gravity = Combat.Bow.Gravity × ammoDrop`, `range = ammoRange or weaponMaxRange or Combat.Bow.MaxRange`.
Draw strength scales from `Combat.Bow.MinDrawDamageMult` (no draw) to full (full draw). Point a bow's
`weaponAmmo` at any arrow id to set its ammo.

## The kill-event schema (designed once)

Both paths fire the same schema, through **`Hooks`** (engine extension) **and `EventBridge`**
(analytics / quests / achievements):

| Event | Payload |
|---|---|
| `combat:hit` | `{ attacker, victim, weapon, source, damage, victimHpLeft }` |
| `combat:kill` | `{ attacker, victim, weapon, source }` — `source` = `"melee"` \| `"bow"` |

This replaces the scattered, content-specific kill events a survival game tends to grow
(`zombie_killed` / `animal_killed` / `pvp_kill` / `bow_kill` / …) with one schema every consumer
subscribes to. A mob's own death also fires the lifecycle `mob:died` (see [mobs.md](mobs.md)) — the
two are complementary: `combat:kill` is attacker-attributed, `mob:died` is the creature lifecycle.

```lua
SurvivorCore.Hooks.on("combat:kill", function(ctx)
    if ctx.source == "bow" then awardArcheryXp(ctx.attacker) end
end)
```

## Runtime & tuning

`SurvivorCore.Combat` boots with the engine (after Inventory + Mobs). Tuning:

```lua
Config.override("Combat", {
    MeleeRange = 8, MeleeCooldown = 0.6, RequireLineOfSight = true, FriendlyFire = false,
    Bow = { Gravity = 80, ProjectileSpeed = 180, MaxRange = 300, MinDrawDamageMult = 0.3, StepSize = 4 },
})
```

Per-weapon `weapon*` values override these fallbacks. **Out of scope:** durability, blocking/parrying,
and AoE are creator content via the hooks above; mob AI lives in [mobs.md](mobs.md).
