#!/bin/bash
#
# Generates a demo video showing the Weather Wallpapers app "in action":
# crossfades through a full day cycle (night -> sunrise -> day -> sunset -> night)
# for every weather condition found in a wallpaper set, then composites the
# result behind an iPhone home-screen screenshot (green-screen background
# is chroma-keyed out so icons/widgets sit on top of the moving wallpaper).
#
# Usage:
#   ./generate_demo.sh <wallpaper-folder> [screenshot] [output.mp4]
#
# <wallpaper-folder>  Folder containing "<Weather> <Time>.png" files, e.g.
#                      the app's exported set (Clear Day.png, Snow Night.png, ...).
# [screenshot]         iPhone home screen screenshot with a flat green wallpaper
#                       background to key out. Defaults to screenshot-template.jpg
#                       next to this script.
# [output.mp4]          Where to write the final composite. Defaults to
#                       Docs/demo_wallpaper_composite.mp4 in the repo root.
#
# Tunable via environment variables:
#   HOLD_SECONDS       seconds each image is held (default 0.85)
#   TRANSITION_SECONDS seconds of crossfade between images (default 0.6)
#   KEY_SIMILARITY     colorkey similarity (default 0.22)
#   KEY_BLEND          colorkey edge blend (default 0.10)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WALLPAPER_DIR="${1:?Usage: $0 <wallpaper-folder> [screenshot] [output.mp4]}"
SCREENSHOT="${2:-$SCRIPT_DIR/screenshot-template.jpg}"
OUTPUT="${3:-$REPO_ROOT/Docs/demo_wallpaper_composite.mp4}"

HOLD_SECONDS="${HOLD_SECONDS:-0.85}"
TRANSITION_SECONDS="${TRANSITION_SECONDS:-0.6}"
KEY_SIMILARITY="${KEY_SIMILARITY:-0.22}"
KEY_BLEND="${KEY_BLEND:-0.10}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Canonical 24 weather conditions, calm -> severe (matches the app's set).
WEATHERS=(
  "Clear" "Mostly Clear" "Partly Cloudy" "Mostly Cloudy" "Cloudy"
  "Foggy" "Breezy" "Windy"
  "Drizzle" "Rain" "Sun Showers" "Heavy Rain" "Thunderstorms"
  "Flurries" "Sun Flurries" "Snow" "Heavy Snow" "Blowing Snow" "Blizzard"
  "Freezing Drizzle" "Freezing Rain" "Frigid"
  "Hail" "Hot"
)
# Full day cycle per weather, closing the loop back on night before the next weather.
TIMES=("Night" "Sunrise" "Day" "Sunset" "Night")

[ -d "$WALLPAPER_DIR" ] || { echo "error: wallpaper folder not found: $WALLPAPER_DIR" >&2; exit 1; }
[ -f "$SCREENSHOT" ] || { echo "error: screenshot not found: $SCREENSHOT" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "error: ffmpeg not found in PATH" >&2; exit 1; }
command -v bc >/dev/null || { echo "error: bc not found in PATH" >&2; exit 1; }

FILES=()
for w in "${WEATHERS[@]}"; do
  for t in "${TIMES[@]}"; do
    f="$WALLPAPER_DIR/$w $t.png"
    [ -f "$f" ] || { echo "error: missing image: $f" >&2; exit 1; }
    FILES+=("$f")
  done
done
N=${#FILES[@]}
echo "Building background from $N frames (${#WEATHERS[@]} weather conditions x ${#TIMES[@]} times)..."

# Target size = the screenshot's own resolution, so icons line up 1:1.
read -r TW TH <<<"$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$SCREENSHOT" | tr 'x' ' ')"
echo "Target size: ${TW}x${TH}"

# Auto-detect the wallpaper key color by averaging a small patch near the screenshot's corner.
KEY_HEX=$(ffmpeg -v error -i "$SCREENSHOT" -vf "crop=10:10:4:4,scale=1:1" -f rawvideo -pix_fmt rgb24 - | xxd -p | tr -d '\n')
echo "Detected key color: #$KEY_HEX"

D="$HOLD_SECONDS"
T="$TRANSITION_SECONDS"
L=$(echo "$D + $T" | bc)

INPUTS=()
FILTER=""
for ((i=0; i<N; i++)); do
  INPUTS+=(-loop 1 -t "$L" -i "${FILES[$i]}")
  FILTER+="[$i:v]scale=-2:${TH},crop=${TW}:${TH}:(in_w-${TW})/2:0,setsar=1,fps=30,format=yuv420p[v$i];"
done

prev="v0"
for ((i=1; i<N; i++)); do
  offset=$(echo "$i * $D" | bc)
  [[ "$offset" == .* ]] && offset="0$offset"
  out="vx$i"
  FILTER+="[$prev][v$i]xfade=transition=fade:duration=${T}:offset=${offset}[$out];"
  prev="$out"
done
FILTER="${FILTER%;}"

BG_VIDEO="$WORK_DIR/bg.mp4"
ffmpeg -y "${INPUTS[@]}" -filter_complex "$FILTER" -map "[${prev}]" \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -movflags +faststart -r 30 "$BG_VIDEO"

echo "Compositing behind screenshot..."
mkdir -p "$(dirname "$OUTPUT")"
ffmpeg -y -i "$BG_VIDEO" -loop 1 -i "$SCREENSHOT" \
  -filter_complex "[1:v]format=rgba,colorkey=0x${KEY_HEX}:${KEY_SIMILARITY}:${KEY_BLEND}[keyed];[0:v][keyed]overlay=shortest=1:format=auto" \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -movflags +faststart -r 30 "$OUTPUT"

echo "Done: $OUTPUT"
