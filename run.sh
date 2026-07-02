#!/bin/bash
# Build & run Weather Wallpapers for quick testing.
#
#   ./run.sh            # iPhone + iPad simulators + Mac
#   ./run.sh iphone     # iPhone simulator only
#   ./run.sh ipad       # iPad simulator only
#   ./run.sh mac        # macOS app only
set -euo pipefail
cd "$(dirname "$0")"

TARGET="${1:-all}"
PROJECT="WeatherWallpapers.xcodeproj"
SCHEME="WeatherWallpapers"
BUNDLE_ID="com.mekedron.WeatherWallpapers"
DERIVED="build/DerivedData"

find_sim() {
    # Prefer an already-booted simulator; otherwise take the newest runtime
    # (runtimes are listed oldest-first, so the last match wins).
    local matches booted
    matches=$(xcrun simctl list devices available | grep -E "^[[:space:]]+$1" || true)
    booted=$(echo "$matches" | grep "(Booted)" | head -1 \
        | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1 || true)
    if [ -n "$booted" ]; then
        echo "$booted"
    else
        echo "$matches" | tail -1 \
            | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1 || true
    fi
}

run_sim() {
    local udid="${1:-}"
    if [ -z "$udid" ]; then
        echo "No matching simulator found. Check: xcrun simctl list devices available" >&2
        exit 1
    fi
    echo "==> Booting simulator $udid..."
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    open -a Simulator
    echo "==> Installing & launching..."
    xcrun simctl install "$udid" "$DERIVED/Build/Products/Debug-iphonesimulator/WeatherWallpapers.app"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$udid" "$BUNDLE_ID"
}

build_sim() {
    echo "==> Building for iOS Simulator..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DERIVED" build | grep -E "error|warning: .*\.swift|BUILD" || true
}

build_mac() {
    echo "==> Building for macOS..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" build | grep -E "error|warning: .*\.swift|BUILD" || true
}

case "$TARGET" in
    iphone)
        build_sim
        run_sim "$(find_sim "iPhone")"
        ;;
    ipad)
        build_sim
        run_sim "$(find_sim "iPad")"
        ;;
    mac)
        build_mac
        echo "==> Launching Mac app..."
        open "$DERIVED/Build/Products/Debug/WeatherWallpapers.app"
        ;;
    all)
        build_sim
        run_sim "$(find_sim "iPhone")"
        run_sim "$(find_sim "iPad")"
        build_mac
        echo "==> Launching Mac app..."
        open "$DERIVED/Build/Products/Debug/WeatherWallpapers.app"
        ;;
    *)
        echo "Usage: ./run.sh [iphone|ipad|mac|all]" >&2
        exit 1
        ;;
esac

echo "OK: Done"
