# Rokid Govee HUD


> **🔵 Connectivity Update — May 2025**
> The glasses connection has been migrated from **raw TCP sockets** to
> **Bluetooth via the Rokid AI glasses SDK** (`pod 'RokidSDK' ~> 1.10.2`).
> No Wi-Fi port forwarding is needed. See **SDK Setup** below.

Control your Govee smart lights from Rokid AR glasses — via your iPhone as a bridge.

```
Govee Cloud API  ←→  iPhone App  ──Bluetooth/RokidSDK──▶ Rokid Glasses
  (OpenAPI v1)         (this app)                 (display + commands)
   poll + control      relay + UI
```

---

## Features

- **Live device list** — all your Govee lights polled from the cloud, streamed to glasses
- **On/Off toggle** — tap the device row or speak from glasses
- **Brightness control** — slider with live preview, per device or all at once
- **Color temperature** — warm-to-cool slider (2000–9000 K), auto-ranges per device
- **RGB colour presets** — 10 one-tap colour presets (warm white, red, cyan, purple…)
- **State change alerts** — when a light turns on/off the glasses get an instant update
- **Glasses commands** — control everything hands-free via text or voice from the glasses

---

## SDK Setup

The glasses now connect over **Bluetooth via the Rokid AI glasses SDK** — no Wi-Fi port or TCP server needed.

The only thing left for each app is filling in the three credential constants (`kAppKey`, `kAppSecret`, `kAccessKey`) from [account.rokid.com/#/setting/prove](https://account.rokid.com/#/setting/prove), then running `pod install`.

1. **Get credentials** at <https://account.rokid.com/#/setting/prove> and paste them into the glasses Swift file:
   ```swift
   private let kAppKey    = "YOUR_APP_KEY"
   private let kAppSecret = "YOUR_APP_SECRET"
   private let kAccessKey = "YOUR_ACCESS_KEY"
   ```

2. **Install CocoaPods dependencies** from the repo root:
   ```bash
   pod install
   open *.xcworkspace   # always open the .xcworkspace, not .xcodeproj
   ```

3. *(Glasses now connect automatically over Bluetooth — no TCP port needed.)*

## Quick Start

### 1. Get your Govee API key

1. Open **Govee Home** app on your phone
2. Go to **Settings → About → Apply for API Key**
3. Key arrives by email within a few minutes

### 2. Install the iOS app

Open `RokidGovee.xcodeproj` in Xcode 15+, select your iPhone, and run.

### 3. Add your API key

Open the app → **Settings** tab → paste your key.  
The app fetches your devices immediately and starts polling every 30 seconds.

### 4. Put on your glasses

Glasses connect to the iPhone on **:8103** and receive device state automatically.

---

## Glasses Commands

Send `{"type":"cmd","text":"<command>"}` (JSON, newline-terminated) over TCP :8103.

| Command | What it does |
|---------|-------------|
| `all on` / `lights on` | Turn all devices on |
| `all off` / `lights off` | Turn all devices off |
| `brightness 50` | Set all devices to 50% |
| `dim 30` | Set all devices to 30% |
| `<device name> on` | Turn one device on |
| `<device name> off` | Turn one device off |
| `<device name> brightness 75` | Set one device to 75% |
| `refresh` | Fetch latest state from Govee cloud |
| `summary` / `status` | Push current summary to glasses |

Device names are matched case-insensitively against your Govee device names.

---

## Wire Protocol (iPhone → Glasses)

JSON packets, newline-delimited, over TCP :8103:

```json
{"type":"devices",       "text":"2/4 lights on\nOn: Living Room, Desk"}
{"type":"device_change", "text":"💡 Living Room: ON · bri:80%"}
{"type":"control",       "text":"⚙️ Desk Lamp: brightness 50%"}
{"type":"error",         "text":"⚠️ Govee API 429: rate limit"}
{"type":"status",        "text":"Rokid Govee HUD — say a command"}
```

### Display Formats

| Format | What glasses see |
|--------|-----------------|
| **Minimal** | `2/4 lights on` (single line) |
| **Summary** | `2/4 lights on` + `On: Living Room, Desk` |
| **Device List** | Up to 8 devices with 💡/○ icon and brightness |

---

## Govee API

| Detail | Value |
|--------|-------|
| Base URL | `https://openapi.api.govee.com/router/api/v1` |
| Auth header | `Govee-API-Key: <your key>` |
| List devices | `GET /user/devices` |
| Get state | `POST /device/state` |
| Control | `POST /device/control` |
| Rate limit | ~10 req/min per device |

All control commands include a `requestId` (UUID) as required by the API.

---

## Supported Capabilities

The app reads the `capabilities` array from the device list and shows only the controls each device actually supports:

| Capability type | What it unlocks |
|-----------------|----------------|
| `devices.capabilities.on_off` | Power toggle |
| `devices.capabilities.range` (brightness) | Brightness slider |
| `devices.capabilities.color_setting` | Colour presets |
| `devices.capabilities.color_temp` | Colour temperature slider |

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| iPhone | iOS 17+, internet access for Govee cloud |
| Xcode | 15.0+ |
| Govee account | Free — API key from Govee Home app |
| Glasses | Rokid AR glasses on same Wi-Fi as iPhone |
| CocoaPods | 1.15+ — run `pod install` after cloning |

---

## Project Structure

```
rokid-govee-ios/
└── RokidGovee/
    ├── App/
    │   ├── RokidGoveeApp.swift         ← @main entry point
    │   └── Info.plist                  ← local network permission
    ├── Data/
    │   └── GoveeModels.swift           ← all Codable structs + GlassesFormat + ColorPreset
    ├── Networking/
    │   └── GoveeAPIClient.swift        ← actor; list/state/control via Govee OpenAPI v1
    ├── Glasses/
    │   └── GlassesServer.swift         ← NWListener :8103, broadcast + inbound commands
    ├── ViewModel/
    │   └── GoveeViewModel.swift        ← polling, control, glasses command handler
    └── UI/
        ├── ContentView.swift           ← TabView root
        ├── DeviceListView.swift        ← device list with stats, all-on/off, device rows
        ├── DeviceDetailView.swift      ← power, brightness, colour temp, colour presets
        └── SettingsView.swift          ← API key, poll interval, glasses format, commands ref
```

---

## Part of the Rokid iOS Bridge Suite

| App | Source | TCP Port | Data Source |
|-----|--------|----------|-------------|
| [rokid-claude-ios](https://github.com/kbaker827/rokid-claude-ios) | Claude AI | :8095 | Anthropic API |
| [rokid-chatgpt-ios](https://github.com/kbaker827/rokid-chatgpt-ios) | ChatGPT | :8096 | OpenAI API |
| [rokid-lansweeper-ios](https://github.com/kbaker827/rokid-lansweeper-ios) | Lansweeper | :8097 | GraphQL API |
| [rokid-teams-ios](https://github.com/kbaker827/rokid-teams-ios) | MS Teams | :8098 | Graph API |
| [rokid-outlook-ios](https://github.com/kbaker827/rokid-outlook-ios) | Outlook | :8099 | Graph API |
| [rokid-compass-ios](https://github.com/kbaker827/rokid-compass-ios) | Compass | :8100 | CoreLocation |
| [rokid-powershell-ios](https://github.com/kbaker827/rokid-powershell-ios) | PowerShell | :8101/:8102 | TCP Bridge |
| **rokid-govee-ios** | **Govee Lights** | **:8103** | **Govee OpenAPI v1** |
