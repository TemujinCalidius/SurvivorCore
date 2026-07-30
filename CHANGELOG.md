# Changelog

All notable changes to SurvivorCore are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project aims to follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). At release time, `## Unreleased`
is promoted to the new version and `main` is tagged `vX.Y.Z`.

## 0.9.0 — 2026-07-30

### Security
- **Bow shots are now rate-limited server-side.** The bow release handler enforced no cooldown — the
  one client-driven action in the engine that didn't — so a client could fire far faster than a bow's
  design rate, and each release costs the server up to `MaxRange / Bow.StepSize` raycasts to simulate
  the arc. The gate runs **before** the arrow is spent and before the simulation, honours a bow's own
  **`weaponCooldown`** (which previously only melee read, despite being offered for every weapon), and
  falls back to the new **`Combat.Bow.Cooldown`** (0.35s, tunable in SurvivorCore Studio). A release
  with no matching draw is rejected, `BowDraw` now validates the sender is alive and holding a bow,
  and aim points are checked for finiteness so a malformed one can't consume an arrow. Affects
  v0.8.0 and earlier.

### Added
- **Player interact window** — walk up to another player and an **"[E] Interact"** badge appears
  over *their* head; press **E** (or tap) to open a window with their name + survival stats and an
  **action list** (Trade ships built-in). Targeting is a client-side nearest-*other*-player scan, so
  it can never point at you — this **replaces** the earlier per-character server ProximityPrompt
  (which wrongly showed on your own character). Games extend it with
  `SurvivorCore.Interact.addAction{…}`; interact key is `UI.Keybinds.Interact` (default `E`). Ported
  from The Counter Earth. See [docs/interact.md](docs/interact.md).
- **Player trading** (#15) — secure, server-authoritative, **dupe-proof** face-to-face item swaps.
  Open a player's interact window and choose **Trade**; the target Accepts/Declines. The trade
  window is **self-contained** — your carried stacks are listed inside it (click to offer, "All" for
  the whole stack), so trading never depends on the separate inventory menu being open — and its
  header is a **drag handle** so it can be moved out of the way. Both stage loose backpack
  stacks (drag from the inventory grid, with −/+ qty steppers) and must **Confirm** before anything
  moves. The swap is one synchronous, no-yield commit — re-validate holds → pre-flight both
  receivers have room (new **`Inventory.canAccept`**) → remove both → grant with `addUpTo` → refund
  any residue — so item count is conserved on every path. Auto-cancels on death / leave / walking
  out of range (`MaxDistance`) / request timeout; a staging change resets both confirms. New
  `Trade` server system + `TradeUi` client window, the `"Trading"` Config section (tunable in
  SurvivorCore Studio), hooks `trade:started` / `trade:completed`, and a `trades_total` progression
  counter. v1 trades loose backpack stacks only (worn gear reserved behind `AllowEquippedItems`).
  See [docs/trading.md](docs/trading.md).

## 0.8.0 — 2026-07-16

### Added
- **Engine Config, no-code** (#21) — a new persisted instance, **`SurvivorCoreEngineConfig`**,
  layers owner overrides over EVERY engine Config section (Movement incl. feedback asset ids,
  Combat + Bow, Mobs, Harvesting, Crafting, Inventory scalars, Consequences, LootBags, Quests,
  Achievements, and UI incl. the full **Theme** — colors and fonts). Same locked, **deltas-only**
  model as `SurvivalStatsConfig`: an attribute exists only where the owner diverged from the
  engine default, so untouched fields keep following engine updates. Applied as the FIRST step of
  `start()`/`startClient()` (edits take effect on the next Play); invalid saved values warn and
  are skipped, never fatal. The schema (`src/shared/EngineConfig.luau`, ~94 typed fields across 11
  sections) is the single source of truth the plugin renders from.
- **Content overrides** (#40) — `SurvivorCoreContent/Overrides/<Category>` entries **field-merge
  onto defs registered from code** (previously untouchable no-code: the loader skips registered
  ids). Deltas-only: blank = inherit; deleting an override restores the code def; an id matching
  no def **warns at boot** (typo backstop). Applied before components bind and before the client
  data caches publish, so tooltips and gatherables see merged values. New
  `Registry.applyOverrides(folder)`.
- **SurvivorCore Studio** — the admin plugin rebuilt as its own **floating window** (drag-dockable,
  660×580 default) with a **sidebar**: Overview (engine status + content counts), Survival Stats,
  **Engine Config** (one page per section; color fields edited as `R, G, B` with a live swatch,
  fonts by name with a cycle button; per-section reset), and Content (one page per category with
  count badges, **+ Override** authoring, blue override pills). A rail **search box** finds any
  content entry by id/name across categories with editable results in place. Last-open page is
  remembered; undo/redo now refreshes the forms. New shared plugin visual system
  (`plugin/Theme.luau`) replaces the copy-pasted styling. *(Window identity changed — your old
  dock position resets once.)*

## 0.7.4 — 2026-07-06

### Fixed
- **Beacon scoped to the newest bag** — dying again mid corpse-run re-points the owner's beacon at
  the new bag (old and new bags coexist, each on its own 5-minute timer); previously the OLDER
  bag's later despawn/looting would wipe the beacon that pointed at the newer bag.

## 0.7.3 — 2026-07-06

### Fixed
- **Loot bag + beacon vanished on respawn (StreamingEnabled places)** — respawning away from the
  death spot let Roblox stream the bag out of the owner's client: the bag looked deleted and the
  local `Destroying` fired, killing the beacon. The bag is now a **stream-persistent Model for its
  owner** (`AddPersistentPlayer`), and the beacon is **position-driven plain data** — no Instance
  reference, so no replication race (the 0.5s delay is gone) and no streaming fragility. The beam
  clears on an explicit server signal when the bag is truly emptied/expired.

## 0.7.2 — 2026-07-06

### Fixed
- **Loot-bag beacon never appeared** — the owner's beacon remote fired the same frame the bag was
  created, so the Instance reference arrived as `nil` on the client (not yet replicated) and the
  beacon silently skipped. The fire is now delayed a beat past replication.
- **Looting while dead** — a dead player could scoop their own bag from the corpse before
  respawning, defeating the corpse-run. The server now rejects collectors who aren't alive.

## 0.7.1 — 2026-07-06

### Fixed
- **Ghost tools** — the hotbar→Tool bridge now verifies the player actually CARRIES a pinned item
  before equipping it: a pin is only a pointer, and a stale/seeded pin without a backing stack
  could previously conjure a usable Tool out of thin air.
- The hotbar now **dims** a pinned item's icon (same 0.45 convention as the Crafting tab) when the
  player has none of it, so an inert pin reads as inert.
- Demo: the husks spawn farther out — new players are no longer farmed at the spawn point before
  they've picked up a weapon.

## 0.7.0 — 2026-07-06

### Added
- **Hunting & butchering** (#13) — slaying a mob whose def sets **carcass fields**
  (`carcassItem` / `carcassHp` / `carcassTool` / `carcassYieldMin`/`Max` / `carcassSeconds`) leaves
  a **butcherable carcass** — literally a tagged `Gatherable`, so butchering reuses the entire
  proven harvesting pipeline: tool gate (a knife `toolType`), per-interaction yields, floating HP
  bar, `gather:*` hooks and progression counters (`gathers_raw_meat` feeds quests + achievements
  automatically). Carcass looks come from `SurvivorCoreContent.Carcasses.<mobType>` (placeholder
  otherwise), per-type juice keys on `"<mobType>_carcass"`, and all six fields are editable in the
  admin plugin's **Mobs** editor. Completes the passive-animal hunting loop the v0.5 FSM began.
  New generic `Gatherable` attributes: **`PromptText` / `PromptObject`** (custom prompt wording for
  any gather node). See [docs/mobs.md](docs/mobs.md).
- **Death loot bags & respawn** (#19, TCE port) — dying drops the player's inventory **and worn
  equipment** (config-toggleable) into an **anchored, ground-clamped loot bag**: contents as
  IntValues, an instant-loot prompt anyone can use, a floating **countdown**, an owner-only golden
  **beacon**, a "You died" toast, and despawn after `LifetimeSeconds`. Pickup is loss-proof —
  equipment restores to empty equip slots FIRST (a satchel re-grows slots/weight before stacks
  return), the rest grants up-to-fit and the remainder stays in the bag. New `LootBags` Config
  section + `SurvivorCore.LootBags`; new lifecycle `player:died` (fired for every death, bag or
  not) flows into Progression as **`deaths_total`** counters; new hooks `lootbag:dropped` /
  `lootbag:collected`. The TCE **respawn camera fix** rides along (CameraSubject re-pointed per
  respawn). See [docs/loot-bags.md](docs/loot-bags.md).
- **Inventory APIs** — `getEquipment`, `clearAll` (capacity-safe snapshot-and-wipe),
  `addUpTo` (granted-count adds), `restoreEquip` (direct empty-slot equip) — the death/restore
  primitives, public for games to reuse.

### Fixed
- Engine-equipped Tools cloned from creator templates are now forced `CanBeDropped = false` — a
  template left droppable would strand a stray pickable Tool in the world on death.

## 0.6.0 — 2026-07-03

### Added
- **Quests** (#10) — the goals & progression foundation. A `Quests` registry + server runtime:
  quests carry **objectives** (`gather` / `craft` / `kill` / `use` a target × count; blank target =
  any) and **rewards**, with `autoStart`, a `requires` prerequisite (completing a quest
  **auto-starts its chain**), and optional `turnIn` at a **quest giver** — tag any part/model
  `QuestGiver` + set `Quest = "<id>"` and the engine attaches the accept/turn-in prompt. Progress is
  driven by the events players already generate — no wiring per quest — and **rewards are never
  lost**: a full inventory parks the quest as *ready* and the grant retries until it fits. A
  **Quests menu tab** (key `L`) renders Active (per-objective progress bars) / Ready / Completed.
  New hooks + bus events: `quest:started/progress/completed/blocked`. Session-scoped (persistence is
  a future system). See [docs/quests.md](docs/quests.md).
- **Achievements** — an always-on runtime for the existing registry, ported architecturally from The
  Counter Earth's proven service: the new shared **Progression** layer translates gameplay events
  into **auto-derived counters** (`gathers_reed`, `crafts_total`, `kills_husk`, `uses_berry`,
  `quests_total`, …) so an achievement def is just `{ key, name, counter, threshold }` — the same
  flat shape in code and no-code. Threshold crossings **unlock once**, fire `achievement:unlocked`,
  and show a **toast**; an **Achievements menu tab** (key `J`) tracks progress bars (gold when
  unlocked). Custom events/counters via `SurvivorCore.Progression.map` / `Achievements.addCount` /
  `Achievements.award`. See [docs/achievements.md](docs/achievements.md).
- **Toasts** — a small themed top-right notification queue (`Notify` remote + `Toasts.show`),
  used by quest completions and achievement unlocks (config-gated per system).
- **No-code quests & achievements** — the admin plugin's Content widget gains **Quests**
  (single-objective: objective type/target/count, reward, auto-start, requires, turn-in; **+ Quest
  giver** drops a tagged giver post) and **Achievements** (counter + threshold) editors; the engine
  loads both from `SurvivorCoreContent` at start.
- **EventBridge parity** — harvesting, crafting and item-use lifecycle events (`gather:*`,
  `craft:*`, `item:use`) now also cross the EventBridge bus (combat/mobs already did), so
  quests/achievements/analytics can consume every gameplay event uniformly.

### Fixed
- `SurvivorCore.UI.registerPanel` now **adopts** a menu tab the authored template already scaffolds
  (hiding its placeholder and running the panel's `build` into it) instead of silently doing
  nothing — this is what lets the Quests/Achievements tabs replace their "coming soon" placeholders.

### Changed
- Toolchain: **rojo 7.6.1 → 7.7.0** (pin in `rokit.toml`; sandbox-verified against the full CI gate).

## 0.5.0 — 2026-06-25

### Added
- **Mob & AI engine** (#17) — the shared creature substrate combat, animals and monsters all build
  on. A **mob is a Model tagged `Mob`** with a Humanoid + PrimaryPart, so it's damaged, healed and
  killed *exactly* like a player. A reusable **FSM** (idle / wander / chase / attack / flee /
  return-on-leash / death) drives behavior, with the profile picked by **data** — a `Mobs` def's
  `faction`: `"hostile"` chases + attacks, `"passive"` flees, `"neutral"` wanders. Line-of-sight,
  leash distance and target selection are built in; movement is `Humanoid:MoveTo`. New
  `SurvivorCore.Mobs` runtime — `spawn` / `adopt` / `damage` / `getActive` / `isMob` (the registry's
  `register` / `loadFromFolder` still author defs in code or no-code) — plus per-mob-type
  **reactions** `SurvivorCore.Mobs.onReaction(mobType, "spawned"|"hit"|"attack"|"died", …)` for death
  fades, spawn cries, etc. A `Mobs` Config section tunes tick rate, default aggro/leash/attack and
  respawn. New hooks: `mob:spawned` / `mob:hit` / `mob:attack` / `mob:died`. See
  [docs/mobs.md](docs/mobs.md).
- **Combat — melee + ranged** (#12, #14) — server-authoritative combat reusing the v0.4.0
  client-input → server-validated-hit pipeline. A **weapon is just an item** (`category = "weapon"` +
  a `toolType` so the hotbar equips it) with flat `weapon*` stats. **Melee:** equip + click; the
  server picks the nearest valid target (a mob, or another player when `FriendlyFire` is on) within
  range + line-of-sight and applies damage. **Ranged (bow):** a TCE-style **aiming** flow — hold
  right-click to aim (over-the-shoulder camera + FOV zoom + a crosshair and a charge ring), hold
  left-click to **draw**, release to **fire** along the crosshair. The server recomputes the shot from
  the bow's muzzle, times the draw (anti-cheat), consumes one arrow from the inventory, and simulates
  the **gravity arc** authoritatively, sending the arc path back so the client flies a cosmetic arrow
  along the real curve. **Arrows are their own configurable ammo item** (`category = "ammo"`): per
  type a **weight**, **damage ×**, **drop/curve ×**, **max range** and **speed ×**, so different
  arrows fly and hit differently — a shot combines the bow's pullback with the arrow's ballistics. The
  **kill-event schema is designed once** here — `combat:hit` / `combat:kill` `{ attacker, victim,
  weapon, source }` — fired through both `Hooks` and `EventBridge`. New `SurvivorCore.Combat` + a
  `Combat` Config section (ranges, cooldowns, friendly fire, bow physics). Because mob/player damage
  flows through `Humanoid:TakeDamage`, it's lethal and **drives the survival Health HUD with no extra
  wiring**. See [docs/combat.md](docs/combat.md).
- **No-code mobs & weapons** (#11, Builder slice) — the admin plugin's **Content** widget gains
  **Mobs**, **Weapons** and **Arrows / Ammo** editors (schema-driven, like Items/Gatherables): create
  a mob type (faction/health/speed/ranges) — **+ Add to World** drops a tagged placeholder rig; create
  a weapon (kind/damage/range/cooldown + bow draw/speed/ammo) — **+ Tool model** drops a starter `Tool`
  to build the held look on; create an arrow type (damage/curve/range/speed/weight). The engine loads
  all of them from `SurvivorCoreContent` at start — what the plugin writes, the runtime registers, no
  code. A creator also authors a mob by tagging any rigged Model **`Mob`** and setting `MobType`.

### Fixed
- Removing or consuming one item no longer clears **unrelated** hotbar pins — the orphaned-pin sweep
  is now scoped to the affected item. (Previously, e.g., firing a bow that consumed an arrow could
  unpin and unequip a hotbar-pinned weapon that had no inventory stack.)

## 0.4.0 — 2026-06-24

### Added
- **Tool-swing harvesting & the gather → craft loop** (#1, #4) — equip a tool from the hotbar,
  **click a node to swing**, and the server validates the hit (range, line-of-sight, equipped tool,
  cooldown) before granting a per-hit **random yield** straight into your inventory; a full
  inventory **blocks** the hit so nothing is wasted. Bare-hand nodes keep the hold-`E` prompt. This
  is the engine's first **client-input → RemoteEvent → server-validation pipeline**, shaped for
  combat to reuse. Selecting a tool in the hotbar now equips a **real `Tool`** (the new
  hotbar→Tool bridge), with a content-free Tool template path. **Hand crafting** closes the loop:
  a server-authoritative runtime consumes a recipe's ingredients and produces its output
  (refunding on no room), surfaced as a **Crafting tab** that lists `Recipes.forStation("hand")`
  and gates each recipe on what you're carrying. New APIs: `SurvivorCore.Harvesting`,
  `SurvivorCore.Crafting`, plus `Harvesting`/`Crafting` Config sections. See
  [docs/harvesting.md](docs/harvesting.md) and [docs/crafting.md](docs/crafting.md).
- **No-code content layer** (#11, Builder first slice) — items and gatherable **resources** can now
  be authored **without code**. A new `Resources` registry defines what a node *is*
  (item it yields, HP/gathers, required tool, yield min/max); a `Gatherable` node binds to one via a
  `Resource` attribute (tag a mesh, set `Resource = "oak_tree"` — no per-node attributes). Content
  can be defined as instances (`Registry.loadFromFolder` reads a `SurvivorCoreContent` folder at
  start), and the **admin plugin gains a "Content" widget** to create/edit/delete items + gatherable
  resources from a form — what it writes, the engine registers, no code. Per-resource-type
  **reaction hooks** (`SurvivorCore.Gather.onReaction`) drive the juice (a reed sways, a tree fells
  and leaves a stump), with `DestroyOnDeplete` so a creator can transform the node on depletion.
  New hooks: `gather:blocked`, `craft:start` / `craft:end` / `craft:blocked`. See
  [docs/content-authoring.md](docs/content-authoring.md).

## 0.3.0 — 2026-06-23

### Added
- **Inventory, hotbar & tabbed menu UI** (#7, #9, #3) — a server-authoritative inventory with a
  **slots + carry-weight** model, a 9-slot quick-use **hotbar** (keys 1-9), **equipment** slots
  (head/top/pants/shoes/back/quiver), and a restyleable **tabbed menu** (functional Inventory +
  Character Sheet; Codex/Achievements/Quests scaffolded). Built the engine's way — authored
  ScreenGui **templates** (`SurvivalMenu`, `SurvivalHotbar`) driven by attribute-discovering
  **binders**, so world creators restyle everything in Studio with zero code (and a zero-setup
  fallback guarantees the UI always appears). Items **stack** and have **weight**; equipping a
  **backpack** raises both slot count and weight limit. **Consumables** apply their `onConsume`
  effects through the stat-effects layer (e.g. food lowers Hunger) and fire an `item:use` hook;
  every change fires `inventory:changed`. Full **drag-and-drop** (move/merge/swap, pin to hotbar),
  pickups **auto-assign** to the smallest free hotbar slot, and gathering a node now grants its
  yield straight into the inventory. New public API: `SurvivorCore.Inventory.*`
  (add/remove/move/split/equip/unequip/setHotbar/swapHotbar/useSlot/…) and
  `SurvivorCore.UI.registerPanel/open/close/toggle` for code-added tabs. Item **display data**
  (name/icon/stack/…) replicates to clients automatically, so games register items once
  (server-side) and the UI just works; item icons resolve via the `ItemIcons` Assets category or an
  inline `icon` field. Tunable via the new `Inventory` and `UI` Config sections. The engine still
  ships **zero items** — the demo registers a sample set and seeds a starter inventory. Opening the
  menu defaults to **Tab** — the engine frees it by disabling Roblox's player roster (which otherwise
  swallows the key), and moves the chat window to the bottom-left so it clears the top-left HUD; both
  are opt-out via the `UI` Config section (`ReclaimCoreKeys`, `Chat`). See
  [docs/inventory.md](docs/inventory.md).

## 0.2.1 — 2026-06-22

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
