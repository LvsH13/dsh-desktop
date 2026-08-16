/**
 * @dsh-external/dsh-desktop — DeepSeek Harness 桌面端 host half.
 *
 * Manages the Windows desktop companion: a tray app (whale icon, right-click
 * open/exit), a desktop shortcut, and the login auto-start registry key. The
 * browser Settings section talks to this plugin through one same-origin JSON
 * route. All Windows-specific work (COM shortcut, registry, tray process) is
 * delegated to the shipped PowerShell companion script, so the plugin stays a
 * thin orchestrator and the desktop app works even while the harness is off.
 *
 * v0.2:
 *  - writes `harness.json` (DSH CLI entry, node, DSH_HOME, origin/port, cwd)
 *    so the tray can launch the harness directly with `node <entry> web`
 *    instead of `npx` (seconds instead of minutes at boot, no registry round
 *    trips, no duplicate-instance port conflicts);
 *  - writes `state.json` (showTerminal / appWindow / autoStart) for the tray;
 *  - app-window mode: `-Open` opens Edge/Chrome in `--app` mode so the harness
 *    UI appears as a normal desktop window (move/resize/minimize/close) driven
 *    by the user's local browser engine;
 *  - companion files live in %LOCALAPPDATA%\dsh-desktop (stable across
 *    DSH_HOME changes), with an automatic migration from the old
 *    $DSH_HOME\desktop location.
 *
 * v0.3:
 *  - the desktop window is now the only open mode: the "open method" setting
 *    (`appWindow`) was removed and `-Open` always uses the Edge/Chrome app
 *    window (default 16:9), falling back to the default browser only when no
 *    local Chromium-family browser exists;
 *  - login auto-start (`-AutoStart`) now opens the desktop window directly as
 *    soon as the harness is ready, instead of leaving nothing open;
 *  - Settings "打开桌面端" became a mode toggle 切换桌面端 / 切换网页端,
 *    backed by new companion modes `-OpenWeb` (close the app window and open
 *    the default browser) and `-AppWindowActive` (is the app window running);
 *  - the desktop shortcut is auto-repaired on apply when it still points at
 *    the legacy $DSH_HOME\desktop script (the old script opened the browser).
 * v0.5:
 *  - desktop/web state detection no longer depends on WMI: the app window
 *    record (self-healed by the watcher to the real owner PID) is the primary
 *    channel, CIM command-line match is a best-effort fallback — the Settings
 *    toggle label (切换桌面端 / 切换网页端) always reflects the real mode even
 *    in restricted environments where WMI is unavailable;
 *  - the desktop window now opens with a dedicated `--user-data-dir`, so the
 *    launched process owns the window (no handoff to an already-running Edge),
 *    `--window-size` is honored instead of Edge's restored session bounds, and
 *    the window is sized to the user's 1352:972 ratio (1352×972 on 1920×1080),
 *    centered on the monitor, min 960×690 DIP;
 *  - the desktop window uses the whale icon: `--app-user-model-id` matches the
 *    desktop shortcut (AppUserModelID written via the property store) for the
 *    taskbar/Alt-Tab, and the watcher sets WM_SETICON on the window itself;
 *  - switching modes closes the previous window: -Open sends the quit signal
 *    (browser pages close themselves) before opening the app window, -OpenWeb
 *    closes the app window before opening the default browser.
 * v0.7:
 *  - the logon scheduled task is now registered via Schedule.Service COM (no
 *    command-line quoting) with a `schtasks /Create /XML` fallback — v0.6's
 *    `schtasks /TR "…\"…\""` quoting failed silently, so the machine kept
 *    falling back to the slow Run key and login auto-start stayed minutes
 *    behind the startup queue;
 *  - the boot open path (`-AutoStart`) skips the CIM fallback window check
 *    (no extra PowerShell job / WMI wait while WMI is still starting);
 *  - new `-AutoStartDiag` companion mode reports registration health.
 * @module @dsh-external/dsh-desktop
 */
import { spawn } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import z from 'schemastery';

export const name = '@dsh-external/dsh-desktop';
export const inject = ['settings'];

/** Settings document namespace owned by this plugin. */
const NS = 'dsh-desktop';
/** Exact same-origin route used by the browser Settings section. */
const ROUTE = '/_dsh/dsh-desktop';
/** Harness web origin fallback when no runtime hint is available. */
const ORIGIN = 'http://127.0.0.1:3080';

const PACKAGE_DIR = fileURLToPath(new URL('../', import.meta.url));
const ASSETS_DIR = join(PACKAGE_DIR, 'assets');
const DSH_HOME = process.env.DSH_HOME ?? join(os.homedir(), '.dsh');
/** Stable per-user companion directory (independent of DSH_HOME). */
const APP_DIR = process.env.LOCALAPPDATA
  ? join(process.env.LOCALAPPDATA, 'dsh-desktop')
  : join(os.homedir(), 'AppData', 'Local', 'dsh-desktop');
/** Legacy companion directory from v0.1 ($DSH_HOME\desktop). */
const LEGACY_APP_DIR = join(DSH_HOME, 'desktop');
const TRAY_SCRIPT = join(APP_DIR, 'dsh-tray.ps1');
const ICON_PATH = join(APP_DIR, 'dsh-whale.ico');
const PID_FILE = join(APP_DIR, 'tray.pid');
/** Legacy terminal visibility file (v0.1), still written for old tray copies. */
const TERMINAL_STATE = join(APP_DIR, 'terminal.json');
/** Tray preferences: showTerminal / autoStart. */
const STATE_FILE = join(APP_DIR, 'state.json');
/** Launch info the tray uses to start the harness without npx. */
const HARNESS_FILE = join(APP_DIR, 'harness.json');
/** Last "open" attempt diagnostics written by the tray. */
const OPEN_STATE_FILE = join(APP_DIR, 'open-state.json');
/** App-window process record written by the tray (`-Open`/watcher self-heals). */
const APP_WINDOW_FILE = join(APP_DIR, 'app-window.json');
const SHORTCUT_PATH = join(process.env.USERPROFILE ?? os.homedir(), 'Desktop', 'DeepSeek Harness.lnk');

/** Configuration schema with defaults. */
const DesktopConfig = z.object({
  autoStart: z.boolean().default(false),
  /** Whether the harness terminal window should be visible when started. */
  showTerminal: z.boolean().default(false),
});

/** Local Chromium-family browser binaries usable for --app windows. */
const BROWSER_CANDIDATES = [
  join(process.env['ProgramFiles(x86)'] ?? '', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
  join(process.env.ProgramFiles ?? '', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
  join(process.env.LOCALAPPDATA ?? '', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
  join(process.env.ProgramFiles ?? '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
  join(process.env['ProgramFiles(x86)'] ?? '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
  join(process.env.LOCALAPPDATA ?? '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
];

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function responseJson(res, status, body) {
  const bytes = Buffer.from(JSON.stringify(body));
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Content-Length', String(bytes.length));
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'");
  res.writeHead(status);
  res.end(bytes);
}

function requestError(res, status, code, message) {
  responseJson(res, status, { ok: false, error: { code, message } });
}

function sameOriginPost(req) {
  const fetchSite = req.headers['sec-fetch-site'];
  if (fetchSite === 'cross-site') return false;
  const origin = req.headers.origin;
  if (origin === undefined) {
    return fetchSite === 'same-origin' || fetchSite === 'same-site' || fetchSite === 'none';
  }
  const host = req.headers.host;
  if (host === undefined) return false;
  try {
    const parsed = new URL(origin);
    return (parsed.protocol === 'http:' || parsed.protocol === 'https:') && parsed.host === host;
  } catch {
    return false;
  }
}

async function readJson(req, maxBytes = 64 * 1024) {
  const contentType = req.headers['content-type']?.split(';', 1)[0]?.trim().toLowerCase();
  if (contentType !== 'application/json') throw new TypeError('Content-Type must be application/json');
  const chunks = [];
  let bytes = 0;
  for await (const chunk of req) {
    const part = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    bytes += part.length;
    if (bytes > maxBytes) throw new RangeError(`request body exceeds ${maxBytes} bytes`);
    chunks.push(part);
  }
  if (chunks.length === 0) throw new TypeError('request body is empty');
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function publicMessage(error) {
  if (error instanceof Error) return error.message;
  return String(error);
}

/** Run a PowerShell -File invocation to completion; resolves the exit code. */
function runPowerShell(args, timeoutMs = 30000) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', ...args], {
        windowsHide: true,
        stdio: 'ignore',
      });
    } catch {
      resolve(1);
      return;
    }
    const timer = setTimeout(() => { try { child.kill(); } catch { /* noop */ } }, timeoutMs);
    child.on('exit', (code) => { clearTimeout(timer); resolve(code ?? 1); });
    child.on('error', () => { clearTimeout(timer); resolve(1); });
  });
}

/** Run a PowerShell -Command invocation to completion; resolves the exit code. */
function runPowerShellCommand(command, timeoutMs = 30000) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-Command', command], {
        windowsHide: true,
        stdio: 'ignore',
      });
    } catch {
      resolve(1);
      return;
    }
    const timer = setTimeout(() => { try { child.kill(); } catch { /* noop */ } }, timeoutMs);
    child.on('exit', (code) => { clearTimeout(timer); resolve(code ?? 1); });
    child.on('error', () => { clearTimeout(timer); resolve(1); });
  });
}

/** Single-quote a value for embedding in a PowerShell command string. */
function psQuote(value) {
  return "'" + String(value).replace(/'/g, "''") + "'";
}

/**
 * Launch a hidden PowerShell -File process (tray or open), fire-and-forget.
 *
 * The target script must run in its OWN process, fully detached from the
 * harness. Node's `detached: true` cannot be used for Windows PowerShell:
 * a powershell.exe created with DETACHED_PROCESS exits immediately with code 0
 * before running anything (observed on this machine for both the harness
 * process and plain Node). Instead a short-lived hidden wrapper powershell
 * (spawned non-detached, which works) hands the real job to Start-Process,
 * which creates an independent process that survives the harness.
 */
function spawnHidden(args) {
  const command = `Start-Process -FilePath ${psQuote('powershell.exe')} -ArgumentList @(${args.map(psQuote).join(', ')}) -WindowStyle Hidden`;
  try {
    const child = spawn('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-Command', command], {
      windowsHide: true,
      stdio: 'ignore',
    });
    child.unref();
  } catch {
    /* noop */
  }
}

/** Poll trayStatus until the tray process is up or the timeout elapses. */
async function waitForTray(timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs;
  let status = trayStatus();
  while (!status.running && Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 250));
    status = trayStatus();
  }
  return status;
}

function trayStatus() {
  let pid = 0;
  try {
    const raw = readFileSync(PID_FILE, 'utf8').trim();
    if (raw.length > 0) pid = Number(raw);
  } catch {
    /* no pid file */
  }
  let alive = false;
  if (Number.isInteger(pid) && pid > 0) {
    try {
      process.kill(pid, 0);
      alive = true;
    } catch {
      alive = false;
    }
  }
  return { running: alive, pid: alive ? pid : null };
}

async function harnessReachable() {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 1500);
    try {
      const res = await fetch(`${detectOrigin().origin}/`, { signal: controller.signal });
      return res.status < 500;
    } finally {
      clearTimeout(timer);
    }
  } catch {
    return false;
  }
}

async function stopTray() {
  const { pid } = trayStatus();
  if (pid !== null) {
    try { process.kill(pid); } catch { /* already gone */ }
  }
  // Fallback: terminate every PowerShell process currently running the tray script.
  await runPowerShellCommand(
    "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*dsh-tray.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }",
  );
  try { rmSync(PID_FILE, { force: true }); } catch { /* noop */ }
}

function installAssets() {
  mkdirSync(APP_DIR, { recursive: true });
  copyFileSync(join(ASSETS_DIR, 'dsh-tray.ps1'), TRAY_SCRIPT);
  copyFileSync(join(ASSETS_DIR, 'dsh-whale.ico'), ICON_PATH);
  copyFileSync(join(ASSETS_DIR, 'boot.html'), join(APP_DIR, 'boot.html'));
}

/**
 * v0.1 kept the companion files under $DSH_HOME\desktop; move them to the
 * stable %LOCALAPPDATA%\dsh-desktop location so the login auto-start registry
 * key survives DSH_HOME changes. The Run key itself is rewritten by
 * syncAutoStart() below when autoStart is on, and removed when it is off.
 */
function migrateAppDir() {
  if (LEGACY_APP_DIR === APP_DIR) return;
  const legacyTray = join(LEGACY_APP_DIR, 'dsh-tray.ps1');
  if (!existsSync(legacyTray)) return;
  mkdirSync(APP_DIR, { recursive: true });
  for (const file of ['dsh-tray.ps1', 'dsh-whale.ico', 'terminal.json', 'state.json', 'harness.json']) {
    const src = join(LEGACY_APP_DIR, file);
    const dst = join(APP_DIR, file);
    if (existsSync(src) && !existsSync(dst)) {
      try { copyFileSync(src, dst); } catch { /* keep going */ }
    }
  }
}

/** Persist the tray preferences so the companion can read them without the harness. */
function writeState(settings) {
  const value = {
    showTerminal: !!settings.showTerminal,
    autoStart: !!settings.autoStart,
  };
  mkdirSync(APP_DIR, { recursive: true });
  writeFileSync(STATE_FILE, JSON.stringify(value), 'utf8');
  // Legacy file for any old tray copy that may still be running.
  writeFileSync(TERMINAL_STATE, JSON.stringify({ showTerminal: value.showTerminal }), 'utf8');
}

/**
 * Detect the harness web origin/port: prefer DSH_WEB_URL (the runtime hint),
 * then the CLI --port flag, then the default.
 */
function detectOrigin() {
  const envUrl = process.env.DSH_WEB_URL;
  if (typeof envUrl === 'string' && envUrl.length > 0) {
    try {
      const parsed = new URL(envUrl);
      if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
        const port = parsed.port ? Number(parsed.port) : (parsed.protocol === 'https:' ? 443 : 80);
        return { origin: parsed.origin, port, via: 'env' };
      }
    } catch {
      /* fall through */
    }
  }
  const argv = process.argv;
  const idx = argv.indexOf('--port');
  if (idx >= 0 && idx + 1 < argv.length) {
    const port = Number(argv[idx + 1]);
    if (Number.isInteger(port) && port > 0 && port < 65536) {
      return { origin: `http://127.0.0.1:${port}`, port, via: 'argv' };
    }
  }
  return { origin: ORIGIN, port: 3080, via: 'default' };
}

/**
 * Resolve the DSH CLI entry (`lib/bin.js`) of the running harness:
 * the current process's own entry script, then the newest npx cache install,
 * then the profile's flat fallback directory. The tray uses this to start the
 * harness with plain `node <entry> web` — no npx, no registry round trip.
 */
function resolveDshEntry() {
  const argvEntry = process.argv[1];
  if (typeof argvEntry === 'string' && argvEntry.length > 0) {
    try {
      const candidate = resolve(argvEntry);
      if (existsSync(candidate) && /\.(?:c|m)?js$/i.test(candidate)) return candidate;
    } catch {
      /* fall through */
    }
  }
  const npxRoot = join(os.homedir(), 'AppData', 'Local', 'npm-cache', '_npx');
  try {
    let newest = null;
    for (const dir of readdirSync(npxRoot, { withFileTypes: true })) {
      if (!dir.isDirectory()) continue;
      const pkg = join(npxRoot, dir.name, 'node_modules', '@deepseek-ai', 'dsh', 'package.json');
      if (!existsSync(pkg)) continue;
      const bin = join(dirname(pkg), 'lib', 'bin.js');
      if (!existsSync(bin)) continue;
      const mtime = statSync(bin).mtimeMs;
      if (newest === null || mtime > newest.mtime) newest = { bin, mtime };
    }
    if (newest !== null) return newest.bin;
  } catch {
    /* ignore */
  }
  const flat = join(DSH_HOME, 'profiles', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js');
  if (existsSync(flat)) return flat;
  return null;
}

/**
 * Write `harness.json` so the tray can start the harness directly and
 * quickly: exact node + CLI entry + DSH_HOME + origin/port + cwd.
 */
function writeHarnessInfo() {
  const { origin, port, via } = detectOrigin();
  mkdirSync(APP_DIR, { recursive: true });
  const info = {
    schemaVersion: 1,
    origin,
    port,
    entry: resolveDshEntry(),
    node: process.execPath,
    dshHome: DSH_HOME,
    cwd: process.cwd(),
    webArgs: via === 'argv' ? ['--port', String(port)] : [],
    writtenAt: new Date().toISOString(),
  };
  writeFileSync(HARNESS_FILE, JSON.stringify(info, null, 2), 'utf8');
}

/** Read the tray's last "open" diagnostics (open-state.json), or null. */
function readOpenState() {
  try {
    const parsed = JSON.parse(readFileSync(OPEN_STATE_FILE, 'utf8').replace(/^\uFEFF/, ''));
    if (!isRecord(parsed) || typeof parsed.at !== 'string') return null;
    return {
      at: parsed.at,
      ok: parsed.ok === true,
      readyMs: typeof parsed.readyMs === 'number' && Number.isFinite(parsed.readyMs) ? parsed.readyMs : null,
      browser: typeof parsed.browser === 'string' ? parsed.browser : null,
      error: typeof parsed.error === 'string' ? parsed.error : null,
    };
  } catch {
    return null;
  }
}

/** Whether any local Edge/Chrome binary is available for app-mode windows. */
function appWindowAvailable() {
  return BROWSER_CANDIDATES.some(path => existsSync(path));
}

/**
 * Whether the Chromium app-mode desktop window for this origin is running.
 *
 * Fast path: read the tray's app-window.json record (self-healed by the
 * watcher to the real window owner), probe the PID and verify the process
 * name is a whitelisted browser (chrome/msedge/brave/opera/vivaldi). This
 * avoids cold-starting a PowerShell process on every settings snapshot (1-3s)
 * and ignores stale records left by third-party browsers such as Doubao —
 * its transparent floating window must never be reported as the desktop
 * window. Falls back to the tray script when the record is missing,
 * unreadable, or the process name cannot be determined.
 */
const BROWSER_PROCESS_NAMES = new Set(['chrome', 'msedge', 'brave', 'opera', 'vivaldi']);

let appWindowFast = { at: 0, active: false };
let appWindowSlow = { at: 0, active: false };
// 与客户端 5 秒轮询对齐: 快速路径 (tasklist 进程名校验) 不再每次轮询都重复;
// 慢路径 (冷启动 PowerShell -AppWindowActive) 仅在记录缺失时才会用到, 拉长 TTL
// 避免设置页打开时每 5 秒拉起一个 PowerShell 进程造成明显卡顿。
const APP_WINDOW_FAST_TTL = 5000;
const APP_WINDOW_SLOW_TTL = 15000;

/** Resolve a PID's process name via tasklist (CSV, header off), or null. */
function processNameOf(pid) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn('tasklist.exe', ['/FI', `PID eq ${pid}`, '/FO', 'CSV', '/NH'], {
        windowsHide: true,
        stdio: ['ignore', 'pipe', 'ignore'],
      });
    } catch {
      resolve(null);
      return;
    }
    let out = '';
    child.stdout.on('data', (chunk) => { out += chunk; });
    child.on('error', () => resolve(null));
    child.on('exit', () => {
      const m = /^"([^"]+)"/.exec(out.trim());
      resolve(m ? m[1].replace(/\.exe$/i, '') : null);
    });
  });
}

async function appWindowActive() {
  const now = Date.now();
  if (now - appWindowFast.at < APP_WINDOW_FAST_TTL) return appWindowFast.active;
  let pid = null;
  try {
    const parsed = JSON.parse(readFileSync(APP_WINDOW_FILE, 'utf8').replace(/^\uFEFF/, ''));
    if (isRecord(parsed) && typeof parsed.pid === 'number') pid = parsed.pid;
  } catch {
    /* no record yet */
  }
  if (pid === 0) {
    // 托盘 -OpenWeb 关闭窗口时写回 pid=0 的"已关闭"记录: 直接走快速路径判定未运行,
    // 不再为每次轮询冷启动一个 PowerShell -AppWindowActive 进程 (卡顿主因)。
    appWindowFast = { at: now, active: false };
    return false;
  }
  if (pid > 0) {
    let alive = false;
    try {
      process.kill(pid, 0);
      alive = true;
    } catch {
      alive = false;
    }
    if (alive) {
      // 进程存活: 必须同时是白名单浏览器, 否则视为第三方残留记录 (如豆包悬浮窗)
      const name = await processNameOf(pid);
      if (name !== null) {
        const active = BROWSER_PROCESS_NAMES.has(name.toLowerCase());
        appWindowFast = { at: now, active };
        return active;
      }
      // tasklist 查询失败 (受限环境): 回退慢路径确认, 保证准确性
    } else {
      appWindowFast = { at: now, active: false };
      return false;
    }
  }
  if (now - appWindowSlow.at < APP_WINDOW_SLOW_TTL) return appWindowSlow.active;
  const code = await runPowerShell([TRAY_SCRIPT, '-AppWindowActive'], 15000);
  appWindowSlow = { at: now, active: code === 0 };
  return appWindowSlow.active;
}

/**
 * Make sure the desktop shortcut points at this script's `-Open` mode.
 * v0.1 shortcuts still target the legacy $DSH_HOME\desktop script, whose
 * `-Open` opened the default browser instead of the desktop window.
 */
async function syncShortcut() {
  const ok = await runPowerShell([TRAY_SCRIPT, '-ShortcutOk'], 15000);
  if (ok === 0) return true;
  const installed = await runPowerShell([TRAY_SCRIPT, '-Install'], 15000);
  return installed === 0;
}

async function syncAutoStart(enabled) {
  const code = await runPowerShell([TRAY_SCRIPT, enabled ? '-AutoStartOn' : '-AutoStartOff']);
  return code === 0;
}

function descriptorOf(ctx) {
  const descriptor = ctx.settings.describe().find(row => row.ns === NS);
  if (descriptor === undefined) throw new Error('dsh-desktop Settings namespace is not registered');
  return descriptor;
}

async function snapshot(ctx) {
  const descriptor = descriptorOf(ctx);
  const tray = trayStatus();
  const [harness, shortcut, appActive] = await Promise.all([
    harnessReachable(),
    Promise.resolve(existsSync(SHORTCUT_PATH)),
    appWindowActive(),
  ]);
  return {
    schemaVersion: 2,
    writable: ctx.settings.writable,
    origin: detectOrigin().origin,
    appDir: APP_DIR,
    settings: {
      value: descriptor.value,
      revision: descriptor.revision,
    },
    tray,
    shortcut: { exists: shortcut, path: SHORTCUT_PATH },
    harness: { reachable: harness },
    appWindow: { active: appActive, available: appWindowAvailable() },
    lastOpen: readOpenState(),
    assets: {
      script: existsSync(TRAY_SCRIPT),
      icon: existsSync(ICON_PATH),
    },
  };
}

function parseRequest(value) {
  if (!isRecord(value) || typeof value.action !== 'string') {
    throw new TypeError('request action is required');
  }
  if (value.action === 'setAutoStart') {
    if (typeof value.enabled !== 'boolean') throw new TypeError('setAutoStart.enabled must be boolean');
    if (!Number.isSafeInteger(value.expectedRevision) || value.expectedRevision < 0) {
      throw new TypeError('setAutoStart.expectedRevision must be a non-negative integer');
    }
    return { action: 'setAutoStart', enabled: value.enabled, expectedRevision: value.expectedRevision };
  }
  if (value.action === 'setTerminal') {
    if (typeof value.visible !== 'boolean') throw new TypeError('setTerminal.visible must be boolean');
    if (!Number.isSafeInteger(value.expectedRevision) || value.expectedRevision < 0) {
      throw new TypeError('setTerminal.expectedRevision must be a non-negative integer');
    }
    return { action: 'setTerminal', visible: value.visible, expectedRevision: value.expectedRevision };
  }
  if (value.action === 'createShortcut' || value.action === 'startTray' || value.action === 'stopTray' || value.action === 'open' || value.action === 'openWeb' || value.action === 'quit') {
    return { action: value.action };
  }
  throw new TypeError(`unsupported action: ${value.action}`);
}

async function perform(ctx, parsed, sseClients) {
  switch (parsed.action) {
    case 'setAutoStart': {
      await ctx.settings.replace(NS, { autoStart: parsed.enabled }, parsed.expectedRevision);
      if (!(await syncAutoStart(parsed.enabled))) {
        throw new Error('failed to update the Windows auto-start registry key');
      }
      return;
    }
    case 'setTerminal': {
      const current = descriptorOf(ctx).value;
      const next = { autoStart: !!current.autoStart, showTerminal: parsed.visible };
      await ctx.settings.replace(NS, next, parsed.expectedRevision);
      writeState(next);
      const code = await runPowerShell([TRAY_SCRIPT, parsed.visible ? '-ShowTerminal' : '-HideTerminal']);
      if (code !== 0) throw new Error('failed to update the terminal window visibility');
      return;
    }
    case 'createShortcut': {
      const code = await runPowerShell([TRAY_SCRIPT, '-Install']);
      if (code !== 0) throw new Error('failed to create the desktop shortcut');
      return;
    }
    case 'startTray': {
      await stopTray();
      spawnHidden([TRAY_SCRIPT]);
      // PowerShell cold start takes a moment; do not report success until the
      // tray process is actually alive, so the status card stays truthful.
      const tray = await waitForTray();
      if (!tray.running) throw new Error('the tray process failed to start');
      return;
    }
    case 'stopTray': {
      await stopTray();
      return;
    }
    case 'open': {
      spawnHidden([TRAY_SCRIPT, '-Open']);
      return;
    }
    case 'openWeb': {
      spawnHidden([TRAY_SCRIPT, '-OpenWeb']);
      return;
    }
    case 'quit': {
      // The tray companion calls this just before killing the harness process
      // tree: push the signal to every connected web page so the tab closes
      // itself instead of being left behind.
      broadcastQuit(sseClients);
      return;
    }
    default:
      throw new TypeError(`unsupported action: ${parsed.action}`);
  }
}

/**
 * Serve the SSE stream that the web page listens to for the desktop quit
 * signal. Responses stay open until the client disconnects.
 */
function handleSse(req, res, sseClients) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    res.statusCode = 405;
    res.end();
    return;
  }
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  res.write('retry: 2000\n\n');
  sseClients.add(res);
  req.on('close', () => { sseClients.delete(res); });
}

/** Push the quit event to every connected page, then close the streams. */
function broadcastQuit(sseClients) {
  for (const res of sseClients) {
    try {
      res.write('event: quit\ndata: {}\n\n');
      res.end();
    } catch {
      /* ignore */
    }
  }
  sseClients.clear();
}

async function handle(ctx, req, res, sseClients) {
  if (req.method === 'GET') {
    try {
      responseJson(res, 200, { ok: true, value: await snapshot(ctx) });
    } catch (error) {
      ctx.logger.warn('dsh-desktop snapshot failed: %s', publicMessage(error));
      requestError(res, 503, 'desktop-unavailable', 'dsh-desktop state is unavailable');
    }
    return;
  }
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    requestError(res, 405, 'method-not-allowed', 'Use GET or POST');
    return;
  }
  if (!sameOriginPost(req)) {
    requestError(res, 403, 'origin-rejected', 'The request must originate from this DSH Web application');
    return;
  }
  let parsed;
  try {
    parsed = parseRequest(await readJson(req));
  } catch (error) {
    requestError(res, error instanceof RangeError ? 413 : 400, 'invalid-request', publicMessage(error));
    return;
  }
  try {
    await perform(ctx, parsed, sseClients);
    responseJson(res, 200, { ok: true, value: await snapshot(ctx) });
  } catch (error) {
    ctx.logger.warn('dsh-desktop action=%s failed: %s', parsed.action, publicMessage(error));
    requestError(res, 400, 'desktop-action-rejected', publicMessage(error));
  }
}

/** Plugin entry. */
export async function apply(ctx, config = {}) {
  const settings = ctx.settings.register(NS, DesktopConfig, { base: config, applies: 'live' });

  installAssets();
  migrateAppDir();
  writeState(settings.get());
  writeHarnessInfo();
  // 注册表自启动与桌面快捷方式同步会各启动一个 PowerShell 子进程, 开机冷启动
  // 时可达数十秒; 改为后台执行, 不再阻塞 Harness 启动 (webServer 就绪不受影响)。
  void syncAutoStart(settings.get().autoStart).then((ok) => {
    if (!ok) ctx.logger.warn('dsh-desktop auto-start registry sync failed');
  });
  void syncShortcut().then((ok) => {
    if (!ok) ctx.logger.warn('dsh-desktop shortcut refresh failed');
  });
  // 托盘只在缺失时拉起。开机自启动时 HKCU Run 键已启动托盘 (-AutoStart 正在拉起
  // 服务并打开桌面窗口), 此处若 stopTray+重启会杀死该流程、并再付一次 PowerShell
  // 冷启动成本; 手动启动 Harness 且无托盘时才补充拉起。旧脚本版本的托盘会在下次
  // 登录时被 Run 键的新副本自然替换。
  if (!trayStatus().running) {
    spawnHidden([TRAY_SCRIPT]);
  }
  ctx.logger.info('dsh-desktop ready (appDir %s, autoStart %s, origin %s)', APP_DIR, settings.get().autoStart, detectOrigin().origin);

  const sseClients = new Set();
  ctx.inject(['webServer'], (webCtx) => {
    webCtx.effect(() => webCtx.webServer.register({
      kind: 'exact',
      path: ROUTE,
      handler: (req, res) => handle(ctx, req, res, sseClients),
    }), 'dsh-desktop: Web routes');
    webCtx.effect(() => {
      const dispose = webCtx.webServer.register({
        kind: 'exact',
        path: `${ROUTE}/events`,
        handler: (req, res) => handleSse(req, res, sseClients),
      });
      return () => {
        dispose();
        // Close any still-open SSE streams when the plugin unwinds.
        for (const res of sseClients) {
          try { res.end(); } catch { /* ignore */ }
        }
        sseClients.clear();
      };
    }, 'dsh-desktop: SSE routes');
  });

  return () => {
    // The tray app is a standalone desktop companion: plugin disposal must not
    // kill it or touch the user's registry preference. Routes and the settings
    // namespace are fiber-owned and unwind automatically.
  };
}
