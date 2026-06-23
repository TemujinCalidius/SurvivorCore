# Inventory, Hotbar & Menu UI

SurvivorCore ships a complete, server-authoritative **inventory** with a **slots + carry-weight**
model, a quick-use **hotbar**, **equipment** slots, and a restyleable **tabbed menu** (Inventory +
Character Sheet, with Codex / Achievements / Quests scaffolded). Like the survival HUD, the UI is a
**template + binder**: you author/restyle the ScreenGui in Studio, and the engine drives only data
(icons, counts, fills) — never layout or colors. The engine ships **zero items**; your game registers
them, and their display data replicates to clients automatically.

- **Data layer (server):** [src/systems/Inventory.luau](../src/systems/Inventory.luau)
- **UI (client):** `PanelManager`, `InventoryUi`, `Hotbar`, `CharacterSheet`, `DragDrop`, `SlotGrid`,
  `UiFallback` under [src/client/](../src/client)
- **Templates:** [assets/ui/SurvivalMenu.model.json](../assets/ui/SurvivalMenu.model.json),
  [assets/ui/SurvivalHotbar.model.json](../assets/ui/SurvivalHotbar.model.json)
- **Tuning:** the `Inventory` and `UI` Config sections.

---

## The model: slots + weight

Every player has a number of inventory **slots** and a **carry-weight** limit. Items **stack** (up to
the item's `stack`) and each unit has a **weight**. `add` fails (returns `false`) when a pickup would
exceed either limit. Equipping a **backpack** raises *both* the slot count and the weight limit.

All state is stored as **Player Attributes**, which Roblox auto-replicates to the owning client — so
the UI needs no read RemoteEvents (the same model as the survival stats). Defaults live in the
`Inventory` Config section:

```lua
SurvivorCore.Config.override("Inventory", {
    BasePocketSlots = 5,      -- slots with no backpack
    BasePocketWeight = 5,     -- kg with no backpack
    HotbarSize = 9,           -- quick-use slots (keys 1-9)
    UseCooldownSeconds = 2.0, -- anti-spam on consuming
    EquipSlots = { "head", "top", "pants", "shoes", "back", "quiver" },
    AutoHotbarCategories = { "tool", "weapon", "placeable", "consumable" },
})
```

---

## Item definitions

The inventory reads these fields off your `Items` registry defs. All are optional except `id`
(the engine tolerates anything missing). Register items **before** `SurvivorCore.start()`:

```lua
SurvivorCore.Items.register({
    id = "berry",
    name = "Wild Berries",
    description = "Tart and filling.",
    stack = 20,               -- max per slot (default 1)
    weight = 0.05,            -- per-unit carry weight (default 0)
    category = "consumable",  -- used for auto-hotbar; freeform otherwise
    icon = "rbxassetid://…",  -- display icon (see "Icons" below)
    onConsume = { Hunger = -15, Thirst = -5 }, -- makes it a consumable
})

SurvivorCore.Items.register({
    id = "reed_satchel",
    name = "Reed Satchel",
    weight = 0.8,
    equipment = { slot = "back" },          -- equips into the Back slot
    backpack = { slots = 6, maxWeight = 10 }, -- +6 slots, +10 kg when equipped
})

SurvivorCore.Items.register({
    id = "straw_hat",
    name = "Straw Hat",
    equipment = { slot = "head" }, -- head / top / pants / shoes / back / quiver
})
```

**`onConsume` keys are stat names**, passed straight to the stat-effects layer
(`Stats.adjust`). SurvivorCore afflictions *rise* toward `100 = bad`, so **feeding lowers them**
(`Hunger = -15`) and a **cure drives one to zero** (`Poison = -100`). No special tags — it's all data.

---

## Server API

Available on `SurvivorCore.Inventory` after `start()` (all act on live players, server-only):

| Call | Effect |
|---|---|
| `add(player, itemId, n?)` → `bool` | Weight/stack-checked; fills partial stacks then empties. Auto-pins hotbar-eligible items. `true` only if **all** placed. |
| `remove(player, itemId, n?)` → `bool` | Removes across slots (newest first). `false` if the player has fewer. |
| `getQty(player, itemId)` → `number` / `has(player, itemId, n?)` → `bool` | Totals across slots. |
| `getSlots(player)` → `{ {slot,itemId,qty} }` | Read-only snapshot. |
| `move(player, from, to)` / `swap(...)` | Merge same item up to stack, else swap. |
| `split(player, slot, qty)` | Split into the first free slot. |
| `equip(player, invSlot, slot?)` / `unequip(player, slot)` → `(bool, reason?)` | Equip/unequip; `back` recomputes capacity and enforces unequip rules. |
| `setHotbar(player, slot, itemId?)` | Pin (itemId) / unpin (nil) a hotbar slot. |
| `swapHotbar(player, a, b)` | Reorder the hotbar. |
| `useSlot(player, hotbarSlotOrItemId)` | Use/consume an item. |

```lua
SurvivorCore.Inventory.add(player, "stone_axe", 1) -- e.g. on a pickup; auto-hotbars tools
```

Gathering is wired for free: when a `Gatherable` is fully harvested, the engine grants its
`Yield × ItemId` into the player's inventory (via the `gather:depleted` hook).

---

## Hooks

| Hook | Payload | Fires when |
|---|---|---|
| `inventory:changed` | `{ player, kind, itemId?, equipSlot? }` | Any inventory mutation (`add`/`remove`/`move`/`use`/`equip`/…). |
| `item:use` | `{ player, itemId, def, slot? }` | **Every** successful consume — the seam for eat animations, sounds, or stopping a poison tick via `Stats.removeModifier`. |

```lua
SurvivorCore.Hooks.on("item:use", function(ctx)
    -- e.g. play a chewing sound, or clear an ongoing affliction the item cures
end)
```

---

## The UI

The menu and hotbar are authored ScreenGui templates driven by attribute-discovering binders —
**restyle them in Studio with zero code**, exactly like the HUD. The binder finds elements by
attribute and drives only their data.

### Open it

Press **Tab** (configurable) to toggle the menu; **C / K / J / L** jump to the Character / Codex /
Achievements / Quests tabs. Hotbar keys **1-9** use the pinned item. Drag items between slots, onto
the hotbar to pin, and right-click a hotbar slot to unpin.

> **Drag-to-drop is intentionally a no-op.** Dragging an item out to empty space does nothing yet —
> dropping items to the world (loot bags, drop-on-death) is the deferred world-drop system (#19).
> When that lands it registers a catch-all drop target. (Dragging is driven by a per-frame cursor
> poll, not `InputChanged`, so it works even though the inventory grid is a `ScrollingFrame` that
> would otherwise swallow the gesture.)

> **Tab & the player roster.** Roblox's CoreGui owns Tab (it toggles the built-in player list) and
> consumes the keypress before any game script sees it — and ContextActionService can't out-rank
> CoreGui. So when the Menu keybind collides with a core key, the engine disables that core element
> to free the key (the same way it hides the default health bar and backpack). This is on by default;
> set `Config.override("UI", { ReclaimCoreKeys = false })` to keep Roblox's stock player list (e.g. if
> you rebind Menu off Tab). The toggle also never fires while a TextBox is focused.

> **Chat placement.** The HUD lives in the top-left, where Roblox's chat sits too, so the client moves
> the chat window (modern TextChatService) to the **bottom-left** by default. Change the alignment, or
> opt out, via `Config.override("UI", { Chat = { Reposition = false } })` (run on the client before
> `startClient()`).

### Template attribute conventions

| Attribute (on a GuiObject) | Children the binder drives | Meaning |
|---|---|---|
| `InventoryTab` = id | optional `Selected` | A tab button; click shows the matching `TabContent`. |
| `TabContent` = id | — | The content shown when its tab is active. |
| `InventoryGrid` = true | one `SlotTemplate` child | Slots are cloned from the template to fill `MaxInvSlots`. |
| `SlotTemplate` = true | `Icon`, `Count`, `Selected` | The prototype slot (drag source + click-to-select). |
| `WeightReadout` = true | `Fill`, `Value` | Carry-weight bar + text. |
| `SlotReadout` = true | `Value` | "used / max slots". |
| `ItemDetail` = true | `Icon`, `Name`, `Description`, buttons `Action`=use/equip/hotbar/split | Selected-item detail strip. |
| `HotbarSlot` = 1..9 | `Icon`, `Count`, `Key`, `Active` | A hotbar slot. |
| `EquipSlot` = name | `Icon`, `Name` | An equipment slot (head/top/pants/shoes/back/quiver). |
| `AttributeReadout` = attr | `Value` | Shows a Player attribute (the seam for equipment-driven attributes). |

If no template ever reaches the player, a deliberately minimal `UiFallback` builds one with the same
attributes, so the UI always works.

### Adding your own tab

```lua
-- client, after startClient():
SurvivorCore.UI.registerPanel({
    id = "map", title = "Map", order = 6,
    build = function(contentFrame) -- fill the (empty) tab content once
        -- … build your panel UI here …
    end,
})
SurvivorCore.UI.open("map") -- open / close / toggle by id
```

---

## Icons

Item icons resolve **per item `icon` field → the `ItemIcons` Assets category → "" (hidden)**. A fresh
engine shows clean, empty slots — never a broken-image box. Supply icons either way:

```lua
-- inline on the def:
SurvivorCore.Items.register({ id = "berry", icon = "rbxassetid://…", … })
-- or via the registry (handy for bulk / theming):
SurvivorCore.Assets.register("ItemIcons", "berry", "rbxassetid://…")
```

Because item registration happens server-side but the UI runs on the client, the engine replicates
each item's **display data** (name, icon, stack, equip slot, consumable flag) automatically at
`start()` — your game registers items once, server-side, and the UI just works. See the icon-style and
generation guidance in [design-language.md](design-language.md).

---

## What's deferred

Dropping items to the world / loot bags (#19), physical `Tool` instances + equip-to-swing (#1),
equipment **attribute modifiers** (armor → defense — a future layer on the `inventory:changed` hook),
durability, spoilage, and the 2D backpack grid are intentionally out of this slice. The seams are
marked in the code.
