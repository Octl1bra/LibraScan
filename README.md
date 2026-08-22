# LibraScan

*[中文](README.zh-Hans.md)*

A QR and barcode scanner for iPhone, and a Mac companion that types what you scan.

- **LibraScan (iOS)** — scans QR codes and barcodes, keeps the history on the device (SwiftData), exports it as TXT. No network, no account, no third-party SDK.
- **LibraScan (macOS, menu bar)** — receives each scan over the local network and **synthesizes keystrokes** into whatever text field has focus, turning the iPhone into a wireless barcode scanner. Same behaviour as a USB scanner in HID keyboard mode: the target app needs no integration at all.

```
iPhone (LibraScan)  ──scan──►  MultipeerConnectivity (encrypted P2P, no server)
                                      │
                              LibraScan for Mac (menu bar)
                                      │  CGEvent Unicode typing
                                      ▼
                          any focused text field (spreadsheet / web form / terminal)
```

Both apps live in one Xcode project and share one bundle identifier (`com.Libra.Scan`).

## How the bridge works

- **Pairing** — the Mac advertises a `librascan-key` service; the iPhone browses and invites. The first connection raises a consent dialog on the Mac, after which the device joins a trust list (manageable in Settings, and auto-accept can be turned off).
- **Typing** — `CGEvent` writes Unicode directly, so CJK text and emoji type correctly regardless of the active keyboard layout. Payloads are chunked into 20 UTF-16 units, never splitting a surrogate pair. The suffix key (Return / Tab / none) and the inter-keystroke delay are configurable.
- **Reliability** — every message carries a sequence number and is acknowledged; duplicates are answered with the recorded outcome instead of being typed twice. A 30-second heartbeat detects dead links. Scans made while offline queue on the iPhone (up to 50) and replay in order on reconnect, which can be disabled.
- **Safety** — encryption is required on the session. The menu bar has a pause switch that takes effect even mid-payload. The Mac keeps only the last five typed items, in memory. Scans always land in the iPhone's history first — the bridge is a side channel, never the system of record.

Protocol details are in [docs/MAC_KEY_BRIDGE.md](docs/MAC_KEY_BRIDGE.md) §5.

## Layout

| Path | Contents |
| --- | --- |
| `LibraScan.xcodeproj` | Two targets: `LibraScan` (iOS) and `LibraScanMac` (macOS); both produce a product named LibraScan |
| `LibraScan/` | iOS sources: `Scan/` (camera, result banner, connection sheet), `History/`, `Bridge/BridgeClient.swift` |
| `LibraScanMac/` | macOS sources: `Bridge/BridgeServer.swift`, `Typing/TypingEngine.swift`, `Updates/`, `UI/` |
| `Shared/` | `BridgeMessage.swift` — the wire protocol, compiled into both targets from a single file |
| `docs/` | [PRD](docs/PRD.md) · [Technical design](docs/TECH_SPEC.md) · [Keyboard bridge design](docs/MAC_KEY_BRIDGE.md) |
| `site/` | [scan.libra.wiki](https://scan.libra.wiki) — a static bilingual page, no build step |

## Requirements

| | iOS | macOS |
| --- | --- | --- |
| System | iOS 18.0+ | macOS 15.0+ |
| Permissions | Camera; Local Network when using the bridge | Accessibility (required to synthesize keystrokes); Local Network |
| Toolchain | Xcode 26 | Xcode 26 |

Both devices need Wi-Fi and Bluetooth switched on. They do not have to be on the same router — MultipeerConnectivity falls back to peer-to-peer Wi-Fi.

## Build

```bash
xcodebuild -project LibraScan.xcodeproj -scheme LibraScan -destination 'generic/platform=iOS' build
```

```bash
xcodebuild -project LibraScan.xcodeproj -scheme LibraScanMac build
```

## Privacy

Everything stays on your devices and your own network. Scan history lives on the iPhone; typed content exists only in the Mac's memory, five items deep, and is gone when the app quits. There is no server, no analytics, and no account. The only network request either app ever makes is the Mac app's daily version check against `scan.libra.wiki`, which sends nothing about you and can be turned off in Settings.
