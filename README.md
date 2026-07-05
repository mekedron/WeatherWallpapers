# Weather Wallpapers

**[Website →](https://mekedron.github.io/WeatherWallpapers/)**

A free, open-source app for iPhone, iPad and Mac that generates **96 wallpaper variants** from a single artwork — one for every combination of 24 weather conditions × 4 times of day — and serves the right one to the Shortcuts app so your wallpaper always matches the sky outside.

<table align="center">
<tr>
<td width="360">

https://github.com/user-attachments/assets/b3653fb8-9e7d-49ee-8e66-f78b6256a9c0

</td>
</tr>
</table>

<p align="center"><em>Every weather condition cycling through a full day, composited behind a real home screen. Generated with <a href="Demo/generate_demo.sh"><code>Demo/generate_demo.sh</code></a> — see <a href="Demo/README.md"><code>Demo/README.md</code></a> to regenerate it for your own wallpaper set.</em></p>

## How it works

1. **Create a wallpaper set.** Pick a source image from Photos or Files, or generate one with AI from any prompt (regenerate until you like it).
2. **Pick your device.** Built-in list of iPhone / iPad / MacBook screen resolutions (or add a custom one) — the target size drives generation cost.
3. **Generate.** The app produces all 96 variants by editing your original with a modular prompt: time-of-day lighting + weather description, preserving the composition and art style. Browse them grouped by weather, regenerate any single image or a whole selection.
4. **Automate with Shortcuts.** The app exposes a **“Get Current Wallpaper”** action: it detects your location, fetches the weather from Open-Meteo (free, no key), maps it to one of the 96 variants and returns the image. Chain it with the system “Set Wallpaper” action and a Time-of-Day automation — done.

## Providers

Bring your own API key (stored in the Keychain, synced via iCloud Keychain):

- **ChatGPT (OpenAI)** — `gpt-image-1`
- **Nano Banana (Google Gemini)** — `gemini-2.5-flash-image`

The provider architecture is pluggable — adding more is a single file.

## Settings

- **Spending.** Every API call is logged with its cost and token usage — per wallpaper set and as a running total across all of them.
- **Weather statistics.** The app quietly tracks which conditions actually occur at your location, entirely on-device, so you know which of the 24 you can skip generating.
- **Language.** Switch the interface language in-app (English and Russian so far), independent of your system language.

## Storage

No database. Each wallpaper set is a plain folder of PNGs (`Clear Day.png`, `Snow Night.png`, …) plus the original image and a small `set.json`, stored in the app's iCloud Drive container. Everything syncs across your devices and stays usable even without the app. With no iCloud account the app falls back to local Documents. Settings → Storage breaks down exactly what's using space, set by set.

## Privacy

- No backend, no analytics, no accounts.
- API keys live in your Keychain and are sent only to the provider you chose.
- Location never leaves the device — it's only used for the weather request to Open-Meteo.

## Building & running

```bash
./run.sh            # iPhone + iPad simulators + Mac app
./run.sh iphone     # iPhone simulator only
./run.sh ipad       # iPad simulator only
./run.sh mac        # macOS app only
```

Or open `WeatherWallpapers.xcodeproj` in Xcode 16+ and run on iOS 17+ / macOS 14+.

**Signing note:** iCloud entitlements are restricted, so macOS **Debug** builds are signed ad-hoc without iCloud and use local storage — they run out of the box, no team required. For iCloud sync on the Mac, set your development team in Signing & Capabilities and build the **Release** configuration (Debug on iOS simulators is unaffected).

## License

MIT
