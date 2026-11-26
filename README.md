# ESP Flasher for macOS

A small, native SwiftUI app that flashes ESP32 boards using the `esptool` you already have installed.

- **Device list** – every `/dev/cu.*` serial port, auto-refreshed; USB-UART bridges (CP210x, CH340/CH9102, native USB) are listed first
- **Flash** – add one or more `.bin` files (drag & drop or file picker), set each flash address, pick a baud rate, optionally erase first, watch live progress
- **Chip info / Erase** – one-click `flash_id` and `erase_flash`
- **Serial monitor** – baud rates from 9600 to 2,000,000 (including 74880 for ESP boot-ROM messages), send box with line-ending choice, RTS reset button, autoscroll, clear, save log
- **Themes** – Light, Dark and Hacker (green-on-black, monospaced)

The monitor automatically disconnects while flashing on the same port and reconnects afterwards.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools (`xcode-select --install`) or Xcode, for Swift 5.9+
- `esptool` – if it's missing, the app shows a warning with an **Install esptool** button that runs `brew install esptool` (or `pipx` / `pip --user` if Homebrew isn't present). With none of those available it links to [brew.sh](https://brew.sh).

The app looks for esptool in the usual Homebrew / `~/.local/bin` locations and then asks a login shell (`command -v esptool`), so it works when launched from Finder. If yours lives elsewhere, use **Change / Locate…** in the Flash tab. Both esptool v4 (`write_flash`) and v5 (`write-flash`) are supported.

## Build & run

```bash
git clone https://github.com/DRMx86/esptoolmacos
cd esptoolmacos

# Quick run from the terminal
swift run

# Or build a double-clickable app bundle
./scripts/build_app.sh
open "build/ESP Flasher.app"

# Optional: universal binary and/or install to /Applications
UNIVERSAL=1 INSTALL=1 ./scripts/build_app.sh
```

You can also open `Package.swift` in Xcode and press Run.

The bundle is ad-hoc signed. If macOS blocks it the first time, right-click → Open (or run `xattr -dr com.apple.quarantine "build/ESP Flasher.app"`).

## Flashing tips

| Image | Typical address |
| --- | --- |
| Merged image (`*.merged.bin`, "factory") | `0x0` |
| Application only (`firmware.bin`, `*.ino.bin`) | `0x10000` |
| Partition table | `0x8000` |
| `boot_app0.bin` | `0xe000` |
| Bootloader | `0x1000` on ESP32 · `0x0` on ESP32-S3/C3/C6/H2 |

The app guesses an address from the file name; always check it for your chip.

If the connection fails, hold the **BOOT** button while it connects, use a data-capable USB cable, or try a lower baud rate. Some boards need the [CP210x](https://www.silabs.com/developer-tools/usb-to-uart-bridge-vcp-drivers) or CH340 driver.

## Project layout

```
Sources/ESPFlasher/
  ESPFlasherApp.swift   app entry
  ContentView.swift     window shell, sidebar (devices + theme), tabs
  FlashView.swift       flashing UI
  MonitorView.swift     serial monitor UI
  TerminalView.swift    fast NSTextView-backed output
  Flasher.swift         esptool discovery and process runner
  SerialMonitor.swift   termios serial I/O
  PortScanner.swift     serial device listing
  Theme.swift           Light / Dark / Hacker palettes
  Components.swift      shared styled controls
Resources/Info.plist
scripts/build_app.sh
```

The app icon lives in `Resources/AppIcon.icns` (source: `Resources/AppIcon.png`); `build_app.sh` copies it into the bundle.
