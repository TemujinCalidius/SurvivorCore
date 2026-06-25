# SurvivorCore admin plugin

A small **Studio plugin** that gives the experience owner friendly forms instead of hand-editing
Attributes in the Explorer. It adds two toolbar buttons under **SurvivorCore**:

- **Survival Stats** — tune the survival-stat rates/thresholds/HUD on the `SurvivalStatsConfig`
  instance (the deltas-only, locked model below).
- **Content** — create/edit/delete **items**, **weapons**, **gatherable resources** and **mobs** with
  no code (the Builder slice). It writes `SurvivorCoreContent` instances the engine loads at `start()`
  — see [content-authoring.md](content-authoring.md). Gatherables and mobs each get a **+ Add to
  World** button that drops the tagged instance in front of the camera. Unlike the stats editor,
  content is full owner-authored defs (not deltas). Every edit is one Studio undo step.

The rest of this page covers the Survival Stats editor; both install the same way. It's the
[Builder / Admin plugin](https://github.com/TemujinCalidius/SurvivorCore/issues/11).

> 📹 **Demos:** [HUD, survival stats & the admin plugin](https://makertube.net/w/xqX7wfRpTqd9L9BkozCS1P) · [no-code item & gatherable creation](https://makertube.net/w/mCneurjoY3Av6yi48VsGQE) · [no-code weapon, ammo & mob creation](https://makertube.net/w/tyn8JEMG3CaMbTXid8osdU)

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
A **SurvivorCore › Survival Stats** button then appears on the **Plugins** ribbon tab; click it to
toggle the dock widget.

> **Open a place that has the engine in it.** The plugin tunes the stats of whatever place is open,
> reading the live roster from `ReplicatedStorage.SurvivorCore` — so sync the engine (or drop in
> `SurvivorCore.rbxm`) first. With no engine present it opens to an instructional empty state and
> writes nothing. Note that restarting Studio drops an *unsaved* Rojo-synced place, so reconnect
> Rojo and re-sync (or save the place before restarting) to bring the engine back.

## Using it

Each stat shows the seven tunable fields, each displaying its **effective** value (your override if
you've set one, otherwise the live engine default):

- **Rate / second** — how fast the stat drifts (the headline knob).
- **Max**, **Start**, **Warn at %** — range, spawn value, warning threshold.
- **Display** — whether it shows on the HUD.
- **Icon** — the HUD icon asset id.
- **Value format** — `fraction` (`99/100`) · `percent` · `value` · `none`.

Edit a field (type a number / click to toggle or cycle) and it's applied immediately. The dot at the
left of a row is **filled + blue when that field is overridden**, hollow when it's following the
engine default. Click the dot to **reset** the field. Every edit is a single **undo** step.

It reads the stat roster + defaults live from the engine in the place, so it always reflects the
version you're running. With no engine synced it shows an instructional empty state and writes
nothing.

### Preview the HUD in Edit mode

Roblox doesn't run the HUD's client binder in Studio's **Edit** view, so an authored `SurvivalHud`
normally shows its static template there — full bars, blank readouts, and only the shipped *default*
icons (an icon override you set above isn't visible until you press Play). The footer's **Preview
HUD** button paints, in Edit, what the running game *would* render: each bar's resolved icon
(including your overrides), a sample partial fill, and a sample value readout — so you can tune and
**see the result without pressing Play**. **Clear** restores the HUD; both are a single **undo**
step. (Preview resolves icons exactly like the engine — per-bar `Icon` attribute › the stat's
effective `icon` — and edits the `SurvivalHud` in StarterGui, so on the Rojo-mounted demo a re-sync
also resets it.)

## Why your tuning is "locked" — it survives re-syncs and engine updates

This is the important part. The engine resolves each stat as **engine default → `Config.override` →
the `SurvivalStatsConfig` instance (highest priority)**, and it only ever *seeds* that instance
when it's missing — it never overwrites it. The plugin builds on that with a **deltas-only** rule:

- It **writes an attribute only when you change a field from the engine default.**
- **Resetting** a field (or typing the default back in) **removes** the attribute, so the field goes
  back to following the engine default.

So two good things hold across a SurvivorCore update:

1. **Your explicit overrides are never lost** — they live on your instance, which the engine never
   overwrites.
2. **Fields you didn't touch keep following engine defaults** — so a future release that improves a
   default rate reaches your game, instead of being frozen at today's value.

The plugin can tune **only** the seven owner-facing fields above. It deliberately **cannot** touch
`Invert` or `DangerHigh` — those are engine-owned stat *semantics* (which way a bar fills / which end
is dangerous); the engine ignores them on the instance, and a guardrail in the plugin makes it
impossible to write them.

> **Caveat — the engine's own demo.** In this repo's demo, `SurvivalStatsConfig` is *Rojo-mounted*,
> so a `rojo serve` re-sync reverts plugin edits there. That's a demo artifact: a **real** game seeds
> the instance once (install-if-absent, not Rojo-managed), so the plugin's edits persist across engine
> updates — which is the whole point.

---

See also: [Survival Stats + HUD](survival-stats.md) · [Design Language](design-language.md).
