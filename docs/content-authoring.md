# No-code content authoring

The engine ships **zero** items, resources, or recipes — your game supplies them. You can do this
two ways, and they coexist:

1. **From code** — `SurvivorCore.Items.register{…}`, `SurvivorCore.Resources.register{…}`,
   `SurvivorCore.Recipes.register{…}` before `start()` (see the demo `Boot.server.luau`).
2. **No-code, as instances** — author content in the place and the engine loads it at `start()`.
   The **admin plugin's Content widget** writes exactly this for you.

## The `SurvivorCoreContent` folder

At `start()`, the engine reads `ReplicatedStorage.SurvivorCoreContent` and registers any defs found:

```
ReplicatedStorage
└─ SurvivorCoreContent
   ├─ Items      (Folder)
   │  └─ berry   (Configuration)   ← child Name = item id
   │     • name = "Wild Berries"        ← attributes = def fields
   │     • stack = 20
   │     • weight = 0.05
   │     • category = "consumable"
   ├─ Resources  (Folder)
   │  └─ berry_bush (Configuration)
   │     • item = "berry"
   │     • hp = 4
   │     • requireTool = ""    (blank = bare-hand)
   │     • yieldMin = 1
   │     • yieldMax = 3
   └─ Tools      (Folder)        ← actual Tool templates the hotbar equips (named by item id)
```

Each child's **Name is the id**; its **attributes are the def fields**
([`Registry.loadFromFolder`](../src/foundation/Registry.luau) copies them verbatim). This is the
same instance-config pattern the survival stats use.

## The admin plugin Content widget

Open Studio → the **SurvivorCore** toolbar → **Content**. Two builders:

- **Items** — create an item by id, then set Name / Max stack / Weight / Category / Tool type /
  Icon / Description.
- **Gatherables** — create a resource by id, then set Yields item / HP (gathers) / Tool required /
  Yield min / Yield max.

Each edit is one Studio **undo** step. Behind the scenes it creates/edits the
`SurvivorCoreContent` instances above, so pressing Play registers your content with no code.

## Binding a world object

A creator builds any mesh, tags it **`Gatherable`** (CollectionService), and sets a `Resource`
attribute to a resource id (e.g. `"berry_bush"`). The node inherits item/HP/tool/yield from the def.
See [harvesting.md](harvesting.md) for the full attribute list and the per-type **reaction** hooks
(shake / fell / etc.).

## Tools

For a tool item, set `toolType` (e.g. `"axe"`) and `category = "tool"`. To give it a custom look,
place a `Tool` named by the item id under `SurvivorCoreContent.Tools`; otherwise the engine equips a
plain default. Trees etc. require the matching `RequireTool`.
