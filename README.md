# Juice Bar

<img src="assets/juice-bar-wordmark.svg" width="480" alt="Juice Bar — Made for Notis">

**Your CPAMC subscriptions in the macOS menu bar. Made for Notis.**

A native CPAMC add-on that uses the compact menu design from Notis Desktop: system typography, two stacked allowance bars, green/orange/red status, a per-account list, and individual quota details.

The add-on has two parts: a **native macOS companion** and a small **CLIProxyAPI C-ABI plugin** that registers a “Juice Bar · Made for Notis” resource in CPAMC. It is a third-party extension, not an official CPAMC/CLIProxyAPI product. CPAMC and the native app read the same local CLIProxyAPI account pool.

## Screenshots

Captured directly from the native app on macOS, cropped to the menu panel. These screenshots use fictional demo subscriptions, never personal account names or credentials.

<img src="assets/screenshots/overview.png" width="720" alt="Juice Bar menu showing Claude and OpenAI subscription allowances in its native menu panel">

| Account details | All settings in one place |
| --- | --- |
| ![Subscription detail](assets/screenshots/account.png) | ![Juice Bar settings](assets/screenshots/settings.png) |

## What it shows

- Claude and Codex accounts connected to your local CPAMC/CLIProxyAPI instance, including disabled accounts. Disabled accounts show readable usage but never count as available; rows without a usage reading cannot be opened.
- Subscription plan, remaining allowance, five-hour/weekly windows, reset times, and local proxy cooldowns.
- Paid credits and extra-usage availability separately from included subscription quotas.
- Unused Claude promotional reset counts, without consuming them.
- Native light/dark appearance, English/French, a privacy switch, launch-at-login, and connection testing.
- Separate Claude session and weekly bars, left to right.
- A **Use this account** toggle inside each subscription’s detail view. It changes that exact account in CPAMC, verifies the result, and leaves every other account untouched.
- Explicit Start/Stop controls for a matching local CLIProxyAPI login service.

Percentages are **not added across subscription accounts**. By default, the menu-bar icon shows the best available account's tightest shared allowance for each provider, in OpenAI/Claude order. Details expose model-specific windows separately. An old reading or an elapsed reset is not presented as newly available quota.

## Menu-bar icon preferences

Open **Settings** for a live preview and automatically saved preferences:

- **Vertical or horizontal** — two side-by-side gauges or two stacked gauges.
- **Color or black & white** — quota colors or native macOS template tint, matching neighboring menu-bar icons and adapting to light/dark backgrounds.
- **OpenAI + Claude** — each provider's best available account, using its tighter session/weekly limit.
- **Session + weekly** — sum OpenAI + Claude, out of 200% per window (100% per provider). One best available account per provider contributes both windows. This equal-weight quota indicator is not a combined token/credit balance. If one provider has no reading, the combined bar shows the known contribution as a lower bound (≥), still out of 200%, and names the unreported provider in the tooltip. Missing values never erase known allowance. Both missing means unknown, not zero.

The first metric is on the left (vertical) or top (horizontal). Disabled, stale and unavailable accounts do not contribute usable quota. Unreported limits and confirmed zero quota keep an empty outline; the tooltip distinguishes “No reading” from exhausted quota. The default is vertical, color, OpenAI + Claude. The app logo is the vertical **Twin Meter** design, paired with the Juice Bar wordmark.

## Requirements

- macOS 13 or later and Xcode Command Line Tools with Swift 6 or later.
- CPAMC backed by a running local CLIProxyAPI. Tested with CLIProxyAPI 8.0.4 and CPAMC 1.26.2.
- Its management key available in a local text file. CPAMC's dashboard password is the management key, not a client API key.

## Build and install

```sh
git clone https://github.com/mindtheflo/juice-bar.git
cd juice-bar
swift test
bash scripts/build.sh
bash scripts/install.sh
```

The repository also includes the built `dist/Juice Bar.app` and `dist/Juice Bar.app.zip` artifacts. The zip is the portable distribution copy and preserves executable permissions when extracted. Local builds are ad-hoc signed by default. To sign with an installed Apple Developer ID certificate, pass its exact identity:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Company (TEAMID)" bash scripts/build.sh
```

The signed bundle is still subject to Apple's notarization and Gatekeeper checks; notarization is not run by this repository build.

There is no standalone app window or Dock icon: the subscription panel is a compact, arrow-free dropdown anchored to the menu-bar icon. It closes on an outside click or Escape.

The app installs into `~/Applications/Juice Bar.app` and opens immediately. Its two allowance bars appear in the macOS menu bar. Click them to inspect subscriptions, or choose **Open CPAMC** to open the existing quota dashboard.

Enable **Launch at login** in Settings, or install with:

```sh
bash scripts/install.sh --login
```

The local build is ad-hoc signed, not notarized with an Apple distribution certificate. Build from source on your Mac; signing/notarization for downloadable releases is not configured.

## Connect your CPAMC instance

The default connection is `http://127.0.0.1:8317`, with the key read from:

```
~/Library/Application Support/CLIProxyAPI/management-key
```

Choose **Settings…** in the menu to change the URL or select an existing key file. Only loopback connections are accepted. The key remains in that file; this app does not copy credentials, log response bodies, or package secrets.

**Upgrading from CPAMC Menu Bar:** Juice Bar keeps the same bundle identity, plugin ID and URL scheme so your preferences and CPAMC integration continue to work. The installer moves only the old, verified app bundle to Trash; it keeps your configuration.

Configuration is stored in `~/Library/Application Support/CPAMC Menu Bar/config.json`. A key-file path is stored, not the key itself. `config.example.json` shows the supported fields.

## Quotas are read-only

The app reads `/v0/management/auth-files` every 30 seconds. Every five minutes (or on explicit Refresh, with a 30-second minimum between reads), it asks the proxy to perform **GET-only** Claude usage/profile and Codex usage queries via `/v0/management/api-call`. Provider OAuth tokens are substituted by the proxy using `$TOKEN$`; they are never read from credential files by this app.

It makes **no model requests**, never buys/enables extra usage, never consumes promotional resets, never clears cooldowns, and never edits tokens. The explicit account toggle updates only that account’s enabled/disabled state through the management API; it does not change routing strategy or other accounts. The explicit Start/Stop buttons only control the matching local proxy process; stopping it interrupts agents using that proxy. The proxy continues running independently when this app quits. Service controls are available only when the existing `~/Library/LaunchAgents/com.flo.cliproxyapi.plist` points to the same CLIProxyAPI installation and port; unrelated services cannot be controlled. HTTP redirects are rejected to prevent the local management key from being forwarded elsewhere.

No analytics, cloud account, Notis sign-in, or third-party packages are required. Connection diagnostics never include keys or raw provider errors.

## Diagnostics

```sh
swift run cpamc-quota-check
```

This prints a live, redacted quota snapshot and exits. Use `--show-names` only when you intentionally want account names in your terminal. Disabled accounts are queried read-only too; a failed reading leaves the account disabled and never makes it available for routing. `cpamc-menubar --demo` uses fictional labels and no network calls, for screenshots/UI review.

## CPAMC plugin integration

The build also produces `dist/plugin/cpamc-menubar.dylib` for the current Mac architecture. Copy it into your CLIProxyAPI plugin directory, then enable only `cpamc-menubar` in your existing plugin configuration:

```yaml
plugins:
  enabled: true
  dir: /absolute/path/to/your/plugins
  configs:
    cpamc-menubar:
      enabled: true
```

Preserve any existing plugin settings. The plugin uses CLIProxyAPI's stable C ABI (version 1), and registers only a management resource: no model, routing, credential, quota or interception hooks. CPAMC lists its “Juice Bar · Made for Notis” page in the plugin menu. Its resource is available at `/v0/resource/plugins/cpamc-menubar/menubar` and links to the installed native app, this repository and the existing quota dashboard. The resource page never reads keys or account data.

The native companion works even when you do not install the dashboard plugin. Disabling/removing this plugin does not stop the companion or the proxy.

## Remove it

```sh
bash scripts/uninstall.sh
```

Only this companion and its optional login item are removed. CPAMC, CLIProxyAPI, Notis, all credentials and routing remain untouched. Local settings are retained.

If you installed the dashboard integration, disable/remove `cpamc-menubar` from CPAMC's Plugins page separately.

## Development

```sh
swift test
swift run cpamc-menubar --demo
```

The dependency-free `QuotaCore` target handles normalization, freshness, subscription aggregation and local proxy I/O. The SwiftUI target provides the native menu. Tests cover shared vs model-specific limits, cooldowns, stale/unknown readings, disabled accounts, quota resets, provider payload formats, loopback-only connections, exact-account toggling and lost-response reconciliation.

Inspired by Notis Desktop's menu-bar usage design. This repository contains no Notis product code or third-party provider logos. See [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) and [CPAMC](https://github.com/router-for-me/Cli-Proxy-API-Management-Center) for the upstream projects.

## License

[MIT](LICENSE) © 2026 Florian Pariset. Source, original branding assets and repository screenshots are included under this license.

Juice Bar is an independent project; it is not affiliated with PromptJuice or other similarly named products. Provider names belong to their respective owners.
