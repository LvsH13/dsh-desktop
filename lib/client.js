window.__ModuleLoader__.load({ id: "@dsh-external/dsh-desktop", factory: (require) => {
var module = { exports: {} }; var exports = module.exports;
"use strict";
var React = require("react");

var ROUTE = '/_dsh/dsh-desktop';
var NS = 'dsh-desktop';

var MESSAGES = {
  setAutoStart: '已更新开机自启动设置',
  createShortcut: '桌面快捷方式已创建',
  startTray: '托盘已启动',
  stopTray: '托盘已退出',
  open: '已切换到桌面端',
  openWeb: '已切换到网页端',
  setTerminal: '终端界面显示设置已更新',
};

function LastOpenLine({ lastOpen }) {
  if (lastOpen === null) return null;
  var browserLabel = {
    'app': '独立窗口',
    'app-existing': '独立窗口（已在运行）',
    'default': '默认浏览器',
    'none': '未能打开窗口',
  }[lastOpen.browser] ?? '未知方式';
  var timeLabel = lastOpen.readyMs === null ? '' : ' · 就绪耗时 ' + (lastOpen.readyMs / 1000).toFixed(1) + 's';
  return React.createElement('div', { className: 'dshd-lastopen' + (lastOpen.ok ? '' : ' error') },
    React.createElement('span', null, '上次打开'),
    React.createElement('strong', null, lastOpen.ok ? browserLabel + timeLabel : '失败: ' + (lastOpen.error ?? '未知错误')));
}

async function apiRequest(init) {
  var response = await fetch(ROUTE, { credentials: 'same-origin', ...init });
  var body = await response.json();
  if (!response.ok || !body.ok) {
    var failure = body;
    throw new Error(failure.error?.message ?? ('dsh-desktop 请求失败 (HTTP ' + response.status + ')'));
  }
  return body.value;
}

/** Small external store shared by the Settings route and pushed invalidations. */
class DesktopController {
  state = { status: 'idle', action: undefined, error: undefined, message: undefined, snapshot: undefined };
  listeners = new Set();
  generation = 0;
  constructor(options = {}) { this.timer = options.timer; this.refresh = options.refresh; }
  subscribe = (listener) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  snapshot = () => this.state;
  set(next) { this.state = next; for (const listener of this.listeners) listener(); }
  async load() {
    const generation = ++this.generation;
    this.set({ ...this.state, status: 'loading', error: undefined, message: undefined });
    try {
      const snapshot = await apiRequest();
      if (generation !== this.generation) return;
      this.set({ status: 'ready', snapshot, action: undefined, error: undefined, message: undefined });
    } catch (error) {
      if (generation !== this.generation) return;
      this.set({ ...this.state, status: 'error', error: error instanceof Error ? error.message : String(error) });
    }
  }
  refreshIfLoaded() {
    if (this.state.status === 'idle') return;
    void this.load();
  }
  async act(action, payload = {}) {
    this.set({ ...this.state, action, error: undefined, message: undefined });
    try {
      const snapshot = await apiRequest({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, ...payload }),
      });
      this.set({ status: 'ready', snapshot, action: undefined, error: undefined, message: action });
      // 桌面端/网页端切换由托盘脚本异步完成 (冷启动 + 打开/关闭窗口需要数秒):
      // 轮询快照直到 appWindow.active 与目标一致, 让切换按钮的文案/状态及时翻转
      if (this.timer !== undefined && this.refresh !== undefined && (action === 'open' || action === 'openWeb')) {
        const wantActive = action === 'open';
        let attempts = 0;
        const poll = () => {
          attempts += 1;
          if (attempts > 20) return; // 上限约 40 秒, 避免无限请求
          this.timer.timeout(() => {
            void this.load().then(() => {
              const current = this.state.snapshot;
              if (current !== undefined && current.appWindow.active === wantActive) return;
              poll();
            });
          }, 2000);
        };
        poll();
      }
    } catch (error) {
      this.set({ ...this.state, action: undefined, error: error instanceof Error ? error.message : String(error) });
    }
  }
}

function StatusCard(label, value, status) {
  return React.createElement('div', { className: 'dshd-card', 'data-status': status },
    React.createElement('span', null, label),
    React.createElement('strong', null, value));
}

function SettingsSection({ controller }) {
  if (controller === undefined) return null;
  return React.createElement(DesktopView, { controller });
}

function DesktopView({ controller }) {
  const state = React.useSyncExternalStore(controller.subscribe, controller.snapshot, controller.snapshot);
  const snapshot = state.snapshot;
  React.useEffect(() => { if (state.status === 'idle') void controller.load(); }, [controller, state.status]);
  // 周期刷新状态: 桌面窗口可能被托盘/快捷方式/开机自启动打开或关闭, 让
  // "切换桌面端/切换网页端"按钮与状态卡片始终反映真实模式 (页面隐藏或操作进行中时跳过)。
  const timer = controller.timer;
  React.useEffect(() => {
    if (timer === undefined) return;
    const refresh = () => {
      if (document.hidden) return;
      if (state.action !== undefined) return;
      controller.refreshIfLoaded();
    };
    const dispose = timer.interval(refresh, 5000);
    const onVisibility = () => { if (!document.hidden) refresh(); };
    document.addEventListener('visibilitychange', onVisibility);
    return () => { dispose(); document.removeEventListener('visibilitychange', onVisibility); };
  }, [timer, controller, state.action]);
  if (state.status === 'idle' || (state.status === 'loading' && snapshot === undefined)) {
    return React.createElement('div', { className: 'dshd-settings' },
      React.createElement('div', { className: 'dshd-loading' }, '加载中…'));
  }
  if (snapshot === undefined) {
    return React.createElement('div', { className: 'dshd-settings' },
      React.createElement('div', { className: 'dshd-alert error' }, state.error ?? '无法连接桌面端服务'),
      React.createElement('button', { className: 'dshd-btn', onClick: () => { void controller.load(); } }, '重试'));
  }
  const busy = state.action !== undefined;
  const s = snapshot;
  const value = s.settings.value;
  return React.createElement('div', { className: 'dshd-settings' },
    React.createElement('header', { className: 'dshd-header' },
      React.createElement('div', { className: 'dshd-header-copy' },
        React.createElement('span', { className: 'dshd-kicker' }, 'DSH 桌面端'),
        React.createElement('h2', null, '桌面端'),
        React.createElement('p', null, '系统托盘黑鲸图标、桌面快捷方式与开机自启动，可与网页端一键互切。')),
      React.createElement('div', { className: 'dshd-release' },
        React.createElement('span', null, React.createElement('span', null, '服务地址'), React.createElement('strong', null, s.origin.replace('http://', ''))),
        React.createElement('span', null, React.createElement('span', null, '安装目录'), React.createElement('strong', null, s.appDir)))),
    LastOpenLine({ lastOpen: s.lastOpen }),
    !s.writable ? React.createElement('div', { className: 'dshd-alert warning' }, '当前 Settings 提供方为只读，无法修改开机自启动。') : null,
    state.error === undefined ? null : React.createElement('div', { className: 'dshd-alert error' }, state.error),
    state.message === undefined ? null : React.createElement('div', { className: 'dshd-alert success' }, MESSAGES[state.message] ?? state.message),
    React.createElement('section', { className: 'dshd-panel' },
      React.createElement('div', { className: 'dshd-panel-title' },
        React.createElement('h3', null, '状态'),
        React.createElement('p', null, '桌面端各部分的实时状态。')),
      React.createElement('div', { className: 'dshd-grid' },
        StatusCard('Harness 服务', s.harness.reachable ? '运行中' : '未运行', s.harness.reachable ? 'ok' : 'error'),
        StatusCard('系统托盘', s.tray.running ? '运行中' : '未运行', s.tray.running ? 'ok' : 'idle'),
        StatusCard('桌面窗口', s.appWindow.active ? '运行中' : '未运行', s.appWindow.active ? 'ok' : 'idle'),
        StatusCard('桌面快捷方式', s.shortcut.exists ? '已创建' : '未创建', s.shortcut.exists ? 'ok' : 'idle'),
        StatusCard('开机自启动', value.autoStart ? '已开启' : '已关闭', value.autoStart ? 'ok' : 'idle'),
        StatusCard('终端界面', value.showTerminal ? '显示中' : '已隐藏', value.showTerminal ? 'ok' : 'idle'))),
    React.createElement('section', { className: 'dshd-panel' },
      React.createElement('div', { className: 'dshd-panel-title' },
        React.createElement('h3', null, '开机自启动'),
        React.createElement('p', null, '登录 Windows 后自动在系统托盘显示 Harness 图标。')),
      React.createElement('label', { className: 'dshd-row' },
        React.createElement('span', { className: 'dshd-row-label' },
          React.createElement('strong', null, '开机自动启动桌面端'),
          React.createElement('small', null, '注册任务计划程序登录触发器（登录即刻启动，不被启动项队列拖慢；不可用时回退 HKCU Run），无需管理员权限')),
        React.createElement('input', {
          type: 'checkbox',
          className: 'dshd-switch',
          checked: !!value.autoStart,
          disabled: busy || !s.writable,
          onChange: (e) => { void controller.act('setAutoStart', { enabled: e.target.checked, expectedRevision: s.settings.revision }); },
        }))),
    React.createElement('section', { className: 'dshd-panel' },
      React.createElement('div', { className: 'dshd-panel-title' },
        React.createElement('h3', null, '操作'),
        React.createElement('p', null, '桌面端与网页端一键互切，切换时另一端自动关闭。')),
      React.createElement('div', { className: 'dshd-actions' },
        React.createElement('button', {
          className: 'dshd-btn primary',
          disabled: busy,
          onClick: () => { void controller.act(s.appWindow.active ? 'openWeb' : 'open'); },
        }, s.appWindow.active ? '切换网页端' : '切换桌面端'),
        React.createElement('button', { className: 'dshd-btn', disabled: busy, onClick: () => { void controller.act('startTray'); } }, '启动托盘'),
        React.createElement('button', { className: 'dshd-btn', disabled: busy, onClick: () => { void controller.act('stopTray'); } }, '退出托盘'),
        React.createElement('button', { className: 'dshd-btn', disabled: busy, onClick: () => { void controller.act('createShortcut'); } }, '创建桌面快捷方式'),
        React.createElement('button', { className: 'dshd-btn', disabled: busy, onClick: () => { void controller.act('setTerminal', { visible: !value.showTerminal, expectedRevision: s.settings.revision }); } }, value.showTerminal ? '隐藏终端界面' : '显示终端界面'))));
}

var CSS = `
.dshd-settings{display:grid;gap:14px;max-width:900px;padding:8px 2px 32px;color:var(--dsw-alias-fg-primary,#26231f)}
.dshd-header{display:flex;flex-wrap:wrap;justify-content:space-between;gap:14px 20px;align-items:flex-start;padding:8px 2px}
.dshd-header-copy{min-width:0;flex:1 1 320px}
.dshd-header h2{font-size:25px;letter-spacing:-.025em;margin:3px 0 6px;white-space:nowrap}
.dshd-header p{max-width:620px;margin:0;color:var(--dsw-alias-fg-muted,#77736d);font-size:13px;line-height:1.55}
.dshd-kicker{font-size:10px;text-transform:uppercase;letter-spacing:.1em;color:#6758d4;font-weight:700}
.dshd-release{display:grid;gap:4px;flex:1 1 240px;min-width:0;padding:9px 11px;border-radius:10px;background:var(--dsw-alias-bg-layer-2,#f7f5f1);font-size:10px;color:var(--dsw-alias-fg-muted,#77736d)}
.dshd-release span{display:flex;justify-content:space-between;gap:12px}
.dshd-release strong{color:var(--dsw-alias-fg-primary,#26231f);font-weight:650;min-width:0;overflow-wrap:anywhere;text-align:right}
.dshd-lastopen{display:flex;align-items:center;justify-content:space-between;gap:4px 12px;padding:8px 12px;border-radius:10px;background:var(--dsw-alias-bg-layer-2,#f7f5f1);font-size:12px;flex-wrap:wrap}
.dshd-lastopen span{color:var(--dsw-alias-fg-muted,#77736d)}
.dshd-lastopen strong{font-weight:650;min-width:0;text-align:right}
.dshd-lastopen.error{background:rgba(205,72,72,.1);color:#aa3939}
.dshd-alert{padding:10px 12px;border-radius:10px;font-size:12px;line-height:1.5}
.dshd-alert.warning{background:rgba(224,162,55,.12);color:#986818}
.dshd-alert.error{background:rgba(205,72,72,.1);color:#aa3939}
.dshd-alert.success{background:rgba(48,154,100,.1);color:#267d52}
.dshd-panel{display:grid;gap:12px;padding:15px;border:1px solid var(--dsw-alias-border-subtle,#dedbd5);border-radius:14px;background:var(--dsw-alias-bg-layer-1,#fff);box-shadow:0 1px 1px rgba(0,0,0,.02)}
.dshd-panel-title{display:grid;gap:4px}
.dshd-panel-title h3{font-size:14px;margin:0}
.dshd-panel-title p{font-size:11px;line-height:1.45;color:var(--dsw-alias-fg-muted,#77736d);margin:0;max-width:620px}
.dshd-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px}
.dshd-card{padding:10px 12px;border-radius:9px;background:var(--dsw-alias-bg-layer-2,#f7f5f1);display:grid;gap:5px;border-left:3px solid #aaa}
.dshd-card[data-status=ok]{border-left-color:#39a66b}
.dshd-card[data-status=error]{border-left-color:#cf5050}
.dshd-card span{font-size:10px;text-transform:uppercase;letter-spacing:.06em;color:var(--dsw-alias-fg-muted,#77736d)}
.dshd-card strong{font-size:13px}
.dshd-row{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:4px 2px;cursor:pointer}
.dshd-row-label{display:grid;gap:3px}
.dshd-row-label strong{font-size:13px}
.dshd-row-label small{font-size:11px;color:var(--dsw-alias-fg-muted,#77736d)}
.dshd-switch{appearance:none;-webkit-appearance:none;width:40px;height:22px;border-radius:999px;background:#c8c4bc;position:relative;cursor:pointer;transition:background .15s ease;flex:none;margin:0}
.dshd-switch::after{content:'';position:absolute;top:2px;left:2px;width:18px;height:18px;border-radius:50%;background:#fff;transition:transform .15s ease;box-shadow:0 1px 2px rgba(0,0,0,.25)}
.dshd-switch:checked{background:#6758d4}
.dshd-switch:checked::after{transform:translateX(18px)}
.dshd-switch:disabled{opacity:.5;cursor:default}
.dshd-actions{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.dshd-btn{display:inline-flex;align-items:center;height:30px;padding:0 14px;border-radius:8px;border:1px solid var(--dsw-alias-border-subtle,#dedbd5);background:var(--dsw-alias-bg-layer-1,#fff);color:inherit;font-size:12px;font-weight:600;cursor:pointer;flex:none}
.dshd-btn:hover:not(:disabled){border-color:#b9aef0;color:#6758d4}
.dshd-btn.primary{background:#6758d4;border-color:#6758d4;color:#fff}
.dshd-btn.primary:hover:not(:disabled){background:#5a4cc4}
.dshd-btn:disabled{opacity:.5;cursor:default}
.dshd-loading{padding:24px;border-radius:12px;background:var(--dsw-alias-bg-layer-2,#f7f5f1);font-size:12px;color:var(--dsw-alias-fg-muted,#77736d)}
@media(max-width:720px){.dshd-header{display:grid}.dshd-release{width:auto}}
`;

function installStyles() {
  const id = '@dsh-external/dsh-desktop/client';
  const existing = document.querySelector('style[data-plugin-css="' + id + '"]');
  if (existing !== null) return () => { };
  const style = document.createElement('style');
  style.dataset.plugin = '@dsh-external/dsh-desktop';
  style.dataset.pluginCss = id;
  style.textContent = CSS;
  document.head.appendChild(style);
  return () => { style.remove(); };
}

/** Required client services. */
exports.inject = ['slots'];
/** Register the desktop Settings section. */
function apply(ctx) {
  ctx.effect(installStyles, 'dsh-desktop: styles');
  const timer = ctx.get('timer');
  const controller = new DesktopController({ timer, refresh: () => controller.refreshIfLoaded() });
  ctx.effect(() => {
    const disposers = [
      ctx.on('settings/changed', (namespace) => {
        if (namespace === NS) controller.refreshIfLoaded();
      }),
      ctx.on('connection/reset', () => { controller.refreshIfLoaded(); }),
    ];
    return () => { for (const dispose of disposers) dispose(); };
  }, 'dsh-desktop: Settings invalidations');
  // 托盘"退出"时宿主会通过 SSE 推送 quit 事件: 收到后自动关闭本标签页。
  ctx.effect(() => {
    const source = new EventSource(ROUTE + '/events');
    const onQuit = () => {
      source.close();
      // 只有脚本打开的窗口才允许 window.close(), 先通过 window.open('', '_self')
      // 把当前标签页标记为脚本打开, 再关闭 (Chrome/Edge/Firefox 通用技巧)。
      try { window.open('', '_self'); } catch (error) { /* ignore */ }
      try { window.close(); } catch (error) { /* ignore */ }
    };
    source.addEventListener('quit', onQuit);
    return () => { source.close(); };
  }, 'dsh-desktop: quit signal');
  ctx.slots.inject('settings.section', () => ctx.slots.register({
    name: 'settings.section',
    id: 'dsh-desktop',
    order: 40,
    label: () => '桌面端',
    inject: () => ({ controller }),
  }, SettingsSection));
}
exports.apply = apply;
return module.exports; } });
