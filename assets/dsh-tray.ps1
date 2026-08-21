# DeepSeek Harness 桌面端 —— 托盘伴侣脚本 v7.6
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
#   dsh-tray.ps1 -Restart         重启 Harness 服务并重新打开桌面窗口, 托盘保持运行
#   dsh-tray.ps1 -AppWindowActive  检测独立桌面窗口是否在运行 (运行: 退出码 0, 未运行: 1)
#   dsh-tray.ps1 -LayoutInfo       打印 DPI 感知的窗口布局计算 (尺寸/位置/缩放比) 后退出
#   dsh-tray.ps1 -AutoStartOn      写入开机自启动 (HKCU Run) 后退出
#   dsh-tray.ps1 -AutoStartOff     删除开机自启动后退出
#   dsh-tray.ps1 -AutoStart        登录自启动模式: 免 npx 直连拉起 Harness 服务, 同时
#                                  立即打开桌面窗口 (内置 boot.html 启动页, 服务就绪后
#                                  自动跳转), 然后常驻托盘图标
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
#
# v6 性能修复 (开机自启动延迟):
#   - 顶层 Add-Type C# 编译改为懒加载, 并按源码哈希缓存为 DLL (dsh-native-<hash>.dll /
#     dsh-shell-<hash>.dll): 简单模式 (-ShortcutOk/-AutoStartOn/-AutoStartOff) 不再
#     编译 C#, 看守进程直接加载缓存程序集, 开机不再为每次 PowerShell 冷启动付 csc 成本;
#   - 所有 Get-CimInstance 查询改为有界 (Invoke-CimBounded, 后台任务 + 超时兜底),
#     并加快速预检查: 开机初期 WMI 服务未就绪时不会再阻塞数分钟;
#   - -AutoStart 全程不依赖 WMI (TCP 端口探活 + 命名互斥锁), 并清除上一会话过期的
#     app-window.json, 避免打开流程走 CIM 回退通道;
#   - -AutoStart 不等 HTTP 就绪: 立即打开 boot.html 启动页 (窗口数秒内可见),
#     页面轮询服务就绪后自动跳转到 Harness 界面。
# v7 修复 (开机自启动仍然慢):
#   - 计划任务注册不再用 schtasks /TR (反斜杠转义引号 \" 会被 schtasks 字面
#     解析, 报 "系统找不到指定的路径" 而失败, 每次都回退 Run 键 —— 开机仍被
#     Explorer 启动项队列拖慢 1~2 分钟); 改为 Schedule.Service COM 注册 (首选,
#     无命令行引号解析, 不依赖 schtasks.exe) 与 schtasks /Create /XML (回退,
#     XML 中的引号无需转义), 注册后校验任务存在才删除 Run 键;
#   - -AutoStart 打开窗口的流程跳过 CIM 回退通道: 开机初期 WMI 未就绪时不再
#     多付一次 Start-Job 子进程 (又是一次 PowerShell 冷启动) 与最长 8 秒等待;
#   - 新增 -AutoStartDiag 诊断模式: 报告两种注册方式的结果与当前自启动状态。
# v7.1 (界面打开仍慢):
#   - 实测开机时间线: 登录瞬间任务触发 (+0s) → PowerShell 冷启动 27 秒
#     (登录峰值争抢下 PS 5.1 的 CLR 初始化) → node 才拉起 → 服务 48 秒才就绪,
#     界面出现被 PS 冷启动 + 服务冷启动双重拖慢。
#   - 任务动作改为 wscript.exe + dsh-autostart.vbs 启动器: wscript 冷启动约
#     1 秒 (无 CLR 初始化), 登录瞬间直接隐藏拉起 node, 再启动 PowerShell
#     伴侣 (窗口/托盘); -AutoStart 检测到"启动器标记 + node 进程在运行"时
#     跳过重复拉起 (纯 Win32 Get-Process, 不依赖 WMI);
#   - 任务优先级 7 (低于正常) → 5 (普通), 启动链不再在开机争抢中垫底。
# v7.2 (退出后立刻重开冲突):
#   - 竞态场景: 托盘"退出"后马上点桌面快捷方式重开 —— 旧实例尚未完全关闭时,
#     -Open 可能误判"已在启动"而跳过拉起, 或撞上正在关闭的端口, 最终服务起不来、
#     托盘不出现, 必须再退出重开一次。修复:
#     a) -Quit/托盘退出期间写 quitting.tmp 标记, -Open/-OpenWeb 先等退出完成
#        (最多 20 秒, 卡死则清除标记继续);
#     b) Stop-Harness 先快照全部目标再统一结束 (防新实例混入被杀), 并等待端口
#        真正释放 (最多 8 秒);
#     c) Ensure-Harness 发现"进程在但端口未监听"时观察该进程: 退出即残留 →
#        立即重新拉起; 20 秒端口仍无且进程存活 → 强杀重启;
#     d) -Open/-OpenWeb 成功后托盘缺失时补充拉起 (快捷方式打开也保证托盘出现);
#     e) -AutoStart 信任启动器但端口 15 秒不起 (如开机时其它软件恰好在跑 node.exe)
#        → 自行拉起, 保证服务必然可用。
#   - 任务动作改为两个顺序动作: ① wscript 启动器直启服务; ② PowerShell -AutoStart
#     兜底 + 窗口/托盘。wscript 被策略禁用时动作②仍会拉起服务。
# v7.3 (退出后立刻重开仍然失败 —— 修复 v7.2 的残余竞态):
#   实测"托盘退出后马上点快捷方式重开"仍会出现: 托盘不出现 / 服务起不来。
#   根因:
#   a) Wait-QuitFinished 20 秒超时后强制清除 quitting.tmp —— 若退出进程还
#      在执行 Stop-Harness (WMI 扫描在最坏情况下可达 20+ 秒), -Open 会提前
#      放行, 与退出者并发启动新实例, 新实例可能被退出者的快照扫描误杀,
#      之后 -Open 干等 60 秒失败: 服务不可访问 + 托盘不出现;
#   b) 退出顺序是"先通知页面/关窗口, 最后停服务" —— 服务在整个退出期间一直
#      存活, 端口长期不释放, 竞态窗口被拉大;
#   c) Ensure-TrayRunning 直接启动新托盘, 不验证旧托盘进程是否已退出 —— 新
#      托盘与垂死旧托盘争 DSHDesktopTray 互斥锁失败而瞬间退出, 或旧托盘
#      pidFile 尚未删除导致跳过启动, 最终没有任何托盘;
#   d) Ensure-Harness 的 60 秒等待循环只被动等待: "端口在监听但 HTTP 一直不
#      就绪"的垂死/卡死实例 (退出中) 不会被回收, 直接超时失败。
#   修复:
#   a) quitting.tmp 写入退出者 PID; Wait-QuitFinished 等"标记消失或退出者进程
#      已结束", 退出者存活期间绝不强行清除标记 (上限 45 秒);
#   b) Invoke-Quit 改为先停服务 (端口尽快释放), 再关桌面窗口, 最后通知页面;
#   c) Ensure-TrayRunning: 先等旧托盘进程完全退出, 再启动新托盘并轮询验证
#      (pidFile + 进程存活), 失败重试最多 3 次;
#   d) Ensure-Harness 等待循环自愈: 每 15 秒评估一次 —— 无进程无端口 → 重新
#      拉起; 端口在但 HTTP 久不就绪且进程够老 (>20 秒) → 强杀后重新拉起;
#   e) Stop-Harness 增加"年龄护栏" (只结束 6 秒前已存在的进程): 即使退出者
#      卡死放行后的并发启动, 新实例也绝不可能被退出者的快照误杀。
# v7.4 (设置页"显示终端"无反应):
#   - 根因: v7.3 给 Get-HarnessNode/Get-HarnessRoot 增加 [datetime]$Cutoff 年龄
#     护栏参数时, Get-HarnessRoot 把未传参的 $null 显式传给 Get-HarnessNode
#     (-Cutoff $null), PowerShell 尝试把 null 转换为 DateTime 抛参数转换异常;
#     $ErrorActionPreference='SilentlyContinue' 把异常静默吞掉 → 调用方拿到
#     空 root → Set-TerminalWindow 静默返回 → "显示终端/隐藏终端"都无反应。
#     修复: Cutoff 参数改为无类型 (不传/传 $null/传真实时间点均安全), 年龄
#     护栏逻辑不变 —— 开机自启动与退出后立刻重开的竞态防护不受影响, 且
#     Ensure-Harness 的"垂死实例观察"随之恢复 (v7.3 里该路径同样被吞异常,
#     永远直接走 Start-Harness)。
#   - 顺手: Set-TerminalWindow 区分"Harness 未运行 (静默成功, 偏好下次生效)"
#     与"Harness 在运行但窗口操作失败 (退出码 1, 设置页显示错误)"。
# v7.5 (退出后 node.exe 驻留):
#   - 根因: Stop-Harness 的结束循环写成了 `foreach ($pid in ...)` —— $PID 是
#     PowerShell 的只读自动变量 (当前进程 ID), 循环变量无法对它赋值, 会抛
#     "Cannot overwrite variable PID because it is read-only or constant";
#     而 $ErrorActionPreference='SilentlyContinue' 把该异常静默吞掉, 导致整个
#     taskkill 循环一次都没有执行 —— 托盘"退出"只通知页面/关窗口, 却从不真正
#     结束 Harness 的 node 进程, 任务管理器里 node.exe 因此一直驻留 (看起来像
#     根本没退出)。这也解释了为何 v7.2/v7.3 "退出后立刻重开" 的竞态曾反复出现:
#     旧实例从未被结束, 只是被新的自愈/重拉逻辑掩盖了。
#     修复: 循环变量改名为 $targetPid (避开只读 $PID), taskkill 恢复执行,
#     Harness node 进程在退出时被真正结束。
# v7.6 (终端闪现 / 开机托盘缺失 / 卡顿):
#   - 彻底消除终端闪现: 所有"外部拉起 PowerShell"的入口 (桌面快捷方式、托盘打开/
#     双击、开机任务动作②、Run 键兜底) 一律改为 wscript.exe + sh.Run(..., 0, False)
#     隐藏启动, 或 Start-Process 的 -WindowStyle Hidden 开关 —— 在 Win32 层以 SW_HIDE
#     创建进程, 控制台从头到尾不出现。此前 'powershell.exe -WindowStyle Hidden' 作为
#     命令行参数要等 CLR 启动完成后才生效, 开机争抢下 CLR 冷启动可达数十秒, 期间
#     控制台一直可见 (即"弹出一个终端, 窗口出来后才消失")。
#   - 修复开机"窗口开了但托盘不显示": 托盘 pidFile 改为拿到互斥锁后才写入 (单一归属),
#     不再与宿主 apply 的补拉托盘互相覆盖; 托盘互斥锁的 abandoned 处理不再错误地
#     ReleaseMutex (旧代码会让两个托盘并存争写 pidFile)。
#   - 降低卡顿: Close-AppWindow 关闭窗口后写回 pid=0 记录而非删除文件, 宿主快速路径
#     据此直接判定"未运行", 不再每 5 秒冷启动一个 PowerShell -AppWindowActive; 看守
#     进程常驻轮询从 200ms 放宽到 500ms。
# 注意: 本文件必须以 UTF-8 带 BOM 保存, 否则 Windows PowerShell 5.1 会按 ANSI 读取,
# 中文注释/字符串乱码会导致脚本解析失败。
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
  [switch]$AutoStartDiag,
  [switch]$ShowTerminal,
  [switch]$HideTerminal,
  [switch]$Restart,
  [switch]$Quit
)
$ErrorActionPreference = 'SilentlyContinue'

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
$openRequestMutexName = 'DSHDesktopOpenRequest'
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

# ---------- C# 原生辅助源码 (懒加载: 仅需要的模式才编译, 开机路径不编译) ----------
$DSHNativeSource = @'
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
$DSHShellSource = @'
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

# ---------- 延迟加载: 编译一次并缓存为 DLL, 后续进程直接加载 ----------
# PowerShell 冷启动时 Add-Type -TypeDefinition 每次都会调用 csc 编译 C#,
# 开机初期可达数十秒; 首次编译产物按源码哈希命名存于脚本目录, 之后所有
# 模式/看守进程只需 Add-Type -Path 加载 (亚秒级), 开机路径不再编译。
$script:winFormsLoaded = $false
$script:nativeLoaded = $false
$script:shellLoaded = $false

function Get-SourceHash([string]$src) {
  try {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
      $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($src))
      return [System.BitConverter]::ToString($bytes).Replace('-', '').Substring(0, 12).ToLowerInvariant()
    } finally { $md5.Dispose() }
  } catch { return 'legacy' }
}

function Ensure-WinForms {
  if ($script:winFormsLoaded) { return }
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $script:winFormsLoaded = $true
}

function Ensure-DSHNative {
  if ($script:nativeLoaded) { return }
  $hash = Get-SourceHash $DSHNativeSource
  $dll = Join-Path $scriptDir ("dsh-native-" + $hash + ".dll")
  if (Test-Path $dll) {
    try { Add-Type -Path $dll; $script:nativeLoaded = $true; return } catch { }
  }
  try {
    Add-Type -TypeDefinition $DSHNativeSource -OutputAssembly $dll -OutputType Library
  } catch {
    # 编译/写盘失败 (如并发竞争或只读目录): 退回到内存编译
    try { Add-Type -TypeDefinition $DSHNativeSource } catch { }
  }
  $script:nativeLoaded = $true
}

function Ensure-DSHShell {
  if ($script:shellLoaded) { return }
  $hash = Get-SourceHash $DSHShellSource
  $dll = Join-Path $scriptDir ("dsh-shell-" + $hash + ".dll")
  if (Test-Path $dll) {
    try { Add-Type -Path $dll; $script:shellLoaded = $true; return } catch { }
  }
  try {
    Add-Type -TypeDefinition $DSHShellSource -OutputAssembly $dll -OutputType Library
  } catch {
    try { Add-Type -TypeDefinition $DSHShellSource } catch { }
  }
  $script:shellLoaded = $true
}

# ---------- 有界 WMI 查询 ----------
# WMI 服务在开机初期可能尚未就绪, 直接 Get-CimInstance 会阻塞数分钟;
# 用进程内 runspace 异步执行并以硬超时兜底, 最坏情况也只等待 $timeoutSec 秒。
# v7.6 性能修复: 原先用 Start-Job, 每次都要冷启动一个完整的 powershell.exe 子进程
# (1~3 秒) —— 在"退出后重开 / 托盘重开"这些 WMI 早已就绪的场景里是纯浪费, 叠加起来
# 就是那 5~10 秒的延迟。runspace 在同一进程内异步执行 (亚秒级), BeginInvoke + WaitOne
# 仍保留硬超时, 开机初期 WMI 未就绪时也不会拖住当前进程。
function Invoke-CimBounded([scriptblock]$script, [object[]]$argList = @(), [int]$timeoutSec = 8) {
  try {
    $ps = [powershell]::Create()
    try {
      [void]$ps.AddScript($script.ToString())
      foreach ($a in $argList) { [void]$ps.AddArgument($a) }
      $handle = $ps.BeginInvoke()
      if (-not $handle.AsyncWaitHandle.WaitOne($timeoutSec * 1000)) {
        $ps.Stop()
        return $null
      }
      $result = $ps.EndInvoke($handle)
      if ($result -is [System.Management.Automation.ErrorRecord]) { return $null }
      # EndInvoke 返回 PSDataCollection, 需归一化为与 Receive-Job 一致的语义:
      # 空 → $null, 单对象 → 该对象, 多对象 → 数组。
      $output = @($result)
      if ($output.Count -eq 0) { return $null }
      if ($output.Count -eq 1) { return $output[0] }
      return ,$output
    } finally {
      $ps.Dispose()
    }
  } catch { return $null }
}

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
    # 本地探测不走系统代理 (如 Clash 的 127.0.0.1:7897), 避免被代理转发/超时
    $req.Proxy = $null
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
# 注意: 查询走有界 WMI (Invoke-CimBounded), 开机初期 WMI 未就绪时最多等待数秒。
# -Cutoff: 年龄护栏 (v7.3) —— 传入时间点后, 只返回该时间点之前已存在的进程;
# 退出流程用它保证绝不误杀"退出期间并发重开"启动的新实例。
# 参数无类型: 不传/传 $null 时不做年龄过滤 (注意 [datetime]$Cutoff 会拒绝显式
# 传入的 $null 并抛参数转换异常, v7.4 修复 —— 那会让 Get-HarnessRoot 静默失效,
# 直接表现为"显示终端"按钮无反应)。
function Get-HarnessNode {
  param($Cutoff)
  # 快速预检查 (纯 Win32 Get-Process, 亚秒级): 没有任何 node 进程时直接返回,
  # 免去一次 WMI 查询 —— "退出后重开"时端口刚释放、进程已死, 这是最常见路径。
  if ($null -eq (Get-Process node -ErrorAction SilentlyContinue)) { return $null }
  $entry = Find-DshEntry
  $patterns = @()
  if ($entry) { $patterns += ('*' + $entry + '*') }
  $patterns += '*@deepseek-ai/dsh*', '*@deepseek-ai\dsh*'
  Invoke-CimBounded {
    param($patterns, $cutoff)
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
      Where-Object {
        $cmd = $_.CommandLine
        if (-not ($cmd -like '*web*')) { return $false }
        if ($null -ne $cutoff -and $_.CreationDate -ge $cutoff) { return $false }
        foreach ($p in $patterns) { if ($cmd -like $p) { return $true } }
        return $false
      } |
      Select-Object -First 1
  } @($patterns, $Cutoff) 8
}

# Harness 根进程 (用于显示/隐藏终端窗口和整树结束):
# 优先新的 node 直连启动进程, 兼容旧版 cmd /k npx 启动方式
function Get-HarnessRoot {
  param($Cutoff)
  $node = Get-HarnessNode -Cutoff $Cutoff
  if ($null -ne $node) { return $node }
  # 快速预检查: 没有 cmd.exe 进程时直接返回, 免去旧版 cmd /k npx 扫描的 WMI 查询
  if ($null -eq (Get-Process cmd -ErrorAction SilentlyContinue)) { return $null }
  Invoke-CimBounded {
    param($legacyCmdPatterns, $cutoff)
    Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue |
      Where-Object {
        $cmd = $_.CommandLine
        if ($null -ne $cutoff -and $_.CreationDate -ge $cutoff) { return $false }
        foreach ($p in $legacyCmdPatterns) { if ($cmd -like $p) { return $true } }
        return $false
      } |
      Select-Object -First 1
  } @($legacyCmdPatterns, $Cutoff) 8
}

# 确保服务运行 (单实例: 启动器互斥锁 + 端口检查, 杜绝端口占用), 最多等待 70 秒。
# 端口已监听即视为有实例在运行 (快路径, 免 WMI 进程扫描 —— 开机初期 WMI 可能未就绪)。
# 竞态防护: "退出后立刻重开"时, 上一个实例可能正处于被终止的残留状态 ——
# 发现进程但端口未监听时, 观察该进程: 端口起来 → 继续等待就绪; 进程退出
# (残留已死) → 立即重新拉起; 观察 20 秒端口仍无且进程还活着 (卡死) → 强杀重启。
function Ensure-Harness {
  if (Test-HarnessHttp) { return $true }
  $launcher = New-Object System.Threading.Mutex($false, $launchMutexName)
  $owned = $false
  # 上一个启动器进程可能被终止而留下 abandoned 互斥锁: 此时应视为我们获得了锁
  try { $owned = $launcher.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true } catch { $owned = $false }
  if ($owned) {
    try {
      if (-not (Test-HarnessTcp)) {
        $running = Get-HarnessNode
        if ($null -eq $running) {
          [void](Start-Harness)
        } else {
          # 存在进程但端口未监听: 观察 (Get-Process 纯 Win32, 不依赖 WMI)
          $observePid = [int]$running.ProcessId
          $observeT0 = [Environment]::TickCount
          $spawned = $false
          while ([Environment]::TickCount - $observeT0 -lt 20000) {
            if (Test-HarnessTcp) { break }
            if ($null -eq (Get-Process -Id $observePid -ErrorAction SilentlyContinue)) {
              # 被观察的进程已退出: 是"退出后立刻重开"留下的垂死残留, 重新拉起
              Start-Sleep -Milliseconds 300
              [void](Start-Harness)
              $spawned = $true
              break
            }
            Start-Sleep -Milliseconds 300
          }
          if (-not $spawned -and -not (Test-HarnessTcp)) {
            # 20 秒端口仍无: 进程卡死或占着端口无法服务 —— 强杀后重新拉起
            if ($null -ne (Get-Process -Id $observePid -ErrorAction SilentlyContinue)) {
              & taskkill.exe /PID $observePid /T /F 2>$null | Out-Null
              Start-Sleep -Milliseconds 500
            }
            [void](Start-Harness)
          }
        }
      }
    } finally {
      try { $launcher.ReleaseMutex() } catch { }
      try { $launcher.Dispose() } catch { }
    }
  } else {
    try { $launcher.Dispose() } catch { }
  }
  # 等待就绪, 期间自我修复 (v7.3):
  #   - 无进程且端口未监听 (之前拉起的实例被并发退出误杀/自身崩溃) → 重新拉起;
  #   - 端口在监听但 HTTP 长时间不就绪 (垂死/卡死的僵尸实例, 如退出中的旧实例
  #     残留) → 观察其启动时间, 够老 (>20 秒, 排除刚拉起的正常冷启动) 则强杀
  #     后重新拉起 (只做一次);
  #   保证"退出后立刻重开"即使撞上异常时序, 服务也必然可用, 不再干等 60 秒失败。
  $recycleT0 = [Environment]::TickCount
  $recycledPid = 0
  for ($i = 0; $i -lt 140; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-HarnessHttp) { return $true }
    if ([Environment]::TickCount - $recycleT0 -lt 15000) { continue }
    $recycleT0 = [Environment]::TickCount
    $tcpUp = Test-HarnessTcp
    $running = Get-HarnessNode
    if (-not $tcpUp -and $null -eq $running) {
      # 没有进程也没有端口: 重新拉起 (启动互斥锁防并发双启)
      $relauncher = New-Object System.Threading.Mutex($false, $launchMutexName)
      $ownedRel = $false
      try { $ownedRel = $relauncher.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ownedRel = $true } catch { $ownedRel = $false }
      if ($ownedRel) {
        try {
          if (-not (Test-HarnessTcp) -and $null -eq (Get-HarnessNode)) { [void](Start-Harness) }
        } finally {
          try { $relauncher.ReleaseMutex() } catch { }
          try { $relauncher.Dispose() } catch { }
        }
      }
    } elseif ($tcpUp -and $null -ne $running -and [int]$running.ProcessId -ne $recycledPid) {
      # 端口在监听但 HTTP 一直不就绪: 僵尸实例 → 进程够老才强杀重拉
      $proc = Get-Process -Id ([int]$running.ProcessId) -ErrorAction SilentlyContinue
      if ($null -ne $proc) {
        $ageSec = 999
        try { $ageSec = ((Get-Date) - $proc.StartTime).TotalSeconds } catch { }
        if ($ageSec -ge 20) {
          & taskkill.exe /PID ([int]$running.ProcessId) /T /F 2>$null | Out-Null
          $recycledPid = [int]$running.ProcessId
          Start-Sleep -Milliseconds 800
          $relauncher = New-Object System.Threading.Mutex($false, $launchMutexName)
          $ownedRel = $false
          try { $ownedRel = $relauncher.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ownedRel = $true } catch { $ownedRel = $false }
          if ($ownedRel) {
            try {
              if (-not (Test-HarnessTcp)) { [void](Start-Harness) }
            } finally {
              try { $relauncher.ReleaseMutex() } catch { }
              try { $relauncher.Dispose() } catch { }
            }
          }
        }
      }
    }
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
#   2) CIM (正常环境可用): 命令行匹配 --app=<origin> (兼容引号包裹的 URL),
#      有界超时 + 预检查 (无白名单浏览器进程在运行则窗口必然不存在, 免 WMI)。
# 豆包 Doubao 等第三方浏览器不在白名单内, 其窗口/进程不会被当作桌面窗口。
function Get-AppWindowProcess {
  param([switch]$SkipCim)
  # 记录文件是否存在: 存在 (含 pid=0 或残留 PID) 即为"已知状态", 无需 CIM 兜底。
  # 只有文件缺失 (如首次安装、-AutoStart 开机清除后) 才需要 CIM 命令行匹配。
  $recordExists = Test-Path $appWindowFile
  $rec = Read-AppWindowRecord
  if ($null -ne $rec) {
    $proc = Get-Process -Id ([int]$rec.pid) -ErrorAction SilentlyContinue
    if ($null -ne $proc -and (Test-BrowserProcessName $proc.ProcessName)) {
      Ensure-DSHNative
      if ((Find-HwndOfPid ([uint32][int]$rec.pid)) -ne [IntPtr]::Zero) {
        return @{ ProcessId = [int]$rec.pid; Via = 'record' }
      }
    }
  }
  # 记录存在但窗口不在运行 (pid=0 / 进程已死 / 非白名单): 直接返回, 不付 WMI 成本
  if ($recordExists) { return $null }
  # 记录文件缺失时才走 CIM 回退: 先快速确认有白名单浏览器进程在运行, 否则直接返回
  # -SkipCim: 开机自启动路径使用 (记录刚被清除且窗口必然不存在), 跳过 CIM 回退
  if ($SkipCim) { return $null }
  $anyBrowser = $false
  foreach ($n in $supportedBrowserNames) {
    if ($null -ne (Get-Process $n -ErrorAction SilentlyContinue)) { $anyBrowser = $true; break }
  }
  if (-not $anyBrowser) { return $null }
  $cim = Invoke-CimBounded {
    param($origin)
    Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe' OR Name='brave.exe' OR Name='opera.exe' OR Name='vivaldi.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match ('--app=["'']?' + [regex]::Escape($origin)) } |
      Select-Object -First 1
  } @($origin) 8
  if ($null -ne $cim) { return @{ ProcessId = [int]$cim.ProcessId; Via = 'cim' } }
  return $null
}

# 关闭独立桌面窗口 (切换回网页端时使用):
# 记录 PID 通道 (纯 Win32, 首选) + 有界 CIM 命令行匹配通道 (正常环境), 并清除记录
function Close-AppWindow {
  $rec = Read-AppWindowRecord
  $recordHandled = $false
  if ($null -ne $rec) {
    $recordHandled = $true
    # 只结束白名单浏览器进程 (防残留的豆包等第三方记录被误杀)
    $proc = Get-Process -Id ([int]$rec.pid) -ErrorAction SilentlyContinue
    if ($null -ne $proc -and (Test-BrowserProcessName $proc.ProcessName)) {
      & taskkill.exe /PID ([int]$rec.pid) /T /F 2>$null | Out-Null
    }
  }
  if (-not $recordHandled) {
    $anyBrowser = $false
    foreach ($n in $supportedBrowserNames) {
      if ($null -ne (Get-Process $n -ErrorAction SilentlyContinue)) { $anyBrowser = $true; break }
    }
  }
  if (-not $recordHandled -and $anyBrowser) {
    [void](Invoke-CimBounded {
      param($origin)
      Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe' OR Name='brave.exe' OR Name='opera.exe' OR Name='vivaldi.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match ('--app=["'']?' + [regex]::Escape($origin)) } |
        ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F 2>$null | Out-Null }
    } @($origin) 8)
  }
  # 写回 pid=0 的"已关闭"记录, 而不是删除文件: 这样宿主插件的快速检测路径 (Node 读
  # app-window.json) 能直接判断"窗口未运行", 无需每 5 秒冷启动一个 PowerShell
  # -AppWindowActive 进程去走 CIM 回退 —— 这是设置页开着时明显卡顿的主要来源之一。
  try {
    @{ pid = 0; origin = $origin; at = (Get-Date).ToString('o') } |
      ConvertTo-Json -Compress | Set-Content -Path $appWindowFile -Encoding Ascii
  } catch { Remove-Item $appWindowFile -Force -ErrorAction SilentlyContinue }
}

# ---------- 桌面窗口布局 (DPI 感知) ----------

# 让本进程成为 DPI 感知进程, 使屏幕度量返回物理像素 (高 DPI 缩放 125%/150% 下依然准确)
function Set-ProcessDpiAware {
  Ensure-DSHNative
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
  Ensure-DSHNative
  try {
    $dpi = [DSHNative]::GetDpiForSystem()
    if ($dpi -gt 0) { return $dpi / 96.0 }
  } catch { }
  Ensure-WinForms
  try {
    $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    try { $dpiX = $g.DpiX } finally { $g.Dispose() }
    if ($dpiX -gt 0) { return $dpiX / 96.0 }
  } catch { }
  return 1.0
}

# 主屏可用工作区 (排除任务栏), 物理像素
function Get-PrimaryWorkArea {
  Ensure-WinForms
  try {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    if ($wa.Width -gt 0 -and $wa.Height -gt 0) {
      return @{ Left = $wa.Left; Top = $wa.Top; Width = $wa.Width; Height = $wa.Height }
    }
  } catch { }
  # 兜底: 系统度量 (SM_CXWORKAREA=48 / SM_CYWORKAREA=49, 主屏左上角视为 0,0)
  Ensure-DSHNative
  $w = [DSHNative]::GetSystemMetrics(48)
  $h = [DSHNative]::GetSystemMetrics(49)
  if ($w -le 0) { $w = 1280 }; if ($h -le 0) { $h = 720 }
  return @{ Left = 0; Top = 0; Width = $w; Height = $h }
}

# 主屏完整边界 (含任务栏区域), 物理像素
function Get-PrimaryScreen {
  Ensure-WinForms
  try {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    if ($b.Width -gt 0 -and $b.Height -gt 0) {
      return @{ Left = $b.Left; Top = $b.Top; Width = $b.Width; Height = $b.Height }
    }
  } catch { }
  # 兜底: 系统度量 (SM_CXSCREEN=0 / SM_CYSCREEN=1)
  Ensure-DSHNative
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
  Ensure-DSHNative
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
  Ensure-DSHNative
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
  Ensure-DSHNative
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
  Ensure-DSHNative
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
  Ensure-DSHNative
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
  Ensure-DSHNative
  $watchMutex = New-Object System.Threading.Mutex($false, 'DSHDesktopWindowWatcher')
  $isFirst = $false
  try { $isFirst = $watchMutex.WaitOne(0) } catch { $isFirst = $true }
  if (-not $isFirst) { return }
  try {
    # v7.6: 先抓"启动前窗口快照"并立即写 ready 信号, 再算布局 —— 快照只需亚秒级,
    # 而 Get-AppWindowLayout 要 Add-Type WinForms (~1 秒); 调换顺序后 -Open 不必
    # 为布局计算多等一次, 布局在浏览器启动的间隙里并行完成。
    $script:appWindowPreexisting = Get-ChromeHwnds
    # 快照完成: 通知 -Open 可以启动浏览器了 (保证"启动前窗口"快照先于新窗口创建,
    # 这样 Find-AppWindowHandle 一定能把新窗口识别为"新窗口"并立即隐藏)
    try { Set-Content -Path $watcherReadyFile -Value '1' -Encoding Ascii } catch { }
    $layout = Get-AppWindowLayout
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
      Start-Sleep -Milliseconds 500
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
# -Boot (登录自启动): 不等服务就绪, 直接打开内置启动页 (boot.html 轮询就绪后
# 自动跳转), 窗口在登录后数秒内可见; 不传 --start-minimized (看守进程超时退出时
# 窗口依然可见)。
function Open-HarnessWindow {
  param([switch]$Boot)
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
      if ($null -ne (Get-AppWindowProcess -SkipCim:$Boot)) { break }
    }
    try { $ownedOpen = $openMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ownedOpen = $true } catch { $ownedOpen = $false }
    if (-not $ownedOpen) {
      try { $openMutex.Dispose() } catch { }
      return 'app-existing'
    }
  }
  try {
    if ($null -ne (Get-AppWindowProcess -SkipCim:$Boot)) { return 'app-existing' }
    if (-not $Boot) {
      # 从网页端切换到桌面端: 先通知所有已打开的 Harness 页面自行关闭 (浏览器标签页/窗口)
      [void](Send-QuitSignal)
    }
    $browser = Find-AppBrowser
    if ($browser) {
      $layout = Get-AppWindowLayout
      $script:lastWindowInfo = ('{0}x{1} @ ({2},{3}) DIP, scale {4}' -f $layout.sizeDip.Width, $layout.sizeDip.Height, $layout.posDip.X, $layout.posDip.Y, $layout.scale)
      $profileDir = Join-Path $scriptDir 'edge-profile'
      # 启动目标: 登录自启动时用内置启动页 (轮询就绪后跳转到 $origin), 让窗口
      # 在 Harness 冷启动期间 (数十秒) 立即可见; 其它路径直接用服务地址。
      $target = $origin
      $bootPage = Join-Path $scriptDir 'boot.html'
      if ($Boot -and (Test-Path $bootPage)) {
        $target = 'file:///' + (($bootPage -replace '\\', '/') + '?port=' + $port)
      }
      $appArgs = '--app=' + $target +
                 ' --window-size=' + $layout.sizeDip.Width + ',' + $layout.sizeDip.Height +
                 ' --window-position=' + $layout.posDip.X + ',' + $layout.posDip.Y +
                 ' --user-data-dir="' + $profileDir + '"' +
                 ' --app-user-model-id=DSHDesktopApp' +
                 ' --no-first-run --no-default-browser-check'
      if (-not $Boot) { $appArgs += ' --start-minimized' }
      # 先启动看守进程 (等窗口出现后隐藏→渲染就绪→恢复显示→守护最小尺寸),
      # 并等待它完成"启动前窗口快照"(watcher.ready) 再打开浏览器:
      # 保证看守进程能识别到新窗口并立即隐藏, 渲染就绪前用户看不到透明窗口
      Start-Process 'powershell.exe' -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $scriptDir + '\dsh-tray.ps1"'),'-WatchAppWindow'
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
  Ensure-DSHShell
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

# 返回 $true = 成功, 或 Harness 未运行 (偏好写入后下次启动生效, 静默成功);
# 返回 $false = Harness 在运行但窗口操作失败 —— 调用方应报错, 不再静默吞掉
# (v7.4: 之前失败被 $ErrorActionPreference='SilentlyContinue' 吞掉,
# 设置页点击"显示终端"无任何反应)。
function Set-TerminalWindow([int]$showCode) {
  Ensure-DSHNative
  $root = Get-HarnessRoot
  if ($null -eq $root) { return $true }
  try {
    $hwnd = [DSHNative]::ConsoleWindowOf([uint32]$root.ProcessId)
    if ($hwnd -eq [IntPtr]::Zero) { return $false }
    [void][DSHNative]::ShowWindowAsync($hwnd, $showCode)
    return $true
  } catch { return $false }
}

# ---------- 结束 Harness ----------

function Stop-Harness {
  $found = $false
  # 年龄护栏 (v7.3): 只结束"退出开始前"就存在的进程。退出期间并发重开
  # (-Open) 启动的新实例绝不能被快照误杀 —— WMI 扫描可能把刚启动的新实例
  # 扫进来 (退出者卡死放行后的并发窗口内尤其危险)。
  $cutoff = (Get-Date).AddSeconds(-6)
  # 先快照所有目标 (根进程 + 全部匹配的 node), 再统一结束 —— 避免"先杀根、
  # 再扫描"之间新实例混入被杀 (退出后立刻重开的竞态)
  $targets = New-Object System.Collections.Generic.List[int]
  $root = Get-HarnessRoot -Cutoff $cutoff
  if ($null -ne $root) {
    $targets.Add([int]$root.ProcessId)
    $found = $true
  }
  $scanNodes = $null -eq $root -or ([string]$root.Name).ToLowerInvariant() -ne 'node.exe'
  if (-not $scanNodes) {
    $scanNodes = @((Get-Process node -ErrorAction SilentlyContinue)).Count -gt 1
  }
  if ($scanNodes) {
    $nodes = Invoke-CimBounded {
      param($cutoff)
      Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
          $_.Name -eq 'node.exe' -and
          ($_.CommandLine -like '*@deepseek-ai/dsh*' -or $_.CommandLine -like '*@deepseek-ai\dsh*') -and
          $_.CommandLine -like '*web*' -and
          $_.CreationDate -lt $cutoff
        }
    } @($cutoff) 8
    foreach ($n in $nodes) {
      $targets.Add([int]$n.ProcessId)
      $found = $true
    }
  }
  foreach ($targetPid in ($targets | Select-Object -Unique)) {
    & taskkill.exe /PID $targetPid /T /F 2>$null | Out-Null
  }
  if (-not $found) { return $false }
  # 有界等待端口真正释放 (最多 8 秒): 让"退出后立刻重开"时新实例不会撞上
  # 正在关闭的旧实例 (端口占用 / 进程残留)
  $teardownT0 = [Environment]::TickCount
  while ([Environment]::TickCount - $teardownT0 -lt 8000) {
    if (-not (Test-HarnessTcp)) { break }
    Start-Sleep -Milliseconds 200
  }
  return $found
}

# ---------- 其它 ----------

# 通知所有打开的 Harness 浏览器页面自动关闭: 向宿主同源路由 POST quit,
# 宿主通过 SSE 向每个已连接页面广播 quit 事件, 页面收到后自行关闭标签页。
# v7.3: 不再固定等待 1.5 秒 —— 后续 Stop-Harness 的 WMI 扫描本身就有数秒
# 窗口供页面关闭; 去掉等待能显著缩短退出耗时, 缩小"退出后立刻重开"的竞态窗口。
function Send-QuitSignal {
  $ok = $false
  try {
    Invoke-WebRequest -Uri ($origin + '/_dsh/dsh-desktop') -Method Post -UseBasicParsing -TimeoutSec 3 -Headers @{
      'Origin' = $origin
      'sec-fetch-site' = 'same-origin'
      'Content-Type' = 'application/json'
    } -Body '{"action":"quit"}' | Out-Null
    $ok = $true
  } catch { }
  return $ok
}

# 托盘"退出"与 -Quit 共用逻辑:
#   1) 通知所有 Harness 页面 (浏览器标签页) 自动关闭 (快速, 服务还活着);
#   2) 结束 Harness 终端与服务 —— 紧随其后 (v7.3): 端口尽快释放, "退出后立刻
#      重开"的 -Open 能更快拿到干净端口, 竞态窗口缩到最小; 页面在 Stop-Harness
#      的 WMI 扫描期间 (数秒) 自然关闭;
#   3) 关闭独立桌面窗口 —— 应用模式窗口不允许脚本自行关闭, 必须显式结束其进程
#      (看守进程会随窗口消失而自行退出)。
# 退出期间写 quitting.tmp 标记 (内容为退出者 PID): 用户"退出后立刻点快捷方式
# 重开"时, -Open/-OpenWeb 会先等待退出真正完成 (标记消失且退出者进程已结束)
# 再启动, 避免撞上正在关闭的旧实例。
$quittingMarkFile = Join-Path $scriptDir 'quitting.tmp'

function Invoke-Quit {
  try { Set-Content -Path $quittingMarkFile -Value ([string]$PID) -Encoding Ascii } catch { }
  try {
    [void](Send-QuitSignal)
    [void](Stop-Harness)
    Close-AppWindow
  } finally {
    Remove-Item $quittingMarkFile -Force -ErrorAction SilentlyContinue
  }
}

function Enter-OpenRequest {
  $script:openRequestMutex = New-Object System.Threading.Mutex($false, $openRequestMutexName)
  $owned = $false
  try { $owned = $script:openRequestMutex.WaitOne(0) }
  catch [System.Threading.AbandonedMutexException] { $owned = $true }
  catch { $owned = $false }
  if (-not $owned) {
    try { $script:openRequestMutex.Dispose() } catch { }
    $script:openRequestMutex = $null
    return $false
  }
  return $true
}

function Exit-OpenRequest {
  if ($null -eq $script:openRequestMutex) { return }
  try { $script:openRequestMutex.ReleaseMutex() } catch { }
  try { $script:openRequestMutex.Dispose() } catch { }
  $script:openRequestMutex = $null
}

# 等待正在进行的退出完成 (v7.3): 标记消失, 且退出者进程已结束。
# 退出者还活着就绝不强行清除标记 —— v7.2 的 20 秒超时强清会让 -Open 与仍在
# 执行 Stop-Harness 的退出者并发, 新实例可能被快照误杀 (本 bug 的主要根因)。
# 退出者进程死亡但标记残留 (异常退出) 时立即清除继续; 退出者卡死时最多等
# 45 秒后继续 —— 此时 Stop-Harness 的年龄护栏保证新实例不会被误杀, 且
# Ensure-Harness 的自愈循环会兜底。
function Wait-QuitFinished {
  $deadline = [Environment]::TickCount + 45000
  while ([Environment]::TickCount -lt $deadline) {
    if (-not (Test-Path $quittingMarkFile)) { break }
    $qPid = 0
    try {
      $raw = Get-Content -Path $quittingMarkFile -Raw
      if ($raw) { $qPid = [int]$raw.Trim() }
    } catch { $qPid = -1 }  # 读取失败 (文件正被写入): 一律视为退出进行中
    if ($qPid -gt 0 -and $null -eq (Get-Process -Id $qPid -ErrorAction SilentlyContinue)) {
      # 退出者已死 (崩溃/被杀), 标记残留: 清除并继续
      break
    }
    Start-Sleep -Milliseconds 200
  }
  Remove-Item $quittingMarkFile -Force -ErrorAction SilentlyContinue
}

# 托盘是否在运行 (pid 文件 + 进程存活, 纯 Win32)
function Test-TrayRunning {
  try {
    if (-not (Test-Path $pidFile)) { return $false }
    $tp = [int](Get-Content -Path $pidFile -Raw)
    return ($tp -gt 0 -and $null -ne (Get-Process -Id $tp -ErrorAction SilentlyContinue))
  } catch { return $false }
}

# 托盘缺失时补充拉起 (如"退出托盘后仅用快捷方式打开"的场景)。
# v7.3: 必须先等旧托盘进程完全退出再启动 —— 新托盘与仍持 DSHDesktopTray
# 互斥锁的垂死旧托盘竞争会瞬间退出 (退出后立刻重开时"托盘不出现"的根因之一);
# 启动后轮询验证 pidFile 出现且进程存活, 失败重试最多 3 次。
function Ensure-TrayRunning {
  if (Test-TrayRunning) { return }
  # 1) pidFile 还指向活着的旧托盘 (正在退出): 等它完全结束 (最多 15 秒)
  $oldTrayPid = 0
  try { $oldTrayPid = [int](Get-Content -Path $pidFile -Raw) } catch { }
  if ($oldTrayPid -gt 0) {
    $waitT0 = [Environment]::TickCount
    while (([Environment]::TickCount - $waitT0 -lt 15000) -and ($null -ne (Get-Process -Id $oldTrayPid -ErrorAction SilentlyContinue))) {
      Start-Sleep -Milliseconds 200
    }
  }
  # 2) 启动并验证 (最多 3 次; 每次等 pidFile + 进程存活, 8 秒)
  for ($attempt = 0; $attempt -lt 3; $attempt++) {
    if (Test-TrayRunning) { return }
    try {
      Start-Process 'powershell.exe' -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $scriptDir + '\dsh-tray.ps1"')
    } catch { }
    $startT0 = [Environment]::TickCount
    while (([Environment]::TickCount - $startT0 -lt 8000)) {
      if (Test-TrayRunning) { return }
      Start-Sleep -Milliseconds 200
    }
    # 8 秒未就绪: 清理可能残留的 pidFile (可能是旧托盘退出时留下的), 重试
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
  }
}

function Install-Shortcut {
  Ensure-DSHShell
  $desktop = [Environment]::GetFolderPath('Desktop')
  $lnkPath = Join-Path $desktop $shortcutName
  # 生成隐藏打开启动器 (wscript + sh.Run(..., 0, False)): 快捷方式经它拉起 -Open,
  # 控制台从头到尾不出现。目标改成 wscript.exe, 参数指向该 VBS。
  [void](Write-HiddenRunner $openVbsFile ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $scriptDir + '\dsh-tray.ps1" -Open'))
  $shell = New-Object -ComObject WScript.Shell
  $sc = $shell.CreateShortcut($lnkPath)
  $sc.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
  $sc.Arguments = '"' + $openVbsFile + '"'
  $sc.WorkingDirectory = $scriptDir
  $sc.IconLocation = $icoPath + ',0'
  $sc.Description = 'DeepSeek Harness 桌面端'
  $sc.Save()
  # 任务栏 AppUserModelID: 让 --app-user-model-id=DSHDesktopApp 的桌面窗口
  # 在任务栏/Alt-Tab 使用本快捷方式的黑鲸图标与名称 (而不是 Edge/Chrome 的 logo)
  try { [void][DSHShell]::SetAppUserModelId($lnkPath, 'DSHDesktopApp', $icoPath) } catch { }
  return $lnkPath
}

# 开机自启动: 优先任务计划程序 (登录触发器)。Run 键由 Explorer 在登录后逐个
# 执行, 启动项多的机器上可能排队数分钟 (实测本机 Run 键在登录 1~2 分钟后才
# 触发); 计划任务由计划任务服务在登录时立即触发, 不依赖 Explorer 的启动队列。
# 注意: schtasks /TR 不支持反斜杠转义引号 (\" 会被字面解析, 导致
# "系统找不到指定的路径" 而注册失败), 因此绝不通过 /TR 拼接带引号的命令行;
# 而是优先用 Schedule.Service COM 注册 (无命令行引号解析, 也不依赖
# schtasks.exe), 回退 schtasks /Create /XML (XML 中的引号无需转义, 绕开
# /TR 缺陷), 全部失败时才回退 Run 键 (下次登录时 -AutoStart 会自动重试迁移)。
$taskName = 'DSHDesktop'

# 记录当前生效的自启动方式 (诊断: 'task' = 计划任务, 'runkey' = Run 键, 'off' = 关闭)
$autoStartMethodFile = Join-Path $scriptDir 'autostart-method.json'

function Write-AutoStartMethod([string]$method, [string]$detail = '') {
  try {
    $obj = @{ method = $method; at = (Get-Date).ToString('o') }
    if ($detail) { $obj.detail = $detail }
    $obj | ConvertTo-Json -Compress | Set-Content -Path $autoStartMethodFile -Encoding Ascii
  } catch { }
}

# 查询 DSHDesktop 计划任务是否存在 (COM 优先, schtasks 兜底)。
# 返回 $true 表示任务存在且含登录触发器 (TASK_TRIGGER_LOGON = 9)。
function Test-DSHDesktopTask {
  try {
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $t = $svc.GetFolder('\').GetTask($taskName)
    if ($null -eq $t) { return $false }
    $triggers = $t.Definition.Triggers
    return ($triggers.Count -ge 1 -and $triggers.Item(1).Type -eq 9)
  } catch { }
  try {
    & schtasks.exe /Query /TN $taskName 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch { }
  return $false
}

# 登录启动器 (wscript + VBS): 任务计划程序的第一个动作运行 wscript.exe 执行
# dsh-autostart.vbs —— wscript 冷启动约 1 秒 (无 .NET CLR 初始化), 登录瞬间
# 立即以隐藏方式直接拉起 Harness 服务; 第二个动作启动 PowerShell 伴侣
# (桌面窗口/托盘, 通过"启动器标记 + node 进程"判断服务已在启动, 不重复拉起)。
# 实测开机争抢下 PowerShell 5.1 冷启动可达 20~30 秒, 让服务等它是最浪费的。
# 启动器内嵌当前 harness.json 的 node/入口/DSH_HOME/cwd, 每次 Set-AutoStart
# 都会重新生成 (入口随 dsh 更新而变化); 生成失败时任务只剩 PowerShell 动作。
$launchMarkFile = Join-Path $scriptDir 'harness-launch.tmp'
$vbsFile = Join-Path $scriptDir 'dsh-autostart.vbs'
# 隐藏启动器 VBS: 开机任务动作②用 companion (隐藏拉起 PowerShell -AutoStart);
# 桌面快捷方式用 open (隐藏拉起 PowerShell -Open)。两者都经 wscript.exe 执行,
# 杜绝终端闪现。
$companionVbsFile = Join-Path $scriptDir 'dsh-companion.vbs'
$openVbsFile = Join-Path $scriptDir 'dsh-open.vbs'

# VBS 字符串字面量: 内部的引号翻倍 (VBS 转义规则)
function ConvertTo-VbsLiteral([string]$value) {
  return [string]$value.Replace('"', '""')
}

# 生成一个"隐藏启动器" VBS: 通过 wscript.exe 执行, sh.Run(..., 0, False) 在 Win32 层
# 以 SW_HIDE 创建目标进程 —— 控制台窗口从头到尾都不会出现 (零闪现)。这是唯一能彻底
# 避免"终端闪现"的方式: 'powershell.exe -WindowStyle Hidden' 作为命令行参数要等 CLR
# 启动完成后才生效, 开机争抢下 CLR 冷启动可达数十秒, 期间控制台一直可见。
function Write-HiddenRunner([string]$vbsPath, [string]$commandLine) {
  try {
    $vbs = "Set sh = CreateObject(""WScript.Shell"")`r`n" +
           "sh.Run """ + (ConvertTo-VbsLiteral $commandLine) + """, 0, False`r`n"
    $vbs | Set-Content -Path $vbsPath -Encoding Unicode
    return (Test-Path $vbsPath)
  } catch { return $false }
}

function Write-AutoStartLauncher {
  try {
    $nodeExe = Get-NodeExe
    $entry = Find-DshEntry
    if ($null -eq $nodeExe -or $null -eq $entry -or -not (Test-Path $entry)) { return $false }
    $nodeCmd = '"' + $nodeExe + '" "' + $entry + '" web'
    if ($null -ne $webArgs -and $webArgs.Count -gt 0) { $nodeCmd += ' ' + (($webArgs | Where-Object { $_ }) -join ' ') }
    $workDir = $harnessCwd
    if (-not (Test-Path $workDir)) { $workDir = $HOME }
    $vbs = @"
' DeepSeek Harness login auto-start launcher (generated by dsh-tray.ps1 Set-AutoStart).
' Runs as the FIRST task action via wscript.exe: starts the harness service
' directly (no PowerShell cold start at peak logon load). The SECOND task
' action starts the PowerShell companion (desktop window + tray).
Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = "$(ConvertTo-VbsLiteral $workDir)"
sh.Environment("PROCESS")("DSH_HOME") = "$(ConvertTo-VbsLiteral $dshHome)"
Set fso = CreateObject("Scripting.FileSystemObject")
fso.CreateTextFile("$(ConvertTo-VbsLiteral $launchMarkFile)", True).Close
sh.Run "$(ConvertTo-VbsLiteral $nodeCmd)", 0, False
"@
    $vbs | Set-Content -Path $vbsFile -Encoding Unicode
    return (Test-Path $vbsFile)
  } catch { return $false }
}

# 任务动作列表 (按顺序执行): ① wscript 启动器 (服务不经 PowerShell 冷启动);
# ② wscript 隐藏启动器拉起 PowerShell -AutoStart (窗口/托盘, 检测到服务已在启动
# 则跳过拉起)。两个动作都经 wscript + sh.Run(..., 0, False) 隐藏启动, 全程无终端闪现。
# 若 dsh-companion.vbs 生成失败, 动作②回退纯 PowerShell -AutoStart (有闪现, 但保证
# 自启动仍可用); 若 dsh-autostart.vbs 生成失败, 只剩动作② (其 -AutoStart 会自行拉起服务)。
function Get-DSHDesktopTaskActions {
  if (Test-Path $companionVbsFile) {
    $companionAction = @{
      Path = Join-Path $env:SystemRoot 'System32\wscript.exe'
      Arguments = '"' + $companionVbsFile + '"'
    }
  } else {
    $companionAction = @{
      Path = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
      Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $scriptDir 'dsh-tray.ps1') + '" -AutoStart'
    }
  }
  if (Test-Path $vbsFile) {
    return @(
      @{
        Path = Join-Path $env:SystemRoot 'System32\wscript.exe'
        Arguments = '"' + $vbsFile + '"'
      },
      $companionAction
    )
  }
  return @($companionAction)
}

# 方式 1: Schedule.Service COM 注册登录触发任务 (首选: 无命令行引号解析,
# 不依赖 schtasks.exe)。TASK_CREATE_OR_UPDATE=6, TASK_LOGON_INTERACTIVE_TOKEN=3
# (当前交互用户, 无需密码)。
function Register-DSHDesktopTaskCom {
  try {
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $folder = $svc.GetFolder('\')
    $task = $svc.NewTask(0)
    $task.RegistrationInfo.Description = 'DeepSeek Harness 桌面端 (登录自启动)'
    $task.Settings.StartWhenAvailable = $true
    $task.Settings.DisallowStartIfOnBatteries = $false
    $task.Settings.StopIfGoingOnBatteries = $false
    $task.Settings.ExecutionTimeLimit = 'PT0S'
    $task.Settings.Enabled = $true
    $task.Settings.Hidden = $true
    # 优先级 5 (普通): 默认 7 (低于正常) 会让启动链在开机争抢中垫底
    $task.Settings.Priority = 5
    $trig = $task.Triggers.Create(9)   # TASK_TRIGGER_LOGON
    $trig.UserId = "$env:USERDOMAIN\$env:USERNAME"
    $trig.Enabled = $true
    foreach ($action in Get-DSHDesktopTaskActions) {
      $act = $task.Actions.Create(0)   # TASK_ACTION_EXEC
      $act.Path = $action.Path
      $act.Arguments = $action.Arguments
      $act.WorkingDirectory = $scriptDir
    }
    $folder.RegisterTaskDefinition($taskName, $task, 6, $null, $null, 3) | Out-Null
    return (Test-DSHDesktopTask)
  } catch { return $false }
}

# 方式 2: schtasks /Create /XML (XML 中的引号无需转义, 绕开 /TR 引号缺陷;
# schtasks 要求任务 XML 为 UTF-16 编码)
function Build-DSHDesktopTaskXml {
  $userId = "$env:USERDOMAIN\$env:USERNAME"
  $actions = Get-DSHDesktopTaskActions
  $esc = { param($v) ([string]$v).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
  $escUser = & $esc $userId
  $escDir  = & $esc $scriptDir
  $execXml = ''
  foreach ($action in $actions) {
    $escCmd  = & $esc $action.Path
    $escArgs = & $esc $action.Arguments
    $execXml += "    <Exec>`n      <Command>$escCmd</Command>`n      <Arguments>$escArgs</Arguments>`n      <WorkingDirectory>$escDir</WorkingDirectory>`n    </Exec>`n"
  }
  return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>DeepSeek Harness 桌面端 (登录自启动)</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$escUser</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>5</Priority>
  </Settings>
  <Actions Context="Author">
$execXml  </Actions>
</Task>
"@
}

function Register-DSHDesktopTaskXml {
  $tmp = Join-Path $scriptDir 'dsh-task.xml'
  try {
    (Build-DSHDesktopTaskXml) | Set-Content -Path $tmp -Encoding Unicode
    & schtasks.exe /Create /TN $taskName /XML $tmp /F 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    & schtasks.exe /Query /TN $taskName 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch { return $false } finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Set-AutoStart {
  # 生成两个 wscript 隐藏启动器:
  #   ① dsh-autostart.vbs —— 直启 node 服务 (绕开 PowerShell 冷启动);
  #   ② dsh-companion.vbs —— 隐藏拉起 PowerShell -AutoStart (窗口/托盘);
  # 两者都经 sh.Run(..., 0, False) 以 SW_HIDE 启动, 开机全程无终端闪现。
  [void](Write-AutoStartLauncher)
  [void](Write-HiddenRunner $companionVbsFile ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $scriptDir + '\dsh-tray.ps1" -AutoStart'))
  # Run 键兜底值同样走 wscript + 隐藏启动器 (仅任务注册失败时使用, 也绝不闪现终端)
  $value = '"' + (Join-Path $env:SystemRoot 'System32\wscript.exe') + '" "' + $companionVbsFile + '"'
  # 1) 首选 COM 注册 (无引号解析问题, 不依赖 schtasks.exe)
  if (Register-DSHDesktopTaskCom) {
    # 成功: 移除 Run 键避免登录时双启动 (计划任务 + Run 键各拉起一次)
    Remove-ItemProperty -Path $runKey -Name $runValue -ErrorAction SilentlyContinue
    Write-AutoStartMethod 'task'
    return
  }
  # 2) 回退 schtasks /Create /XML (绕开 /TR 引号缺陷)
  if (Register-DSHDesktopTaskXml) {
    Remove-ItemProperty -Path $runKey -Name $runValue -ErrorAction SilentlyContinue
    Write-AutoStartMethod 'task'
    return
  }
  # 3) 最后回退 Run 键 (行为与旧版一致; 下次登录时 -AutoStart 会再自动重试迁移)
  New-Item -Path $runKey -Force | Out-Null
  Set-ItemProperty -Path $runKey -Name $runValue -Value $value -Type String
  Write-AutoStartMethod 'runkey' 'task registration failed (COM and schtasks XML both failed)'
}

function Clear-AutoStart {
  Remove-ItemProperty -Path $runKey -Name $runValue -ErrorAction SilentlyContinue
  try {
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    try { $svc.GetFolder('\').DeleteTask($taskName, 0) } catch { }
  } catch { }
  try { & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null } catch { }
  Remove-Item $vbsFile, $companionVbsFile, $launchMarkFile -Force -ErrorAction SilentlyContinue
  Remove-Item $autoStartMethodFile -Force -ErrorAction SilentlyContinue
}

function Write-OpenState([bool]$ok, [long]$readyMs, [string]$browser, [string]$error, [string]$window) {
  $obj = @{ at = (Get-Date).ToString('o'); ok = $ok; readyMs = $readyMs; browser = $browser; error = $error; window = $window }
  try { $obj | ConvertTo-Json -Compress | Set-Content -Path $openStateFile -Encoding Ascii } catch { }
}

function Invoke-Restart {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  Invoke-Quit
  $ok = Ensure-Harness
  $sw.Stop()
  if ($ok) {
    $script:lastWindowInfo = $null
    $browser = Open-HarnessWindow
    Write-OpenState $true $sw.ElapsedMilliseconds $browser $null $script:lastWindowInfo
  } else {
    Write-OpenState $false $sw.ElapsedMilliseconds $null 'harness did not become ready within 70s' $null
  }
  return $ok
}

# ---------- 命令分发 ----------

if ($ShortcutOk) {
  # 桌面快捷方式存在, 且指向本脚本的 -Open 模式 (经 wscript + dsh-open.vbs 隐藏启动;
  # 用于宿主插件自动修复旧版指向 powershell.exe 的快捷方式)
  $lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) $shortcutName
  $ok = $false
  try {
    if (Test-Path $lnkPath) {
      $sh = New-Object -ComObject WScript.Shell
      $sc = $sh.CreateShortcut($lnkPath)
      $target = [string]$sc.TargetPath
      $args   = [string]$sc.Arguments
      $ok = ($target -like '*wscript.exe') -and
            ($args -like ('*' + $scriptDir + '*')) -and
            ($args -like '*dsh-open.vbs*')
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

# -AutoStartDiag: 诊断自启动注册链路。尝试两种计划任务注册方式并报告结果
# (若注册成功会创建/更新任务本身, 但不修改 Run 键; 不改变任何偏好)。
if ($AutoStartDiag) {
  $comOk = Register-DSHDesktopTaskCom
  $xmlOk = if ($comOk) { $false } else { Register-DSHDesktopTaskXml }
  $exists = Test-DSHDesktopTask
  $runKeyValue = $null
  try { $runKeyValue = (Get-ItemProperty -Path $runKey -Name $runValue -ErrorAction Stop).$runValue } catch { }
  $method = 'none'
  try { $method = (Get-Content -Path $autoStartMethodFile -Raw | ConvertFrom-Json).method } catch { }
  Write-Output ("script  = " + $MyInvocation.MyCommand.Path)
  Write-Output ("task    = " + $taskName)
  Write-Output ("com     = " + $comOk)
  Write-Output ("xml     = " + $xmlOk)
  Write-Output ("exists  = " + $exists)
  Write-Output ("runkey  = " + $(if ($runKeyValue) { 'present' } else { 'absent' }))
  Write-Output ("method  = " + $method)
  exit 0
}

# 终端窗口显示/隐藏 (由设置页调用; Harness 未运行时静默成功, 偏好会用于下次启动;
# Harness 在运行但窗口操作失败时退出码 1, 设置页会显示错误而不是毫无反应)
if ($ShowTerminal) {
  $termOk = Set-TerminalWindow 9
  if (-not (Set-TerminalWindow 5)) { $termOk = $false }
  if (-not $termOk) { exit 1 }
  exit 0
}
if ($HideTerminal) {
  if (-not (Set-TerminalWindow 0)) { exit 1 }
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

# -Restart: 托盘保持运行, 只重启 Harness 服务和桌面窗口。
if ($Restart) {
  if (-not (Enter-OpenRequest)) { exit 0 }
  try { [void](Invoke-Restart) } finally { Exit-OpenRequest }
  exit 0
}

# -OpenWeb: 切换到网页端 —— 确保服务运行, 关闭独立桌面窗口 (看守进程随窗口退出而自行结束),
# 用默认浏览器打开, 记录诊断信息并退出
if ($OpenWeb) {
  if (-not (Enter-OpenRequest)) { exit 0 }
  try {
  # 竞态防护: 若刚执行过"退出", 等待退出真正完成再启动 (避免撞上垂死旧实例)
  Wait-QuitFinished
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
    # 先打开浏览器, 再补托盘 (托盘缺失时): 用户先看到结果, 托盘在后台跟上
    Ensure-TrayRunning
  } else {
    Write-OpenState $false $sw.ElapsedMilliseconds $null 'harness did not become ready within 70s' $null
  }
  } finally { Exit-OpenRequest }
  exit 0
}

# -Open: 确保服务运行后打开 (独立窗口优先), 记录诊断信息并退出
if ($Open) {
  if (-not (Enter-OpenRequest)) { exit 0 }
  try {
  # 竞态防护: 若刚执行过"退出", 等待退出真正完成再启动 (避免撞上垂死旧实例)
  Wait-QuitFinished
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $ok = Ensure-Harness
  $sw.Stop()
  if ($ok) {
    $script:lastWindowInfo = $null
    $browser = Open-HarnessWindow
    # 先打开窗口, 再补托盘 (托盘缺失时): 窗口尽快可见, 托盘在后台跟上
    Ensure-TrayRunning
    Write-OpenState $true $sw.ElapsedMilliseconds $browser $null $script:lastWindowInfo
  } else {
    Write-OpenState $false $sw.ElapsedMilliseconds $null 'harness did not become ready within 70s' $null
  }
  } finally { Exit-OpenRequest }
  exit 0
}

# -WatchAppWindow: 窗口看守进程 (由 -Open/-AutoStart 启动, 隐藏运行, 自行退出)
if ($WatchAppWindow) {
  Start-WatchAppWindow
  exit 0
}

# -AutoStart: 登录自启动。不等服务就绪 —— 立即后台拉起服务 (免 npx 直连,
# 端口/互斥锁防重复), 同时直接打开桌面窗口 (内置启动页轮询就绪后自动跳转),
# 然后进入托盘。全程不依赖 WMI: 开机初期 WMI 服务未就绪时 Get-CimInstance
# 可能阻塞数分钟, 这里只用 TCP 端口探活 + 命名互斥锁。
if ($AutoStart) {
  # 条件式提前登记托盘 PID (仅当当前没有托盘在运行时): 让宿主 apply 看到"托盘已在/
  # 将启动"而不补拉重复托盘进程 (避免开机多付一次 PowerShell 冷启动); 若与宿主补拉的
  # 托盘发生竞态, 下方托盘模式拿到互斥锁后会以互斥锁持有者身份重新写 pidFile, 保证
  # 最终 pidFile 永远指向真正的托盘 (单一归属, 互不覆盖)。
  if (-not (Test-TrayRunning)) {
    try { $PID | Set-Content -Path $pidFile -Encoding ASCII } catch {}
  }
  if (-not (Test-HarnessHttp)) {
    $launcher = New-Object System.Threading.Mutex($false, $launchMutexName)
    $owned = $false
    try { $owned = $launcher.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true } catch { $owned = $false }
    if ($owned) {
      try {
        # 任务动作 (wscript 启动器) 可能已在 PowerShell 冷启动期间直接拉起服务:
        # 启动器标记存在且确有 node 进程在运行 → 信任启动器, 不重复拉起。
        # (Get-Process 纯 Win32, 不依赖开机初期未就绪的 WMI; 标记在决定后即清除)
        $launcherStarted = (Test-Path $launchMarkFile) -and ($null -ne (Get-Process node -ErrorAction SilentlyContinue))
        if (-not (Test-HarnessTcp) -and -not $launcherStarted) {
          [void](Start-Harness)
        } elseif (-not (Test-HarnessTcp)) {
          # 信任启动器但端口尚未监听: 有界观察最多 15 秒 —— 启动器拉起的进程
          # 可能不是 harness (如开机时其它软件恰好在跑 node.exe), 或已崩溃;
          # 端口一直不起就自行拉起, 保证服务必然可用。
          $launchT0 = [Environment]::TickCount
          while ([Environment]::TickCount - $launchT0 -lt 15000) {
            if (Test-HarnessTcp) { break }
            Start-Sleep -Milliseconds 300
          }
          if (-not (Test-HarnessTcp)) { [void](Start-Harness) }
        }
      } finally {
        try { $launcher.ReleaseMutex() } catch { }
        try { $launcher.Dispose() } catch { }
      }
    } else {
      try { $launcher.Dispose() } catch { }
    }
    Remove-Item $launchMarkFile -Force -ErrorAction SilentlyContinue
  }
  # 上一会话的应用窗口记录必然过期 (重启后 PID 已失效), 直接清除,
  # 避免 Open-HarnessWindow 的 CIM 回退通道在开机初期被 WMI 阻塞
  Remove-Item $appWindowFile -Force -ErrorAction SilentlyContinue
  [void](Open-HarnessWindow -Boot)
  # 自动迁移 (不阻塞上面的启动流程): 本次若仍由 Run 键触发 (计划任务未创建过),
  # 立即迁移到计划任务登录触发器并删除 Run 键 —— 下次登录起不再被 Explorer 的
  # 启动项队列拖慢。迁移失败 (如计划任务服务被禁用) 时保持 Run 键, 行为与旧版一致。
  try {
    $runKeyValue = (Get-ItemProperty -Path $runKey -Name $runValue -ErrorAction SilentlyContinue).$runValue
    if ($runKeyValue -and -not (Test-DSHDesktopTask)) { Set-AutoStart }
  } catch { }
  # 继续进入托盘模式
}

# ---------- 托盘模式: 单实例 ----------
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$isFirst = $false
# v7.6 修复: abandoned 互斥锁被 WaitOne 获取后绝不能再 Release —— 旧代码在 catch 里
# ReleaseMutex 后又把 isFirst 置 true, 会让两个托盘进程同时以"我是第一个"继续运行,
# 争写 tray.pid。现在 abandoned 视为已获得锁 (原持有者已死), 其它异常视为未获得。
try { $isFirst = $mutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $isFirst = $true }
catch { $isFirst = $false }
if (-not $isFirst) { exit 0 }
# 拿到托盘互斥锁后才登记 pidFile: 单一归属, 与宿主 apply / -AutoStart 的补拉互不覆盖。
try { $PID | Set-Content -Path $pidFile -Encoding ASCII } catch {}

Ensure-WinForms
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
  # 用 Start-Process 的 -WindowStyle Hidden 开关 (而非 powershell.exe 的命令行参数):
  # 它在 Win32 层以 SW_HIDE 创建子进程, 控制台从头到尾都不会出现; 而
  # 'powershell.exe -WindowStyle Hidden' 作为参数要等 CLR 启动完成后才生效, 会闪现终端。
  Start-Process 'powershell.exe' -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $scriptDir + '\dsh-tray.ps1"'),'-Open'
})
$restartItem = New-Object System.Windows.Forms.ToolStripMenuItem('重新启动')
$restartItem.Add_Click({
  Start-Process 'powershell.exe' -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $scriptDir + '\dsh-tray.ps1"'),'-Restart'
})
$quitItem = New-Object System.Windows.Forms.ToolStripMenuItem('退出')
# 退出 = 先停服务/关窗口/通知页面 (Invoke-Quit), 然后退出托盘
$quitItem.Add_Click({
  $notify.Visible = $false
  Invoke-Quit
  # 只删除属于自己的 pidFile: 退出期间若新托盘已接管 (pidFile 已换成新 PID),
  # 绝不误删新托盘的记录
  try {
    $pf = (Get-Content -Path $pidFile -Raw).Trim()
    if ($pf -eq [string]$PID) { Remove-Item $pidFile -ErrorAction SilentlyContinue }
  } catch { }
  [System.Windows.Forms.Application]::Exit()
})
[void]$menu.Items.Add($openItem)
[void]$menu.Items.Add($restartItem)
[void]$menu.Items.Add($quitItem)
$notify.ContextMenuStrip = $menu
$notify.Add_DoubleClick({
  Start-Process 'powershell.exe' -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $scriptDir + '\dsh-tray.ps1"'),'-Open'
})

[System.Windows.Forms.Application]::Run()
$notify.Dispose()
# 只删除属于自己的 pidFile (同上: 退出时新托盘可能已接管)
try {
  $pf = (Get-Content -Path $pidFile -Raw).Trim()
  if ($pf -eq [string]$PID) { Remove-Item $pidFile -ErrorAction SilentlyContinue }
} catch { }
$mutex.Dispose()
