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

| Stat | Start | Rises to bad? | Behaviour in this version |
|---|---|---|---|
| Health | 100 | no (0 = bad) | display-only |
| Energy | 100 | no (0 = bad) | display-only |
| Hunger | 0 | **yes** (100 = starving) | rises over ~30 min |
| Thirst | 0 | **yes** (100 = dehydrated) | rises over ~20 min |
| Fatigue | 0 | **yes** (100 = exhausted) | rises over ~60 min |
| Poison | 0 | **yes** (100 = bad) | inert until a poison source |
| Blood | 100 | no (0 = death) | inert until a bleed source |

> Consequences (hunger/thirst draining energy, energy draining health, blood = 0 → death, …)
> and the energy/movement coupling arrive in later versions. This version is the stat
> simulation + HUD + tuning.

`Invert` (per stat) controls only the HUD: an inverted bar shows the *healthy* amount, so Hunger
(0 = fed) renders as a bar that **depletes** as you get hungry.

## Tuning — no code (recommended for creators)

The engine ships a **`SurvivalStatsConfig`** `Configuration` instance (in `ReplicatedStorage`).
It has one child `Configuration` per stat; edit their **Attributes** in Studio — no Lua:

| Attribute | Meaning |
|---|---|
| `RatePerSecond` | signed change per second (`+` rises toward `Max`, `−` falls toward 0) |
| `Max` / `Start` | range and spawn value |
| `WarnAt` | warn when the displayed bar drops below this percent |
| `Invert` | bar full = healthy |
| `Display` | show this stat in the HUD |

Edits take effect **live** — drag `Thirst.RatePerSecond` up and thirst drains faster
immediately.

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

## The HUD — restyle it freely

The HUD is the `SurvivalHud` ScreenGui in **StarterGui**. Restyle anything — colors, gradients,
textures, position, fonts, add or remove bars — in Studio. The engine only ever drives each
bar's fill, so your styling is untouched.

**A stat bar** is any `GuiObject` that:
- carries a **`Stat`** attribute (the player-attribute name, e.g. `"Hunger"`), and
- contains a child **`GuiObject` named `Fill`** (the part the engine resizes/recolors).

Optional per-bar attributes (each defaults from the stat's config, so usually you set only
`Stat`): `Max`, `Invert`, `WarnAt`, `FillColor`, `WarnColor`, `FillAxis` (`"X"` or `"Y"`).

To add a bar: duplicate an existing one, change its `Stat` attribute. To remove one: delete it.
To re-skin: edit the `Fill` and surrounding elements however you like. (Bars tagged
`SurvivorStatBar` work too — handy for the upcoming Builder UI.)

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

See also: [Extending SurvivorCore](extending.md) · [Architecture](architecture.md).
