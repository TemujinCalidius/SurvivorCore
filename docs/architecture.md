# SurvivorCore — Architecture

> Companion to the boundary map in the TheCounterEarth repo
> (`docs/survivorcore-boundary-map.md`), which tracks what is being extracted from the
> production game into this engine.

## The shape

SurvivorCore is an **engine of mechanics, not content**. It exposes two extension layers
over a small foundation.

```
                ┌─────────────────────────────────────────────┐
   Creators →   │  Component layer   (tag + attributes + UI)   │  "I own the object"
                ├─────────────────────────────────────────────┤
   Developers → │  Registry layer    (register() from code)    │  "I own the data"
                ├─────────────────────────────────────────────┤
                │  Foundation: Config · Assets · EventBridge ·  │
                │              Hooks · Registry                 │
                └─────────────────────────────────────────────┘
```

### Foundation
- **Config** — engine ships default tunables per section; games override via deep merge.
- **Assets** — typed asset-id registry; the engine never hardcodes ids.
- **EventBridge** — semantic event bus (`fire`/`onFire`); subscribers decouple from sources.
- **Hooks** — lifecycle extension points (`Hooks.on("craft:start", ...)`).
- **Registry** — the shared register/validate/index/query lifecycle behind every registry.

### Registry layer (developers)
Empty registries the game populates at startup: `Items`, `Recipes` (crafting + cooking are
one registry routed by `station`), `Stats`, `Achievements`, `Codex`, `Appearance`, `Mobs`.

### Component layer (creators)
Behaviors bound to a CollectionService tag, configured by per-instance Attributes. Creators
tag their **own** meshes (`Gatherable`, and later craftable/huntable/farmable/station
components) and fill in values — optionally through a builder UI. No engine-side definition
required.

## Why hooks instead of baked-in behavior

Game-specific flourish stays out of the engine. TheCounterEarth's trees physically fall and
segment into logs — SurvivorCore will **not** ship that. Instead it fires
`gather:hit` / `gather:depleted` (and similar) hooks; a creator (including TheCounterEarth
itself, going forward) implements the felling physics in their own hook handler. The engine
stays small and universal; creativity lives at the edges.

## Status & roadmap

v0.1.0 is the foundation scaffold. Extraction order (from the boundary map): foundations →
pure-core lift → registries → SPLIT server systems (incl. the mob/combat cluster) → UI
layer → harvesting/wildlife sub-engine.

## Related docs

- [Getting Started](getting-started.md) — install via Rojo + Wally or the drop-in `.rbxm`.
- [Extending SurvivorCore](extending.md) — the `register()` API, the component/attribute
  model, and Hooks.
- [Survival Stats + HUD](survival-stats.md) — the stat simulation, no-code tuning, and the
  designer-editable HUD.
- [CONTRIBUTING](../CONTRIBUTING.md) — local dev setup, code style, and the branching model.
