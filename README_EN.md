<div align="center">

[**中文**](./README.md) · [**English**](./README_EN.md)

# 🐋 @dsh-external/dsh-desktop

**A desktop companion plugin for DeepSeek Harness** — tray whale icon · desktop shortcut · auto-start straight to the desktop window · one-click desktop/web switching

![banner](assets/banner.svg)

[![dsh-plugin](https://img.shields.io/badge/topic-dsh--plugin-1e3a8a?style=flat-square)](https://github.com/topics/dsh-plugin)
[![type](https://img.shields.io/badge/type-Web%20Plugin-818cf8?style=flat-square)](cordis.patch.yml)
[![version](https://img.shields.io/badge/version-0.5.0-38bdf8?style=flat-square)](package.json)
[![license](https://img.shields.io/badge/license-MIT-22d3ee?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0ea5e9?style=flat-square)](#requirements)
[![node](https://img.shields.io/badge/node-%3E%3D20-6366f1?style=flat-square)](package.json)

**A Windows desktop companion for DeepSeek Harness: system tray (whale) icon, desktop shortcut, login auto-start straight into the desktop window, and one-click desktop/web switching.**

</div>

> 🚀 **Key point: the desktop experience = DeepSeek Harness + one plugin — no extra installation.**
> DeepSeek Harness's desktop experience is delivered entirely as a **Web plugin**. No separate desktop client to download, no reinstall, no admin rights required.
> If you already have a DeepSeek Harness Web environment, install this plugin and restart to get the full desktop experience.

## ✨ Features

| Feature | Description |
| --- | --- |
| 🐋 **System tray companion** | A whale icon in the notification area with a right-click menu: **Open / Quit** the harness |
| 🖥️ **Native desktop window** | Rendered by your local Chromium in app mode (`--app`): 1352:972 adaptive ratio, centered, freely resizable; a dedicated browser profile keeps extensions, notifications and sign-in prompts out of the window; no startup flicker |
| 🔄 **One-click desktop/web switching** | The Settings button shows **Switch to Desktop** in web mode and **Switch to Web** in desktop mode; state is detected without WMI, so the label is always truthful |
| ⚡ **Fast boot** | Harness starts directly via `node <entry> web` (the exact entry is recorded in `harness.json`) — login auto-start is ready in seconds, with no npx round trip and no port conflicts |
| 🔁 **Login auto-start toggle** | Writes `HKCU\...\Run` (no admin rights); at login the service starts in the background and the desktop window opens directly once ready |
| 🪟 **Show/hide terminal** | Toggle the harness terminal window from Settings |
| ⚙️ **Native Settings panel** | A new **Desktop** section in the DSH Web UI: status cards, one-click actions, last-open diagnostics |

## 📦 Installation

### Requirements

| Item | Requirement |
| --- | --- |
| OS | Windows 10 / 11 (built-in Windows PowerShell 5.1) |
| Runtime | Node.js ≥ 20 (the same Node you use for DeepSeek Harness) |
| Harness | DeepSeek Harness Web profile (`dsh web`) |
| Browser | Chromium-based recommended (Edge ships with Windows); the desktop window uses your default browser when it is Chromium-based, otherwise Edge → Chrome |

### ⚡ Option 1: Install with a single command (recommended)

Run in any terminal (requires the `dsh` CLI and pnpm — DSH plugin management is built on pnpm):

```sh
dsh plugin --profile web add github:LvsH13/dsh-desktop
```

Then **restart the running Web profile**:

- A 🐋 whale tray icon appears in the notification area;
- A new **Desktop** section shows up in Settings;
- Once auto-start is enabled, the desktop window opens directly at login.

### Option 2: Install from a source checkout

```sh
git clone https://github.com/LvsH13/dsh-desktop.git
dsh plugin --profile web add "FULL/PATH/TO/dsh-desktop"
```

Restart the Web profile afterwards.

### Option 3: Manual install (standard Web plugin flow)

1. Go to the web profile directory (default `%USERPROFILE%\.dsh\profiles\web`);
2. Add this package to the `dependencies` of `package.json` — one command:
   ```sh
   npm install github:LvsH13/dsh-desktop
   ```
3. Add the following entry to the `insert` list of the profile's `cordis.patch.yml`:
   ```yaml
   - insert:
       - id: dsh-desktop
         name: '@dsh-external/dsh-desktop'
   ```
4. Restart the Web profile — the plugin is now active.

### Uninstall

```sh
dsh plugin --profile web remove "@dsh-external/dsh-desktop"
```

Optionally: quit the tray, disable auto-start (delete the `DSHDesktop` value under `HKCU\...\Run`), delete the desktop shortcut and remove `%LOCALAPPDATA%\dsh-desktop`.

## 🚀 Usage

Open **Settings → Desktop**:

| Panel | What it does |
| --- | --- |
| Status | Live state of the harness service, tray, desktop window, desktop shortcut, auto-start, terminal |
| Auto-start | Enable/disable login auto-start (`HKCU Run`); when enabled, login starts the service in the background and opens the desktop window directly once ready |
| Actions | **Switch to Desktop / Switch to Web** (labeled by the current mode), start/quit tray, create desktop shortcut, show/hide terminal |

The **Last open** line reports the previous launch: readiness time (e.g. `ready in 1.2s`) and window mode (`standalone window` / `default browser`), or the failure reason — check this first when something feels slow.

## ⚙️ Configuration

| Item | Location / Notes |
| --- | --- |
| Companion directory | `%LOCALAPPDATA%\dsh-desktop\` (auto-migrated from v0.1's `$DSH_HOME\desktop`) |
| `dsh-tray.ps1` | Core tray/launcher script (window layout, single instance, readiness polling, quit signal) |
| `harness.json` | Exact CLI entry of the running installation: node, DSH_HOME, origin, port |
| `state.json` | `showTerminal` / `autoStart` state |
| `open-state.json` | Last-open diagnostics (readiness time, window mode) |
| Auto-start registry | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\DSHDesktop` |
| Desktop/web state detection | Dual-channel: recorded window PID (primary) + WMI command-line match (fallback) — reliable even without WMI |
| Runtime dependency | `schemastery` (the only runtime dependency) |

> ⚠️ Keep `dsh-tray.ps1` as **UTF-8 with BOM** — Windows PowerShell 5.1 misreads BOM-less UTF-8.

## 📸 Showcase

| 🖥️ Desktop DeepSeek Harness | 🐋 Tray icon |
| :---: | :---: |
| ![Desktop DeepSeek Harness](images/desktop.png) | ![Whale tray icon](images/tray.png) |
| 📌 Desktop shortcut | 🗔 Taskbar |
| :---: | :---: |
| ![Desktop shortcut](images/shortcut.png) | ![DeepSeek Harness in the taskbar](images/taskbar.png) |
| ⚙️ Settings panel · dsh-desktop | |
| :---: | :---: |
| ![dsh-desktop in the Settings panel](images/settings.png) | |

## 📄 License

[MIT](./LICENSE) · Copyright © 2026 [LvsH13](https://github.com/LvsH13)

---

<div align="center">

🔖 Part of the **dsh-plugin** ecosystem: [dsh-plugin topic](https://github.com/topics/dsh-plugin) · [GitHub repository](https://github.com/LvsH13/dsh-desktop)

</div>
