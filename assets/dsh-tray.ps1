# DeepSeek Harness 桌面端 —— 托盘伴侣脚本 v5
# 用法:
#   dsh-tray.ps1 -Install          创建/更新桌面快捷方式后退出
#   dsh-tray.ps1 -ShortcutOk       桌面快捷方式存在且指向本脚本 -Open 时退出码 0, 否则 1
#   dsh-tray.ps1 -Open             切换到桌面端: 先通知所有已打开的 Harness 页面自行关闭
#                                  (浏览器标签页/窗口), 确保 Harness 服务在运行, 以独立窗口
#                                  (Chromium 应用模式: 优先默认浏览器, 否则 Edge/Chrome;
#                                  独立配置目录) 打开: 按主屏比例 1352×972 (宽度 = 工作区
#                                  宽度 × 1352/1920, 高度按比例) 计算尺寸并居中于显示器,
#                                  最小 960×690 DIP, 适配高 DPI, 渲染就绪前先隐藏再显示,
#                                  窗口使用黑鲸图标 (通过带图标的 .lnk 启动 + AppUserModelID
#                                  + WM_SETICON), 并启动隐藏式 -WatchAppWindow 看守进程,
#                                  记录诊断信息后退出
#   dsh-tray.ps1 -WatchAppWindow   窗口看守进程 (由 -Open/-AutoStart 自动启动, 一般不单独使用):
#                                  等应用窗口出现后立即隐藏, 页面渲染就绪后恢复显示并强制
#                                  居中尺寸, 写回窗口真实所有者 PID 记录 (自愈), 设置黑鲸
#                                  窗口图标, 之后常驻守护最小尺寸, 窗口关闭后自行退出
#   dsh-tray.ps1 -OpenWeb          切换到网页端: 确保服务运行, 关闭独立桌面窗口,
#                                  用默认浏览器打开, 记录诊断信息后退出
#   dsh-tray.ps1 -AppWindowActive  检测独立桌面窗口是否在运行 (运行: 退出码 0, 未运行: 1)
#   dsh-tray.ps1 -LayoutInfo       打印 DPI 感知的窗口布局计算 (尺寸/位置/缩放比) 后退出
#   dsh-tray.ps1 -AutoStartOn      写入开机自启动 (HKCU Run) 后退出
#   dsh-tray.ps1 -AutoStartOff     删除开机自启动后退出
#   dsh-tray.ps1 -AutoStart        登录自启动模式: 后台拉起 Harness 服务(免 npx 直连启动),
#                                  就绪后直接打开桌面窗口, 然后常驻托盘图标
#   dsh-tray.ps1 -ShowTerminal     显示 Harness 终端窗口后退出
#   dsh-tray.ps1 -HideTerminal     隐藏 Harness 终端窗口后退出
#   dsh-tray.ps1 -Quit             通知浏览器页面自动关闭、关闭桌面窗口后, 结束 Harness 终端与服务 (与托盘菜单"退出"共用同一逻辑)
#   dsh-tray.ps1                   (无参数) 常驻托盘图标, 右键可打开/退出
#
# 状态文件 (位于脚本所在目录, 由宿主插件写入):
#   harness.json    -- 启动信息: origin/port/entry(DSH CLI 入口)/node/DSH_HOME/cwd/webArgs
#   state.json      -- 偏好: showTerminal(终端是否显示); 打开方式固定为独立桌面窗口
#   open-state.json -- 最近一次"打开"的耗时与结果诊断
#   tray.pid        -- 当前托盘进程 PID
#   app-window.json -- 应用窗口进程 PID 记录 (看守进程会自愈为真实窗口所有者)
param(
  [switch]$Install,
  [switch]$ShortcutOk,
  [switch]$Open,
  [switch]$OpenWeb,
  [switch]$WatchAppWindow,
  [switch]$AppWindowActive,
  [switch]$LayoutInfo,
  [switch]$AutoStartOn,
  [switch]$AutoStartOff,
  [switch]$AutoStart,
  [switch]$ShowTerminal,
  [switch]$HideTerminal,
  [switch]$Quit
)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$icoPath    = Join-Path $scriptDir 'dsh-whale.ico'
$pidFile    = Join-Path $scriptDir 'tray.pid'
$stateFile  = Join-Path $scriptDir 'state.json'
$legacyTerminalFile = Join-Path $scriptDir 'terminal.json'
$harnessFile = Join-Path $scriptDir 'harness.json'
$openStateFile = Join-Path $scriptDir 'open-state.json'
$mutexName  = 'DSHDesktopTray'
$launchMutexName = 'DSHDesktopHarnessLaunch'
# 打开桌面窗口的互斥锁: 设置按钮/托盘/登录自启动可能并发触发 -Open,
# 用同一 --user-data-dir 启动两个浏览器实例会打开两个窗口 (一透明一实体)
$openMutexName = 'DSHDesktopOpenWindow'
# 看守进程就绪标记: -Open 启动看守后等待该文件出现再启动浏览器,
# 保证看守进程的"启动前窗口快照"先于浏览器窗口创建 (杜绝透明窗口)
$watcherReadyFile = Join-Path $scriptDir 'watcher.ready'
$runKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValue   = 'DSHDesktop'
$shortcutName = 'DeepSeek Harness.lnk'
# 兼容旧版本用 cmd /k npx 启动的根进程命令行特征
$legacyCmdPatterns = @('*title DeepSeek Harness*', '*npx @deepseek-ai/dsh web*', '*npx @deepseek-ai\dsh web*')

# ---------- 配置读取 ----------

$harnessJson = $null
try {
  if (Test-Path $harnessFile) {
    $harnessJson = Get-Content -Path $harnessFile -Raw -Encoding UTF8 | ConvertFrom-Json
  }
} catch { }

# 服务地址: 优先 harness.json, 兜底默认值
$origin = 'http://127.0.0.1:3080'
$port   = 3080
$dshHome = $env:DSH_HOME
$harnessCwd = $HOME
$webArgs = @()
if ($null -ne $harnessJson) {
  if ($harnessJson.origin) { $origin = [string]$harnessJson.origin }
  if ($harnessJson.port)   { $port = [int]$harnessJson.port }
  if ($harnessJson.dshHome) { $dshHome = [string]$harnessJson.dshHome }
  if ($harnessJson.cwd -and (Test-Path ([string]$harnessJson.cwd))) { $harnessCwd = [string]$harnessJson.cwd }
  if ($null -ne $harnessJson.webArgs) { $webArgs = @($harnessJson.webArgs) }
}

# 用户偏好: state.json (新), 缺失时回退 terminal.json (旧版) 的 showTerminal
$state = @{ showTerminal = $false }
try {
  if (Test-Path $stateFile) {
    $parsed = Get-Content -Path $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $parsed) {
      if ($null -ne $parsed.showTerminal) { $state.showTerminal = [bool]$parsed.showTerminal }
    }
  } elseif (Test-Path $legacyTerminalFile) {
    $parsed = Get-Content -Path $legacyTerminalFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $parsed -and $null -ne $parsed.showTerminal) { $state.showTerminal = [bool]$parsed.showTerminal }
  }
} catch { }

# ---------- Win32 辅助: 通过 AttachConsole 拿到其它进程所属控制台的窗口句柄 ----------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DSHNative {
  [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint dwProcessId);
  [DllImport("kernel32.dll")] public static extern bool FreeConsole();
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  // ---- DPI 感知与窗口管理 (桌面窗口布局/守护) ----
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadImageW(IntPtr hinst, string lpszName, uint type, int cx, int cy, uint fuLoad);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr hIcon);
  public static IntPtr ConsoleWindowOf(uint pid) {
    FreeConsole();
    if (!AttachConsole(pid)) return IntPtr.Zero;
    try { return GetConsoleWindow(); } finally { FreeConsole(); }
  }
}
'@

# 设置快捷方式的 AppUserModelID 等属性: 任务栏据此为 --app-user-model-id=DSHDesktopApp
# 的桌面窗口显示黑鲸图标与"DeepSeek Harness"名称 (而不是 Edge/Chrome 的 logo)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DSHShell {
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IPropertyStore {
    [PreserveSig] int GetCount(out uint cProps);
    [PreserveSig] int GetAt(uint iProp, out PropertyKey pkey);
    [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant pv);
    [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant pv);
    [PreserveSig] int Commit();
  }
  [StructLayout(LayoutKind.Sequential, Pack = 4)]
  public struct PropertyKey { public Guid fmtid; public uint pid; }
  [StructLayout(LayoutKind.Sequential)]
  public struct PropVariant { public ushort vt; public ushort wReserved1; public ushort wReserved2; public ushort wReserved3; public IntPtr data1; public IntPtr data2; }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
  static extern int SHGetPropertyStoreFromParsingName(string pszPath, IntPtr pbc, uint flags, ref Guid riid, out IPropertyStore ppv);
  public static void SetAppUserModelId(string path, string appId, string iconPath) {
    Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
    IPropertyStore store;
    // GPS_READWRITE (0x2): 只有读写标志才能拿到可写的属性存储
    int hr = SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, 2, ref iid, out store);
    if (hr != 0) return;
    try {
      SetString(store, new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5, appId);
      SetString(store, new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 4, iconPath + ",0");
      store.Commit();
    } finally {
      Marshal.ReleaseComObject(store);
    }
  }
  static void SetString(IPropertyStore store, Guid fmtid, uint pid, string value) {
    PropertyKey key = new PropertyKey();
    key.fmtid = fmtid; key.pid = pid;
    PropVariant pv = new PropVariant();
    pv.vt = 31; // VT_LPWSTR
    pv.data1 = Marshal.StringToCoTaskMemUni(value);
    try { store.SetValue(ref key, ref pv); } finally { Marshal.FreeCoTaskMem(pv.data1); }
  }
}
'@

# ---------- 服务检测 ----------

function Test-HarnessTcp {
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect('127.0.0.1', $port, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(1200)
    if ($ok) { $client.EndConnect($iar) }
    $client.Close()
    return $ok
  } catch { return $false }
}

# 权威就绪检查: TCP 通了不一定页面可用, HTTP 返回非 5xx 才算真正就绪
function Test-HarnessHttp {
  try {
    $req = [System.Net.HttpWebRequest]::Create($origin + '/')
    $req.Timeout = 1500
    $req.Method = 'GET'
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $resp.Close()
    return ($code -ge 200 -and $code -lt 500)
  } catch { return $false }
}

# ---------- 启动信息 ----------

# 解析 DSH CLI 入口 (lib/bin.js): harness.json > npx 缓存(最新) > 安装平铺目录
function Find-DshEntry {
  if ($null -ne $harnessJson -and $harnessJson.entry -and (Test-Path ([string]$harnessJson.entry))) {
    return [string]$harnessJson.entry
  }
  $npxRoot = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
  if (Test-Path $npxRoot) {
    $pkg = Get-ChildItem -Path $npxRoot -Directory -ErrorAction SilentlyContinue |
      ForEach-Object {
        $candidate = Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\package.json'
        if (Test-Path $candidate) { Get-Item $candidate }
      } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($null -ne $pkg) {
      $bin = Join-Path (Split-Path $pkg.FullName -Parent) 'lib\bin.js'
      if (Test-Path $bin) { return $bin }
    }
  }
  if ($dshHome) {
    $flat = Join-Path $dshHome 'profiles\node_modules\@deepseek-ai\dsh\lib\bin.js'
    if (Test-Path $flat) { return $flat }
  }
  return $null
}

function Get-NodeExe {
  if ($null -ne $harnessJson -and $harnessJson.node -and (Test-Path ([string]$harnessJson.node))) {
    return [string]$harnessJson.node
  }
  try { return (Get-Command node.exe -ErrorAction Stop).Source } catch { return $null }
}

# 启动 Harness 服务。优先直连 node 启动 (无需 npx, 秒级就绪);
# 兜底用 npx (先 --no-install, 再普通 npx)。
function Start-Harness {
  $entry = Find-DshEntry
  $nodeExe = Get-NodeExe
  $workDir = $harnessCwd
  if (-not (Test-Path $workDir)) { $workDir = $HOME }
  $show = $state.showTerminal
  if ($null -ne $entry -and (Test-Path $entry) -and $null -ne $nodeExe -and (Test-Path $nodeExe)) {
    $argLine = '"' + $entry + '" web'
    if ($null -ne $webArgs -and $webArgs.Count -gt 0) { $argLine += ' ' + (($webArgs | Where-Object { $_ }) -join ' ') }
    $oldDshHome = $env:DSH_HOME
    try {
      if ($dshHome) { $env:DSH_HOME = $dshHome }
      if ($show) {
        Start-Process -FilePath $nodeExe -ArgumentList $argLine -WorkingDirectory $workDir
      } else {
        Start-Process -FilePath $nodeExe -ArgumentList $argLine -WorkingDirectory $workDir -WindowStyle Hidden
      }
      return $true
    } catch {
      return $false
    } finally {
      if ($null -eq $oldDshHome) { Remove-Item Env:DSH_HOME -ErrorAction SilentlyContinue } else { $env:DSH_HOME = $oldDshHome }
    }
  }
  $npxCmd = 'title DeepSeek Harness && npx --no-install @deepseek-ai/dsh web'
  try {
    if ($show) {
      Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k', $npxCmd) -WorkingDirectory $workDir
    } else {
      Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k', $npxCmd) -WorkingDirectory $workDir -WindowStyle Hidden
    }
    return $true
  } catch { return $false }
}

# 正在运行的 Harness node 进程 (含正在启动中的实例)
function Get-HarnessNode {
  $entry = Find-DshEntry
  $patterns = @()
  if ($entry) { $patterns += ('*' + $entry + '*') }
  $patterns += '*@deepseek-ai/dsh*', '*@deepseek-ai\dsh*'
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $cmd = $_.CommandLine
      if (-not ($cmd -like '*web*')) { return $false }
      foreach ($p in $patterns) { if ($cmd -like $p) { return $true } }
      return $false
    } |
    Select-Object -First 1
}

# Harness 根进程 (用于显示/隐藏终端窗口和整树结束):
# 优先新的 node 直连启动进程, 兼容旧版 cmd /k npx 启动方式
function Get-HarnessRoot {
  $node = Get-HarnessNode
  if ($null -ne $node) { return $node }
  Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $cmd = $_.CommandLine
      foreach ($p in $legacyCmdPatterns) { if ($cmd -like $p) { return $true } }
      return $false
    } |
    Select-Object -First 1
}

# 确保服务运行 (单实例: 启动器互斥锁 + 进程检查, 杜绝端口占用), 最多等待 60 秒
function Ensure-Harness {
  if (Test-HarnessHttp) { return $true }
  $launcher = New-Object System.Threading.Mutex($false, $launchMutexName)
  $owned = $false
  # 上一个启动器进程可能被终止而留下 abandoned 互斥锁: 此时应视为我们获得了锁
  try { $owned = $launcher.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true } catch { $owned = $false }
  if ($owned) {
    try {
      $running = Get-HarnessNode
      if ($null -eq $running) { [void](Start-Harness) }
    } finally {
      try { $launcher.ReleaseMutex() } catch { }
      try { $launcher.Dispose() } catch { }
    }
  } else {
    try { $launcher.Dispose() } catch { }
  }
  for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-HarnessHttp) { return $true }
  }
  return $false
}

# ---------- 打开方式 ----------

# 查询"默认浏览器"的 exe: 从 HKCU UserChoice ProgId → HKCR 注册的 open 命令提取。
# 仅当默认浏览器是 Chromium 系 (chrome/msedge/brave/opera/vivaldi 等, 支持 --app
# 应用模式窗口) 时返回其路径, 否则返回 $null (如 Firefox —— 不支持应用模式)。
function Get-DefaultChromiumBrowser {
  try {
    $progId = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice' -ErrorAction Stop).ProgId
    if (-not $progId) { return $null }
    $cmdKey = Get-Item ("Registry::HKEY_CLASSES_ROOT\" + $progId + '\shell\open\command') -ErrorAction Stop
    $cmd = [string]$cmdKey.GetValue('')
    if (-not $cmd) { return $null }
    # 提取 exe 路径: 优先引号包裹, 退回空格分隔的第一个令牌
    $m = [regex]::Match($cmd, '"([^"]+\.exe)"')
    if (-not $m.Success) { $m = [regex]::Match($cmd, '^([^\s]+\.exe)') }
    if (-not $m.Success) { return $null }
    $exe = $m.Groups[1].Value
    if (-not (Test-Path $exe)) { return $null }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($exe).ToLowerInvariant()
    if ($name -match '^(chrome|msedge|brave|opera|vivaldi|edge)') { return $exe }
  } catch { }
  return $null
}

# 本地浏览器应用模式窗口: Chromium 系浏览器的 --app 参数会产生一个无标签栏/地址栏、
# 可移动、可缩放、可最小化的独立窗口, 内核仍是用户本地的浏览器。
# 选择顺序: 默认浏览器 (若是 Chromium 系) → Edge (Windows 10/11 必装) → Chrome;
# 都没有时才在调用方回退到默认浏览器普通窗口。
function Find-AppBrowser {
  $defaultExe = Get-DefaultChromiumBrowser
  if ($defaultExe) { return $defaultExe }
  $candidates = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  return $null
}

# 本脚本 -Open 打开应用窗口时记录的进程信息 (CIM 不可用时检测/关闭仍可用)
$appWindowFile = Join-Path $scriptDir 'app-window.json'

function Read-AppWindowRecord {
  try {
    $parsed = Get-Content -Path $appWindowFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $parsed -and [int]$parsed.pid -gt 0) { return $parsed }
  } catch { }
  return $null
}

function Write-AppWindowRecord([int]$targetPid) {
  try {
    $obj = @{ pid = $targetPid; origin = $origin; at = (Get-Date).ToString('o') }
    $obj | ConvertTo-Json -Compress | Set-Content -Path $appWindowFile -Encoding Ascii
  } catch { }
}

# 应用窗口进程。双通道检测, 不依赖单一机制:
#   1) 记录 (纯 Win32, 首选): -Open 写入的窗口进程 PID, 要求进程存活、名为
#      白名单浏览器 (chrome/msedge/brave/opera/vivaldi) 且有顶层
#      Chrome_WidgetWin_1 窗口 (看守进程会自愈为真实所有者);
#   2) CIM (正常环境可用): 命令行匹配 --app=<origin> (兼容引号包裹的 URL)。
# 豆包 Doubao 等第三方浏览器不在白名单内, 其窗口/进程不会被当作桌面窗口。
function Get-AppWindowProcess {
  $rec = Read-AppWindowRecord
  if ($null -ne $rec) {
    $proc = Get-Process -Id ([int]$rec.pid) -ErrorAction SilentlyContinue
    if ($null -ne $proc -and (Test-BrowserProcessName $proc.ProcessName) -and
        (Find-HwndOfPid ([uint32][int]$rec.pid)) -ne [IntPtr]::Zero) {
      return @{ ProcessId = [int]$rec.pid; Via = 'record' }
    }
  }
  try {
    $cim = Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe' OR Name='brave.exe' OR Name='opera.exe' OR Name='vivaldi.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match ('--app=["'']?' + [regex]::Escape($origin)) } |
      Select-Object -First 1
    if ($null -ne $cim) { return @{ ProcessId = [int]$cim.ProcessId; Via = 'cim' } }
  } catch { }
  return $null
}

# 关闭独立桌面窗口 (切换回网页端时使用):
# 记录 PID 通道 (纯 Win32, 首选) + CIM 命令行匹配通道 (正常环境), 并清除记录
function Close-AppWindow {
  $rec = Read-AppWindowRecord
  if ($null -ne $rec) {
    # 只结束白名单浏览器进程 (防残留的豆包等第三方记录被误杀)
    $proc = Get-Process -Id ([int]$rec.pid) -ErrorAction SilentlyContinue
    if ($null -ne $proc -and (Test-BrowserProcessName $proc.ProcessName)) {
      & taskkill.exe /PID ([int]$rec.pid) /T /F 2>$null | Out-Null
    }
  }
  try {
    Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe' OR Name='brave.exe' OR Name='opera.exe' OR Name='vivaldi.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match ('--app=["'']?' + [regex]::Escape($origin)) } |
      ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F 2>$null | Out-Null }
  } catch { }
  Remove-Item $appWindowFile -Force -ErrorAction SilentlyContinue
}

# ---------- 桌面窗口布局 (DPI 感知) ----------

# 让本进程成为 DPI 感知进程, 使屏幕度量返回物理像素 (高 DPI 缩放 125%/150% 下依然准确)
function Set-ProcessDpiAware {
  try {
    # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 (Win10 1703+)
    [void][DSHNative]::SetProcessDpiAwarenessContext([IntPtr](-4))
    return
  } catch { }
  try {
    # PROCESS_PER_MONITOR_DPI_AWARE (Win8.1+)
    [void][DSHNative]::SetProcessDpiAwareness(2)
    return
  } catch { }
  try { [void][DSHNative]::SetProcessDPIAware() } catch { }
}

# 主屏缩放比 (物理像素 / DIP)
function Get-PrimaryScale {
  try {
    $dpi = [DSHNative]::GetDpiForSystem()
    if ($dpi -gt 0) { return $dpi / 96.0 }
  } catch { }
  try {
    $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    try { $dpiX = $g.DpiX } finally { $g.Dispose() }
    if ($dpiX -gt 0) { return $dpiX / 96.0 }
  } catch { }
  return 1.0
}

# 主屏可用工作区 (排除任务栏), 物理像素
function Get-PrimaryWorkArea {
  try {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    if ($wa.Width -gt 0 -and $wa.Height -gt 0) {
      return @{ Left = $wa.Left; Top = $wa.Top; Width = $wa.Width; Height = $wa.Height }
    }
  } catch { }
  # 兜底: 系统度量 (SM_CXWORKAREA=48 / SM_CYWORKAREA=49, 主屏左上角视为 0,0)
  $w = [DSHNative]::GetSystemMetrics(48)
  $h = [DSHNative]::GetSystemMetrics(49)
  if ($w -le 0) { $w = 1280 }; if ($h -le 0) { $h = 720 }
  return @{ Left = 0; Top = 0; Width = $w; Height = $h }
}

# 主屏完整边界 (含任务栏区域), 物理像素
function Get-PrimaryScreen {
  try {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    if ($b.Width -gt 0 -and $b.Height -gt 0) {
      return @{ Left = $b.Left; Top = $b.Top; Width = $b.Width; Height = $b.Height }
    }
  } catch { }
  # 兜底: 系统度量 (SM_CXSCREEN=0 / SM_CYSCREEN=1)
  $w = [DSHNative]::GetSystemMetrics(0)
  $h = [DSHNative]::GetSystemMetrics(1)
  if ($w -le 0) { $w = 1280 }; if ($h -le 0) { $h = 720 }
  return @{ Left = 0; Top = 0; Width = $w; Height = $h }
}

# 计算应用窗口布局 (按用户确认的比例 1352×972, 1920×1080 主屏下最合适):
#   宽度 = 主屏工作区宽度 × 1352/1920 (≈70.4%), 高度 = 宽度 × 972/1352 (保持比例);
#   最小 960×690 DIP (同比例), 不大于工作区;
#   位置 = 整个显示器水平/垂直居中 (窗口正中落在屏幕中心)。
# Chrome/Edge 的 --window-size / --window-position 使用 DIP, 因此返回 DIP 值。
function Get-AppWindowLayout {
  Set-ProcessDpiAware
  $scale = Get-PrimaryScale
  $wa = Get-PrimaryWorkArea
  $scr = Get-PrimaryScreen
  $ratio = 1352.0 / 972.0
  $wPhys = [math]::Round($wa.Width * (1352.0 / 1920.0))
  $hPhys = [math]::Round($wPhys / $ratio)
  $minWPhys = [math]::Round(960 * $scale)
  $minHPhys = [math]::Round($minWPhys / $ratio)
  if ($wPhys -lt $minWPhys) { $wPhys = $minWPhys; $hPhys = [math]::Round($wPhys / $ratio) }
  if ($hPhys -lt $minHPhys) { $hPhys = $minHPhys; $wPhys = [math]::Round($hPhys * $ratio) }
  if ($wPhys -gt $wa.Width)  { $wPhys = $wa.Width;  $hPhys = [math]::Round($wPhys / $ratio) }
  if ($hPhys -gt $wa.Height) { $hPhys = $wa.Height; $wPhys = [math]::Round($hPhys * $ratio) }
  $xPhys = $scr.Left + [math]::Round(($scr.Width - $wPhys) / 2)
  $yPhys = $scr.Top  + [math]::Round(($scr.Height - $hPhys) / 2)
  return @{
    scale    = $scale
    workArea = $wa
    screen   = $scr
    ratio    = $ratio
    sizeDip  = @{ Width = [math]::Round($wPhys / $scale); Height = [math]::Round($hPhys / $scale) }
    posDip   = @{ X = [math]::Round($xPhys / $scale); Y = [math]::Round($yPhys / $scale) }
    minPhys  = @{ Width = $minWPhys; Height = $minHPhys }
  }
}

# ---------- 应用窗口句柄与标题 ----------

# 支持的浏览器进程名白名单 (应用模式引擎): 只认主流 Chromium 内核浏览器。
# 明确排除豆包 Doubao / RoxyBrowser 等第三方套壳 —— 其进程名不在白名单内,
# 窗口 (含透明悬浮窗) 永远不会被当作 DSH 桌面窗口目标或被看守进程处理。
$supportedBrowserNames = @('chrome', 'msedge', 'brave', 'opera', 'vivaldi')

# 刷新当前白名单浏览器进程 PID 集合 (每次窗口枚举前调用, 包含刚启动的引擎进程)
function Get-SupportedBrowserPids {
  $script:supportedBrowserPids = @()
  foreach ($n in $supportedBrowserNames) {
    foreach ($p in (Get-Process $n -ErrorAction SilentlyContinue)) {
      $script:supportedBrowserPids += [int]$p.Id
    }
  }
  return $script:supportedBrowserPids
}

# 判断进程名是否在白名单内
function Test-BrowserProcessName([string]$name) {
  if (-not $name) { return $false }
  foreach ($n in $supportedBrowserNames) { if ($name -eq $n) { return $true } }
  return $false
}

# 找到指定 PID 进程的顶层窗口句柄 (类名 Chrome_WidgetWin_1)。
# 基于窗口枚举 (纯 Win32, 不依赖 WMI), 优先可见窗口,
# 找不到时退回该进程的第一个此类窗口。
function Find-HwndOfPid([uint32]$targetPid) {
  $script:foundHwnd = [IntPtr]::Zero
  $script:fallbackHwnd = [IntPtr]::Zero
  $cb = [DSHNative+EnumWindowsProc]{
    param($h, $l)
    $wpid = [uint32]0
    [void][DSHNative]::GetWindowThreadProcessId($h, [ref]$wpid)
    if ($wpid -eq $targetPid) {
      $cls = New-Object System.Text.StringBuilder 256
      [void][DSHNative]::GetClassName($h, $cls, $cls.Capacity)
      if ($cls.ToString() -eq 'Chrome_WidgetWin_1') {
        if ($script:fallbackHwnd -eq [IntPtr]::Zero) { $script:fallbackHwnd = $h }
        if ([DSHNative]::IsWindowVisible($h)) { $script:foundHwnd = $h; return $false }
      }
    }
    return $true
  }
  [void][DSHNative]::EnumWindows($cb, [IntPtr]::Zero)
  if ($script:foundHwnd -ne [IntPtr]::Zero) { return $script:foundHwnd }
  return $script:fallbackHwnd
}

# 看守进程启动前已存在的白名单浏览器窗口快照。
# 只收集白名单进程 (chrome/msedge/brave/opera/vivaldi) 的窗口:
# 豆包等第三方浏览器的窗口 (含透明悬浮窗) 一律不收集、不处理。
function Get-ChromeHwnds {
  [void](Get-SupportedBrowserPids)
  $script:chromeHwnds = New-Object System.Collections.Generic.List[IntPtr]
  $cb = [DSHNative+EnumWindowsProc]{
    param($h, $l)
    $wpid = [uint32]0
    [void][DSHNative]::GetWindowThreadProcessId($h, [ref]$wpid)
    if ($script:supportedBrowserPids -notcontains [int]$wpid) { return $true }
    $cls = New-Object System.Text.StringBuilder 256
    [void][DSHNative]::GetClassName($h, $cls, $cls.Capacity)
    if ($cls.ToString() -eq 'Chrome_WidgetWin_1') { [void]$script:chromeHwnds.Add($h) }
    return $true
  }
  [void][DSHNative]::EnumWindows($cb, [IntPtr]::Zero)
  return $script:chromeHwnds
}

# 启动后新出现的白名单浏览器窗口句柄列表 (不含看守进程启动前的窗口)。
# 看守进程隐藏全部新窗口, 渲染就绪后再恢复目标窗口, 防止"透明窗口 + 实体窗口"并存。
# 注意: 不能用启动前的 PID 集合过滤——浏览器进程是启动后新建的, 枚举前重新刷新集合,
# 且只收白名单浏览器进程的窗口 (豆包等第三方浏览器的窗口永不处理)。
function Get-NewChromeHwnds {
  [void](Get-SupportedBrowserPids)
  $script:newChromeHwnds = New-Object System.Collections.Generic.List[IntPtr]
  $cb = [DSHNative+EnumWindowsProc]{
    param($h, $l)
    if ($null -ne $script:appWindowPreexisting -and $script:appWindowPreexisting.Contains($h)) { return $true }
    $wpid = [uint32]0
    [void][DSHNative]::GetWindowThreadProcessId($h, [ref]$wpid)
    if ($script:supportedBrowserPids -notcontains [int]$wpid) { return $true }
    $cls = New-Object System.Text.StringBuilder 256
    [void][DSHNative]::GetClassName($h, $cls, $cls.Capacity)
    if ($cls.ToString() -eq 'Chrome_WidgetWin_1') {
      # 只收可见窗口 (启动瞬间的 app 窗口可见; 后台辅助窗口不可见, 无需处理)
      if ([DSHNative]::IsWindowVisible($h)) { [void]$script:newChromeHwnds.Add($h) }
    }
    return $true
  }
  [void][DSHNative]::EnumWindows($cb, [IntPtr]::Zero)
  return $script:newChromeHwnds
}

# 找到应用窗口句柄, 双通道 (均不依赖 WMI):
#   1) 记录 PID 的窗口 (首选, -Open 写入, 看守进程自愈为真实所有者;
#      记录 PID 必须属于白名单浏览器进程 —— 残留的豆包等第三方记录会被忽略);
#   2) 启动前不存在的白名单浏览器顶层窗口 (记录缺失/失效时兜底,
#      例如本机 Edge 已在运行、启动进程是转发进程的场景)。
# 返回 [IntPtr]::Zero 表示未找到。
function Find-AppWindowHandle {
  $rec = Read-AppWindowRecord
  if ($null -ne $rec) {
    # 记录 PID 必须是白名单浏览器进程, 否则忽略该记录 (防豆包悬浮窗被误当目标)
    $recProc = Get-Process -Id ([int]$rec.pid) -ErrorAction SilentlyContinue
    if ($null -ne $recProc -and (Test-BrowserProcessName $recProc.ProcessName)) {
      $hwnd = Find-HwndOfPid ([uint32][int]$rec.pid)
      if ($hwnd -ne [IntPtr]::Zero) { return $hwnd }
    }
  }
  if ($null -eq $script:appWindowPreexisting) { return [IntPtr]::Zero }
  [void](Get-SupportedBrowserPids)
  $script:newHwnd = [IntPtr]::Zero
  $script:newFallback = [IntPtr]::Zero
  $cb = [DSHNative+EnumWindowsProc]{
    param($h, $l)
    if ($script:appWindowPreexisting.Contains($h)) { return $true }
    $wpid = [uint32]0
    [void][DSHNative]::GetWindowThreadProcessId($h, [ref]$wpid)
    if ($script:supportedBrowserPids -notcontains [int]$wpid) { return $true }
    $cls = New-Object System.Text.StringBuilder 256
    [void][DSHNative]::GetClassName($h, $cls, $cls.Capacity)
    if ($cls.ToString() -eq 'Chrome_WidgetWin_1') {
      if ($script:newFallback -eq [IntPtr]::Zero) { $script:newFallback = $h }
      if ([DSHNative]::IsWindowVisible($h)) { $script:newHwnd = $h; return $false }
    }
    return $true
  }
  [void][DSHNative]::EnumWindows($cb, [IntPtr]::Zero)
  if ($script:newHwnd -ne [IntPtr]::Zero) { return $script:newHwnd }
  return $script:newFallback
}

function Get-WindowTitle([IntPtr]$hwnd) {
  $sb = New-Object System.Text.StringBuilder 512
  [void][DSHNative]::GetWindowText($hwnd, $sb, $sb.Capacity)
  return $sb.ToString()
}

# ---------- 窗口看守进程 ----------

# 由 -Open/-AutoStart 在打开浏览器前启动的隐藏看守进程:
#   1. 记录启动前已有的 chrome/msedge 窗口, 等待应用窗口出现, 立即隐藏 (杜绝启动闪烁);
#   2. 等页面标题就绪 (不再是 URL/新标签页) 或超时后, 恢复显示并强制居中尺寸;
#   3. 把窗口真实所有者 PID 写回记录 (自愈, 供状态检测/切换关闭使用), 设置黑鲸窗口图标;
#   4. 常驻轮询: 窗口被缩到 960×690 DIP 以下时强制拉回; 窗口关闭后自行退出。
function Start-WatchAppWindow {
  $watchMutex = New-Object System.Threading.Mutex($false, 'DSHDesktopWindowWatcher')
  $isFirst = $false
  try { $isFirst = $watchMutex.WaitOne(0) } catch { $isFirst = $true }
  if (-not $isFirst) { return }
  try {
    $layout = Get-AppWindowLayout
    $script:appWindowPreexisting = Get-ChromeHwnds
    # 快照完成: 通知 -Open 可以启动浏览器了 (保证"启动前窗口"快照先于新窗口创建,
    # 这样 Find-AppWindowHandle 一定能把新窗口识别为"新窗口"并立即隐藏)
    try { Set-Content -Path $watcherReadyFile -Value '1' -Encoding Ascii } catch { }
    $t0 = [Environment]::TickCount
    # 阶段 1: 等待窗口出现 (最多 30 秒)
    while ([Environment]::TickCount - $t0 -lt 30000) {
      $hwnd = Find-AppWindowHandle
      if ($hwnd -ne [IntPtr]::Zero) { break }
      Start-Sleep -Milliseconds 100
    }
    if ($hwnd -eq [IntPtr]::Zero) { return }
    # 阶段 2: 立即隐藏"本次启动新出现"的所有 chrome 顶层窗口 (不只是第一个):
    # 部分 Chromium 系浏览器会额外创建未渲染的透明窗口, 只隐藏一个会导致
    # "透明窗口 + 实体窗口"并存; 全部隐藏后, 渲染就绪时只恢复目标窗口。
    $newHwnds = Get-NewChromeHwnds
    foreach ($h in $newHwnds) { [void][DSHNative]::ShowWindow($h, 0) }
    # 等页面渲染就绪 (标题不再是 URL/New Tab, 或 15 秒超时)。
    # 就绪判断必须同时排除带协议的 URL (http://127.0.0.1:3080/), 否则页面还在
    # 加载就会被误判为就绪而提前显示透明窗口。
    $t1 = [Environment]::TickCount
    while ([Environment]::TickCount - $t1 -lt 15000) {
      $title = Get-WindowTitle $hwnd
      if ($title -and $title -ne 'New Tab' -and $title -notmatch $origin -and $title -notmatch '(localhost|127\.0\.0\.1):\d+') { break }
      Start-Sleep -Milliseconds 150
    }
    # 阶段 2.5: 记录真实窗口所有者 PID (自愈; 窗口可能属于转发进程或既有的 Edge 实例)。
    # 只写回白名单浏览器进程 (防豆包等第三方窗口被误记录为桌面窗口)
    $ownerPid = [uint32]0
    [void][DSHNative]::GetWindowThreadProcessId($hwnd, [ref]$ownerPid)
    if ($ownerPid -gt 0) {
      $ownerProc = Get-Process -Id ([int]$ownerPid) -ErrorAction SilentlyContinue
      if ($null -ne $ownerProc -and (Test-BrowserProcessName $ownerProc.ProcessName)) {
        Write-AppWindowRecord ([int]$ownerPid)
      }
    }
    # 阶段 3: 恢复显示并按布局强制尺寸与居中位置, 设置黑鲸窗口图标 (标题栏/Alt-Tab)
    [void][DSHNative]::ShowWindow($hwnd, 9)
    $wScale = [DSHNative]::GetDpiForWindow($hwnd) / 96.0
    if ($wScale -le 0) { $wScale = $layout.scale }
    $x = [math]::Round($layout.posDip.X * $wScale)
    $y = [math]::Round($layout.posDip.Y * $wScale)
    $w = [math]::Round($layout.sizeDip.Width * $wScale)
    $h = [math]::Round($layout.sizeDip.Height * $wScale)
    [void][DSHNative]::SetWindowPos($hwnd, [IntPtr]::Zero, $x, $y, $w, $h, 0x0014) # SWP_NOZORDER|SWP_NOACTIVATE
    # WM_SETICON: 0x80, ICON_BIG=1 / ICON_SMALL=0; IMAGE_ICON=1, LR_LOADFROMFILE=0x10
    $iconSmall = [DSHNative]::LoadImageW([IntPtr]::Zero, $icoPath, 1, 16, 16, 0x10)
    $iconBig   = [DSHNative]::LoadImageW([IntPtr]::Zero, $icoPath, 1, 32, 32, 0x10)
    if ($iconBig -ne [IntPtr]::Zero)   { [void][DSHNative]::SendMessage($hwnd, 0x80, [IntPtr]1, $iconBig) }
    if ($iconSmall -ne [IntPtr]::Zero) { [void][DSHNative]::SendMessage($hwnd, 0x80, [IntPtr]0, $iconSmall) }
    [void][DSHNative]::SetForegroundWindow($hwnd)
    # 阶段 4: 常驻最小尺寸守护 (最大化时跳过; 最小尺寸保持 1352:972 比例)
    $minRatio = $layout.sizeDip.Width / $layout.sizeDip.Height
    while ($true) {
      Start-Sleep -Milliseconds 200
      if (-not [DSHNative]::IsWindow($hwnd)) { break }
      if ([DSHNative]::IsZoomed($hwnd)) { continue }
      $rect = New-Object DSHNative+RECT
      if (-not [DSHNative]::GetWindowRect($hwnd, [ref]$rect)) { continue }
      $wScale = [DSHNative]::GetDpiForWindow($hwnd) / 96.0
      if ($wScale -le 0) { $wScale = $layout.scale }
      $minW = [math]::Round(960 * $wScale)
      $minH = [math]::Round($minW / $minRatio)
      $cw = $rect.Right - $rect.Left
      $ch = $rect.Bottom - $rect.Top
      if ($cw -lt $minW -or $ch -lt $minH) {
        $nw = [math]::Max($cw, $minW)
        $nh = [math]::Max($ch, $minH)
        # SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE
        [void][DSHNative]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, $nw, $nh, 0x0006)
      }
    }
    if ($iconBig -ne [IntPtr]::Zero)   { [void][DSHNative]::DestroyIcon($iconBig) }
    if ($iconSmall -ne [IntPtr]::Zero) { [void][DSHNative]::DestroyIcon($iconSmall) }
  } finally {
    try { $watchMutex.ReleaseMutex() } catch { }
    try { $watchMutex.Dispose() } catch { }
  }
}

# 返回打开方式: app / app-existing / default / none
# 默认固定以独立桌面窗口打开: 主屏比例 1352:972 居中 (最小 960×690 DIP),
# 使用独立配置目录 (--user-data-dir): 应用窗口进程就是窗口所有者, 不受本机
# Edge/Chrome 是否已在运行的影响 (不会转发给既有进程, 也不会恢复旧窗口尺寸),
# 以 --start-minimized 最小化启动, 由看守进程在渲染就绪后恢复显示并守护最小尺寸;
# 窗口使用黑鲸图标 (--app-user-model-id 匹配桌面快捷方式 + 看守进程 WM_SETICON);
# 只有本机没有 Edge/Chrome 时才回退默认浏览器。
function Open-HarnessWindow {
  # 并发防双开: 设置页按钮/托盘双击/登录自启动可能几乎同时触发打开流程,
  # 若两个实例都用同一 --user-data-dir 启动浏览器, 会打开两个 app 窗口
  # (一个渲染完成=实体, 一个还在加载=透明)。用命名互斥锁串行化整个打开流程。
  $openMutex = New-Object System.Threading.Mutex($false, $openMutexName)
  $ownedOpen = $false
  try { $ownedOpen = $openMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ownedOpen = $true } catch { $ownedOpen = $false }
  if (-not $ownedOpen) {
    # 另一个打开流程正在进行: 等待它完成 (最多 30 秒), 期间窗口出现即视为已打开
    for ($i = 0; $i -lt 60; $i++) {
      Start-Sleep -Milliseconds 500
      if ($null -ne (Get-AppWindowProcess)) { break }
    }
    try { $ownedOpen = $openMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ownedOpen = $true } catch { $ownedOpen = $false }
    if (-not $ownedOpen) {
      try { $openMutex.Dispose() } catch { }
      return 'app-existing'
    }
  }
  try {
    if ($null -ne (Get-AppWindowProcess)) { return 'app-existing' }
    # 从网页端切换到桌面端: 先通知所有已打开的 Harness 页面自行关闭 (浏览器标签页/窗口)
    [void](Send-QuitSignal)
    $browser = Find-AppBrowser
    if ($browser) {
      $layout = Get-AppWindowLayout
      $script:lastWindowInfo = ('{0}x{1} @ ({2},{3}) DIP, scale {4}' -f $layout.sizeDip.Width, $layout.sizeDip.Height, $layout.posDip.X, $layout.posDip.Y, $layout.scale)
      $profileDir = Join-Path $scriptDir 'edge-profile'
      $appArgs = '--app=' + $origin +
                 ' --window-size=' + $layout.sizeDip.Width + ',' + $layout.sizeDip.Height +
                 ' --window-position=' + $layout.posDip.X + ',' + $layout.posDip.Y +
                 ' --user-data-dir="' + $profileDir + '"' +
                 ' --app-user-model-id=DSHDesktopApp' +
                 ' --no-first-run --no-default-browser-check --start-minimized'
      # 先启动看守进程 (等窗口出现后隐藏→渲染就绪→恢复显示→守护最小尺寸),
      # 并等待它完成"启动前窗口快照"(watcher.ready) 再打开浏览器:
      # 保证看守进程能识别到新窗口并立即隐藏, 渲染就绪前用户看不到透明窗口
      Start-Process 'powershell.exe' -ArgumentList '-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"' + $scriptDir + '\dsh-tray.ps1"'),'-WatchAppWindow' -WindowStyle Hidden
      for ($i = 0; $i -lt 80; $i++) {
        if (Test-Path $watcherReadyFile) { break }
        Start-Sleep -Milliseconds 100
      }
      Remove-Item $watcherReadyFile -Force -ErrorAction SilentlyContinue
      # 通过带黑鲸图标的 .lnk 启动窗口: Windows 直接用该快捷方式的图标/名称作为
      # 任务栏按钮 (而不是引擎的 logo), 并按 DSHDesktopApp 分组
      $appLnk = Update-AppWindowShortcut $browser $appArgs
      if ($appLnk -and (Test-Path $appLnk)) {
        try {
          $launched = Start-Process -FilePath $appLnk -PassThru
          if ($null -ne $launched) { Write-AppWindowRecord $launched.Id }
          return 'app'
        } catch { }
      }
      # 兜底: 直接启动浏览器 (图标退化为引擎 logo, 功能不受影响)
      try {
        $launched = Start-Process -FilePath $browser -ArgumentList $appArgs -PassThru
        if ($null -ne $launched) { Write-AppWindowRecord $launched.Id }
        return 'app'
      } catch {
        $script:lastWindowInfo = $null
      }
    }
    try { Start-Process $origin; return 'default' } catch { return 'none' }
  } finally {
    try { $openMutex.ReleaseMutex() } catch { }
    try { $openMutex.Dispose() } catch { }
  }
}

# 更新/创建应用窗口启动快捷方式 (黑鲸图标 + AppUserModelID):
#   dsh-appwindow.lnk (脚本目录) —— -Open 通过它启动窗口, 任务栏按钮直接使用
#   该快捷方式的图标与名称;
#   开始菜单 DeepSeek Harness.lnk —— 作为任务栏按 AppUserModelID 查找图标时的
#   锚点, 同时也是一个面向用户的启动入口。
function Update-AppWindowShortcut([string]$browser, [string]$appArgs) {
  try {
    $shell = New-Object -ComObject WScript.Shell
    $lnkPath = Join-Path $scriptDir 'dsh-appwindow.lnk'
    $sc = $shell.CreateShortcut($lnkPath)
    $sc.TargetPath = $browser
    $sc.Arguments = $appArgs
    $sc.IconLocation = $icoPath + ',0'
    $sc.Description = 'DeepSeek Harness 桌面端'
    $sc.WorkingDirectory = $scriptDir
    $sc.Save()
    try { [void][DSHShell]::SetAppUserModelId($lnkPath, 'DSHDesktopApp', $icoPath) } catch { }
    $startMenu = [Environment]::GetFolderPath('Programs')
    if ($startMenu) {
      $lnkStart = Join-Path $startMenu $shortcutName
      $sc2 = $shell.CreateShortcut($lnkStart)
      $sc2.TargetPath = $browser
      $sc2.Arguments = $appArgs
      $sc2.IconLocation = $icoPath + ',0'
      $sc2.Description = 'DeepSeek Harness 桌面端'
      $sc2.WorkingDirectory = $scriptDir
      $sc2.Save()
      try { [void][DSHShell]::SetAppUserModelId($lnkStart, 'DSHDesktopApp', $icoPath) } catch { }
    }
    return $lnkPath
  } catch { return $null }
}

# ---------- 终端窗口显示/隐藏 ----------

function Set-TerminalWindow([int]$showCode) {
  $root = Get-HarnessRoot
  if ($null -eq $root) { return $false }
  $hwnd = [DSHNative]::ConsoleWindowOf([uint32]$root.ProcessId)
  if ($hwnd -eq [IntPtr]::Zero) { return $false }
  [void][DSHNative]::ShowWindowAsync($hwnd, $showCode)
  return $true
}

# ---------- 结束 Harness ----------

function Stop-Harness {
  $found = $false
  $root = Get-HarnessRoot
  if ($null -ne $root) {
    & taskkill.exe /PID $root.ProcessId /T /F 2>$null | Out-Null
    $found = $true
  }
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'node.exe' -and ($_.CommandLine -like '*@deepseek-ai/dsh*' -or $_.CommandLine -like '*@deepseek-ai\dsh*') -and $_.CommandLine -like '*web*' } |
    ForEach-Object {
      & taskkill.exe /PID $_.ProcessId /T /F 2>$null | Out-Null
      $found = $true
    }
  return $found
}

# ---------- 其它 ----------

# 通知所有打开的 Harness 浏览器页面自动关闭: 向宿主同源路由 POST quit,
# 宿主通过 SSE 向每个已连接页面广播 quit 事件, 页面收到后自行关闭标签页。
# 仅当通知成功时才等待片刻 (给页面关闭留时间)。
function Send-QuitSignal {
  $ok = $false
  try {
    Invoke-WebRequest -Uri ($origin + '/_dsh/dsh-desktop') -Method Post -UseBasicParsing -TimeoutSec 5 -Headers @{
      'Origin' = $origin
      'sec-fetch-site' = 'same-origin'
      'Content-Type' = 'application/json'
    } -Body '{"action":"quit"}' | Out-Null
    $ok = $true
  } catch { }
  if ($ok) { Start-Sleep -Milliseconds 1500 }
  return $ok
}

# 托盘"退出"与 -Quit 共用逻辑:
#   1) 通知所有 Harness 页面 (浏览器标签页) 自动关闭;
#   2) 关闭独立桌面窗口 —— 应用模式窗口不允许脚本自行关闭, 必须显式结束其进程
#      (看守进程会随窗口消失而自行退出);
#   3) 结束 Harness 终端与服务。
function Invoke-Quit {
  [void](Send-QuitSignal)
  Close-AppWindow
  [void](Stop-Harness)
}

function Install-Shortcut {
  $desktop = [Environment]::GetFolderPath('Desktop')
  $lnkPath = Join-Path $desktop $shortcutName
  $shell = New-Object -ComObject WScript.Shell
  $sc = $shell.CreateShortcut($lnkPath)
  $sc.TargetPath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
  $sc.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptDir + '\dsh-tray.ps1" -Open'
  $sc.WorkingDirectory = $scriptDir
  $sc.IconLocation = $icoPath + ',0'
  $sc.Description = 'DeepSeek Harness 桌面端'
  $sc.Save()
  # 任务栏 AppUserModelID: 让 --app-user-model-id=DSHDesktopApp 的桌面窗口
  # 在任务栏/Alt-Tab 使用本快捷方式的黑鲸图标与名称 (而不是 Edge/Chrome 的 logo)
  try { [void][DSHShell]::SetAppUserModelId($lnkPath, 'DSHDesktopApp', $icoPath) } catch { }
  return $lnkPath
}

function Set-AutoStart {
  $value = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptDir + '\dsh-tray.ps1" -AutoStart'
  New-Item -Path $runKey -Force | Out-Null
  Set-ItemProperty -Path $runKey -Name $runValue -Value $value -Type String
}

function Clear-AutoStart {
  Remove-ItemProperty -Path $runKey -Name $runValue -ErrorAction SilentlyContinue
}

function Write-OpenState([bool]$ok, [long]$readyMs, [string]$browser, [string]$error, [string]$window) {
  $obj = @{ at = (Get-Date).ToString('o'); ok = $ok; readyMs = $readyMs; browser = $browser; error = $error; window = $window }
  try { $obj | ConvertTo-Json -Compress | Set-Content -Path $openStateFile -Encoding Ascii } catch { }
}

# ---------- 命令分发 ----------

if ($ShortcutOk) {
  # 桌面快捷方式存在, 且指向本脚本的 -Open 模式 (用于宿主插件自动修复旧版快捷方式)
  $lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) $shortcutName
  $ok = $false
  try {
    if (Test-Path $lnkPath) {
      $sh = New-Object -ComObject WScript.Shell
      $sc = $sh.CreateShortcut($lnkPath)
      $target = [string]$sc.TargetPath
      $args   = [string]$sc.Arguments
      $ok = ($target -like '*powershell.exe') -and
            ($args -like ('*' + $scriptDir + '*')) -and
            ($args -like '*dsh-tray.ps1*') -and
            ($args -like '*-Open*')
    }
  } catch { $ok = $false }
  if ($ok) { exit 0 } else { exit 1 }
}
if ($Install) {
  $lnk = Install-Shortcut
  Write-Output ("shortcut: " + $lnk)
  exit 0
}
if ($AutoStartOn) { Set-AutoStart; Write-Output 'autostart on'; exit 0 }
if ($AutoStartOff) { Clear-AutoStart; Write-Output 'autostart off'; exit 0 }

# 终端窗口显示/隐藏 (由设置页调用; Harness 未运行时静默成功, 偏好会用于下次启动)
if ($ShowTerminal) {
  [void](Set-TerminalWindow 9)
  [void](Set-TerminalWindow 5)
  exit 0
}
if ($HideTerminal) {
  [void](Set-TerminalWindow 0)
  exit 0
}

# -Quit: 通知页面自动关闭 → 关闭桌面窗口 → 结束 Harness (与托盘菜单"退出"共用同一逻辑)
if ($Quit) {
  Invoke-Quit
  exit 0
}

# -AppWindowActive: 检测独立桌面窗口是否在运行 (退出码 0/1), 供设置页判断当前是桌面端还是网页端
if ($AppWindowActive) {
  if ($null -ne (Get-AppWindowProcess)) { exit 0 } else { exit 1 }
}

# -LayoutInfo: 打印 DPI 感知的窗口布局计算 (不打开任何窗口), 供诊断高 DPI 环境下的尺寸/位置
if ($LayoutInfo) {
  $layout = Get-AppWindowLayout
  $layout | ConvertTo-Json -Compress
  exit 0
}

# -OpenWeb: 切换到网页端 —— 确保服务运行, 关闭独立桌面窗口 (看守进程随窗口退出而自行结束),
# 用默认浏览器打开, 记录诊断信息并退出
if ($OpenWeb) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $ok = Ensure-Harness
  $sw.Stop()
  Close-AppWindow
  if ($ok) {
    try {
      Start-Process $origin
      Write-OpenState $true $sw.ElapsedMilliseconds 'default' $null $null
    } catch {
      Write-OpenState $false $sw.ElapsedMilliseconds $null 'failed to open default browser' $null
    }
  } else {
    Write-OpenState $false $sw.ElapsedMilliseconds $null 'harness did not become ready within 60s' $null
  }
  exit 0
}

# -Open: 确保服务运行后打开 (独立窗口优先), 记录诊断信息并退出
if ($Open) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $ok = Ensure-Harness
  $sw.Stop()
  if ($ok) {
    $script:lastWindowInfo = $null
    $browser = Open-HarnessWindow
    Write-OpenState $true $sw.ElapsedMilliseconds $browser $null $script:lastWindowInfo
  } else {
    Write-OpenState $false $sw.ElapsedMilliseconds $null 'harness did not become ready within 60s' $null
  }
  exit 0
}

# -WatchAppWindow: 窗口看守进程 (由 -Open/-AutoStart 启动, 隐藏运行, 自行退出)
if ($WatchAppWindow) {
  Start-WatchAppWindow
  exit 0
}

# -AutoStart: 登录自启动。若服务未运行且没有正在启动/运行的实例, 后台拉起服务;
# 等 HTTP 就绪后直接打开桌面窗口 (默认桌面端, 而不是浏览器), 然后进入托盘
if ($AutoStart) {
  if (-not (Test-HarnessHttp)) {
    $running = Get-HarnessNode
    if ($null -eq $running) { [void](Start-Harness) }
    for ($i = 0; $i -lt 120; $i++) {
      Start-Sleep -Milliseconds 500
      if (Test-HarnessHttp) { break }
    }
  }
  [void](Open-HarnessWindow)
  # 继续进入托盘模式
}

# ---------- 托盘模式: 单实例 ----------
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$isFirst = $false
try { $isFirst = $mutex.WaitOne(0) } catch { try { $mutex.ReleaseMutex() } catch {}; $isFirst = $true }
if (-not $isFirst) { exit 0 }

$notify = New-Object System.Windows.Forms.NotifyIcon
if (Test-Path $icoPath) {
  try { $notify.Icon = New-Object System.Drawing.Icon($icoPath) } catch { $notify.Icon = [System.Drawing.SystemIcons]::Application }
} else {
  $notify.Icon = [System.Drawing.SystemIcons]::Application
}
$notify.Text = 'DeepSeek Harness'
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$openItem = New-Object System.Windows.Forms.ToolStripMenuItem('打开 DeepSeek Harness')
# 打开逻辑放到独立进程执行, 避免阻塞托盘 UI
$openItem.Add_Click({
  Start-Process 'powershell.exe' -ArgumentList '-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"' + $scriptDir + '\dsh-tray.ps1"'),'-Open'
})
$quitItem = New-Object System.Windows.Forms.ToolStripMenuItem('退出')
# 退出 = 通知浏览器页面自动关闭 + 关闭桌面窗口 + 结束 Harness 终端与服务, 然后退出托盘
$quitItem.Add_Click({
  $notify.Visible = $false
  Invoke-Quit
  Remove-Item $pidFile -ErrorAction SilentlyContinue
  [System.Windows.Forms.Application]::Exit()
})
[void]$menu.Items.Add($openItem)
[void]$menu.Items.Add($quitItem)
$notify.ContextMenuStrip = $menu
$notify.Add_DoubleClick({
  Start-Process 'powershell.exe' -ArgumentList '-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"' + $scriptDir + '\dsh-tray.ps1"'),'-Open'
})

try { $PID | Set-Content -Path $pidFile -Encoding ASCII } catch {}

[System.Windows.Forms.Application]::Run()
$notify.Dispose()
Remove-Item $pidFile -ErrorAction SilentlyContinue
$mutex.Dispose()
