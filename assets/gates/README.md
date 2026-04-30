# Gate sprites

Drop PNG files here named after each color id from `lib/models/box_color.dart`:

- `red.png`
- `blue.png`
- `green.png`
- `yellow.png`
- `purple.png`

**Recommended size:** 192×48 (wider than tall, transparent background). The
painter blits each sprite into a 58×40 game-space rect at the end of its
matching belt, so the source aspect ratio should be roughly 4:1.

## Fallback

If a file is missing, `GameAssets.gateImage()` returns `null` and
`GamePainter._drawProceduralGate` draws the layered rounded-rect gate. The
game runs fine without any of these files.

The down/up direction arrow (▼/▲) is rendered on top of the sprite by the
painter, so it stays legible regardless of art style — the sprite itself
should not include an arrow.

## Generating with AI

Free option: [bing.com/create](https://www.bing.com/create) (DALL-E 3).

Prompt template (swap the **bold** color words per file):

> Top-down pixel art of a collection gate panel at the end of a
> conveyor belt, rectangular tray with **vibrant red** surface, **dark red**
> border frame, bright **light-red** glowing strip across the top edge,
> 4:1 wide aspect ratio, transparent background, no arrows, no text,
> dark industrial factory game asset.

Match the palette in `lib/models/box_color.dart` so each gate reads as the
same color as its matching boxes.
