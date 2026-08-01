# SurvivorCore Studio (the admin plugin)

A **Studio plugin** that gives the experience owner friendly forms instead of hand-editing
Attributes in the Explorer. One **SurvivorCore › Studio** toolbar button opens one **floating
window** (drag-dock it anywhere) with a sidebar of editors:

- **Overview** — is the engine synced, what content exists (click through), how the model works.
- **Build** — select a Part or Model in the viewport, answer **"what is this object?"**, and fill a
  form: it becomes a gatherable node, a mob, or a quest giver. No tags to memorise, no attribute
  names to type. See [Build: world objects](#build-world-objects) below.
- **Survival Stats** — tune the survival-stat rates/thresholds/HUD on the `SurvivalStatsConfig`
  instance (the deltas-only, locked model below), with an Edit-mode **HUD preview**.
- **Engine Config** — every engine Config section (issue #21): Movement (speeds, energy, audio,
  feedback **asset ids**), Combat + Bow, Mobs & AI, Harvesting, Crafting, Inventory, Consequences,
  Loot bags, Quests, Achievements, and **UI & theme** (keybinds, chat placement, layout — and the
  full **Theme**: colors edited as `R, G, B` with a live swatch, fonts by name). Same deltas-only
  model, persisted on **`SurvivorCoreEngineConfig`**; edits apply on the **next Play**.
- **Content** — create/edit/delete **items**, **weapons**, **arrows**, **gatherable resources**,
  **mobs**, **quests** and **achievements** with no code, one page per category with entry counts —
  plus **Overrides** that tune defs registered *from code* (issue #40, below). Gatherables/mobs get
  **+ Add to World**, weapons **+ Tool model**, quests **+ Quest giver**. See
  [content-authoring.md](content-authoring.md).

The **search box** at the top of the sidebar finds any content entry by id or name across every
category and shows fully **editable** results in place. The window remembers your last-open page.
Every edit is one Studio **undo** step (and undo/redo refreshes the forms).

This is the [Builder / Admin plugin](https://github.com/TemujinCalidius/SurvivorCore/issues/11).

> **Upgrading from the tabbed panel?** The window identity changed (`SurvivorCore Studio`), so
> Studio forgets the old panel's dock position **once** — the new window opens floating; dock it
> wherever you like and Studio remembers from then on.

> 📹 **Demos:** [HUD, survival stats & the admin plugin](https://makertube.net/w/xqX7wfRpTqd9L9BkozCS1P) · [no-code item & gatherable creation](https://makertube.net/w/mCneurjoY3Av6yi48VsGQE) · [no-code weapon, ammo & mob creation](https://makertube.net/w/tyn8JEMG3CaMbTXid8osdU) · [no-code quest & achievement creation](https://makertube.net/w/uSGJ2MHEFjSSKxMiJBJ6Y5) · [SurvivorCore Studio — the no-code admin window](https://makertube.net/w/g4oySJeXD4Th7f1zYEu9Bz) · [Build — a plain Part into a working iron node](https://makertube.net/w/2kkyPbDWqoyuKcgbiCGwQG)

## Install

> **This is a Studio editor tool, not game content — so syncing the engine does _not_ install it.**
> A Rojo sync (or the drop-in `SurvivorCore.rbxm`) populates a *place's* `ReplicatedStorage`. The
> plugin is different: it lives in Studio's **local plugins folder** and runs in the editor across
> every place you open. You install it **once**, separately from any place.

Build it straight into your local plugins folder:

```bash
rojo build plugin.project.json --plugin SurvivorCoreStatAdmin.rbxm
```

The `--plugin` flag writes the built model into Studio's plugins folder for you:

| OS | Plugins folder |
|---|---|
| macOS | `~/Documents/Roblox/Plugins/` |
| Windows | `%LOCALAPPDATA%\Roblox\Plugins\` |

(Prefer to place it by hand? Build to a file instead — `rojo build plugin.project.json -o
SurvivorCoreStatAdmin.rbxm` — and drop it into that folder, or open it from Studio → **Plugins** tab
→ **Plugins Folder**.)

Then **restart Studio** — a brand-new plugin's toolbar only registers when Studio loads it. (After
this first install, re-running the `--plugin` build hot-reloads the plugin live, no restart needed.)
A **SurvivorCore › Studio** button then appears on the **Plugins** ribbon tab; click it to toggle
the window.

> **Open a place that has the engine in it.** The plugin edits whatever place is open, reading the
> stat roster and the Engine Config schema live from `ReplicatedStorage.SurvivorCore` — so sync the
> engine (or drop in `SurvivorCore.rbxm`) first. With no engine present it opens to an
> instructional empty state and writes nothing. Note that restarting Studio drops an *unsaved*
> Rojo-synced place, so reconnect Rojo and re-sync (or save the place before restarting) to bring
> the engine back.

## Build: world objects

The **Build** page is how a creator turns their *own* geometry into engine content. Select a Part or
Model and it asks **"What is this object?"** — pick **Gatherable**, **Mob (creature)** or **Quest
giver** and the plugin applies the tag for you, then renders that component's setup form.

The form is generated from the **engine's own component schema**
([`src/components/Schema.luau`](../src/components/Schema.luau)) — the same source the engine binds
from — so the fields, their defaults and their help text can never drift from what actually runs.
**Any component that declares a schema gets a form here automatically; there is no per-component UI
code.**

### Your first tree, in 60 seconds

1. **Author the resource.** *Content › Gatherables › + Create* → id `oak_tree`, yields item `wood`,
   HP 4.
2. **Build the mesh.** Insert a Part (or your own tree model) and select it.
3. **Say what it is.** Open **Build** → click the **Gatherable** card.
4. **Point it at the resource.** In the form, click the **⌄** next to *Resource* until it reads
   `oak_tree` — that's it; item, HP, tool and yield all follow the entry.
5. **Play.** Walk up and hold **E**. Wood lands in your inventory.

Change your mind later: **Change type** swaps the component (clearing the old one's settings), and
**Clear** removes the tag and every attribute the engine added.

### How it behaves

- **Deltas only.** Applying a component writes **no attributes** — the object follows every default
  until you change something, and a changed field that you set back to its default is removed again.
  The ○/● dot next to each field tells you which is which.
- **Pickers, not memory.** Fields that reference authored content (a resource, a mob type, a quest)
  offer a **⌄** that cycles the ids you've created in *Content*.
- **Eligibility is enforced.** *Mob* needs a Model (Humanoid + PrimaryPart), so it's dimmed with the
  reason when a plain Part is selected.
- **Multi-select** applies to every eligible object at once, as one undo step.
- **Undo** — every apply, clear and field edit is a single Studio undo step.
- **Needs SurvivorCore ≥ 0.9.** Against an older engine the page explains that instead of failing.

> Components a game defines **at runtime** (in its own code) can't appear here — the plugin reads a
> static module in Edit mode, where your server scripts haven't run. Tag those by hand as before.

## Survival Stats

Each stat shows the seven tunable fields, each displaying its **effective** value (your override if
you've set one, otherwise the live engine default):

- **Rate / second** — how fast the stat drifts (the headline knob).
- **Max**, **Start**, **Warn at %** — range, spawn value, warning threshold.
- **Display** — whether it shows on the HUD.
- **Icon** — the HUD icon asset id.
- **Value format** — `fraction` (`99/100`) · `percent` · `value` · `none`.

Edit a field (type a number / click to toggle or cycle) and it's applied immediately — stats apply
**live**, no restart. The dot at the left of a row is **filled + blue when that field is
overridden**, hollow when it's following the engine default. Click the dot to **reset** the field.

The plugin can tune **only** the seven owner-facing fields above. It deliberately **cannot** touch
`Invert` or `DangerHigh` — those are engine-owned stat *semantics*; a guardrail makes them
impossible to write.

### Preview the HUD in Edit mode

Roblox doesn't run the HUD's client binder in Studio's **Edit** view, so an authored `SurvivalHud`
normally shows its static template there. The footer's **Preview HUD** button paints, in Edit, what
the running game *would* render: each bar's resolved icon (including your overrides), a sample
partial fill, and a sample value readout — so you can tune and **see the result without pressing
Play**. **Clear** restores the HUD; both are a single **undo** step.

## Engine Config

Every page under **Engine Config** edits one engine Config section with the exact same row model as
the stats editor (override dot, engine-default placeholder, blue = overridden). Differences worth
knowing:

- **Persisted on `SurvivorCoreEngineConfig`** (a Configuration in ReplicatedStorage, one child per
  section, one grandchild per group) — created on your first real override, deltas-only, never
  seeded, never overwritten by the engine.
- **Applies on the next Play / server start.** The engine layers the instance over its defaults as
  the very first step of `start()`/`startClient()` — before any system boots — so live-reading and
  boot-caching systems all agree. (Survival Stats stay live-applied; everything else is
  boot-applied. The footer reminds you.)
- **Theme colors** are edited as `R, G, B` (0–255) with a live **swatch**; **fonts** by
  `Enum.Font` name (the ↻ button cycles common ones; any valid name can be typed). Invalid values
  are rejected in the form, and a hand-authored bad attribute is **warned about and skipped at
  boot** — never fatal.
- **Reset section** (footer) removes every override on that page in one undo step.
- The two Inventory **lists** (equip slots, auto-hotbar categories) are code-managed — set them
  via `Config.override("Inventory", …)`.
- **After re-syncing an UPDATED engine** (one whose config fields/defaults changed), restart
  Studio — Studio caches required modules per session, so the plugin keeps seeing the old schema
  until it reloads.

Resolution order everywhere: **engine default → `Config.override(...)` in your game code → the
instance (highest)**. Fields you never touched keep following engine defaults across updates —
that's the locked model.

## Content: authored entries & overrides

Each category page lists the **merged roster**:

- **Authored entries** — full defs this plugin created under `SurvivorCoreContent/<Category>`;
  every field editable, **Delete** removes the def.
- **Override entries** (blue *override* pill) — **deltas over a def registered from code** (e.g. a
  starter kit's `SurvivorCore.Items.register{...}`). Code-registered defs can't be listed here in
  Edit mode (registries fill at runtime), so: type the id, click **+ Override**, and set **only the
  fields you want to change** — **blank = inherit** the code value (booleans cycle
  `(inherit) → true → false`). **Remove** deletes the override and the pristine code def returns on
  the next Play. A typo'd id can only be caught at runtime: the engine **warns in Output on Play**
  (`override 'x' matches no registered def`).

Overrides live under `SurvivorCoreContent/Overrides/<Category>` and are field-merged onto the
registered defs at `start()` — before anything caches or replicates, so tooltips, recipes and
gatherables all see the merged values. One caveat: on a **code-registered quest** with nested
objective/reward tables, the flat `objective*`/`reward*` override fields are ignored (name/
description/autoStart/requires/turnIn still merge); overrides of no-code quests merge fully.

## Why your tuning is "locked" — it survives re-syncs and engine updates

The engine resolves configuration as **engine default → `Config.override` → your instance
(highest priority)**, and it never overwrites your instances. The plugin builds on that with the
**deltas-only** rule:

- It **writes an attribute only when you change a field from the engine default.**
- **Resetting** a field (or typing the default back in) **removes** the attribute, so the field
  goes back to following the engine default.

So two good things hold across a SurvivorCore update:

1. **Your explicit overrides are never lost** — they live on your instances, which the engine never
   overwrites.
2. **Fields you didn't touch keep following engine defaults** — so a future release that improves a
   default reaches your game, instead of being frozen at today's value.

> **Caveat — the engine's own demo.** In this repo's demo, config instances are *Rojo-mounted*, so
> a `rojo serve` re-sync reverts plugin edits there. That's a demo artifact: a **real** game keeps
> its instances in the place file, so plugin edits persist across engine updates — which is the
> whole point.

---

See also: [Survival Stats + HUD](survival-stats.md) · [Content authoring](content-authoring.md) ·
[Design Language](design-language.md).
