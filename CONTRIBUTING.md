# Contributing to SurvivorCore

Thanks for your interest in contributing to SurvivorCore! This guide will help you get set up
and understand how the project is organized.

SurvivorCore is an **engine of mechanics, not content**. Most of what makes a survival game
*yours* — items, world, art, lore — lives in your own game and plugs in through the engine's
two extension layers. Contributions to this repo are about the *engine*: registries,
components, hooks, and the foundation. See [Architecture Overview](#architecture-overview).

## Prerequisites

- **Roblox Studio** — to serve the project into and play-test.
- **The Rojo Studio plugin, version `7.6.1`** — pin it to match the CLI the project uses (see
  `rokit.toml`). A mismatched plugin can fail to sync. Install from the
  [Rojo plugin page](https://create.roblox.com/store/asset/13916111004/Rojo) or via
  `rojo plugin install`.
- **[Rokit](https://github.com/rojo-rbx/rokit)** — the toolchain manager. It installs the
  exact pinned versions of `rojo`, `wally`, `stylua`, `selene`, and `luau-lsp` from
  `rokit.toml`.
- **[Wally](https://wally.run)** — the Roblox package manager (installed by Rokit). The engine
  ships with no dependencies today, but `wally install` keeps you forward-compatible.
- **Git** — for cloning and version control.

## Local Development Setup

1. **Fork & clone the repo:**
   ```bash
   git clone https://github.com/<you>/SurvivorCore.git
   cd SurvivorCore
   ```

2. **Install the toolchain** (reads `rokit.toml`):
   ```bash
   rokit install
   ```

3. **Install packages** (no-op until `wally.toml` gains dependencies, but get in the habit):
   ```bash
   wally install
   ```

4. **Serve into Studio.** Open a place in Studio (an empty baseplate is fine), make sure the
   Rojo plugin is connected, then in your terminal:
   ```bash
   rojo serve demo.project.json
   ```
   Click **Connect** in the Rojo plugin. This mounts the engine at
   `ReplicatedStorage.SurvivorCore` and the demo boot script in `ServerScriptService`.

5. **Run the demo place.** Press **Play**. The demo registers a couple of items and a recipe,
   then watches for creator-owned `Gatherable` objects. To try the component layer: add a
   `Part` to the Workspace, tag it `Gatherable` (CollectionService), set the attributes
   `ItemId="reed"`, `Yield=2`, `HP=3`, then play and interact with the prompt.

> Working on the engine alone (not the demo)? `rojo serve default.project.json` mounts just
> `src` as the `SurvivorCore` model.

> **Studio + Rojo gotcha — restart before trusting a Play test.** When you change scripts during a
> `rojo serve` session, Studio updates each script's `Source` in the Edit datamodel, but **Play
> Solo can run cached old bytecode** — so your change silently doesn't take effect on Play. If a
> fix isn't showing up, **restart Studio** (clears the script cache) and reconnect, or test from a
> fresh build: `rojo build demo.project.json -o /tmp/demo.rbxlx` and open that file.

## Code Style

- **Luau, typed where practical.** Use `--!strict` on new modules when the types are clean;
  fall back to the project default otherwise. Prefer `export type` for public shapes.
- **Formatting & linting are enforced by CI.** Before you push, run the same checks CI does
  (see [Making a Pull Request](#making-a-pull-request)). `stylua` owns formatting — don't
  hand-format around it.
- **Never hardcode asset IDs in `.luau`.** Asset IDs are content. Register them through
  `Assets` (`Assets.register("Sounds", "Harvest", "rbxassetid://…")`) and read them back, with
  the empty-string fallback convention. The engine must contain **zero** concrete asset IDs.
- **Keep the core content-free.** No concrete items, recipes, lore, world strings, or
  instance-name string matches (`name == "campfire"`) in the engine. Content enters two ways:
  - **Registries** — developers call `register()` from code (`Items`, `Recipes`, `Stats`,
    `Mobs`, …).
  - **Components** — creators tag their own objects and set Attributes (`Gatherable`, and the
    component family that follows).
- **Extend via Hooks, don't fork.** Game-specific flourish (felling physics, station VFX,
  custom drops) belongs in a `Hooks.on(...)` handler in the *game*, not baked into the engine.
  If you need a new extension point, add a `Hooks.run("…")` call and document it.
- **Mind the two layers.** Engine code lives in `src/`; `demo/` is an example consumer and may
  use concrete content freely (it stands in for a game).

## Branching model

SurvivorCore uses two long-lived branches:

- **`dev`** — the active development / integration branch. **All code changes land here.**
- **`main`** — the stable, released branch. It only moves when maintainers cut a release (by
  merging `dev` → `main`) or for **documentation-only** changes.

**In short: code → `dev`, docs → `main`.**

- **Code work** (anything under `src/`, `demo/`, workflows, toolchain/build config): fork,
  branch from **`dev`**, and open your PR against **`dev`**.
- **Documentation only** (`README`, `docs/`, `CONTRIBUTING.md`, code comments, typos): you may
  branch from **`main`** and PR against **`main`** — apply the `skip-changelog` label.

Use branch prefixes: `feat/*`, `fix/*`, `docs/*` (e.g. `feat/mob-registry`).

`main` is the default branch, so a fresh PR targets `main` — **retarget code PRs to `dev`.** A
code PR left on `main` will be asked to retarget. Releases are cut by maintainers: `dev` is
merged into `main` (a **merge commit**, not a squash, so the branches stay in sync),
`## Unreleased` is promoted to the new version, and `main` is tagged + a GitHub Release is
published (which auto-posts to Discussions → Announcements).

## Making a Pull Request

1. **Fork** the repository on GitHub.
2. **Create a branch from the right base** — `dev` for code, `main` for docs-only:
   ```bash
   git checkout -b feat/my-feature dev      # code work
   # git checkout -b docs/my-fix main        # documentation only
   ```
3. **Implement your change.** Write clear, typed Luau. Add comments where the "why" isn't
   obvious. Keep the engine content-free.
4. **Test locally.** Play-test in Studio, then run the same checks CI does:
   ```bash
   stylua --check src demo assets
   selene .
   rojo sourcemap demo.project.json --output sourcemap.json
   curl -fsSL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
   luau-lsp analyze --sourcemap sourcemap.json --defs globalTypes.d.luau --no-strict-dm-types \
     --ignore "Packages/**" --ignore "DevPackages/**" --ignore "ServerPackages/**" src demo assets/client
   rojo build default.project.json --output SurvivorCore.rbxm
   rojo build demo.project.json --output demo.rbxl
   ```
   (`stylua src demo` auto-formats; `sourcemap.json`, `globalTypes.d.luau`, and the build
   outputs are git-ignored.)
5. **Commit** with a clear message describing what the change does and why:
   ```bash
   git commit -m "Add Mobs registry kill-event schema"
   ```
6. **Push** and open a pull request against **`dev`** (or `main` for documentation-only
   changes):
   ```bash
   git push origin feat/my-feature
   ```
7. In the PR description, explain what the change does, why it's needed, and how to test it in
   Studio. Add a clip/screenshot for anything visible.

**Changelog (required).** Every pull request must add an entry to [`CHANGELOG.md`](CHANGELOG.md)
under the `## Unreleased` heading (create it if missing), grouped under
`### Added` / `### Changed` / `### Fixed` / `### Security`, with `(#N)` referencing the issue or
PR. CI enforces this. If a change genuinely warrants no entry (a docs-only PR, a CI-config
tweak, a typo fix), apply the `skip-changelog` label to bypass the check. At release time,
`## Unreleased` is renamed to the new version.

**Tracking staged fixes (`fixed-pending-merge`).** When a PR implements the fix for an open
issue or a security alert, maintainers label it `fixed-pending-merge` (and the issue it
closes), so it's easy to see at a glance which problems are fixed and just waiting on a merge.
The label needs no cleanup: on merge the PR closes and any linked issue auto-closes via a
`Closes #N` reference.

## Issue Templates

File issues with the forms in `.github/ISSUE_TEMPLATE/`:

- **Bug report** — include a clear repro (which project to serve and what to do in Studio),
  expected behavior, the SurvivorCore version, your Roblox Studio version, your Rojo plugin
  version, how you consume the engine (Rojo / Wally / drop-in `.rbxm`), and any Output errors.
- **Feature request** — describe a reusable *engine* capability (a registry, component, hook,
  or config section), the use case, and which layer it touches. Game-specific content belongs
  in your own game, not the engine.

Open-ended questions and "how do I…?" go to
[Discussions](https://github.com/TemujinCalidius/SurvivorCore/discussions), not Issues.

## Architecture Overview

SurvivorCore exposes two extension layers over a small foundation:

- **Foundation** (`src/foundation/`) — `Config`, `Assets`, `EventBridge`, `Hooks`, `Registry`.
- **Registry layer** (`src/registries/`) — empty registries the game populates at startup
  (`Items`, `Recipes`, `Stats`, `Achievements`, `Codex`, `Appearance`, `Mobs`).
- **Component layer** (`src/components/`) — behaviors bound to a CollectionService tag and
  configured by per-instance Attributes (`Gatherable`, …).

For the full picture, read [docs/architecture.md](docs/architecture.md) and the companion
[Extending SurvivorCore](docs/extending.md) guide. The engine/content **boundary map** (which
systems are being extracted from the production game [The Counter
Earth](https://github.com/TemujinCalidius/TheCounterEarth) into this engine) lives in that
game's repo at `docs/survivorcore-boundary-map.md`.

## Code of Conduct

SurvivorCore is a small project, and we want to keep the community welcoming for everyone.

- **Be kind.** Assume good intent. Disagree respectfully.
- **Be inclusive.** Welcome newcomers. Avoid jargon without explanation.
- **Be constructive.** When reviewing code, suggest improvements rather than just pointing out
  problems. Explain why.
- **No harassment, discrimination, or personal attacks.** This includes issues, PRs,
  Discussions, and any project communication channels.

If someone's behavior makes you uncomfortable, reach out to the maintainers. We will address it.
