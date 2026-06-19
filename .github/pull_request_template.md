<!-- Thanks for contributing to SurvivorCore! -->
<!-- Code PRs target `dev`. Documentation-only PRs may target `main` (apply `skip-changelog`). -->

## Summary

<!-- What does this change do, and why? -->

## How to test in Studio

<!-- Steps to verify: which project to serve (default vs demo), what to do in Studio,
     and what you should see. Include a screenshot/clip for visible behavior. -->

## Checklist

- [ ] Added an entry to **`CHANGELOG.md`** under `## Unreleased` (or applied the `skip-changelog` label if no entry is warranted — e.g. a CI-only or trivial docs change)
- [ ] CI is green — `stylua --check`, `selene`, `luau-lsp analyze`, and **all three** `rojo build`s (engine, demo, plugin) pass
- [ ] No secrets or personal data added (this is a public repo)
- [ ] **No game-specific design content** — items / recipes / lore / world strings enter via `register()` / components / `Assets`, not the engine (free *default* art, e.g. HUD icons, is fine)
