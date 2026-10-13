# CPAMC Menu Bar

**Your CPAMC subscriptions in the macOS menu bar. Made for Notis.**

A native, read-only CPAMC add-on that uses the compact menu design from Notis Desktop: system typography, two stacked allowance bars, green/orange/red status, a per-account list, and individual quota details.

The add-on has two parts: a **native macOS companion** and a small **CLIProxyAPI C-ABI plugin** that registers a “Menu Bar · Made for Notis” resource in CPAMC. It is a third-party extension, not an official CPAMC/CLIProxyAPI product. CPAMC and the native app read the same local CLIProxyAPI account pool.

## What it shows

- Claude and Codex accounts connected to your local CPAMC/CLIProxyAPI instance, including disabled accounts. Disabled accounts show readable usage but never count as available; rows without a usage reading cannot be opened.
- Subscription plan, remaining allowance, five-hour/weekly windows, reset times, and local proxy cooldowns.
- Paid credits and extra-usage availability separately from included subscription quotas.
- Unused Claude promotional reset counts, without consuming them.
- Native light/dark appearance, English/French, a privacy switch, launch-at-login, and connection testing.
- Separate Claude session and weekly bars, left to right.
- Explicit Start/Stop controls for a matching local CLIProxyAPI login service.

Percentages are **not added across subscriptions**. The menu-bar icon shows the best account's tightest shared allowance for each provider, in Codex/Claude order. Details expose model-specific windows separately. An old reading or an elapsed reset is not presented as newly available quota.

## Requirements

- macOS 13 or later and Xcode Command Line Tools with Swift 6 or later.
- CPAMC backed by a running local CLIProxyAPI. Tested with CLIProxyAPI 8.0.4 and CPAMC 1.26.2.
- Its management key available in a local text file. CPAMC's dashboard password is the management key, not a client API key.

## Build and install

```sh
git clone https://github.com/mindtheflo/cpamc-menubar.git
cd cpamc-menubar
swift test
bash scripts/build.sh
bash scripts/install.sh
```

There is no standalone app window or Dock icon: the subscription panel is a transient popover anchored to the menu-bar icon.

The app installs into `~/Applications/CPAMC Menu Bar.app` and opens immediately. Its two allowance bars appear in the macOS menu bar. Click them to inspect subscriptions, or choose **Open CPAMC** to open the existing quota dashboard.

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

Configuration is stored in `~/Library/Application Support/CPAMC Menu Bar/config.json`. A key-file path is stored, not the key itself. `config.example.json` shows the supported fields.

## Quotas are read-only

The app reads `/v0/management/auth-files` every 30 seconds. Every five minutes (or on explicit Refresh, with a 30-second minimum between reads), it asks the proxy to perform **GET-only** Claude usage/profile and Codex usage queries via `/v0/management/api-call`. Provider OAuth tokens are substituted by the proxy using `$TOKEN$`; they are never read from credential files by this app.

It makes **no model requests**, never buys/enables extra usage, never consumes promotional resets, never clears cooldowns, and never edits credentials or routing. The explicit Start/Stop buttons only control the matching local proxy process; stopping it interrupts agents using that proxy. The proxy continues running independently when this app quits. Service controls are available only when the existing `~/Library/LaunchAgents/com.flo.cliproxyapi.plist` points to the same CLIProxyAPI installation and port; unrelated services cannot be controlled. HTTP redirects are rejected to prevent the local management key from being forwarded elsewhere.

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

Preserve any existing plugin settings. The plugin uses CLIProxyAPI's stable C ABI (version 1), and registers only a management resource: no model, routing, credential, quota or interception hooks. CPAMC lists its “Menu Bar · Made for Notis” page in the plugin menu. Its resource is available at `/v0/resource/plugins/cpamc-menubar/menubar` and links to the installed native app, this repository and the existing quota dashboard. The resource page never reads keys or account data.

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

The dependency-free `QuotaCore` target handles normalization, freshness, subscription aggregation and local proxy I/O. The SwiftUI target provides the native menu. Tests cover shared vs model-specific limits, cooldowns, stale/unknown readings, disabled accounts, quota resets, provider payload formats and loopback-only connections.

Inspired by Notis Desktop's menu-bar usage design. This repository contains no Notis product code or third-party provider logos. See [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) and [CPAMC](https://github.com/router-for-me/Cli-Proxy-API-Management-Center) for the upstream projects.

## License

[MIT](LICENSE) © Florian Pariset.
