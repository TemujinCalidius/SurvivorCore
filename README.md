<div align="center">

<img src="site/assets/img/logo-256.png" alt="SurvivorCore" width="120" />

# SurvivorCore

**A batteries-included, creator-extensible survival game engine for Roblox.**

[![Release](https://img.shields.io/github/v/release/TemujinCalidius/SurvivorCore?include_prereleases&color=5ACD78)](https://github.com/TemujinCalidius/SurvivorCore/releases)
[![CI](https://github.com/TemujinCalidius/SurvivorCore/actions/workflows/ci.yml/badge.svg)](https://github.com/TemujinCalidius/SurvivorCore/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**[🌐 Website](https://temujincalidius.github.io/SurvivorCore/)** · **[📖 Docs](docs/)** · **[📹 Demo](https://makertube.net/w/tyn8JEMG3CaMbTXid8osdU)** · **[⬇ Releases](https://github.com/TemujinCalidius/SurvivorCore/releases)**

</div>

> **Status: v0.5.0 — pre-release.** The core survival loop is in and working; the engine is
> being grown toward v1.0 and APIs may still shift. Production-tested in
> [The Counter Earth](https://thecounterearth.com).

## What it is

SurvivorCore gives you the *mechanics* of a survival game — without dictating your *content*.
You bring the items, world and art; the engine wires up the behavior, the UI, and the no-code
authoring tools. If you know Roblox Studio, you can build a survival game.

- **Survival stats & HUD** — health, energy, hunger, thirst, fatigue, blood, poison; ticking,
  draining, and biting back, on a clean restyleable HUD.
- **Inventory, hotbar & crafting** — slots + carry-weight, a 9-slot hotbar, equipment, and hand
  crafting in a tabbed, drag-and-drop menu — server-authoritative.
- **Gathering** — tag any mesh `Gatherable`: hold-E or tool-swing, per-hit yields, and reaction
  hooks (a reed sways; a tree fells and leaves a stump).
- **Combat — melee & bow** — click to swing, or aim a bow and loose arrows that arc under real
  weight. One server-validated `combat:hit` / `combat:kill` schema.
- **Mobs & AI** — a shared FSM substrate: hostile mobs chase & attack, passive animals flee.
  Behavior is data — a mob's `faction` picks the profile.
- **No-code admin plugin** — create items, weapons, ammo and mobs from a Studio form (damage,
  range, arrow curve, weight, aggro, leash) and drop them into the world. No scripting.

Everything is **content-free by design**, **server-authoritative**, and **restyleable** — the UI
is real Instances driven by attributes, and every default is overridable.

## Quickstart

```lua
local SurvivorCore = require(ReplicatedStorage.SurvivorCore)

-- register content from code (or author it no-code in the admin plugin)
SurvivorCore.Items.register({ id = "berry", name = "Wild Berries", stack = 20 })
SurvivorCore.Mobs.register({ id = "husk", faction = "hostile", health = 60 })

SurvivorCore.start()  -- boots stats, inventory, gathering, crafting, combat, mobs…
```

The built-in HUD loader calls `SurvivorCore.startClient()` for you.

**Install** — drop `SurvivorCore.rbxm` from a [Release](https://github.com/TemujinCalidius/SurvivorCore/releases)
into `ReplicatedStorage`, or add it via [Wally](https://wally.run):

```toml
# wally.toml
[dependencies]
SurvivorCore = "temujincalidius/survivorcore@0.5.0"
```

Working from source? Clone and `rojo serve` the `demo.project.json` place.

## Creator-owned, no code

Build *any* mesh, tag it with a component, set attributes — no engine-side definition needed:

| Tag | Set | It becomes |
|---|---|---|
| `Gatherable` | `Resource = "oak_tree"` | a harvestable node (item/HP/tool/yield from the def) |
| `Mob` | `MobType = "husk"` | a creature that runs the AI FSM |

For game-specific flourish (a tree that physically fells, a custom death effect), hook the engine
lifecycle instead of forking it:

```lua
SurvivorCore.Gather.onReaction("oak_tree", "depleted", function(ctx) fellTrunk(ctx.instance) end)
SurvivorCore.Hooks.on("combat:kill", function(ctx) awardXp(ctx.attacker) end)
```

The **admin plugin** turns all of this into Studio forms — see
[docs/admin-plugin.md](docs/admin-plugin.md) and [docs/content-authoring.md](docs/content-authoring.md).

## Docs

[Architecture](docs/architecture.md) · [Survival stats + HUD](docs/survival-stats.md) ·
[Inventory](docs/inventory.md) · [Harvesting](docs/harvesting.md) · [Crafting](docs/crafting.md) ·
[Combat](docs/combat.md) · [Mobs & AI](docs/mobs.md) · [No-code content](docs/content-authoring.md) ·
[Admin plugin](docs/admin-plugin.md) · [Design language](docs/design-language.md) ·
[Extending](docs/extending.md)

## Project layout

```
src/
  init.luau          -- SurvivorCore root: .start() / .startClient() + the public API
  foundation/        -- Config, Assets, EventBridge, Hooks, Reactions, Registry
  registries/        -- Items, Recipes, Resources, Stats, Mobs, …
  components/         -- creator-facing tag/attribute components (Gatherable, Mob)
  systems/           -- Inventory, Harvesting, Crafting, Combat, Mobs, SurvivalStats…
  client/            -- HUD + UI binders, combat/harvest input
plugin/              -- the Studio admin plugin (separate Rojo tree)
demo/                -- a runnable demo place that consumes the engine
site/                -- the landing page (deployed to GitHub Pages)
docs/                -- documentation
```

## Sponsor

SurvivorCore is free and open source. If it's useful — or you just want to help the engine grow —
support development via [GitHub Sponsors](https://github.com/sponsors/TemujinCalidius). 💛

## License

[MIT](LICENSE) © 2026 Samuel Lison
