# Changelog

All notable changes to SurvivorCore are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project aims to follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). At release time, `## Unreleased`
is promoted to the new version and `main` is tagged `vX.Y.Z`.

## Unreleased

### Fixed
- **Custom stat `attribute` overrides now work end to end** (#20) — the HUD bound stat bars by the
  stat *name*, but the engine stores each value under the stat's backing `attribute` (overridable
  via `Config.override("SurvivalStats", { Stat = { attribute = "…" } })`), so an override silently
  froze the bar. The binder now reads + listens on the resolved `attribute`; the same hardcoded-name
  slip in the Health↔Humanoid sync and the energy (vignette/breathing) feedback is fixed too.
  Default behaviour (attribute defaults to the name) is unchanged.

## 0.2.0 — 2026-06-20

### Added
- **Survival consequences** — stats now bite back (server-authoritative, all tunable via the
  `Consequences` Config section): **starving** (Hunger maxed) and **dehydrated** (Thirst maxed)
  drain health; **poison drains health at 100%**; **Blood at 0 → bleed out (instant death)**.
  Health drains stack and reduce real character health, so death + respawn happen naturally.
  **Energy stops regenerating** while starving, dehydrated, or fully fatigued (even after the
  post-sprint delay). The engine now syncs the **Health** stat to the character Humanoid (the HUD
  bar reflects real damage), **hides Roblox's built-in health GUI** in favour of the HUD bar, and
  **resets all stats + clears modifiers on respawn** (no death-loop). Default drift is slow and
  realistic — Hunger/Thirst ~8 h, Fatigue ~24 h, and ~8 h more to die of starvation/dehydration.
- **Sprinting, jumping & energy** — hold **Shift** to sprint (server-authoritative): it drains
  the Energy stat, speeds you up, and forces an exhausted crawl at 0 energy; energy regenerates
  after a short idle delay. Jumps cost energy and are blocked below a threshold. Ships a low-stat
  **feedback** layer too — a screen vignette + breathing loop that intensify as energy drops, and
  a heartbeat loop below 40% health. Adds the engine's first RemoteEvent (`SprintIntent`) and a
  `Movement` Config section (`Config.override("Movement", …)`). Logic + tuning + free default art
  ported from The Counter Earth. See [docs/survival-stats.md](docs/survival-stats.md).
- **Dynamic stat effects** — a per-player, server-side modifier layer over the base rates, so
  stats can be driven by events instead of only a constant drift. `SurvivorCore.Stats.adjust`
  (one-time clamped delta), `addModifier` / `removeModifier` (named, optionally-timed rate
  modifiers; effective rate = base + Σ active), and `getValue`. This is the foundation for poison
  ticking until cured, bleeding until clotted, and sprint draining energy. Modifiers are dropped
  when a player leaves. See [docs/survival-stats.md](docs/survival-stats.md).
- **Survival-stats engine + built-in HUD** (#8, #2) — a server tick simulates per-stat
  drain/regen, stored as auto-replicating Player Attributes, and a reactive **top-left HUD**
  renders them (no RemoteEvents). The HUD is a real, designer-editable `SurvivalHud` ScreenGui
  in StarterGui — restyle it in Studio with zero code; bars bind by a `Stat` attribute and a
  `Fill` child. It's a translucent panel that shows **Health + Energy** by default and **expands**
  to the full roster, with per-bar **numeric readouts** (`99/100` / `%`, configurable) and per-stat
  **icons** — the engine ships a free default icon set (baked into `StatDefs` + the HUD template),
  so the HUD is iconed out of the box and the icons even show in Studio's **Edit** view, no Play
  needed. Afflictions
  (Hunger/Thirst/Fatigue/Poison) read as empty-when-safe and fill up as they worsen (`dangerHigh`),
  and the header carries a **credits** readout (a bar-less `Counter` bound to a Player attribute).
  HUD icons resolve per bar/counter and update **live** — a game can swap art at runtime by setting
  the `Icon` attribute, or override the shipped defaults per stat (config / admin plugin / `Assets`).
  Ships with seven default stats (health/energy/hunger/thirst/fatigue/blood/
  poison), tunable **without code** via a `SurvivalStatsConfig` Configuration instance (or, for
  developers, `Config.override("SurvivalStats", …)` / `Stats.defineStat`). Works out of the box
  for every distribution — the demo/Rojo source mount it, the drop-in `.rbxm` auto-installs it
  on `start()`, and a runtime fallback guarantees a HUD always appears. Adds the engine's first
  client layer (`SurvivorCore.startClient()`). See [docs/survival-stats.md](docs/survival-stats.md).
- **Survival Stats admin plugin** (#11, first slice) — a Studio dock widget to tune the survival
  stats from a validated form instead of hand-editing Attributes. It writes **deltas only** (an
  attribute only when a field differs from the engine default; removed on reset / edit-back), so
  owner tuning survives engine updates while untouched fields keep following improvable defaults,
  and a hard guardrail makes the engine-owned `Invert`/`DangerHigh` semantics impossible to write.
  Built as a separate `plugin.project.json` Rojo target (install via
  `rojo build plugin.project.json --plugin …`); CI lints and builds it too. Includes a reversible
  **edit-mode HUD preview** (Preview / Clear) that paints resolved icons + sample fills onto the
  StarterGui HUD, so owners see play-time styling without pressing Play.
  See [docs/admin-plugin.md](docs/admin-plugin.md).
- **Continuous integration** (`.github/workflows/ci.yml`) — every push to `main`/`dev` and
  every PR runs `stylua --check`, `selene`, `luau-lsp analyze` (against a Rojo sourcemap +
  Roblox type defs), then builds **all three** Rojo targets — `default.project.json` (the drop-in
  engine model), `demo.project.json` (the runnable demo place), and `plugin.project.json` (the
  admin plugin) — to prove they compile.
- **Changelog enforcement** (`.github/workflows/changelog.yml`) — PRs must update
  `CHANGELOG.md` unless they carry the `skip-changelog` label.
- **Contributor guide** (`CONTRIBUTING.md`) — prerequisites, local dev setup, code style,
  the `dev`/`main` branching model, PR flow, and the engine conventions (no hardcoded asset
  IDs, content via `register()`/components, content-free core).
- **Issue & PR templates** — bug-report and feature-request issue forms (Studio / Rojo
  plugin versions, repro), a PR template (changelog, CI, no secrets, no hardcoded asset IDs),
  and a Discussions link for questions.
- **Toolchain pins** for `stylua`, `selene`, and `luau-lsp` added to `rokit.toml`, plus
  `stylua.toml`, `selene.toml`, and `.luaurc` so local dev and CI lint/format/analyze
  identically.
- **Docs** — a getting-started/install guide (Rojo + Wally and the drop-in `.rbxm`) and an
  "Extending SurvivorCore" guide (the `register()` API, the component/attribute model, Hooks).
- **README** — a "See it live" pointer to [The Counter Earth](https://thecounterearth.com)
  (the engine's closed-Alpha showcase) and a GitHub Sponsors section.

### Changed
- The release workflow now cross-posts each tagged release to Discussions → **Announcements**
  (`discussion_category_name` + `discussions: write`).

### Fixed
- `Components` attribute reading (`src/components/init.luau`) no longer iterates an optional
  union; it guards the optional first. Behavior is unchanged — this clears a `luau-lsp`
  type-analysis error so CI starts green.

## 0.1.0 (2026-06-18)

### Added
- **Foundation scaffold.** The core plumbing every layer builds on:
  - `Config` — engine-default tuning sections that games override via deep merge.
  - `Assets` — a typed asset-id registry; the engine never hardcodes IDs.
  - `EventBridge` — a semantic event bus (`fire`/`onFire`) that decouples subscribers from
    sources.
  - `Hooks` — lifecycle extension points (`Hooks.on("gather:depleted", …)`) so game-specific
    flourish stays out of the engine.
  - `Registry` — the shared register/validate/index/query lifecycle behind every registry.
- **Content registries** — empty `Items`, `Recipes` (crafting + cooking, routed by
  `station`), `Stats`, `Achievements`, `Codex`, `Appearance`, and `Mobs` registries the game
  populates at startup. The engine ships zero concrete content.
- **Component layer** — the creator-facing `Gatherable` component (tag your own mesh, set
  `ItemId`/`Yield`/`HP` attributes) over a generic `Components.define`/`scan` framework.
- **Public API** — `SurvivorCore.start()` and the dot-callable surface
  (`SurvivorCore.Items.register{…}`, `SurvivorCore.Hooks.on(…)`, …).
- **Runnable demo** (`demo/`) and a `demo.project.json` Rojo target that mounts the engine
  under `ReplicatedStorage.SurvivorCore` and exercises both extension layers.
- **Release pipeline** (`.github/workflows/release.yml`) — builds `SurvivorCore.rbxm` from
  source and attaches it to each `v*` tag's GitHub Release.
- **Docs & project setup** — `README.md`, `docs/architecture.md`, MIT `LICENSE`, `rokit.toml`
  (rojo + wally pins), and `wally.toml` package metadata.
