# SurvivorCore — Design Language

The look we hold to across this project. SurvivorCore is a **generic engine**, so everything
here is **tasteful, neutral, and game-agnostic** — never tied to one game's theme. Owners
re-skin freely; these are the engine's clean defaults and the rules any shipped art follows.

> If you're generating art or building UI, read this first and match it.

## Principles

- **Free, swappable defaults.** Assets in this repo are free to use, so the engine ships free
  **default** art (e.g. the HUD stat icons) — every piece overridable per stat (config / admin
  plugin) or via the `Assets` registry. No look is hard-coded; where no art resolves, the fallback
  is plain colors + text. (Game-specific *design* — items, recipes, lore — still never ships in the
  engine; see [CONTRIBUTING](../CONTRIBUTING.md).)
- **Owner-editable.** UI is real, restyleable Instances driven by attributes — never hard-coded
  layouts the owner can't change.
- **Tasteful, not flashy.** Clean, modern, readable. Flat surfaces, soft translucency, restraint.
  Legibility beats decoration.
- **Consistent.** One panel style, one icon style, one type scale everywhere.

## UI / HUD style

- **Panels:** dark translucent. Background `RGB(20, 23, 30)` at **0.25 transparency**, `UICorner`
  radius **10**, a subtle `UIStroke` `RGB(210, 220, 245)` at **0.85 transparency**, `UIPadding`
  ~10 (top/bottom) / ~14 (sides). Auto-size where content varies.
- **Type:** `GothamMedium` for labels/values (`GothamBold` for emphasis like the toggle glyph).
  Sizes ~12–13. Text `RGB(245, 245, 245)`; secondary/title text `RGB(210, 220, 245)`.
- **Bars:** dark track `RGB(28, 32, 42)`, rounded, with a colored `Fill`. The engine drives only
  `Fill` size + color and the `Value`/`Icon`; everything else is the owner's styling.
- **Warning state:** fill turns `RGB(200, 40, 40)` near the dangerous end of a stat.

### Stat palette (default fill colors)

| Stat | RGB | Stat | RGB |
|---|---|---|---|
| Health | 232, 70, 70 | Fatigue | 160, 100, 220 |
| Energy | 90, 205, 120 | Blood | 180, 40, 40 |
| Hunger | 220, 140, 40 | Poison | 120, 180, 60 |
| Thirst | 60, 160, 230 | (warn) | 200, 40, 40 |

## Icon style

Flat, minimal, **two-tone** glyphs — modern and crisp, legible at ~20 px in a HUD.

- **Form:** a single clear glyph, centered, **filling ~70–80% of the frame** (minimal margin so
  it stays large when downscaled). Consistent visual weight across the set.
- **Shading:** a soft saturated fill, a slightly darker outline, and one subtle highlight — no
  gradients-heavy rendering, no text, no drop shadows, no borders.
- **Palette:** lean on each stat's color above so the icon reads even without its bar.
- **Background:** **transparent** (post-processed — see pipeline). Generate on plain white, then
  key it out.
- **Set consistency:** same line weight, lighting direction, corner rounding, and margin for
  every icon so they sit together as a family.

## Icon generation pipeline (3D AI Studio · Gemini 3 Pro)

1. **Generate:** `POST https://api.3daistudio.com/v1/images/gemini/3/pro/generate/`
   (`Authorization: Bearer <key>`), body `{ prompt, output_format:"png", aspect_ratio:"1:1",
   resolution:"1K", num_images:1 }`. Async — poll `GET /v1/generation-request/<task_id>/status/`
   until `status:"FINISHED"`, then wait for `results[0].asset` to populate (it lags FINISHED by a
   few seconds) and download that URL.
2. **Review (required):** look at every result and **iterate the prompt** until it matches this
   doc — never ship the first draft uncritically.
3. **Post-process:** key out the white background → transparent (RGBA), trim to the glyph's
   bounding box, then pad to a uniform square so the set is visually consistent.
4. **Upload to Roblox** → asset id, and register: `Assets.register("StatIcons", "<Stat>", id)`
   (the HUD's `Icon` slots resolve from category `StatIcons`, key = stat / counter name).

The API key lives **outside the repo** at `~/.config/survivorcore/3daistudio.key` (read at call
time, never printed or committed).

---

Related: [Survival Stats + HUD](survival-stats.md) · [Architecture](architecture.md).
