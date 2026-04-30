# Box sprites

Drop PNG files here named after each color id from `lib/models/box_color.dart`:

- `red.png`
- `blue.png`
- `green.png`
- `yellow.png`
- `purple.png`

**Recommended size:** 128×128 (square, transparent background).

## Fallback

If a file is missing, `GameAssets.boxImage()` returns `null` and `GamePainter`
falls back to its procedural box drawing. The game runs fine without any of
these files — only colors with a PNG present get the sprite treatment.

## Generating with AI

Free option: [bing.com/create](https://www.bing.com/create) (DALL-E 3).

Prompt template (swap the **bold** color words per file):

> Top-down pixel art of a small square shipping crate, **vibrant red**
> painted lid, **dark red** border edge, **light pink** highlight stripe
> along the top, single small light-colored rivet in the center, flat
> shading, clean pixel grid, transparent background, no drop shadow,
> dark industrial factory game asset, 1:1 square.

Color swaps: red / blue / green / yellow / purple — match the
hex palette in `lib/models/box_color.dart` so the sprites read as the
same colors as the procedural fallbacks.
