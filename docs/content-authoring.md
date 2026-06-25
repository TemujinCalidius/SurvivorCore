# No-code content authoring

> 📹 **Demos:** [creating mobs, weapons & ammo (with full stats)](https://makertube.net/w/tyn8JEMG3CaMbTXid8osdU) · [creating an item + gatherable](https://makertube.net/w/mCneurjoY3Av6yi48VsGQE)

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
   ├─ Weapons    (Folder)        ← items with category="weapon" (loaded into the Items registry)
   │  └─ wood_club (Configuration)
   │     • category = "weapon"
   │     • toolType = "club"          (lets the hotbar equip it)
   │     • weaponKind = "melee"       ("melee" | "bow")
   │     • weaponDamage = 20
   ├─ Arrows     (Folder)        ← items with category="ammo" (loaded into the Items registry)
   │  └─ heavy_arrow (Configuration)
   │     • category = "ammo"
   │     • ammoDamage = 1.4           (× the bow's damage)
   │     • ammoDrop = 2               (× gravity = the curve)
   │     • ammoRange = 140
   ├─ Resources  (Folder)
   │  └─ berry_bush (Configuration)
   │     • item = "berry"
   │     • hp = 4
   │     • requireTool = ""    (blank = bare-hand)
   │     • yieldMin = 1
   │     • yieldMax = 3
   ├─ Mobs       (Folder)
   │  └─ husk (Configuration)
   │     • faction = "hostile"        ("hostile" | "passive" | "neutral")
   │     • health = 60
   │     • aggroRange = 40
   ├─ Tools      (Folder)        ← Tool templates the hotbar equips (named by item id)
   └─ MobModels  (Folder)        ← rigged mob templates Mobs.spawn clones (named by mob id)
```

Each child's **Name is the id**; its **attributes are the def fields**
([`Registry.loadFromFolder`](../src/foundation/Registry.luau) copies them verbatim). This is the
same instance-config pattern the survival stats use.

## The admin plugin Content widget

Open Studio → the **SurvivorCore** toolbar → **Content**. Five builders:

- **Items** — create an item by id, then set Name / Max stack / Weight / Category / Tool type /
  Icon / Description.
- **Weapons** — create a weapon by id, then set Kind (melee/bow) / Damage / Range / Cooldown, plus
  bow Draw time / Arrow speed / Max range / Ammo item. (Weapons are items with `category = "weapon"`;
  they live in their own folder so this editor never collides with the Items editor.) **+ Tool model**
  drops a starter `Tool` (a Handle carrying the weapon's `ToolType`/`WeaponKind`) into the world so you
  can build the held look on it; move the finished Tool under `SurvivorCoreContent.Tools` (named by the
  weapon id) and the hotbar clones it when the weapon is equipped.
- **Arrows / Ammo** — create an arrow type by id, then set Damage × / Drop (curve) × / Max range /
  Speed × / Carry weight. A bow's *Ammo item* points at one of these. (Arrows are items with
  `category = "ammo"`, in their own folder — see [combat.md](combat.md).)
- **Gatherables** — create a resource by id, then set Yields item / HP (gathers) / Tool required /
  Yield min / Yield max. **+ Add to World** drops a tagged `Gatherable` node.
- **Mobs** — create a mob type by id, then set Faction / Health / Speeds / Aggro / Leash / Attack.
  **+ Add to World** drops a tagged `Mob` placeholder rig (swap in your own model later).

Each edit is one Studio **undo** step. Behind the scenes it creates/edits the
`SurvivorCoreContent` instances above, so pressing Play registers your content with no code.

## Binding a world object

A creator builds any mesh, tags it **`Gatherable`** (CollectionService), and sets a `Resource`
attribute to a resource id (e.g. `"berry_bush"`). The node inherits item/HP/tool/yield from the def.
See [harvesting.md](harvesting.md) for the full attribute list and the per-type **reaction** hooks
(shake / fell / etc.).

For creatures, tag a rigged Model (Humanoid + PrimaryPart) **`Mob`** and set `MobType` to a mob id
(e.g. `"husk"`); it inherits faction/health/speed/ranges from the def. See [mobs.md](mobs.md) and
[combat.md](combat.md).

## Tools

For a tool item, set `toolType` (e.g. `"axe"`) and `category = "tool"`. To give it a custom look,
place a `Tool` named by the item id under `SurvivorCoreContent.Tools`; otherwise the engine equips a
plain default. Trees etc. require the matching `RequireTool`.
