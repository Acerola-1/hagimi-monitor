# HagimiMonitor

> [中文](README.md) · [Website](https://acerola-1.github.io/hagimi-monitor/)

<p align="center">
  <img src="docs/images/icon.png" width="132" alt="HagimiMonitor icon">
</p>

<p align="center">
  <strong>Your Mac, at a Glance.</strong>
</p>

<p align="center">
  HagimiMonitor is an elegant macOS menu bar system monitor that displays CPU, GPU, memory, storage, network, battery, Bluetooth, and display status through a dynamic ring and a compact glass panel, with built-in data statistics reports and quick tools like keyboard lock.
</p>

<p align="center">
  <a href="https://github.com/Acerola-1/hagimi-monitor/releases/latest"><strong>Download Latest</strong></a> ·
  <a href="https://apps.apple.com/app/hagimimonitor/id6792169908"><strong>App Store</strong></a> ·
  <a href="#editions">Editions</a> ·
  <a href="#highlights">Highlights</a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#build">Build</a>
</p>

<p align="center">
  <a href="https://github.com/Acerola-1/hagimi-monitor/releases/latest">
    <img alt="Download from GitHub" src="https://img.shields.io/badge/GitHub-Free%20Download-2ECC71?style=for-the-badge&logo=github&logoColor=white" height="42">
  </a>
  &nbsp;
  <a href="https://apps.apple.com/app/hagimimonitor/id6792169908">
    <img alt="Download on the App Store" src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" height="42">
  </a>
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-111827?style=flat-square&logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-M%20series-2ECC71?style=flat-square&logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square">
  <img alt="Commercial" src="https://img.shields.io/badge/commercial-licensing%20available-2ECC71?style=flat-square">
  <a href="https://x.com/Acerola64175279"><img alt="Follow on X" src="https://img.shields.io/badge/X-@Acerola64175279-000000?style=flat-square&logo=x"></a>
</p>

## Screenshots

### Multi-Theme Color Schemes

HagimiMonitor includes a semantic Palette. Module colors, glass backgrounds, dividers, progress tracks, and status colors change consistently with the selected theme. It currently offers Balanced and Vibrant styles, fully adapted for light / dark mode.

| Balanced · Dark | Balanced · Light |
| --- | --- |
| ![Balanced dark theme](docs/images/balance-dark.png) | ![Balanced light theme](docs/images/balance-light.png) |

| Vibrant · Dark | Vibrant · Light |
| --- | --- |
| ![Vibrant dark theme](docs/images/vitality-dark.png) | ![Vibrant light theme](docs/images/vitality-light.png) |

### Expand for Details

The default state stays compact. Click the menu bar item to expand complete details for CPU, GPU, memory, storage, network, battery, displays, and more.

<p align="center">
  <img src="docs/images/detailed-data.png" width="430" alt="HagimiMonitor expanded rich metrics">
</p>

## Highlights

### Visible Directly from the Menu Bar

The dynamic ring icon reflects system load in real time, smoothly combining CPU and GPU usage into one pressure indicator. Light load, busy, or near critical — visible at a glance.

### Eight Monitoring Modules

From the menu bar to the detailed panel, key metrics are always within reach:

- **CPU**: system / user / idle usage, uptime, P/E split, thermal pressure; the direct edition adds temperature reading and per-core load rings
- **GPU**: graphics load, render / tiler performance, VRAM info, process-level usage
- **Memory**: usage rate, memory pressure, swap, compressed memory, pressure level changes
- **Storage**: system disk, external volumes, read / write rates, SMART health
- **Network**: upload / download rates, interface type, IP info, Wi-Fi signal and latency
- **Battery & Power**: level, power status, power draw, health, cycle count, and other available info
- **Bluetooth**: battery monitoring for connected devices (GATT-first reading)
- **Display**: display info in both editions; brightness / volume / contrast control depends on DDC/CI support (direct edition only)

> CPU temperature and fan speed rely on SMC (AppleSMC), which is inaccessible to the App Store sandbox, so they are only available in the direct edition.

### Glass UI and Unified Colors

The panel uses a lightweight glassmorphism UI, with a unified Palette for module accents, status semantics, dividers, progress tracks, and light / dark mode adaptation.

### Menu Bar Styles, Your Choice

More than just the dynamic ring — icon, text, and compact single-line layouts are all available, with a static total width that never jitters. You can also pin the panel and summon it with a global shortcut.

### Statistics and Health Score

HagimiMonitor provides longer-term views and generates a web report (defaults to today; switchable to 24 hours / 7 days / 30 days / one year):

- Sampling into SQLite with minute / hour / day aggregation to auto-generate an HTML report with trend curves and heatmaps
- 0-100 Mac health score across CPU, GPU, disk, fan, and memory pressure dimensions
- Automatic detection for CPU high load, memory pressure, low disk space, network traffic peaks, and other key events

### Quick Tools

Keyboard lock (blocks all keys including F1–F12, with a 20-minute auto-unlock fallback), system sleep prevention, and display-awake — togglable from the menu bar or pinned panel, with active state lit up in real time in the panel header.

### External Display Control

Adjust brightness, volume, and contrast for external displays from the menu bar via DDC/CI. This depends on display, cable, connection, and system support; unsupported controls are not shown as available.

### Native Swift, Lightweight Resident

Built with Swift / SwiftUI and optimized for Apple Silicon. Daily memory footprint is around 50 MB, making it suitable as a long-running menu bar status panel.

## Editions

HagimiMonitor offers two ways to get it, with the same core monitoring experience; due to App Store sandbox restrictions, some features are only available in the GitHub direct edition:

| Feature | GitHub (Free) | App Store (Support) |
| --- | :---: | :---: |
| Eight monitoring modules (CPU / GPU / Memory / Storage / Network / Battery / Bluetooth / Display) | ✅ | ✅ |
| Statistics · Health score · Event detection (HTML report + storage management) | ✅ | ✅ |
| Quick tools (keyboard lock / sleep prevention / display-awake) | ✅ | ✅ |
| Dual themes · Glassmorphism · Multiple menu bar styles | ✅ | ✅ |
| CPU top process list | ✅ | ✅ |
| Memory top process list | ✅ | ✅ |
| Storage / network top process list | ✅ | ❌ Sandbox limit |
| Temperature sensor reading (CPU temperature) | ✅ | ❌ SMC sandbox limit |
| Fan speed reading | ✅ | ❌ SMC sandbox limit |
| External display control (DDC/CI brightness / volume / contrast) | ✅ | ❌ Sandbox limit |
| Media key capture | ✅ | ❌ Sandbox limit |
| Updates | Built-in auto-update | App Store updates |
| Price | Free | Paid · Support the developer |

> Due to App Store sandbox restrictions, some features cannot work properly in the sandboxed environment, so the App Store edition is not feature-complete.

> 💚 **The App Store edition is a token of thanks**: both editions share the same core monitoring experience. If HagimiMonitor helps you and you don't need the out-of-sandbox features — display control, storage / network top processes, temperature / fan readings — buying it on the [App Store](https://apps.apple.com/app/hagimimonitor/id6792169908) is like leaving a coffee — a small, sincere way to support and encourage an indie developer. Whichever edition you choose, thank you all the same.

## Installation

1. Download the latest `.dmg` from [Releases](https://github.com/Acerola-1/hagimi-monitor/releases/latest)
2. Open the DMG and drag HagimiMonitor into the Applications folder
3. Launch it from Launchpad or Applications

The app is notarized by Apple and opens directly after download.

## Requirements

- macOS 15 or later
- Apple Silicon (M-series chips)

## Build

For development, use the `HagimiMonitorDirect` scheme:

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

Release / App Store build:

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Release build
```

Run tests:

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug test
```

## Star History

<p align="center">
  <a href="https://star-history.com/#Acerola-1/hagimi-monitor&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Acerola-1/hagimi-monitor&type=Date&theme=dark" />
      <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Acerola-1/hagimi-monitor&type=Date" />
      <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Acerola-1/hagimi-monitor&type=Date" width="720" />
    </picture>
  </a>
</p>

<p align="center">
  If this project helps you, a ⭐ would mean a lot for continued maintenance.
</p>

## License

This project is dual-licensed under **GNU AGPL-3.0**:

- **Open-source use**: The source is public and may be freely used, modified, and
  distributed under the [AGPL-3.0](LICENSE). As required by the AGPL, any derivative
  work — including software offered as a network service — must also release its
  complete source under AGPL-3.0.
- **Commercial use**: If you wish to use this project in a commercial product
  **without complying with the AGPL's copyleft obligations** (e.g. closed-source
  distribution or paid distribution without publishing source), you **must obtain a
  commercial license**. Open an issue or contact the author via
  [GitHub](https://github.com/Acerola-1/hagimi-monitor).

Copyright © 2026 Acerola. All rights reserved.

### Third-Party Components

Third-party libraries are governed by their own licenses, independent of this
project's AGPL/commercial terms:

- **Sparkle** (auto-update framework) — MIT-style license
