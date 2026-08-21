# dsh-desktop v0.7.7 交接说明

本文档用于交给下一会话的 AI 或维护者，说明本次从当前工作版同步到
`https://github.com/LvsH13/dsh-desktop` 的内容。

## 版本

- 当前版本：`0.7.7`
- 包名：`@dsh-external/dsh-desktop`
- 目标仓库：`https://github.com/LvsH13/dsh-desktop`
- 目标路径：`F:\Deepseek_Harness\.gitpub\dsh-desktop\repo`

本次没有改动目标目录的 `.git` 历史，也保留了原仓库的 `images/`、封面图和展示资源。

## 本次修复

### 1. 退出后重新打开较慢

根因是退出流程会依次执行 Harness 进程扫描、端口释放等待、桌面窗口检测和关闭；已知窗口或正常单 Node 进程仍会额外触发 WMI 扫描，快捷方式还会等待前一个退出进程结束。

现在的处理方式：

- 已记录桌面窗口 PID 时直接结束窗口，不再重复进行 WMI 窗口扫描。
- 当前直连启动的单个 Node 根进程由进程树结束，跳过不必要的完整 Node WMI 扫描。
- 只有旧版 `cmd /k npx` 根进程或检测到多个 Node 进程时，才保留完整扫描作为残留实例清理兜底。
- 没有找到 Harness 目标进程时，不再无条件等待端口释放。

### 2. 重复点击导致 Node 反复启动/关闭

旧流程虽然有服务启动互斥锁，但多个 `-Open` 进程仍可能同时进入完整的就绪等待和打开流程，退出/重开竞态下会表现为 Node 进程反复出现。

现在 `-Open`、`-OpenWeb` 和 `-Restart` 共用命名互斥锁 `DSHDesktopOpenRequest`，锁覆盖整个服务就绪和窗口打开流程：

- 第一次请求取得锁并继续执行。
- 后续快捷方式、托盘打开或重启点击立即返回，不排队、不启动第二个 Node 流程。
- 原有 `DSHDesktopHarnessLaunch` 服务启动锁仍然保留，用于开机自启动和服务级别的重复启动保护。

### 3. 托盘新增“重新启动”

托盘右键菜单新增 **重新启动**：

1. 通知已打开的 Harness 页面关闭。
2. 结束 Harness 服务和桌面窗口。
3. 等待旧实例和端口释放。
4. 只启动一个新的 Harness 实例。
5. 重新打开桌面窗口。

托盘进程本身保持运行，开机自启动配置不会被关闭或重置。

## 主要文件

| 文件 | 作用 |
| --- | --- |
| `assets/dsh-tray.ps1` | Windows 托盘、启动、退出、重启、桌面窗口和自启动核心逻辑 |
| `assets/boot.html` | Harness 冷启动期间显示的启动页 |
| `lib/index.js` | 插件宿主、状态文件、同源 API 路由和资源安装 |
| `lib/client.js` | Web 设置页客户端界面与状态刷新 |
| `package.json` | `0.7.7` 版本、GitHub 仓库元数据和 DSH bundle 声明 |
| `CHANGELOG.md` | `0.7.7` 版本修复和新增功能记录 |
| `README.md` | 中文主页、安装、使用与故障排查说明 |
| `README_EN.md` | English homepage and installation guide |

## 安装说明判断

推荐安装命令是：

```sh
dsh plugin --profile web add github:LvsH13/dsh-desktop
```

源码目录安装方式是：

```sh
git clone https://github.com/LvsH13/dsh-desktop.git
dsh plugin --profile web add "克隆后的 dsh-desktop 目录绝对路径"
```

这两种方式的前提是用户已经安装并能运行 `dsh` CLI，并且已有 DeepSeek Harness 的 Web profile。安装完成后必须重启正在运行的 Web profile，插件才会被加载。Windows 桌面功能还要求 Windows PowerShell 5.1，运行时要求 Node.js `>=20`。

文档中的 `github:LvsH13/dsh-desktop` 是 DSH 插件管理器使用的包来源标识；源码目录命令中的路径只是占位符，用户必须替换为实际绝对路径。不能把占位符原样复制执行。

当前环境没有可用于真实联网安装的 `dsh` CLI，因此无法在本机完成 GitHub 下载端到端验证；仓库结构、`package.json` 的 DSH bundle 声明和本地插件代码已经完成检查。发布后建议用一台干净环境分别验证上述两种安装方式。

## 已完成的本地验证

- PowerShell 解析检查通过。
- `node --check lib/index.js` 通过。
- `node --check lib/client.js` 通过。
- 重复启动互斥锁实测：后续请求立即返回，退出码为 `0`。
- `F:\Deepseek_Harness\_tray-race-test.ps1`：`15 passed, 0 failed`；WMI 相关测试在受限环境中按脚本规则跳过。
- `git diff --check` 无空白错误。

## 下一步建议

1. 在 Windows 真实用户环境安装/加载插件，验证托盘右键菜单是否出现 **重新启动**。
2. 测试“托盘退出 → 立即点击桌面快捷方式”以及连续点击快捷方式，确认任务管理器中只有一个 Harness Node 实例。
3. 测试开机自启动，并检查 `%LOCALAPPDATA%\dsh-desktop\autostart-method.json` 是否记录为 `task`；若任务注册失败才应为 `runkey`。
4. 检查 `git diff` 后提交并推送到 `LvsH13/dsh-desktop`，不要提交 `node_modules/` 或本地生成的 `%LOCALAPPDATA%\dsh-desktop` 文件。
