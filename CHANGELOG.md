# Changelog

All notable changes to SurvivorCore are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project aims to follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). At release time, `## Unreleased`
is promoted to the new version and `main` is tagged `vX.Y.Z`.

## Unreleased

### Added
- **Survival-stats engine + built-in HUD** (#8, #2) — a server tick simulates per-stat
  drain/regen, stored as auto-replicating Player Attributes, and a reactive **top-left HUD**
  renders them (no RemoteEvents). The HUD is a real, designer-editable `SurvivalHud` ScreenGui
  in StarterGui — restyle it in Studio with zero code; bars bind by a `Stat` attribute and a
  `Fill` child. It's a translucent panel that shows **Health + Energy** by default and **expands**
  to the full roster, with per-bar **numeric readouts** (`99/100` / `%`, configurable) and blank
  **icon slots** (filled from the `Assets` registry — the engine ships none). Ships with seven default stats (health/energy/hunger/thirst/fatigue/blood/
  poison), tunable **without code** via a `SurvivalStatsConfig` Configuration instance (or, for
  developers, `Config.override("SurvivalStats", …)` / `Stats.defineStat`). Works out of the box
  for every distribution — the demo/Rojo source mount it, the drop-in `.rbxm` auto-installs it
  on `start()`, and a runtime fallback guarantees a HUD always appears. Adds the engine's first
  client layer (`SurvivorCore.startClient()`). See [docs/survival-stats.md](docs/survival-stats.md).
- **Continuous integration** (`.github/workflows/ci.yml`) — every push to `main`/`dev` and
  every PR runs `stylua --check`, `selene`, `luau-lsp analyze` (against a Rojo sourcemap +
  Roblox type defs), then builds **both** `default.project.json` (the drop-in engine model)
  and `demo.project.json` (the runnable demo place) to prove they compile.
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
