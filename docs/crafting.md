# Crafting

Hand crafting closes the **gather → craft → use** loop: from your inventory, a recipe's ingredients
are consumed and its output produced — server-authoritative, via
[`src/systems/Crafting.luau`](../src/systems/Crafting.luau).

> 📹 Demo video: _coming soon_

## Recipes

Recipes live in the `Recipes` registry, routed by `station` (`"hand"` is the first consumer;
campfire/cooking later use the same engine). Register in code or
[no-code](content-authoring.md):

```lua
SurvivorCore.Recipes.register({
    id = "plank",
    station = "hand",
    ingredients = { { item = "wood", count = 2 } },
    output = { item = "plank", count = 1 },
})
```

## Runtime

`SurvivorCore.Crafting` (available after `start()`):

| Function | Behavior |
|---|---|
| `canCraft(player, recipeId) -> (bool, reason?)` | recipe exists, station `"hand"`, has all ingredients |
| `craft(player, recipeId) -> bool` | consume ingredients → produce output; **refunds** on any mid-way failure or no room |

It fires `craft:start` → `craft:end` (success) or `craft:blocked` (reason: `unknown` / `station` /
`ingredients` / `full`). The client requests a craft via the `CraftRecipe` RemoteEvent; the server
re-validates everything.

## The Crafting tab

The menu's **Crafting** tab ([`src/client/CraftingUi.luau`](../src/client/CraftingUi.luau)) is
registered through the engine's own `SurvivorCore.UI.registerPanel` API. It lists every hand recipe
(replicated to the client via `RecipeData`), shows the output icon/name + ingredient line, and
**greys out** recipes you can't afford — re-checked live as your inventory changes. Click **Craft**
to fire the request. Styling comes from the `UI` Config `Theme`.

## Tuning

`Config.override("Crafting", { CraftTime = 0 })` (reserved for a future craft-channel progress bar).
