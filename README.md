# SnowDesk

A cozy snowy-desktop app for macOS 14 (Sonoma) or newer. It lives in the menu bar.

## What it does

- Snow that piles up on your windows, rain, storms, leaves, petals, fireflies, mist, clouds and shooting stars. Mix several at once.
- Seasons (Winter, Spring, Summer, Autumn, Monsoon) that set the weather, trees and river, optionally following the calendar.
- Festivals: Christmas, New Year, Valentine's Day, Easter, Holi, Halloween and Diwali, by date or by hand.
- Birds that fly in, perch on windows (and on buttons, rows and dividers with Accessibility allowed) and hop about; bats that hang under ledges; butterflies; skiers and sledders that jump off window ledges; a river along the bottom.
- Seven snowman styles, 14 painted wallpapers, Christmas lights, a fireplace, a cozy room, Santa, a snowplough, frost and a snow globe.

It never gets in your way: clicks and typing always go to your apps, things fade when the pointer is near, hold ⌘ to drag or click them, and press ⌃⌥S to hide everything. The Performance menu has a Battery Saver mode (used automatically in Low Power Mode).

## Install (no build needed)

Paste in Terminal:

```bash
curl -fsSL https://github.com/arvind-m-dev/SnowDesk/releases/latest/download/install.sh | bash
```

## Build and customize

1. Install Apple's free developer tools (once):
   ```bash
   xcode-select --install
   ```
2. Edit the Swift files in `Sources/SnowDesk`.
3. Build:
   ```bash
   ./build.sh
   ```
   This makes `SnowDesk.app` (universal: Apple silicon and Intel) and `dist/SnowDesk.zip`.
   An app built on your own Mac opens without a Gatekeeper warning.

## License

MIT. See [LICENSE](LICENSE).
