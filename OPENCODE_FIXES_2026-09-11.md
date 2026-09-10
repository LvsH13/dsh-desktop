# dsh-desktop 修复记录（opencode，2026-09-11）

> 供另一个会话 AI 审阅/接手使用。本文档只描述**实际已做的改动**及其原因、验证结果和注意事项。
> 涉及组件：`dsh-desktop`（宿主/客户端插件 + Windows 托盘伴侣脚本）、profile 配置，以及同批修复的 `dsh-github`。
>
> **本日共四批改动**：
> | 批次 | 时间 | 主题 |
> | --- | --- | --- |
> | ① | ~01:00 | 托盘脚本稳定性：401 就绪判定、删除强杀、`--no-open`、认证 URL、左键单击 |
> | ② | ~02:28 | `dsh-desktop` 从设置中消失 → 恢复依赖与 bundle；`dsh-github` 报错 → 声明为 bundle |
> | ③ | ~02:55–03:01 | 打开/重启慢（~20–30s 无反馈）→ 启动页提前显示 + 就绪后原地切换认证页 |
> | ④ | ~03:10–03:22 | 重启/打开出现两个窗口（启动页停在错误页 + 认证页新窗口）→ DevTools 协议单窗口原地切换 |

---

## 0. 环境与背景

| 项 | 值 |
| --- | --- |
| DeepSeek Harness CLI | `@deepseek-ai/dsh` 0.1.5-rc.1（npx 缓存路径 `C:\Users\21131\AppData\Local\npm-cache\_npx\1e7f6d9597241db0\node_modules\@deepseek-ai\dsh\lib\bin.js`） |
| DSH_HOME | `F:\.dsh`（profile：`F:\.dsh\profiles\web`） |
| Harness 地址 | `http://127.0.0.1:3080` |
| 安装副本 | `C:\Users\21131\AppData\Local\dsh-desktop\dsh-tray.ps1` |
| 插件源副本 | `F:\Deepseek_Harness\dsh-desktop\assets\dsh-tray.ps1`（插件加载时 `installAssets()` 会把它复制到上面那个目录） |
| 原始备份 | `C:\Users\21131\AppData\Local\dsh-desktop\dsh-tray.ps1.bak-opencode`（批次①前的原始版本） |
| 批次①备份 | `C:\Users\21131\AppData\Local\dsh-desktop\dsh-tray.ps1.bak-opencode-20260911-speed`（批次①后、批次③前） |
| 桌面窗口 | 不固定 Chrome/Edge：跟随默认 Chromium 系浏览器；本机实际为 `chrome.exe`，`--user-data-dir=%LOCALAPPDATA%\dsh-desktop\edge-profile` |
| 启动页 | `C:\Users\21131\AppData\Local\dsh-desktop\boot.html`（黑鲸图标 + “正在启动 + 已等待秒数”，每 500ms 轮询服务，就绪后 `location.replace(origin)`） |

改动规模：
- 托盘脚本相对原始备份：**+164 行 / -64 行**（原始 2018 行/100423 字节 → 现在 2118 行/106306 字节，UTF-8 带 BOM）。
- 批次③相对批次①备份：+77 行 / -4 行。
- 当前源副本 SHA256：`475D346495245DB987661F4C9321ECDD93AD03D6103BFFF7FDBC4A64FA41EF6F`（与安装副本一致）。

---

## 1. 问题与根因

### 1.1 抢占端口 / 重复启动（批次①，核心问题）

**现象**：用命令行（或任意方式）启动 `dsh web` 后，托盘会再拉起一个实例或把已运行的实例杀掉，导致 3080 端口争抢、界面反复提示连接异常/重新连接。

**根因有两处**（都在托盘脚本里）：

1. **`Test-HarnessHttp` 把 401 当成“未就绪”**
   Harness 0.1.5 起 Web 端启用了浏览器认证：不带 cookie 访问 `/` 返回 **401**。
   .NET 的 `HttpWebRequest.GetResponse()` 对 4xx/5xx 会**抛 `WebException`**，而原实现把所有异常直接吞成 `return $false`。因此托盘永远认为“服务没起来”。
2. **`Ensure-Harness` 里有“20 秒没监听就强杀”的僵尸实例逻辑**
   因为 (1) 永远不就绪，这个逻辑必然在 20 秒后 `taskkill` 掉（哪怕是命令行正常冷启动中的）实例，再拉一个新的 → 端口抢占/重复启动/页面断连。

另外：托盘隐藏启动 Harness 时没有传 `--no-open`，Harness CLI 自己还会弹一个默认浏览器（与托盘的桌面窗口重复）。

### 1.2 认证导致的 401 卡死（批次①）

**现象**：重启 Harness 后桌面窗口落在 “dsh web authentication required; reopen the URL printed by dsh web.” 的 401 纯文本页，不会恢复。

**根因**：托盘用 `--app=$origin`（不带 token）打开窗口；认证 cookie 缺失/失效时无法通过认证栅栏。CLI 启动时打印的 `?token=...` 认证 URL 被隐藏窗口丢掉了，托盘拿不到。token 是每个 Harness 进程随机生成的，只能从 CLI stdout 解析。

### 1.3 托盘图标单击无反应（批次①）

原脚本只注册了 `Add_DoubleClick`（双击打开）；没有左键单击处理器。

### 1.4 连接报错后无限自动重连（批次①，配置层面）

Web 前端的 `@deepseek-ai/dsh-client-connection` 默认“连接丢失 → 指数退避无限重试”。
用户明确要求：**出错后停止自动重连**（保留手动“立即重连”）。

> 该行为通过 profile 配置实现，见第 3.3 节；不在 `dsh-tray.ps1` 内。

### 1.5 dsh-desktop 从设置中消失（批次②）

**现象**：设置页里看不到「桌面端」这一节；插件市场“已安装”列表里也没有 `@dsh-external/dsh-desktop`。

**根因**：Harness 升级过程中，`F:\.dsh\profiles\web\package.json` 里的两处引用被移除：

- `dependencies` 中不再有 `"@dsh-external/dsh-desktop": "link:F:/Deepseek_Harness/dsh-desktop"`；
- `dsh.profile.bundles` 中不再有 `"@dsh-external/dsh-desktop"`。

`node_modules\@dsh-external\dsh-desktop` 的 junction 还在、包本身（0.7.7）完好，但**没有任何入口把它挂进组合树**：宿主半边不加载（没有 `settings` 命名空间、没有 `/_dsh/dsh-desktop` 路由与 SSE），客户端半边（设置页 section）也不加载，所以设置里完全看不到。

> 对照：同期的 `dsh-github`（问题 1.6）因为是 `dependencies` 成员但不在 bundles，被插件市场当作“纯客户端插件”用 no-op shim 热挂载，客户端半边还能显示；`dsh-desktop` 连依赖都被删了，所以连客户端都不显示。

### 1.6 冷启动打开/重启慢且长时间无反馈（批次③）

**现象**：点桌面快捷方式打开、以及托盘“重新启动”，大约都要 30 秒，而且这期间屏幕上什么都没有；Harness 服务已运行时点快捷方式又很快。

**实测构成**（2026-09-11 02:55 一次完整 `-Restart` 采样）：

| 阶段 | 耗时 |
| --- | --- |
| `Invoke-Quit`（通知页面关闭 + 杀进程 + 等端口释放） | ~2.4s |
| `Ensure-Harness` 启动前检查（含 `Get-HarnessNode` 的 WMI 进程扫描） | ~4.2s |
| Harness 进程启动 → HTTP 就绪（加载全部插件） | ~11–13s |
| 打开浏览器窗口（PowerShell 看守进程 + Chrome 冷启动） | ~2–3s |
| **合计** | **~20–22s（差的情况到 30s）** |

**根因**：托盘脚本的顺序是 `Ensure-Harness`（**等完全就绪，最多 360s**）→ `Open-HarnessWindow`，即**就绪之前不开任何窗口**。启动页 `boot.html` 只有登录自启动（`-AutoStart`）在用，普通打开/重启没有用上，所以用户只能对着空屏幕等 17 秒以上。

另一个相关限制：认证 cookie 是 `SameSite=Strict; HttpOnly`（见 `@deepseek-ai/dsh-client-connection` 的 `sessionCookie()`）。启动页是 `file://`，自动跳转到 `http://127.0.0.1` 属于**跨站顶层导航**，浏览器不会附带该 cookie → 直接跳转必然落入 401 纯文本页。这解释了为什么启动页以前只敢在登录自启动用、且被列为“已知边界”。批次③用“原地重新导航”解决了它（见 2.10、4.8）。

---

## 2. `dsh-tray.ps1` 的修改明细（按函数）

### 2.1 新增日志路径变量（批次①，约原 168 行附近）

```powershell
# Harness 启动日志: 隐藏启动时重定向到这里, 用于解析 CLI 打印的认证 URL
# (http://127.0.0.1:<port>/?token=...), 打开窗口时带上 token 避免 401。
$harnessLogFile = Join-Path $scriptDir 'harness-console.log'
$harnessErrFile = Join-Path $scriptDir 'harness-console.err.log'
```

### 2.2 `Test-HarnessHttp`：把 401 视为“已就绪”（批次①）

**改动前**（异常全部吞掉）：

```powershell
function Test-HarnessHttp {
  try {
    $req = [System.Net.HttpWebRequest]::Create($origin + '/')
    $req.Timeout = 1500
    $req.Method = 'GET'
    $req.Proxy = $null
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $resp.Close()
    return ($code -ge 200 -and $code -lt 500)
  } catch { return $false }
}
```

**改动后**（从 `WebException.Response` 取 4xx 状态码）：

```powershell
# 权威就绪检查: TCP 通了不一定页面可用, HTTP 返回非 5xx 才算真正就绪。
# 注意: 新版 Harness 需要浏览器认证, 未带 cookie 访问 "/" 会返回 401 ——
# .NET 的 GetResponse 对 4xx 抛 WebException, 必须从异常里取状态码,
# 否则会把"已就绪但需要认证"误判为"未就绪", 进而误杀进程/重复拉起。
function Test-HarnessHttp {
  try {
    $req = [System.Net.HttpWebRequest]::Create($origin + '/')
    $req.Timeout = 1500
    $req.Method = 'GET'
    # 本地探测不走系统代理 (如 Clash 的 127.0.0.1:7897), 避免被代理转发/超时
    $req.Proxy = $null
    $code = 0
    try {
      $resp = $req.GetResponse()
      $code = [int]$resp.StatusCode
      $resp.Close()
    } catch [System.Net.WebException] {
      if ($null -eq $_.Exception.Response) { return $false }
      $code = [int]$_.Exception.Response.StatusCode
      $_.Exception.Response.Close()
    }
    return ($code -ge 200 -and $code -lt 500)
  } catch { return $false }
}
```

判定语义：2xx–4xx（含 401/403/404）= 服务已就绪；5xx 或连接失败 = 未就绪。

### 2.3 `Start-Harness`：加 `--no-open` + 捕获 CLI 输出（批次①）

```powershell
if ($null -ne $entry -and (Test-Path $entry) -and $null -ne $nodeExe -and (Test-Path $nodeExe)) {
    # --no-open: 由托盘/快捷方式负责打开桌面窗口, 避免 Harness 自己再弹一个默认浏览器
    $argLine = '"' + $entry + '" web --no-open'
    if ($null -ne $webArgs -and $webArgs.Count -gt 0) { $argLine += ' ' + (($webArgs | Where-Object { $_ }) -join ' ') }
    $oldDshHome = $env:DSH_HOME
    try {
      if ($dshHome) { $env:DSH_HOME = $dshHome }
      if ($show) {
        Start-Process -FilePath $nodeExe -ArgumentList $argLine -WorkingDirectory $workDir
      } else {
        # 清空旧日志 (避免复用上一进程的失效 token), 并捕获 CLI 打印的认证 URL
        Remove-Item $harnessLogFile, $harnessErrFile -Force -ErrorAction SilentlyContinue
        Start-Process -FilePath $nodeExe -ArgumentList $argLine -WorkingDirectory $workDir -WindowStyle Hidden -RedirectStandardOutput $harnessLogFile -RedirectStandardError $harnessErrFile
      }
      return $true
    } ...
  }
  $npxCmd = 'title DeepSeek Harness && npx --no-install @deepseek-ai/dsh web --no-open'
```

说明：
- 只有“隐藏启动”（`showTerminal=false`，默认）才重定向日志；显示终端模式不抓日志（`Get-HarnessAuthUrl` 会因“无日志/日志比进程旧”安全返回 `$null`）。
- `--no-open` 同时加到了 node 直连和 npx 兜底两条路径。

### 2.4 新增 `Get-HarnessAuthUrl`（批次①，紧跟 `Start-Harness` 之后）

```powershell
# 读取当前 Harness 进程的认证 URL (CLI 启动时打印到日志的 ?token=... 地址)。
# 仅当日志比进程创建时间新时才采用, 避免复用上一个进程的失效 token;
# 命令行/手动启动的实例没有本日志, 返回 $null (调用方回退 origin + cookie)。
function Get-HarnessAuthUrl {
  try {
    if (-not (Test-Path $harnessLogFile)) { return $null }
    $logItem = Get-Item $harnessLogFile -ErrorAction SilentlyContinue
    if ($null -eq $logItem) { return $null }
    $node = Get-HarnessNode
    if ($null -eq $node) { return $null }
    $created = $null
    try { $created = [datetime]$node.CreationDate } catch { $created = $null }
    if ($null -ne $created -and $logItem.LastWriteTime -lt $created) { return $null }
    $text = Get-Content -Path $harnessLogFile -Raw -ErrorAction SilentlyContinue
    if (-not $text) { return $null }
    $urlMatches = [regex]::Matches($text, 'http://127\.0\.0\.1:' + [string]$port + '/\?token=[A-Za-z0-9_\-]+')
    if ($urlMatches.Count -eq 0) { return $null }
    return $urlMatches[$urlMatches.Count - 1].Value
  } catch { return $null }
}
```

要点：
- 用“日志文件 LastWriteTime ≥ 进程 CreationDate”做**新鲜度校验**，防止把上一个进程的 token 用在下一次打开窗口上。
- token 是每个进程随机生成的（`randomBytes`），必须从 CLI 输出解析，无法外部构造。

### 2.5 `Ensure-Harness`：删除一切强杀/重拉逻辑，改为“只等待、可接管”（批次①）

改动点：
1. “存在进程但端口未监听”的分支：观察窗口 20s → **30s**，且**删掉了 20 秒超时后的 `taskkill`**。进程退出才补拉。
2. 等待循环从 `140` 次 → `720` 次（每次 500ms，即上限约 360s 墙钟；失败时实际约 6–12 分钟，因为每次探测本身有耗时），并**删掉了“端口在监听但 HTTP 不就绪 → 进程够老就强杀重拉”的整段 `elseif`**。
3. 就绪后增加“等认证 URL 落盘”的小循环（解决 race，见下）：

```powershell
  $waitT0 = [Environment]::TickCount
  for ($i = 0; $i -lt 720; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-HarnessHttp) {
      # 刚由本脚本拉起时, CLI 打印的认证 URL 可能比监听就绪晚几毫秒才落盘;
      # 短暂等待它出现, 保证 Open-HarnessWindow 能用 ?token=... 打开窗口。
      for ($k = 0; $k -lt 25; $k++) {
        if (-not (Test-Path $harnessLogFile)) { break }
        $rawLog = Get-Content -Path $harnessLogFile -Raw -ErrorAction SilentlyContinue
        if ($rawLog -and $rawLog -match '\?token=') { break }
        Start-Sleep -Milliseconds 200
      }
      return $true
    }
    if ([Environment]::TickCount - $waitT0 -lt 15000) { continue }
    $waitT0 = [Environment]::TickCount
    $tcpUp = Test-HarnessTcp
    $running = Get-HarnessNode
    if (-not $tcpUp -and $null -eq $running) {
      # 没有进程也没有端口: 重新拉起 (启动互斥锁防并发双启) —— 这段保留
      ...
    }
    # 注意: 原来这里还有一段 elseif (tcpUp 且进程够老 → taskkill) 已整体删除
  }
  return $false
```

行为总结（新）：
- 只要检测到匹配的 `dsh web` 进程（**包括命令行启动的实例**，`Get-HarnessNode` 按入口路径 / `@deepseek-ai/dsh` 命令行匹配），就只等待其就绪，**绝不抢占、绝不强杀**。
- 只有“既没有进程也没有端口监听”时才重新拉起（沿用 `DSHDesktopHarnessLaunch` 互斥锁防双开）。
- 观察到的进程自己退出时，等 300ms 后补拉。
- 超时只影响 open-state 诊断信息，不再触发破坏性动作。

### 2.6 `Open-HarnessWindow`：非启动页路径优先使用认证 URL（批次①）

```powershell
      # 启动目标: 登录自启动时用内置启动页 (轮询就绪后跳转到 $origin), 让窗口
      # 在 Harness 冷启动期间 (数十秒) 立即可见; 其它路径优先使用 CLI 打印的
      # 认证地址 (?token=...), 首次打开即可通过 401 认证栅栏, 之后 cookie 生效。
      $target = $origin
      $bootPage = Join-Path $scriptDir 'boot.html'
      if ($Boot -and (Test-Path $bootPage)) {
        $target = 'file:///' + (($bootPage -replace '\\', '/') + '?port=' + $port)
      } elseif (-not $Boot) {
        $authUrl = Get-HarnessAuthUrl
        if ($authUrl) { $target = $authUrl }
      }
```

> 批次③起，`-Open`/`-Restart` 冷启动时也会**提前**调用一次 `Open-HarnessWindow -Boot`（先显示启动页），就绪后再用 2.10 的原地切换导航到认证地址；服务已就绪时仍然走上面的常规路径。

### 2.7 `-OpenWeb`（切到网页端）：默认浏览器同样带认证 URL（批次①）

```powershell
  if ($ok) {
    try {
      $openUrl = Get-HarnessAuthUrl
      if (-not $openUrl) { $openUrl = $origin }
      Start-Process $openUrl
      Write-OpenState $true $sw.ElapsedMilliseconds 'default' $null $null
    } ...
```

### 2.8 就绪超时文案：70s → 360s（批次①）

`Invoke-Restart`、`-OpenWeb`、`-Open` 三处失败诊断字符串：

```powershell
'harness did not become ready within 70s'   # 旧
'harness did not become ready within 360s'  # 新
```

只影响 `open-state.json` 里的诊断文本。

### 2.9 托盘图标左键单击 = 启动/打开（批次①）

追加在原有 `Add_DoubleClick` 之后：

```powershell
# 左键单击图标: 启动/恢复 Harness 并打开桌面窗口 (与双击、桌面快捷方式同一路径;
# 命令行走的就是 -Open → Ensure-Harness 复用已有实例, 不会抢占端口或重复启动)
$notify.Add_MouseClick({
  param($sender, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
    Start-Process 'powershell.exe' -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $scriptDir + '\dsh-tray.ps1"'),'-Open'
  }
})
```

行为：
- 左键单击 → 隐藏启动一个新 PowerShell 执行 `dsh-tray.ps1 -Open`（与双击/桌面快捷方式完全同路径）。
- `-Open` 内部：`Ensure-Harness`（复用已有实例）→ `Open-HarnessWindow`（带 token）→ `Ensure-TrayRunning`；批次③后冷启动会先显示启动页再原地切换。
- 右键仍弹菜单（`MouseClick` 里按 `Left` 过滤，不会干扰右键）。
- 双击处理器保留不变。

### 2.10 新增 `Retarget-HarnessWindow`：启动页窗口原地切换到认证页（批次③，紧跟 `Open-HarnessWindow` 之后）

```powershell
# 冷启动"启动页 → Harness"原地切换: 启动页窗口 (file://) 打开后, 服务就绪时
# 把同一个 app 窗口导航到带认证地址 (?token=) 的 Harness 页面。
# 为什么必须这样做: 认证 cookie 是 SameSite=Strict, 从 file:// 顶层跳转到
# http://127.0.0.1 属于跨站导航, 浏览器不会附带该 cookie —— 启动页自动跳转会
# 落入 401 纯文本页。而用同一 --user-data-dir + --app-user-model-id 再次启动
# Chromium 时, 现有 app 窗口会被复用并直接导航到新地址 (不会新开窗口),
# 带 token 的导航会完成认证并种下 cookie。
function Retarget-HarnessWindow {
  $browser = Find-AppBrowser
  if (-not $browser) { return $false }
  $target = Get-HarnessAuthUrl
  if (-not $target) { $target = $origin }
  $layout = Get-AppWindowLayout
  $profileDir = Join-Path $scriptDir 'edge-profile'
  $appArgs = '--app=' + $target +
             ' --window-size=' + $layout.sizeDip.Width + ',' + $layout.sizeDip.Height +
             ' --window-position=' + $layout.posDip.X + ',' + $layout.posDip.Y +
             ' --user-data-dir="' + $profileDir + '"' +
             ' --app-user-model-id=DSHDesktopApp' +
             ' --no-first-run --no-default-browser-check'
  $appLnk = Update-AppWindowShortcut $browser $appArgs
  if ($appLnk -and (Test-Path $appLnk)) {
    try { Start-Process -FilePath $appLnk | Out-Null; return $true } catch { }
  }
  try { Start-Process -FilePath $browser -ArgumentList $appArgs | Out-Null; return $true } catch { return $false }
}
```

要点：
- **不新开窗口**：Chromium 对同一 `--user-data-dir` + `--app-user-model-id` 的第二次 `--app=URL` 启动，会复用现有 app 窗口并导航（已实测，见 4.8）。
- **不带 `--start-minimized`**：复用现有窗口时无需再最小化；窗口尺寸/居中由已在运行的看守进程负责。
- **不写 app-window 记录**：复用时的启动进程只是转发进程，记录沿用看守进程自愈后的真实窗口 PID。
- 认证 URL 拿不到时回退 `origin`（依赖 profile 里已有的 cookie，与旧行为一致）。

### 2.11 `-Open`：冷启动提前显示启动页 + 就绪后原地切换（批次③）

```powershell
if ($Open) {
  if (-not (Enter-OpenRequest)) { exit 0 }
  try {
  # 竞态防护: 若刚执行过"退出", 等待退出真正完成再启动 (避免撞上垂死旧实例)
  Wait-QuitFinished
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  # 冷启动反馈优化: 服务未就绪时, 先打开内置启动页窗口 (数秒内可见), 再等待
  # 服务就绪; 启动页在就绪后自动跳转到 Harness 页面。服务已就绪时维持原路径
  # (带 ?token= 认证地址直接打开 Harness)。
  $earlyBoot = -not (Test-HarnessHttp)
  $browser = $null
  if ($earlyBoot) { $browser = Open-HarnessWindow -Boot }
  $ok = Ensure-Harness
  $sw.Stop()
  if ($ok) {
    if ($earlyBoot) {
      if ($browser -eq 'app' -or $browser -eq 'app-existing') {
        # 服务已就绪: 把启动页窗口原地导航到带认证地址的 Harness 页面
        [void](Retarget-HarnessWindow)
      } elseif ($browser -eq 'none' -or $browser -eq 'default') {
        $script:lastWindowInfo = $null
        $browser = Open-HarnessWindow
      }
    } else {
      $script:lastWindowInfo = $null
      $browser = Open-HarnessWindow
    }
    # 先打开窗口, 再补托盘 (托盘缺失时): 窗口尽快可见, 托盘在后台跟上
    Ensure-TrayRunning
    Write-OpenState $true $sw.ElapsedMilliseconds $browser $null $script:lastWindowInfo
  } else {
    Write-OpenState $false $sw.ElapsedMilliseconds $null 'harness did not become ready within 360s' $null
  }
  } finally { Exit-OpenRequest }
  exit 0
}
```

### 2.12 `Invoke-Restart`：同策略（批次③）

```powershell
function Invoke-Restart {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  Invoke-Quit
  # 冷启动反馈优化: 旧实例已停、端口已释放, 立即拉起服务进程并先打开内置
  # 启动页窗口 (数秒内可见, 显示"正在启动"+已等待秒数), 启动页会在服务就绪后
  # 自动跳转到 Harness 页面 —— 不再等 Ensure-Harness 全部就绪 (10 秒以上)
  # 才让用户看到任何东西。
  if (-not (Test-HarnessTcp)) { [void](Start-Harness) }
  $browser = Open-HarnessWindow -Boot
  $ok = Ensure-Harness
  $sw.Stop()
  if ($ok) {
    if ($browser -eq 'app' -or $browser -eq 'app-existing') {
      # 服务已就绪: 把启动页窗口原地导航到带认证地址的 Harness 页面
      [void](Retarget-HarnessWindow)
    } else {
      # 本机没有 Chromium 内核浏览器时启动页不可用: 服务已就绪, 回退常规
      # 路径 (带 ?token= 认证地址) 打开。
      $browser = Open-HarnessWindow
    }
    Write-OpenState $true $sw.ElapsedMilliseconds $browser $null $script:lastWindowInfo
  } else {
    Write-OpenState $false $sw.ElapsedMilliseconds $null 'harness did not become ready within 360s' $null
  }
  return $ok
}
```

说明：`Start-Harness` 放在开窗之前，让 Harness 冷启动与 Chrome 启动并行；`Invoke-Quit` 已确认端口释放（`Test-HarnessTcp` 为假）才直接拉起，避免与垂死实例抢端口。

### 2.13 `-RetargetWhenReady` 补位进程 + `-AutoStart` 接入（批次③）

新增参数（param 块）：

```powershell
  [switch]$Restart,
  [switch]$RetargetWhenReady,
  [switch]$Quit
```

新增分发（在 `-WatchAppWindow` 之前）：

```powershell
# -RetargetWhenReady: 登录自启动的补位进程 —— 等 Harness 就绪后, 把已打开的
# 启动页窗口原地导航到带认证地址的 Harness 页面 (见 Retarget-HarnessWindow 注释)。
if ($RetargetWhenReady) {
  for ($i = 0; $i -lt 720; $i++) {
    if (Test-HarnessHttp) {
      Start-Sleep -Milliseconds 700
      [void](Retarget-HarnessWindow)
      break
    }
    Start-Sleep -Milliseconds 500
  }
  exit 0
}
```

`-AutoStart` 中打开启动页之后追加：

```powershell
  Remove-Item $appWindowFile -Force -ErrorAction SilentlyContinue
  [void](Open-HarnessWindow -Boot)
  # 启动页窗口出现后, 另起一个隐藏进程在服务就绪时把它原地导航到带认证地址
  # 的 Harness 页面 (file:// 直跳会被 SameSite=Strict 挡下, 见 Retarget-HarnessWindow)
  Start-Process 'powershell.exe' -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $scriptDir + '\dsh-tray.ps1"'),'-RetargetWhenReady'
```

---

## 3. profile 层相关改动（非 `dsh-tray.ps1`）

### 3.1 恢复 `@dsh-external/dsh-desktop` 挂载（批次②）

文件：`F:\.dsh\profiles\web\package.json`

```diff
   "dependencies": {
     ...
     "@deepseek-ai/dsh-timeout": "0.1.5-rc.1",
+    "@dsh-external/dsh-desktop": "link:F:/Deepseek_Harness/dsh-desktop",
     "@liustack/modsearch": "^5.10.2",
     ...
   },
   "dsh": {
     "profile": {
       "bundles": [
         "@deepseek-ai/dsh-base",
         "@deepseek-ai/dsh-web-app",
+        "@dsh-external/dsh-desktop",
         "dshmarket",
         ...
       ]
     }
   },
```

执行：

```powershell
pnpm install --prefer-offline   # pnpm 10.33.0；link 依赖只重建 junction + 更新 lockfile
```

要点：
- `node_modules\@dsh-external\dsh-desktop` 是指向 `F:\Deepseek_Harness\dsh-desktop` 的 junction（`LinkType: Junction`），包本体 0.7.7 未变；本次只重建引用并回写 `pnpm-lock.yaml`（新增 `link:` 条目）。
- `@dsh-external/dsh-desktop` 的 `package.json` 自带 `dsh.bundle.patch = ./cordis.patch.yml`，其 patch 插入 `id: dsh-desktop` / `name: @dsh-external/dsh-desktop`；加入 bundles 后宿主与客户端两边都会加载。
- 备份：`package.json.bak-opencode-20260911-dshdesktop`。

### 3.2 `dsh-github` 声明为 bundle（批次②，同批修复的另一个报错）

**问题**：设置页「Git 发布」面板报 `加载失败：Failed to execute 'json' on 'Response': Unexpected end of JSON input`。

**根因**：`dsh-github` 只声明了 `dsh.client`、没有声明 `dsh.bundle`，插件市场把它当“纯客户端插件”用 no-op shim 热挂载（市场日志：`dsh-github: live (client-only shim)`）。客户端面板正常渲染，但**宿主半边从未加载**，`POST /_dsh/github` 命中 web 服务器的兜底路由返回 **405 + 空 body**，前端 `response.json()` 解析空 body 即抛该错误。

**改动**：

1. `F:\Deepseek_Harness\dsh-github\package.json`：

```diff
   "exports": {
     ".": "./lib/index.js",
     "./client": "./lib/client.js",
+    "./cordis.patch.yml": "./cordis.patch.yml",
     "./package.json": "./package.json"
   },
   "files": [
-    "lib"
+    "lib",
+    "cordis.patch.yml"
   ],
   ...
   "dsh": {
+    "bundle": {
+      "patch": "./cordis.patch.yml"
+    },
     "client": {
       "inject": [ ... ],
       "platform": "web"
     }
   },
```

2. 新建 `F:\Deepseek_Harness\dsh-github\cordis.patch.yml`：

```yaml
# dsh-github bundle patch: mounts the GitPub host + client plugin into a
# profile layer stack. Declared via package.json dsh.bundle.patch so the
# market and the dsh CLI treat this package as a loadable bundle (not a
# client-only shim). Host half serves the /_dsh/github route.
- insert:
    - id: gitpub
      name: dsh-github
```

3. `F:\.dsh\profiles\web\package.json` 的 `dsh.profile.bundles` 末尾加入 `"dsh-github"`。

4. `F:\.dsh\profiles\web\cordis.patch.yml` 里原先被注释掉的 GitPub insert 说明改为：

```yaml
# GitPub (dsh-github) 现在自带 bundle patch 并已加入 package.json 的
# dsh.profile.bundles, 由 bundle 层负责 insert (id: gitpub)。
# 请勿在此处再加 name: dsh-github 的 insert 行 —— 重复的 gitpub 行会导致启动失败。
```

要点：
- 声明 `dsh.bundle` 后，市场的 `mountClientOnlyDeps` 会跳过它（不再 shim），改由 bundle 层在启动时挂载宿主 + 客户端。
- 市场可正常识别 `rowIdsForPackage`（bundle patch 的 `gitpub` 行），插件市场“启用/禁用”开关对它有效。
- 备份：`F:\Deepseek_Harness\dsh-github\package.json.bak-opencode-20260911`。

### 3.3 连接恢复策略（批次①，原文保留）

文件：`F:\.dsh\profiles\web\cordis.patch.yml`（profile 用户补丁层）追加：

```yaml
# 连接恢复策略: 出错后停止自动重连 (退避时长拉到最大 ~24.8 天, 相当于不再
# 自动重试); 设置页的"立即重连"按钮仍即时生效, 网络恢复事件也会触发重连。
- id: connection
  config:
    trustedHosts: !!js ctx.webRuntime.trustedHosts
    recovery:
      backoffBaseMs: 2147483647
      backoffMaxMs: 2147483647
```

要点：
- `id: connection` 是 `@deepseek-ai/dsh-client-connection` 在组合树中的条目 id。
- 该插件的补丁是**整体替换 config**（之前给 webserver 打补丁时验证过），所以必须把原有的 `trustedHosts: !!js ctx.webRuntime.trustedHosts` 一起写上，否则会丢。
- 生效方式：下次 Harness 启动时注入页面全局 `__DSH_CONNECTION_RECOVERY__`；已验证下发值为
  `{"backoffBaseMs":2147483647,"backoffFactor":2,"backoffMaxMs":2147483647,"generationReadyWarnMs":3000,"generationReadyTimeoutMs":15000}`。
- 效果：连接丢失后第一次退避上限即 ≈24.8 天，等效“不再自动重连”；前端“立即重连”按钮和网络状态变化仍会立即触发重连。
- 服务端渲染入口：`resolveConnectionConfig(globalThis.__DSH_CONNECTION_RECOVERY__)`（客户端 `dsh-client-connection/lib/client.js`）。

---

## 4. 验证记录（已实际执行）

1. **语法/编码（每批都做）**
   - `[System.Management.Automation.Language.Parser]::ParseFile`：0 errors。
   - 文件 BOM 检查：`EF BB BF` 存在（PowerShell 5.1 必须 UTF-8 带 BOM 才能正确读中文）。
   - 源副本与安装副本 SHA256 一致；批次③后当前值 `475D3464…41EF6F`。
2. **命令行启动 + 托盘接管（批次①，核心场景）**
   - 先以“命令行方式”（外部进程）启动 `dsh web`，端口尚未监听时执行 `dsh-tray.ps1 -Open`：
     - 不再强杀、不再起第二个实例；
     - 唯一 `node` 进程保持存活；
     - 服务就绪后打开桌面窗口。
3. **重启全流程（批次①）**
   - `dsh-tray.ps1 -Restart`：`open-state.json = {"ok":true,"readyMs":18594,"browser":"app"}`；
   - 唯一 node 进程；窗口命令行实际为
     `--app=http://127.0.0.1:3080/?token=cjDWIl7Vmp0e-bpzAaYSAc5gqqXHVW8w6EXjMrRbUKs`
     （带 token，修复了 401 卡死）。
4. **已运行时快速打开（批次①）**
   - `dsh-tray.ps1 -Open`：`readyMs=47`，`browser="app-existing"`，仍在同一窗口（不会重复开窗）。
5. **401 判定（批次①）**
   - `Test-HarnessHttp` 对 `GET /`（无 cookie，401）返回 true 的逻辑经修复后，托盘能立即识别“已就绪”。
6. **单实例（每批都查）**
   - 全程检查：`deepseek-ai` 相关 harness node 进程始终为 1；`--app=…3080` 窗口为 1。
7. **批次②：dsh-desktop 恢复 + dsh-github 修复**
   - `GET /_dsh/dsh-desktop`（带认证 cookie）返回 200：
     `ok=True tray=True shortcut=True appWindow=True available=True`（设置页「桌面端」命名空间已注册）。
   - 页面启动列表出现 `@dsh-external/dsh-desktop/client.js` 与 `dsh-github/client.js`（客户端半边都加载）。
   - `POST /_dsh/github`（带 `Origin` + `Sec-Fetch-Site: same-origin`，同浏览器行为）返回 200：`gitpub.list` 列出 69 个插件；`gitpub.checkGit` 返回 `installed=true, version=2.53.0.windows.1`，不再出现空 body JSON 解析错误。
   - 市场日志不再出现 `client-only shims mounted: dsh-github`；`.dsh-market/hot-*.yml` 开机被清空且不再生成 shim 条目；`/dsh-market/api/v1/capabilities` 200。
8. **批次③：启动加速实测（自动采样，精度 0.2s）**

   | 场景 | 窗口出现（app-window 记录） | `-Open`/`-Restart` 命令结束 | 结果 |
   | --- | --- | --- | --- |
   | 优化前一次重启（02:55） | 约 19.8s（等就绪后才开窗） | 19.8s，readyMs 17516 | 全程无窗口 |
   | 优化后重启（02:56，首版） | **4.2s**（启动页） | 17.3s，readyMs 16625 | 启动页→… |
   | 优化后冷开（02:57） | **3.3s**（启动页） | 17.6s，readyMs 17052 | 启动页→… |
   | 优化后重启（02:59，含原地切换） | **5.0s** | 18.3s，readyMs 17130 | 切换后标题 `DeepSeek Harness` ✅ |
   | 已运行 + 窗口已开（03:00） | 0.8s 结束 | `browser=app-existing`，readyMs 61 | 不开新窗 ✅ |
   | 优化后冷开（03:00，含原地切换） | **3.2s** | 18.4s，readyMs 17096 | 切换后标题 `DeepSeek Harness` ✅ |

   - 结论：窗口可见时间从 ~20s 降到 **3–5s**；真正的 DSH 界面仍在服务就绪时（~17–18s，Harness 自身冷启动耗时）自动切过去。
   - 原地切换验证：切换前窗口标题为 `127.0.0.1`（启动页/401 形态），切换后为 `DeepSeek Harness`（认证通过的应用页），且始终只有 1 个 app 窗口（同一窗口被复用导航）。
9. **批次③：单实例/进程卫生**
   - 结束检查：harness node 1 个；托盘驻留 1 个（`tray.pid` 指向的进程，无参运行）；窗口看守 1 个（`-WatchAppWindow`）；app 窗口 1 个。

测试用到的临时手段：直接用 `taskkill`/`Stop-Process` 没有参与业务流程；启动捕获实例时曾用 `.cmd` 包装、事后已删除；批次③曾手工用 Chrome 命令行验证“同 profile 复用窗口”行为，随后由脚本实现。

---

## 5. 文件清单 / 备份 / 回滚

| 文件 | 说明 |
| --- | --- |
| `F:\Deepseek_Harness\dsh-desktop\assets\dsh-tray.ps1` | **修复后的源副本**（插件加载时 `installAssets()` 会覆盖安装副本） |
| `C:\Users\21131\AppData\Local\dsh-desktop\dsh-tray.ps1` | **修复后的当前生效副本**（与源副本 SHA256 一致） |
| `C:\Users\21131\AppData\Local\dsh-desktop\dsh-tray.ps1.bak-opencode` | 批次①前的原始副本（完全回滚用） |
| `C:\Users\21131\AppData\Local\dsh-desktop\dsh-tray.ps1.bak-opencode-20260911-speed` | 批次①后、批次③前的副本（只回滚启动加速用） |
| `F:\.dsh\profiles\web\package.json` | profile 清单：已恢复 desktop 依赖 + bundles；新增 dsh-github bundle |
| `F:\.dsh\profiles\web\package.json.bak-opencode-20260911-dshdesktop` | 批次②改动前备份 |
| `F:\.dsh\profiles\web\cordis.patch.yml` | 连接恢复策略 + GitPub 注释说明 |
| `F:\.dsh\profiles\web\cordis.patch.yml.bak-opencode-20260911` | 批次②改动前备份 |
| `F:\Deepseek_Harness\dsh-github\package.json` / `cordis.patch.yml` | GitPub 声明为 bundle（+ 新增 patch 文件） |
| `F:\Deepseek_Harness\dsh-github\package.json.bak-opencode-20260911` | dsh-github 改动前备份 |
| `C:\Users\21131\AppData\Local\dsh-desktop\boot.html` | 启动页（自动从 `assets/boot.html` 安装；黑鲸 + 秒数 + 轮询） |
| `C:\Users\21131\AppData\Local\dsh-desktop\harness-console.log` / `.err.log` | 托盘隐藏启动 Harness 的日志（功能文件：`Get-HarnessAuthUrl` 依赖它，**不要删/不要改成只读**） |
| `C:\Users\21131\AppData\Local\dsh-desktop\open-state.json` | 上次打开诊断（`readyMs` 只统计“服务就绪”耗时，不含窗口渲染） |

回滚：
- 只回滚启动加速（保留批次①稳定修复）：`Copy-Item dsh-tray.ps1.bak-opencode-20260911-speed dsh-tray.ps1`（保持 BOM）。
- 完全回滚托盘脚本：`Copy-Item dsh-tray.ps1.bak-opencode dsh-tray.ps1`，并结束 `tray.pid` 里的驻留进程后无参运行 `dsh-tray.ps1`。
- 回滚 profile：用对应 `.bak-opencode-*` 覆盖后 `pnpm install`，再重启 Harness（`dsh-tray.ps1 -Restart`）。

修改后重载托盘：
1. 结束 `tray.pid` 指向的驻留进程；
2. `powershell -NoProfile -ExecutionPolicy Bypass -File %LOCALAPPDATA%\dsh-desktop\dsh-tray.ps1`（无参 = 只驻留图标，不改动 Harness）。
3. 注意：`-Open`/`-Restart`/`-WatchAppWindow`/`-RetargetWhenReady` 都是**新起进程读取脚本文件**，所以托盘驻留进程不重启也会用新逻辑；只有托盘菜单里由旧进程内联处理的行为需要重启驻留进程才更新（本批改动不涉及）。

---

## 6. 已知边界 / 未决事项（供审阅）

1. **命令行/手动启动的实例没有日志** → `Get-HarnessAuthUrl` 返回 `$null`，`Open-HarnessWindow`/`Retarget-HarnessWindow` 回退到 `origin`，依赖浏览器 profile 里已有的认证 cookie。
   - 若该 profile 从未登录过（cookie 缺失），窗口会停在 401；需先访问一次 CLI 打印的 `?token=...` 地址（CLI 默认会自动用系统默认浏览器打开一次）。
   - 这是当前架构下无法避免的：token 是进程内随机值，仅 CLI stdout 可得。
2. ~~登录自启动 `-Boot` 路径用 `boot.html` 轮询跳 `origin`，全新 profile 可能 401~~ → **批次③已解决**：`-AutoStart` 后会另起 `-RetargetWhenReady` 进程，就绪时用带 `?token=` 的地址**原地导航现有窗口**（Chromium 复用同 profile/app-id 的 app 窗口），无需用户手动处理。普通 `-Open`/`-Restart` 也走同一原地切换逻辑。
3. `Get-HarnessAuthUrl` 的“新鲜度”依赖 WMI 进程创建时间（`Get-HarnessNode`）；WMI 不可用时 `Get-HarnessNode` 走的是有界查询，失败即回退 origin（安全降级）。
4. 抓日志仅限“隐藏启动”模式；`showTerminal=true` 时不抓，属预期。
5. 测试时未实际用鼠标点击托盘图标（无法自动化模拟通知区域图标点击）；单击行为通过执行它调用的同一命令 `dsh-tray.ps1 -Open` 验证。处理器注册本身经语法解析与代码审查确认。
6. 批次①“宿主插件无需重装”的说明已被批次②取代：**`@dsh-external/dsh-desktop` 现在重新挂载在 profile bundles 中**（宿主 `lib/index.js`、客户端 `lib/client.js` 本体未改），设置页「桌面端」恢复显示；托盘脚本仍可独立运行。
7. **Harness 自身冷启动约 11–17s**（加载全部插件，含 MCP 子进程）是批次③无法消除的固定成本；托盘侧已做到“窗口先可见 + 就绪自动切换”。若还要更快，方向是减少启动插件或让服务常驻（登录自启动）。
8. 认证 cookie 为 `SameSite=Strict; HttpOnly`：任何从 `file://` 或其它站点顶层跳转到 `http://127.0.0.1:3080` 的导航都不会带 cookie；不要用“启动页自动跳转”直接替代原地切换，否则必 401。

---

## 7. 一句话总结

批次①修复了托盘脚本“HTTP 就绪检测把 401 当失败 + 20 秒僵尸强杀 + 启动不带 `--no-open`”导致的抢端口/重复拉起，删除所有强杀逻辑（改为只等待/可接管外部实例，上限 360s），并从 CLI 日志解析 `?token=...` 认证地址打开窗口（含竞态等待）、新增托盘左键单击；批次②把升级中丢失的 `@dsh-external/dsh-desktop` 重新写回 profile 依赖与 bundles（恢复设置页「桌面端」），并把只声明客户端的 `dsh-github` 补上 `dsh.bundle.patch` 声明为正式 bundle（修复其 405 空 body 导致的 JSON 解析报错）；批次③针对“打开/重启 ~30s 且无反馈”，让 `-Open`/`-Restart` 在冷启动时**先显示内置启动页**（3–5s 可见），就绪后用同一 Chromium profile/app-id 把该窗口**原地导航**到带 token 的认证页（绕过 `SameSite=Strict` 的 file:// 跳转限制），同时通过 profile 配置把连接恢复退避拉到最大实现“报错后停止自动重连”（手动“立即重连”保留）；**批次④修正了批次③的原地切换实现**：实测 Chromium 并不会复用 app 窗口，第二次 `--app` 启动必开新窗，导致“启动页错误窗 + 认证新窗”两个窗口；改为给启动页窗口加 `--remote-debugging-port=0`，服务就绪后通过 DevTools 协议对**同一窗口**发 `Page.navigate(认证地址)`——浏览器级导航没有跨站发起方，`SameSite=Strict` cookie 正常生效，真正单窗口。

---

## 8. 批次④（~03:10–03:22）：重启/打开出现两个窗口 → DevTools 协议单窗口原地切换

### 8.1 现象与根因

现象：`-Restart`/桌面快捷方式冷启动后最终出现两个独立桌面窗口——一个是启动页窗口，加载完成后停在错误页（用户截图为 Chrome 的 `HTTP ERROR 404`；实测为 401 纯文本页 `dsh web authentication required; ...`），另一个是能正常使用的 Harness 窗口。

根因（批次③的“原地切换”实际没有生效）：

1. `boot.html` 自己仍在轮询到服务可达时执行 `location.replace(origin)`（不带 token）。认证 cookie 是 `SameSite=Strict`，`file://` → `http://127.0.0.1` 是跨站导航，服务返回 401，启动页窗口变成错误页。
2. `Retarget-HarnessWindow` 用**再启动一个 `--app=token` 浏览器进程**做“原地切换”。实测 Chromium 不会复用已有 app 窗口（同一 `--user-data-dir` + `--app-user-model-id` 也不行），第二次启动必开新窗口 → 启动页错误窗 + 新认证窗，恰好两个。批次③当时观察到“只有一个窗口”是竞态的另一半：启动页自跳发生在 retarget 之后时，启动页窗口被 navigate 掉，看不到错误页。

### 8.2 修复：DevTools 协议对同一窗口发浏览器级导航

- `Open-HarnessWindow -Boot` 启动参数追加 `--remote-debugging-port=0`（浏览器自选空闲调试端口并写入 `edge-profile\DevToolsActivePort`）。
- 服务就绪后 `Switch-BootWindowToHarness`（替代旧的 retarget 调用）：
  1. `Get-BootCdpPort`：等待 `DevToolsActivePort` 且 `/json/version` 端点存活（防残留端口文件）；
  2. `Invoke-CdpNavigateBootWindow`：从 `/json/list` 找到 `boot.html` 的 page target，用 `ClientWebSocket` 连 `webSocketDebuggerUrl` 发 `Page.navigate`（认证地址）。DevTools 导航没有发起方站点（等同地址栏输入），`SameSite=Strict` cookie 正常种下，原 target/窗口被复用——全程一个窗口。
- 回退路径（DevTools 不可用，如 profile 被无调试端口的旧浏览器进程占用）：`Retarget-HarnessWindow` 新开认证窗口后再 `Close-BootWindow`（按标题 `DeepSeek Harness 正在启动` 找窗口，只发 `WM_CLOSE`，不杀浏览器进程），短暂两个窗口后收尾为一个。为此在 `DSHNative` 新增 `GetWindowTextW` / `PostMessageW`。
- `boot.html` 不再自己跳转：只显示等待秒数/提示，45 秒后显示手动兜底链接（`hintLink` 直接打开 origin）。
- 删除批次③引入的 `auth-url.js` 中间文件及其相关函数/调用（已被 DevTools 导航取代）；`-RetargetWhenReady` 改为等就绪后执行 `Switch-BootWindowToHarness`。

### 8.3 验证（2026-09-11 03:21，实际执行）

- `dsh-tray.ps1 -Restart` 以 1 秒粒度采样所有浏览器顶层窗口标题：
  - 03:21:26 出现唯一 app 窗口（pid 38068），标题 `DeepSeek Harness 正在启动`；
  - 03:21:37 **同一 pid** 标题变为 `DeepSeek Harness`（认证完成，同一窗口）；
  - 03:21:47 标题变为会话名 `你好 AI 模型询问 — DeepSeek Harness`；
  - 全程没有出现第二个 DSH app 窗口（采样记录见临时目录 `watch.log`，已清理）；
  - `open-state.json`：`{"ok":true,"readyMs":17455,"browser":"app"}`。
- 已运行时再执行 `dsh-tray.ps1 -Open`：`readyMs=56`、`browser="app-existing"`，不开新窗。
- 截图确认窗口内容为已认证的 Harness UI（非错误页）。
- 回归复核：`GET /_dsh/dsh-desktop`（带认证 cookie）200 且 tray/shortcut 状态正常；页面注入 `__DSH_CONNECTION_RECOVERY__` 仍为 `backoffBaseMs/MaxMs=2147483647`；`POST /_dsh/github {"method":"gitpub.checkGit"}` 200（git 2.53.0.windows.1）、`{"method":"gitpub.list"}` 200（69 个插件）；harness node 进程唯一。
- 源副本与安装副本 SHA256 一致：
  - `dsh-tray.ps1` = `2032665695487E4397DBBFCE214BFA5807301FFA4D805FC8CAF7F7A52A9F73B6`
  - `boot.html` = `FE4254A56FEEE50AC38F4890A73703760C5BAE83B75B1B58A0104E3B2D590704`

### 8.4 注意

- DevTools 端口只绑定 127.0.0.1、随窗口进程存活，属本地调试通道；桌面窗口关闭即消失。
- 批次③文档里“Chromium 会复用同 profile/app-id 的 app 窗口”的说法**已被实测推翻**；8.2 的 DevTools 导航才是单窗口的可靠实现。
- 认证 401 的根因仍是 `SameSite=Strict` + 跨站发起方：任何由 `file://` 页面发起的跳转都好不了；必须保持“浏览器级”导航。
- 回滚批次④：从 `assets/dsh-tray.ps1` 与 `assets/boot.html` 还原即可；注意旧版靠“新开窗口”切换，会重新出现两个窗口。
