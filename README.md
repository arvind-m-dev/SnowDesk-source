# SnowDesk

A cozy snowy-desktop app for macOS 14 (Sonoma) or newer. It lives in the menu bar.

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
