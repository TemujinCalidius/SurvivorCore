# Getting Started

SurvivorCore is the *mechanics* of a survival game — stats, inventory, crafting, harvesting,
mobs, and more — without dictating your *content*. There are two ways to bring it into your
place: as **source** (via Rojo + Wally, the recommended path for active development) or as a
**drop-in model** (`SurvivorCore.rbxm`, the fastest way to try it).

> **Status:** early scaffold (v0.1.0). APIs will change. See the
> [README](../README.md) for what's implemented today.

## Option A — Rojo + Wally (recommended)

Best if you're actively developing and want source, types, and live sync into Studio.

### 1. Install the toolchain

SurvivorCore pins its tools with [Rokit](https://github.com/rojo-rbx/rokit). In your game's
repo, add SurvivorCore's tools to your `rokit.toml` (or copy the pins) and run:

```bash
rokit install
```

This gets you `rojo` (7.6.1) and `wally`, among others. In Studio, install the **Rojo plugin
version 7.6.1** to match.

### 2. Add SurvivorCore as a Wally dependency

> Wally publishing is planned for a later release. Until then, use the
> [Git submodule / source](#3-or-vendor-the-source) approach below, or the
> [drop-in model](#option-b--drop-in-model-survivorcorerbxm).

Once published, add it to your game's `wally.toml`:

```toml
[dependencies]
SurvivorCore = "temujincalidius/survivorcore@0.1.0"
```

Then:

```bash
wally install
```

…and map the `Packages` folder into `ReplicatedStorage` in your `*.project.json`.

### 3. …or vendor the source

Clone or submodule this repo and point your Rojo project at it:

```jsonc
// your.project.json
{
  "tree": {
    "ReplicatedStorage": {
      "SurvivorCore": { "$path": "path/to/SurvivorCore/src" }
    }
  }
}
```

### 4. Boot it from a server script

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivorCore = require(ReplicatedStorage:WaitForChild("SurvivorCore"))

-- Register your content (see "Extending SurvivorCore")…
SurvivorCore.Items.register({ id = "reed", name = "Reed", stack = 20 })

-- …then start the engine. Call once, from the server, after registering.
SurvivorCore.start()
```

## Option B — Drop-in model (`SurvivorCore.rbxm`)

Best for a quick look with no toolchain.

1. Download `SurvivorCore.rbxm` from the latest
   [Release](https://github.com/TemujinCalidius/SurvivorCore/releases) (it's built from source
   by CI on every version tag).
2. In Studio, right-click **ReplicatedStorage** → **Insert from File…** → pick the `.rbxm`.
   You'll get a `SurvivorCore` ModuleScript.
3. Add a `Script` in **ServerScriptService**:

   ```lua
   local ReplicatedStorage = game:GetService("ReplicatedStorage")
   local SurvivorCore = require(ReplicatedStorage:WaitForChild("SurvivorCore"))

   SurvivorCore.Items.register({ id = "reed", name = "Reed", stack = 20 })
   SurvivorCore.start()
   ```

4. Press **Play**.

## Try the demo

This repo ships a runnable demo that exercises both extension layers:

```bash
rojo serve demo.project.json
```

Connect the Rojo plugin, press **Play**, then add a `Part` to the Workspace, tag it
`Gatherable` (CollectionService), and set the attributes `ItemId="reed"`, `Yield=2`, `HP=3`.
Interact with the prompt to see the component + hook flow. The boot script is
[`demo/server/Boot.server.luau`](../demo/server/Boot.server.luau).

## Next steps

- **[Extending SurvivorCore](extending.md)** — the `register()` API, the component/attribute
  model, and Hooks.
- **[Architecture](architecture.md)** — how the layers fit together.
