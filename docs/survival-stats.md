# Survival Stats + HUD

SurvivorCore ships a survival-stat simulation and a reactive **top-left HUD**. It's batteries-
included — register nothing and you already get seven stats and a working HUD — but every rate
is tunable, and the HUD is a real ScreenGui you restyle in Studio with **zero code**.

## How it works

- Each stat value lives as a **Roblox Player Attribute** on the player (e.g. `Hunger`). Roblox
  replicates attributes to that player's client automatically, so the HUD reads them directly —
  **no RemoteEvents**.
- A server tick (10 Hz) moves each stat by its signed **rate per second** toward `0` or its
  `Max`, clamped.
- The HUD binds each bar to its stat's attribute and re-renders on change.

`SurvivorCore.start()` (server) boots the simulation. The client HUD is booted by
`SurvivorCore.startClient()`, which the built-in HUD's loader does for you.

## The default stats

| Stat | Start | Rises to bad? | Behaviour |
|---|---|---|---|
| Health | 100 | no (0 = bad) | real character health (death + respawn); HUD-synced |
| Energy | 100 | no (0 = bad) | sprint/jump drain, regen at rest ([Sprint](#sprint-jump--energy)) |
| Hunger | 0 | **yes** (100 = starving) | rises over ~8 h; maxed → drains health |
| Thirst | 0 | **yes** (100 = dehydrated) | rises over ~8 h; maxed → drains health |
| Fatigue | 0 | **yes** (100 = exhausted) | rises over ~24 h; maxed → blocks energy regen |
| Poison | 0 | **yes** (100 = bad) | drains health **at 100%** |
| Blood | 100 | no (0 = death) | bleeds while wounded; 0 → bleed out → death |

> Starving/dehydrated/fatigued also **stop energy regenerating**. See
> [Consequences](#consequences--when-stats-bite-back) for the full rules + tuning.

Bar **fill direction is engine-owned**: a stat that's *dangerous when high* (Hunger, Thirst,
Poison…) fills **up** as it worsens and sits empty when you're safe, while a resource (Health,
Blood…) depletes toward empty. You don't set this per stat — it follows the stat's semantics. (A
custom HUD can still flip an individual bar with a per-bar `Invert` attribute; see the HUD section.)

## Tuning — no code (recommended for creators)

The engine ships a **`SurvivalStatsConfig`** `Configuration` instance (in `ReplicatedStorage`).
It has one child `Configuration` per stat; edit their **Attributes** in Studio — no Lua:

| Attribute | Meaning |
|---|---|
| `RatePerSecond` | signed change per second (`+` rises toward `Max`, `−` falls toward 0) |
| `Max` / `Start` | range and spawn value |
| `WarnAt` | warn when the stat is within this percent of its dangerous end |
| `Display` | show this stat in the HUD |
| `Icon` | HUD icon asset id for this stat |
| `ValueFormat` | numeric readout: `fraction` · `percent` · `value` · `none` |

These seven are the only owner-tunable fields; bar-fill and danger direction are engine-owned (see
above). Edits take effect **live** — drag `Thirst.RatePerSecond` up and thirst drains faster
immediately.

**Prefer a form?** The [Survival Stats admin plugin](admin-plugin.md) is a Studio dock that edits
exactly these fields with validation, per-field reset and undo — and writes only what you change,
so your tuning survives engine updates.

## Tuning — code (for developers)

Both work, and both lose to the Studio `SurvivalStatsConfig` instance if it's present:

```lua
-- tweak shipped rates
SurvivorCore.Config.override("SurvivalStats", {
    Thirst = { ratePerSecond = 0.10 },
    Hunger = { ratePerSecond = 0 },
})

-- or add your own stat (it gets a HUD bar if a bar binds it)
SurvivorCore.Stats.defineStat({
    name = "Sanity", start = 100, max = 100, ratePerSecond = -0.05, invert = false, warnAt = 25, display = true,
})
```

**Precedence (last wins):** engine defaults → `Config.override` → the Studio `SurvivalStatsConfig`
instance.

## Dynamic effects — poison, bleeding, sprint drain (server)

The config rates above are the stat's **constant baseline drift** (e.g. hunger always creeps up).
But most survival behaviour is *event-driven and per-player*: a poison that ticks until you take an
antidote, a cut that bleeds until you bandage it, sprinting that drains energy until you stop. Those
aren't a static number — so the engine layers two **server-side** runtime operations on top of the
baseline (available on `SurvivorCore.Stats` once `start()` has run):

```lua
-- one-time signed delta, clamped to 0..max (a hit, a cost, eating)
SurvivorCore.Stats.adjust(player, "Poison", 1)          -- "you got 1 poison" → now 1/100
SurvivorCore.Stats.adjust(player, "Hunger", -30)        -- ate food

-- a named, optionally-timed rate modifier; effective tick rate = base + Σ(active modifiers)
SurvivorCore.Stats.addModifier(player, "Poison", { ratePerSecond = 2, source = "venom" })
SurvivorCore.Stats.removeModifier(player, "Poison", "venom")   -- antidote → ticking stops
SurvivorCore.Stats.getValue(player, "Energy")           -- read the current value
```

So the patterns you'd expect fall out directly:

| Scenario | Calls |
|---|---|
| Poisoned, ticks up to 100 | `adjust(+1)` then `addModifier("Poison", {ratePerSecond = 2, source = "venom"})` |
| Antidote / it wears off | `removeModifier("Poison", "venom")`, or pass a `duration` so it auto-expires |
| Cut bleeds out | `addModifier("Blood", {ratePerSecond = -1.5, source = "cut"})` |
| Bandage / clot | `removeModifier("Blood", "cut")` |
| Sprinting drains energy | `addModifier("Energy", {ratePerSecond = -drain, source = "sprint"})` while held |
| Resting / furniture regen | a positive `Energy` modifier (per-furniture strength) |

A modifier with the same `source` replaces the old one (no implicit stacking); a `duration` (seconds)
makes it expire on its own; a player's modifiers are dropped when they leave. These are **server-only**
(authoritative) — drive them from your gameplay code, never trust the client.

## Sprint, jump & energy

The engine ships a server-authoritative movement system that spends the **Energy** stat (ported
from The Counter Earth's proven tuning):

- **Hold Shift** to sprint — the client sends intent over the `SprintIntent` RemoteEvent; the
  server speeds the character up (`SprintSpeed`) and drains energy while you're actually moving.
- At **0 energy** you're forced to a slow `ExhaustedSpeed` until it recovers.
- **Energy regenerates** after `RegenDelaySeconds` of not exerting (and not moving).
- **Jumps cost energy** (`JumpCost`) and are **blocked below `MinToJump`** (JumpPower drops to 0).

It's all tunable via the **`Movement`** Config section — no engine edits:

```lua
SurvivorCore.Config.override("Movement", {
    Energy = { SprintDrainPerSecond = 20, RegenPerSecond = 10, JumpCost = 8 },
    Movement = { SprintSpeed = 28, WalkSpeed = 16, ExhaustedSpeed = 6, JumpPower = 80 },
})
```

**Low-stat feedback (client).** A full-screen **vignette** + a **breathing** loop fade in as energy
drops, and a **heartbeat** loop fades in below `Health.HeartbeatStartRatio` (40%) of health. The
engine ships default art for these (overridable under `Movement.Assets` / the audio + ratio knobs
in the same section). It boots automatically from `SurvivorCore.startClient()`.

## Consequences — when stats bite back

Letting a stat reach its dangerous extreme now has teeth (server-authoritative, all rates in the
`Consequences` Config section). Health drains **stack** and reduce the character's **real** health,
so death + Roblox respawn happen naturally:

| Condition | Effect |
|---|---|
| **Starving** — Hunger at max | drains health (~8 h to die) **+ stops energy regen** |
| **Dehydrated** — Thirst at max | drains health (~8 h to die; both at once → ~4 h) **+ stops energy regen** |
| **Fatigued** — Fatigue at max | **stops energy regen** |
| **Poisoned** — Poison at 100% | drains health (`1.0`/s) — only once fully poisoned |
| **Bled out** — Blood at 0 | drains health fast (`3.0`/s) — you bleed out and die |

Energy refusing to regen while starving/dehydrated/fatigued holds **even after the post-sprint
delay** — a depleted player stays depleted until they address the cause.

```lua
SurvivorCore.Config.override("Consequences", {
    HealthDrainPerSecond = { Starving = 100 / (8 * 3600), Dehydrated = 100 / (8 * 3600), PoisonAtMax = 1.0, BledOut = 3.0 },
    Affliction = { BleedRatePerSecond = 100 / 3600, PoisonRatePerSecond = 100 / 3600 }, -- ~1h each
})
```

The engine keeps the **Health** stat in sync with the character's Humanoid (so the HUD Health bar
reflects real damage), and on every (re)spawn **resets all stats and clears modifiers** — a fresh
body, so injuries never carry across death. Drive poison/bleeding from gameplay with the
[dynamic effects](#dynamic-effects--poison-bleeding-sprint-drain-server) API; persistence + a
loot-on-death flow are tracked in [issue #19](https://github.com/TemujinCalidius/SurvivorCore/issues/19).

## The HUD — restyle it freely

The HUD is the `SurvivalHud` ScreenGui in **StarterGui**. Restyle anything — colors, gradients,
textures, position, fonts, add or remove bars — in Studio. The engine only ever drives each
bar's fill, value text, and icon, so your styling is untouched.

**Layout.** The shipped template is a translucent **`Panel`** containing a **`Header`** (title +
the expand `Toggle`), a **`Primary`** group (always visible — Health + Energy), and a
**`Collapsible`** group (the rest, hidden until the player clicks the toggle). Move a bar between
`Primary` and `Collapsible` by drag-and-drop to change what shows by default.

**A stat bar** is any `GuiObject` that:
- carries a **`Stat`** attribute (the player-attribute name, e.g. `"Hunger"`), and
- contains a child **`GuiObject` named `Fill`** (the part the engine resizes/recolors).

Optional per-bar **children** the binder also drives if present: a `TextLabel` named **`Value`**
(filled with the numeric readout) and an `ImageLabel` named **`Icon`** (hidden until an icon id
resolves). Optional per-bar **attributes** (each defaults from the stat's config, so usually you
set only `Stat`): `Max`, `Invert`, `WarnAt`, `FillColor`, `WarnColor`, `FillAxis` (`"X"`/`"Y"`),
`ValueFormat` (`"fraction"` `99/100` · `"percent"` `99%` · `"value"` `99` · `"none"`), and `Icon`
(an asset-id override).

**Icons** resolve from the per-bar `Icon` attribute → the stat's `icon` config → the `Assets`
registry category **`StatIcons`** (key = stat name) — e.g. `SurvivorCore.Assets.register("StatIcons",
"Hunger", "rbxassetid://…")`. The engine now ships **default** icons for its built-in stats (as
each stat's `icon` default), so bars are iconed out of the box; the chain above replaces them.

**Collapse** is wired generically: a `GuiButton` with a **`HudToggle`** attribute (its value names
the container, e.g. `"Collapsible"`) toggles a container marked **`HudCollapsible`**. Both are also
discoverable by the names `Toggle`/`Collapsible` or matching CollectionService tags.

To add a bar: duplicate an existing one, change its `Stat` attribute. To remove one: delete it.
To re-skin: edit the `Fill` and surrounding elements however you like. (Bars tagged
`SurvivorStatBar` work too — handy for the upcoming Builder UI.)

## Providing your own HUD art

The engine ships **default** icons for its built-in stats, so the HUD is iconed out of the box (and
they show in Studio's Edit view, no Play needed). To use your own art, set any of these — first match wins:

1. set a bar's **`Icon`** attribute (or the credits/counter element's) to an asset id — **live**:
   the HUD renders it the instant it's set, so a game can assign art at runtime;
2. set the stat's **`Icon`** on the `SurvivalStatsConfig` instance / via `Stats.defineStat`;
3. register into the **`Assets`** registry:
   `SurvivorCore.Assets.register("StatIcons", "Hunger", id)` (category `StatIcons`, key = stat /
   counter name).

**Upload to your own account.** A Roblox image asset is owned by whoever uploads it, so the clean
model is **per-game**: each game uploads its own icons (to its account or group) and references
its own ids. That keeps your art private to your game, avoids cross-experience asset-permission
gating, and needs no Premium (image uploads are free, just rate-limited). To share a set publicly,
publish it to the Creator Store (moderated). The demo's example flat set lives in
`demo/assets/icons/` — drop them in and upload to your account, or generate your own (the icon
pipeline is in the [design language](design-language.md)).

## How it ships (and always appears)

You never have to wire the HUD up:

1. **Rojo source / the demo** mount the `SurvivalHud` template into StarterGui directly.
2. **The drop-in `SurvivorCore.rbxm`** carries the templates inside the model; `start()`
   installs them into StarterGui / StarterPlayerScripts / ReplicatedStorage if you haven't
   supplied your own.
3. If somehow no HUD is present, the client builds a **minimal fallback** so a HUD always shows.

Supply your own HUD (a ScreenGui in StarterGui with `Stat`-bearing bars) and the engine uses it
instead of installing the default.

## Editing the bundled template (contributors)

The template is version-controlled as JSON (`assets/hud/SurvivalHud.model.json`,
`assets/config/SurvivalStatsConfig.model.json`) and mounted by Rojo. **Rojo syncs files → Studio,
not back** — so if you restyle the template live during a `rojo serve` session, save your changes
back to the `.model.json` (or re-author and overwrite it); a plain Studio edit under an active
sync is overwritten on the next sync. For your *own game*, just edit the `SurvivalHud` ScreenGui
in your place — it persists there normally.

---

See also: [Admin plugin](admin-plugin.md) · [Extending SurvivorCore](extending.md) · [Architecture](architecture.md).
