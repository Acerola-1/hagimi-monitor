# HagimiMonitor

> [中文](README.md) · [Website](https://acerola-1.github.io/hagimi-monitor/)

<p align="center">
  <img src="docs/images/icon.png" width="132" alt="HagimiMonitor icon">
</p>

<p align="center">
  <strong>Your Mac, at a Glance.</strong>
</p>

<p align="center">
  HagimiMonitor is an elegant macOS menu bar system monitor that displays CPU, GPU, memory, storage, network, battery, and display status through a dynamic ring and a compact glass panel.
</p>

<p align="center">
  <a href="https://github.com/Acerola-1/hagimi-monitor/releases/latest"><strong>Download Latest</strong></a> ·
  <a href="#highlights">Highlights</a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#build">Build</a>
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

### Seven Monitoring Modules

From the menu bar to the detailed panel, key metrics are always within reach:

- **CPU**: system / user / idle usage, uptime, temperature reading, process-level usage
- **GPU**: graphics load, render / tiler performance, VRAM info
- **Memory**: usage rate, memory pressure, swap, pressure level changes
- **Storage**: system disk, external volumes, read / write rates
- **Network**: upload / download rates, network interface type, IP information
- **Battery & Power**: level, power status, power draw, health, and other available info
- **Display**: brightness, volume, and contrast control depending on DDC/CI support

### Glass UI and Unified Colors

The panel uses a lightweight glassmorphism UI, with a unified Palette for module accents, status semantics, dividers, progress tracks, and light / dark mode adaptation.

### Statistics, Health Score, and Event Detection

HagimiMonitor provides longer-term views around system state:

- 0-100 Mac health score across CPU, GPU, disk, memory pressure, and thermal dimensions
- Multi-range statistics for 24 hours, 7 days, 30 days, and one year
- Automatic detection for CPU high load, memory pressure, low disk space, network traffic peaks, and other key events

### External Display Control

Adjust brightness, volume, and contrast for external displays from the menu bar via DDC/CI. This depends on display, cable, connection, and system support; unsupported controls are not shown as available.

### Native Swift, Lightweight Resident

Built with Swift / SwiftUI and optimized for Apple Silicon. Daily memory footprint is around 50 MB, making it suitable as a long-running menu bar status panel.

## Installation

1. Download the latest `.dmg` from [Releases](https://github.com/Acerola-1/hagimi-monitor/releases/latest)
2. Open the DMG and drag HagimiMonitor into the Applications folder
3. Launch it from Launchpad or Applications

## Allowing Unsigned Apps

HagimiMonitor is currently not notarized by Apple, so macOS may block it. After installation, run in Terminal:

```bash
sudo xattr -cr /Applications/HagimiMonitor.app
```

Then launch normally.

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
