# Harvesting (gathering)

SurvivorCore turns any part/mesh into a harvestable node via the **`Gatherable`** component, with
two interaction styles:

- **Bare-hand** — walk up, hold **E** (a `ProximityPrompt`). For reeds, berries, loose stone.
- **Tool-swing** — equip a tool, **click** to swing. The node requires a tool *type* (e.g. an axe)
  and takes several hits. This is the engine's first **client-input → server-validated-hit**
  pipeline (combat reuses it later).

Every hit is resolved server-side by [`src/systems/Harvesting.luau`](../src/systems/Harvesting.luau):
it validates, rolls a **per-hit yield** (`yieldMin..yieldMax`), tries to add it to the inventory
(**blocking the hit if you're full** — nothing wasted), then spends one HP and fires the hooks. On
depletion the node is destroyed (unless it opts out — see reactions).

> 📹 **Demo:** [chopping a tree, gathering reeds & hand crafting](https://makertube.net/w/b6RWPeiW6vLz4iVXuuiRtP)

## Defining a node

A node's stats come from a **resource def** (preferred) or raw per-node attributes.

### Resource defs (recommended)
Register once, reuse on every node — in code or [no-code via the admin plugin](content-authoring.md):

```lua
SurvivorCore.Resources.register({
    id = "oak_tree",
    item = "wood",       -- the item it yields (an Items id)
    hp = 5,              -- hits/gathers to deplete
    requireTool = "axe", -- tool type required ("" = bare-hand)
    yieldMin = 1,
    yieldMax = 2,        -- random yield per hit
})
```

Then a creator builds a mesh, tags it **`Gatherable`** (CollectionService), and sets one attribute:

| Attribute | Meaning |
|---|---|
| `Resource` | the resource def id to inherit from (e.g. `"oak_tree"`) |

### Raw attributes (overrides / quick nodes)
Any of these override the resource def (or stand alone without one):

| Attribute | Default | Meaning |
|---|---|---|
| `ItemId` | `""` | item yielded |
| `HP` | `3` | hits to deplete |
| `RequireTool` | `""` | tool type needed; `""` = bare-hand |
| `YieldMin` / `YieldMax` | `1` / `1` | random yield per hit (or legacy single `Yield`) |
| `Interaction` | `"auto"` | `"auto"` (tool if `RequireTool` set, else prompt), `"prompt"`, or `"tool"` |
| `DestroyOnDeplete` | `true` | `false` keeps the node so a reaction can transform it (stump/fell) |

## Tools

Tool-swing needs a held Roblox `Tool` whose **`ToolType`** attribute matches the node's
`RequireTool` (falling back to the Tool's `Name`). The hotbar does this for you: give an item a
`toolType` field and a `category` of `"tool"`, and selecting it in the hotbar equips a real `Tool`
(the **hotbar→Tool bridge**, [`src/systems/ToolEquip.luau`](../src/systems/ToolEquip.luau)). The
Tool's look is content-free: it clones a creator template from
`ReplicatedStorage.SurvivorCoreContent.Tools` (a `Tool` named by item id), or builds a minimal
default if none is registered.

## Reactions (the juice)

Global `Hooks.on("gather:hit"/"gather:depleted"/"gather:blocked", …)` fire for every node. For
behavior tied to **one** resource type, use the reaction API — no core edits:

```lua
SurvivorCore.Gather.onReaction("reed_bush", "hit", function(ctx)
    -- ctx = { instance, player, resource, item, granted, hpLeft, position }
    sway(ctx.instance)
end)
SurvivorCore.Gather.onReaction("oak_tree", "depleted", function(ctx)
    rezStumpAndFell(ctx.instance) -- the node had DestroyOnDeplete = false
end)
```

## Tuning

`Config.override("Harvesting", { SwingRange = 12, SwingCooldown = 0.45, RequireLineOfSight = true })`.

## Out of scope (for now)

Durability, multi-phase tree growth/regrow, and particle systems are creator content via the hooks
above — the engine ships none. Combat (#12) reuses this same swing pipeline.
