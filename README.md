<p align="center">
  <img src="Assets/NetDog.png" width="128" alt="NetDog logo">
</p>

<h1 align="center">NetDog</h1>

<p align="center">A minimal macOS menu bar network monitor, extracted from <a href="https://github.com/exelban/stats">Stats</a>.</p>

<p align="center">macOS 13+ · Swift · MIT License</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

## Features

- Live download/upload speed in the menu bar (two-row or one-row, dots/arrows/no icon, units toggle, monochrome, idle threshold)
- Stats-style popup: usage history chart, connectivity history grid, traffic totals, interface & Wi-Fi details, addresses, top processes — every section can be enabled/disabled
- Bandwidth from interface counters (`sysctl NET_RT_IFLIST2`) or per-process totals (`nettop`)
- Connectivity probe: ICMP first, HTTP fallback; latency and jitter
- Public IP lookup (`ip.mac-stats.com`) with optional auto-refresh
- Usage totals persisted across launches, with never/at-start/daily/weekly/monthly reset
- Full network settings ported from Stats and applied live
- Launch at login

## Screenshots

<table>
  <tr>
    <td align="center"><img src="Assets/screenshots/popup.png" width="260" alt="Popup"></td>
    <td align="center"><img src="Assets/screenshots/settings.png" width="560" alt="Settings"></td>
  </tr>
  <tr>
    <td align="center">Popup</td>
    <td align="center">Settings</td>
  </tr>
</table>

## Install

1. Download `NetDog-0.2.2.zip` from [Releases](https://github.com/hellolib/netdog/releases).
2. Unzip and drag `NetDog.app` into `/Applications`.
3. The app is ad-hoc signed. If macOS blocks the first launch, right-click the app → **Open**.

Requires macOS 13 or later.

## Build from source

Xcode Command Line Tools are enough (no SwiftPM needed):

```bash
make app     # build build/NetDog.app (swiftc + ad-hoc signing)
make run     # build and launch
make check   # compare sampling against netstat
make dist    # produce build/NetDog-<version>.zip
make install # copy to /Applications
```

## Configuration

Click the menu bar item → right-click → **Settings…**. Options are grouped as:

- **General** — refresh interval, bandwidth source (interface/process), interface selection, process count
- **Display** — byte/bit base, speed unit, menu bar rows/icon/units/monochrome, idle threshold, country flags
- **Chart** — history length, scale (linear/square/cube/log/fixed), upload-on-top, download/upload colors
- **Popup sections** — show or hide each of the six popup sections
- **Usage** — reset policy
- **Public IP** — enable, auto-refresh interval
- **Connectivity** — auto/ICMP/HTTP, hosts, probe interval
- **Launch** — launch at login

## Permissions

- **Location** — required to read the Wi-Fi SSID/BSSID (macOS 10.15+). The popup offers a shortcut button when access has not been granted.
- No sandbox, no network extension, no privileged helper.

## Data sources

- Interface bandwidth: `sysctl(NET_RT_IFLIST2)` byte counters
- Process bandwidth: `nettop` (all interfaces)
- Connectivity: ICMP echo by default (`223.5.5.5`), automatic HTTP fallback (`captive.apple.com`)
- Public IP: `ip.mac-stats.com`

## Credits

Based on [Stats](https://github.com/exelban/stats) by Serhiy Mytrovtsiy (MIT). The app icon is derived from the Stats waveform motif.

## License

[MIT](LICENSE)
