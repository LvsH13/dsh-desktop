# Changelog

## 0.5.0 — 2025-xx-xx

- **Reliable desktop/web state detection (no WMI dependency)**: `-AppWindowActive`,
  `Get-AppWindowProcess` and `Close-AppWindow` no longer depend on WMI. The PID
  recorded by `-Open` is now the primary channel — and the `-WatchAppWindow`
  watcher **self-heals the record to the real window-owner PID** after the
  window appears — with the CIM command-line match kept as a best-effort
  fallback in normal environments. The Settings **切换桌面端 / 切换网页端**
  button and the "桌面窗口" status card now always reflect the real mode, and
  switching to web reliably closes the desktop window, even where WMI is
  unavailable. The Settings page also **refreshes state every 5 s** while open
  (paused while hidden/busy), so the label stays truthful when the window is
  opened or closed from the tray or the desktop shortcut.
- **Window size per user spec**: the desktop window now opens at the **1352:972
  ratio** — width = 70.42% of the primary work-area width, height keeps the
  ratio (1352×972 on a 1920×1080 display), **centered on the monitor**, min
  **960×690 DIP** (ratio-consistent), still fully DPI-aware.
- **Dedicated browser profile for the app window**: the window launches with its
  own `--user-data-dir`, so the launched process *is* the window owner. This
  fixes the cases where an already-running Edge hijacked the launch (dead broker
  PID recorded, `--window-size` ignored, stale session bounds restored — the
  931×1005 window) and makes detection/closing deterministic.
- **Whale icon on the desktop window**: the desktop shortcut gets the
  `System.AppUserModel.ID`/`RelaunchIconResource` properties (IPropertyStore),
  the window launches with `--app-user-model-id=DSHDesktopApp`, and the watcher
  applies `WM_SETICON` with the whale `.ico` — the taskbar, Alt-Tab and the
  window itself show the DeepSeek Harness whale instead of the Edge logo.
- **Switching modes closes the previous window**: `-Open` first sends the quit
  signal so open Harness browser pages close themselves, then opens the desktop
  window; `-OpenWeb` closes the app window before opening the default browser.
- **Engine follows the user's default browser**: the app window now prefers the
  **default browser when it is Chromium-based** (Chrome/Edge/Brave/Opera/Vivaldi,
  resolved from the `http` UserChoice ProgId), falling back to **Edge** (ships
  with Windows 10/11) then **Chrome**; only when no Chromium browser exists at
  all does it open the default browser as a normal window. The window stays
  fully isolated from the user's normal browsing session via its dedicated
  `--user-data-dir`, so browser extensions, notifications and sign-in prompts
  never leak into it.
- **Whale icon made bullet-proof**: the window is launched **through a whale-icon
  `.lnk`** (`dsh-appwindow.lnk`, with `System.AppUserModel.ID` properties), so
  Windows uses that shortcut's icon and name for the taskbar button; a matching
  Start Menu shortcut anchors the AppUserModelID lookup, and the watcher still
  applies `WM_SETICON` to the window itself.
- **Tray quit now closes the desktop window too**: the app-mode window cannot
  close itself via script (`window.close()` is blocked for `--app` windows), so
  the shared quit path (`-Quit` and the tray menu 退出) now explicitly calls
  `Close-AppWindow` (record PID + CIM fallback) after signaling the browser
  pages — the desktop window and the browser tabs close together.
- `Send-QuitSignal` only waits for page close when the signal was delivered.

## 0.4.0 — 2025-xx-xx

- **Window layout per spec**: the desktop window now opens at **72% × 80% of the
  primary screen work area** (taskbar excluded), **horizontally and vertically
  centered**, with a **960×600 DIP minimum size** enforced while the window is
  open. All sizing is **DPI-aware** (125%/150% scaling supported): the script
  becomes a per-monitor DPI-aware process, measures the work area in physical
  pixels, and converts to the DIP values Edge/Chrome expect.
- **No startup flicker or position shift**: the window launches minimized with
  its final size/position pre-set; a hidden `-WatchAppWindow` watcher process
  hides the window immediately, waits for the page title to be ready (first
  content render), then restores it at the exact centered size. The watcher
  then enforces the minimum size (maximize excluded) and exits when the window
  closes.
- **Toggle state check fixed for restricted environments**: `-AppWindowActive`
  and `Close-AppWindow` no longer depend solely on WMI. Detection now uses a
  dual channel — CIM command-line match (`--app=<origin>`) plus the PID recorded
  by `-Open` (verified alive, chrome/msedge, and with a visible main window) —
  so the Settings **切换桌面端 / 切换网页端** button always reflects the real
  mode and switching to web reliably closes the window.
- **Settings toggle now polls**: after switching, the Settings page polls the
  snapshot (up to ~40s) until the window state matches the target, so the
  button label flips without a manual reload.
- **Edge install-path fix**: `${env:ProgramFiles(x86)}` is now expanded
  correctly, so Edge installed under "Program Files (x86)" is found.
- **Diagnostics**: `-LayoutInfo` prints the computed layout (work area, size,
  position, scale); `open-state.json` records the applied window geometry.

## 0.3.0 — 2025-xx-xx

- **Desktop window is the default and only open mode**: the "open method"
  setting (`appWindow`) was removed. `-Open` always launches local Edge/Chrome
  in `--app` mode with a default **16:9** window (1600×900), falling back to the
  default browser only when no Chromium-family browser is installed.
- **Startup opens the desktop window, not the browser**: login auto-start
  (`-AutoStart`) now waits for HTTP readiness and opens the desktop window
  directly; the desktop shortcut is auto-repaired when it still points at the
  legacy `$DSH_HOME\desktop` script (whose `-Open` opened the default browser).
- **Settings "打开桌面端" became a mode toggle**: it shows **切换桌面端** in
  web mode and **切换网页端** in desktop mode. Switching to web closes the
  app-mode window and opens the default browser (`-OpenWeb`); a new
  `-AppWindowActive` companion mode reports whether the desktop window is
  running, and a "桌面窗口" status card shows the live mode.

## 0.2.0 — 2025-xx-xx

- **Boot speed**: the tray now starts the harness directly with `node <entry> web`
  (entry recorded in `harness.json` from the running installation) instead of
  `npx @deepseek-ai/dsh web` — no registry round trip, readiness in seconds.
- **Single-instance launcher**: named mutex + running-process check prevent
  duplicate harness instances, eliminating the "port already in use" bug when
  the first instance was still booting.
- **Desktop window mode**: "open" launches local Edge/Chrome in `--app` mode —
  a movable/resizable/minimizable/closable desktop window over the local
  browser engine, with fallback to the default browser.
- **Login auto-start now also starts the service**: `-AutoStart` brings up the
  harness in the background (hidden) right after login.
- **Readiness check**: HTTP polling (not just TCP) before opening the window.
- **Diagnostics**: `open-state.json` records every open attempt (readiness
  time, window mode, error) and is shown in Settings.
- **Portability**: companion files moved to `%LOCALAPPDATA%\dsh-desktop`
  (auto-migrated from the old `$DSH_HOME\desktop`); origin/port now derive from
  `DSH_WEB_URL` / `--port` instead of a hard-coded `3080`; no machine-specific
  paths remain in the PowerShell script.
- **Publishing**: README (EN/zh), LICENSE, .gitignore, keywords.

## 0.1.0

- Initial release: tray icon, desktop shortcut, auto-start registry toggle,
  terminal visibility toggle, same-origin Settings section.
