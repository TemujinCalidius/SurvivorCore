# Extending SurvivorCore

SurvivorCore ships **mechanics, not content**. You bring the items, world, art, and rules;
the engine wires up behavior. There are three ways to plug in, in rough order of how often
you'll reach for them:

1. **[Registries](#1-registries--register-content-from-code)** — register content from code
   (`Items`, `Recipes`, `Stats`, `Mobs`, …).
2. **[Components](#2-components--tag-your-own-objects)** — tag your own objects and set
   Attributes; no engine-side definition needed.
3. **[Hooks](#3-hooks--react-to-engine-lifecycle-events)** — react to engine lifecycle events
   to add game-specific flourish without forking the engine.

Two foundation services — [`Config`](#config--tune-the-engine) and
[`Assets`](#assets--keep-ids-out-of-code) — support all three.

Everything below assumes you've required the engine and will call `SurvivorCore.start()`
**once, from the server, after** registering your content:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivorCore = require(ReplicatedStorage:WaitForChild("SurvivorCore"))
```

---

## 1. Registries — register content from code

A registry is an empty table the engine owns and your game fills. Every registry shares the
same lifecycle — `register` a definition, it's validated and indexed by a key field, and you
query it back. The engine ships **zero** concrete entries.

```lua
SurvivorCore.Items.register({ id = "reed", name = "Reed", stack = 20 })
SurvivorCore.Items.register({ id = "reed_basket", name = "Reed Basket", stack = 1 })

SurvivorCore.Recipes.register({
    id = "reed_basket",
    station = "hand", -- "hand", "campfire", … — just a routing tag
    ingredients = { { item = "reed", count = 5 } },
    output = { item = "reed_basket", count = 1 },
})
```

### The registries

| Registry | Key field | What it holds |
|---|---|---|
| `Items` | `id` | Item definitions (name, stack size, …). |
| `Recipes` | `id` | Crafting **and** cooking recipes — one registry, routed by `station`. |
| `Stats` | `name` | Survival/status stat models. |
| `Achievements` | `key` | Achievement definitions. |
| `Codex` | `id` | Discoverable lore / collectible entries. |
| `Appearance` | `id` | Character appearance options. |
| `Mobs` | `id` | Creature / hostile-mob definitions. |

### Shared API (every registry)

```lua
local Items = SurvivorCore.Items

Items.register(def)            -- add one; errors on missing/duplicate key
Items.registerMany({ a, b })   -- add several
Items.get("reed")              -- fetch by key, or nil
Items.getAll()                 -- array of every def
Items.query(function(d)        -- filtered array
    return d.stack == 1
end)
```

Some registries add convenience helpers — e.g. recipes by station:

```lua
SurvivorCore.Recipes.forStation("campfire")
SurvivorCore.Stats.defineStat({ name = "Thirst", max = 100 }) -- alias of Stats.register
```

---

## 2. Components — tag your own objects

When the *content is a Roblox object you built*, you don't need a code-side definition at all.
Tag your mesh with a [CollectionService](https://create.roblox.com/docs/reference/engine/classes/CollectionService)
tag and set per-instance **Attributes**; the engine binds behavior to it.

The flagship component is `Gatherable`. Build any part/mesh, tag it `Gatherable`, and set:

| Attribute | Type | Meaning |
|---|---|---|
| `ItemId` | string | what it yields |
| `Yield` | number | amount per full harvest |
| `HP` | number | interactions to deplete |

That's it — the engine adds a ProximityPrompt and runs the harvest loop. Attributes can be set
in Studio's Properties panel or from code; a future builder UI will set them visually.

### Defining your own component

```lua
SurvivorCore.Components.define({
    name = "Campfire",
    tag = "Campfire",
    attributes = { -- attribute name -> default value
        FuelSeconds = 60,
        Lit = false,
    },
    onSetup = function(instance, values)
        -- `values` is the resolved attributes (instance value, else the default).
        -- Wire up prompts, signals, etc. here.
    end,
})
```

`SurvivorCore.start()` calls `Components.scan()` for you, which binds everything currently
tagged and keeps binding new instances as they appear. Each instance is bound once (guarded by
an internal `_scBound` attribute).

---

## 3. Hooks — react to engine lifecycle events

Hooks are where game-specific flourish lives **outside** the engine. Where a registry says
"here is my content" and a component says "here is my object," a hook says "engine, when X
happens, run my code." This is how The Counter Earth's trees physically fall and segment into
logs while SurvivorCore itself ships none of that.

```lua
SurvivorCore.Hooks.on("gather:depleted", function(ctx)
    -- ctx = { instance, player, values }
    spawnFallingTreePhysics(ctx.instance)      -- your game's flair
    grantBonusDrop(ctx.player, ctx.values.ItemId)
end)
```

`Hooks.on` returns a disconnect function:

```lua
local disconnect = SurvivorCore.Hooks.on("gather:hit", function(ctx)
    -- ctx = { instance, player, values, hpLeft }
    flashOutline(ctx.instance)
end)
-- later: disconnect()
```

Engine systems fire hooks with `Hooks.run("name", ctx)`. Today the `Gatherable` component
fires:

| Hook | Context |
|---|---|
| `gather:hit` | `{ instance, player, values, hpLeft }` — each interaction. |
| `gather:depleted` | `{ instance, player, values }` — final hit, before the instance is destroyed. |

More hooks land as systems are extracted (`craft:start`/`craft:end`, mob lifecycle, …).

### Hooks vs. EventBridge

- **Hooks** = "the engine is about to / just did X — creators, do your thing here." Scoped,
  lifecycle-shaped extension points.
- **[EventBridge](architecture.md#foundation)** = a semantic event *bus* for things that
  happened (`animal_killed`, …), which any number of decoupled subscribers (achievements,
  quests, analytics, a webhook) can observe:

```lua
local disconnect = SurvivorCore.Events.onFire(function(eventType, player, data)
    if eventType == "animal_killed" then
        analytics:track(player, "hunt", data)
    end
end)
```

---

## `Config` — tune the engine

The engine declares default tunables per section; your game overrides them via deep merge.

```lua
-- (engine declares defaults internally, e.g.)
-- Config.defineSection("Energy", { DrainPerSecond = 16, RegenPerSecond = 14 })

SurvivorCore.Config.override("Energy", { DrainPerSecond = 10 }) -- your tweak
SurvivorCore.Config.get("Energy.DrainPerSecond")               -- 10
```

## `Assets` — keep IDs out of code

The engine **never** hardcodes asset IDs — your game registers them and the engine reads them
back, with a safe empty-string fallback if one's missing. This is a hard rule for engine code
and the right pattern for your content too.

```lua
SurvivorCore.Assets.register("Sounds", "Harvest", "rbxassetid://123456789")
SurvivorCore.Assets.registerCategory("Animations", {
    Idle = "rbxassetid://111",
    Chop = "rbxassetid://222",
})

SurvivorCore.Assets.get("Sounds", "Harvest") -- "rbxassetid://123456789"
```

---

## Putting it together

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivorCore = require(ReplicatedStorage:WaitForChild("SurvivorCore"))

-- content
SurvivorCore.Items.register({ id = "reed", name = "Reed", stack = 20 })
SurvivorCore.Assets.register("Sounds", "Harvest", "rbxassetid://123456789")

-- flourish
SurvivorCore.Hooks.on("gather:depleted", function(ctx)
    print(ctx.player.Name, "harvested", ctx.values.ItemId)
end)

-- go
SurvivorCore.start()
```

See [Getting Started](getting-started.md) to wire the engine into your place, and
[Architecture](architecture.md) for how the layers fit together.
