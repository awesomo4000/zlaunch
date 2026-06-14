<p align="center">
  <img src="images/zlaunch-logo.png" alt="zlaunch" width="520">
</p>

# zlaunch

Press a global hotkey, type part of an app name, and launch the highlighted result.

zlaunch discovers local `.app` bundles at startup, filters them in process, and launches selections with `/usr/bin/open`.

## Features

- Global hotkey, default `cmd-space`  (may need to unassign it from spotlight)
- Substring app search, case insensitive
- Arrow-key selection with a five-row scrolling result list
- `cmd-1` through `cmd-5` to launch visible rows
- `tab` autocomplete to the longest common app-name prefix
- Light and dark mode styling
- No Dock icon while running

## Build

Requires Zig `0.16.0` and macOS.

```sh
zig build
```

Run the launcher:

```sh
./zig-out/bin/zlaunch
```

Show the launcher immediately on startup:

```sh
./zig-out/bin/zlaunch --now
```

## Usage

- `cmd-space`: show zlaunch
- Type to filter apps
- `up` / `down`: move selection
- `return`: launch selected app
- `cmd-1` ... `cmd-5`: launch a visible row
- `tab`: autocomplete common prefix
- `esc`: dismiss

If `cmd-space` is still bound to Spotlight, macOS will keep it. Unbind Spotlight
in System Settings before using the default hotkey.

## Config

On startup, zlaunch creates:

```text
~/.config/zlaunch/zlaunch.json
```

Default config:

```json
{
  "version": 1,
  "hotkey": "cmd-space"
}
```

Supported modifier names include `cmd`, `command`, `apple`, `shift`, `option`,
`alt`, `ctrl`, and `control`. Supported keys are letters, digits, `space`,
`tab`, `enter`/`return`, and `esc`/`escape`.

Example:

```json
{
  "version": 1,
  "hotkey": "ctrl-option-m"
}
```

## App Discovery

zlaunch scans:

- `/Applications`
- `/Applications/Utilities`
- `/System/Applications`
- `/System/Applications/Utilities`
- `~/Applications`

Symlinked `.app` bundles are included, which covers apps such as Safari on newer macOS installs.
