# Demo video generator

Generates a video that shows the app "in action": every weather condition in a
wallpaper set, cycling night → sunrise → day → sunset → night, composited
behind an iPhone home screen screenshot (the screenshot's green wallpaper
background is chroma-keyed out so icons/widgets sit on top of the moving
wallpaper).

## Usage

```bash
./generate_demo.sh <wallpaper-folder> [screenshot] [output.mp4]
```

- `<wallpaper-folder>` — a folder of `<Weather> <Time>.png` files, i.e. an
  exported wallpaper set from the app (`Clear Day.png`, `Snow Night.png`, …).
  Must contain all 24 weather conditions × 4 times of day (96 files).
- `[screenshot]` — an iPhone home screen screenshot with a flat green
  wallpaper background to key out. Defaults to `screenshot-template.jpg` in
  this folder. Take a fresh one (Settings → set wallpaper to a flat green
  color → screenshot) if you rearrange icons/widgets.
- `[output.mp4]` — defaults to `../Docs/demo_wallpaper_composite.mp4`.

The key color and target resolution are both auto-detected from the
screenshot, so any device size / any shade of green works without editing
the script.

Tunable via environment variables (all optional):

```bash
HOLD_SECONDS=0.85 TRANSITION_SECONDS=0.6 ./generate_demo.sh /path/to/wallpapers
```

- `HOLD_SECONDS` — how long each image is held (default `0.85`)
- `TRANSITION_SECONDS` — crossfade duration between images (default `0.6`)
- `KEY_SIMILARITY` / `KEY_BLEND` — chroma-key tolerance / edge softness
  (defaults `0.22` / `0.10`)

Requires `ffmpeg`, `ffprobe`, `bc` and `xxd` (all standard on macOS with
Homebrew ffmpeg installed).

## screenshot-template.jpg

A home screen screenshot with a flat green wallpaper, some widgets/icons on
top, and no personal metadata (re-encoded fresh, no EXIF/location data — it
never had any, screenshots don't carry camera EXIF). Swap it for your own
screenshot to change which icons appear over the demo.
