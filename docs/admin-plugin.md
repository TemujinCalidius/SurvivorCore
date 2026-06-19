# Survival Stats admin plugin

A small **Studio plugin** that gives the experience owner a friendly form to tune the survival
stats — instead of hand-editing Attributes on the `SurvivalStatsConfig` instance in the Explorer.
It's the first slice of the [Builder / Admin plugin](https://github.com/TemujinCalidius/SurvivorCore/issues/11).

## Install

Build it straight into your Studio plugins folder, then restart Studio:

```bash
rojo build plugin.project.json --plugin SurvivorCoreStatAdmin.rbxm
```

(Or build to a file — `rojo build plugin.project.json -o SurvivorCoreStatAdmin.rbxm` — and drop it
into the local Plugins folder yourself: Studio → **Plugins** tab → **Plugins Folder**.)

A **SurvivorCore › Survival Stats** button appears in the toolbar; click it to toggle the dock widget.

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
