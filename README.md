<div align="center">

# SurvivorCore

**A batteries-included, creator-extensible survival game framework for Roblox.**

</div>

> ⚠️ **Status: early scaffold (v0.1.0).** The foundation layer and architecture are in
> place; survival systems are being extracted from a production game ([The Counter
> Earth](https://github.com/TemujinCalidius/TheCounterEarth)) into this engine. APIs will
> change. Not yet production-ready.

## What it is

SurvivorCore gives you the *mechanics* of a survival game — stats (energy/hunger/thirst…),
inventory, crafting, cooking, harvesting, hostile mobs & combat, achievements, a codex, and
player persistence — without dictating your *content*. You bring your own items, world, and
art; the engine wires up the behavior.

## See it live

SurvivorCore powers **[The Counter Earth](https://thecounterearth.com)** — a full survival
game built on this engine, and its live showcase. The Counter Earth is in **closed Alpha**
(not yet open to beta testers), but SurvivorCore contributors and engine devs may get early
access — a good reason to [get involved](CONTRIBUTING.md). 👀

## Two ways to extend it

**1. Programmatic — register content from code:**

```lua
local SurvivorCore = require(ReplicatedStorage.SurvivorCore)

SurvivorCore.Items.register({ id = "reed", name = "Reed", stack = 20 })
SurvivorCore.Recipes.register({
    id = "reed_basket", station = "hand",
    ingredients = { { item = "reed", count = 5 } },
    output = { item = "reed_basket", count = 1 },
})

SurvivorCore.start()
```

**2. Creator-owned — attach behavior to your own objects:**

Build *any* mesh, tag it `Gatherable`, and set attributes — no engine-side definition needed:

| Attribute | Meaning |
|---|---|
| `ItemId` | what it yields |
| `Yield`  | amount per full harvest |
| `HP`     | hits to deplete |

The same pattern extends to craftables, huntables, farmables, and more. For advanced,
game-specific behavior (e.g. trees that physically fall and cut into pieces), hook into
engine lifecycle events instead of forking the engine:

```lua
SurvivorCore.Hooks.on("gather:depleted", function(ctx)
    -- your custom drop / VFX / physics here
end)
```

## Getting started

- **Developers** — consume via [Rojo](https://rojo.space) (clone + `rojo serve`) or, once
  published, as a [Wally](https://wally.run) package.
- **Drop-in** — grab `SurvivorCore.rbxm` from a [Release](../../releases) (auto-built from
  source via `rojo build`), drop it into `ReplicatedStorage`, and add a short bootstrap
  script that `require`s it and calls `.start()`.
- **Tuning, no code** — owners can adjust the survival stats from a Studio form with the
  [Survival Stats admin plugin](docs/admin-plugin.md). It's editor tooling, so it installs
  separately from the engine (built once into your Studio plugins folder).

## Project layout

```
src/
  init.luau            -- SurvivorCore root: .start() + the public API
  foundation/          -- Config, Assets, EventBridge, Hooks, Registry (the core plumbing)
  registries/          -- Items, Recipes, Stats, Achievements, Codex, Appearance, Mobs
  components/          -- creator-facing tag/attribute components (e.g. Gatherable)
demo/                  -- a runnable demo place that consumes the engine
docs/architecture.md   -- how the layers fit together
```

## Sponsor

SurvivorCore is free and open source. If it's useful to you — or you just want to help the
engine grow — you can support development via
[GitHub Sponsors](https://github.com/sponsors/TemujinCalidius). 💛

## License

[MIT](LICENSE) © 2026 Samuel Lison
