(() => {
  'use strict';

  // Everything is derived from one local clock, so pause and seeking freeze the
  // camera, character, game, cursor and notifications at exactly the same frame.
  const $ = (id) => document.getElementById(id);
  const sceneButtons = [...document.querySelectorAll('[data-select-scene]')];
  const themeMedia = matchMedia('(prefers-color-scheme: dark)');
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const params = new URLSearchParams(location.search);
  const aliases = { away: 'long', desk: 'short', desktop: 'short' };
  const requestedScene = aliases[params.get('scene')] || params.get('scene');
  let scene = requestedScene === 'short' ? 'short' : 'long';
  const durations = { long: 24, short: 14 };
  const titles = { long: '长通知', short: '短通知' };
  const descriptions = {
    long: '长通知短片：把复杂任务交给 Agent，离开电脑休息。电脑屏幕变暗，Agent 继续工作。手机游戏画面上出现飞书通知，打开后确认任务已完成，再回到电脑验收。',
    short: '短通知短片：三个独立的 Agent 窗口同时工作。右上角出现 macOS 通知，用户选择对应窗口的标题栏，回复问题，再切回继续工作。第二条通知到来后，切到测试窗口检查结果。'
  };
  const clamp = (value, min = 0, max = 1) => Math.min(max, Math.max(min, value));
  const mix = (a, b, amount) => a + (b - a) * amount;
  const smooth = (value) => { const n = clamp(value); return n * n * (3 - 2 * n); };
  const between = (time, start, end) => smooth((time - start) / (end - start));
  const windowAt = (time, start, end, fade = 0.35) => between(time, start, start + fade) * (1 - between(time, end - fade, end));
  const rawTime = Number(params.get('t'));
  let time = params.has('t') && Number.isFinite(rawTime)
    ? clamp(rawTime, 0, durations[scene])
    : reducedMotion.matches ? (scene === 'long' ? 12 : 3.5) : 0;
  let playing = params.get('paused') !== '1' && !reducedMotion.matches;
  let narrow = false;
  let scrubbing = false;
  let raf = 0;
  let previousStamp = null;
  let currentShot = '';
  let selectedTheme = 'system';

  const nodes = {};
  document.querySelectorAll('[id]').forEach((element) => { nodes[element.id] = element; });
  const text = (id, value) => { if (nodes[id].textContent !== String(value)) nodes[id].textContent = value; };
  const opacity = (id, value) => { nodes[id].style.opacity = clamp(value).toFixed(3); };
  const display = (id, visible, mode = '') => { nodes[id].style.display = visible ? mode : 'none'; };

  // Pose keyframes are [seconds, x, y, scale, opacity, rotation]. They use canvas
  // coordinates, not viewport pixels. The actual screen keeps a 16:10 ratio.
  function sample(at, frames) {
    let from = frames[0];
    let to = from;
    for (let i = 1; i < frames.length; i += 1) {
      to = frames[i];
      if (at <= to[0]) break;
      from = to;
    }
    const amount = from === to ? 0 : between(at, from[0], to[0]);
    return from.slice(1).map((value, index) => mix(value, to[index + 1], amount));
  }

  function pose(id, values) {
    const [x, y, scale = 1, alpha = 1, angle = 0] = values;
    nodes[id].style.transform = 'translate3d(' + x.toFixed(2) + 'px,' + y.toFixed(2) + 'px,0) scale(' + scale.toFixed(4) + ') rotate(' + angle.toFixed(3) + 'deg)';
    nodes[id].style.opacity = alpha.toFixed(3);
  }

  function cursor(at, frames, clicks) {
    const [x, y, alpha = 1] = sample(at, frames);
    nodes['mac-cursor'].style.transform = 'translate(' + x + 'px,' + y + 'px)';
    opacity('mac-cursor', alpha);
    let ripple = 0;
    let size = 0.5;
    clicks.forEach((moment) => {
      const age = at - moment;
      if (age >= 0 && age < 0.5) { ripple = 1 - age / 0.5; size = 0.5 + age * 2.1; }
    });
    const ring = nodes['mac-cursor'].querySelector('i');
    ring.style.opacity = ripple;
    ring.style.transform = 'scale(' + size + ')';
  }

  const longShots = [
    { at: 0, id: 'mission', eyebrow: '长通知 / 01 · 交给 AGENT', title: '这个任务，\n有点难。', subtitle: '重构、回归测试、兼容性检查。', caption: '长任务交给 Agent，注意力还给自己。', copy: [88, 245, 1, 1, 0], width: 440 },
    { at: 2.8, id: 'busy', eyebrow: '长通知 / 02 · 放心离开', title: '它继续忙。\n你先歇一会。', subtitle: '屏幕暗下来，工作还在继续。', caption: '时间快进 · Agent 仍在推进任务', copy: [88, 245, 0.93, 1, 0], width: 430 },
    { at: 5.7, id: 'break', eyebrow: '长通知 / 03 · 把时间还给你', title: '喝杯咖啡。\n再玩一小局。', subtitle: '', caption: '电脑还在工作，你可以做点别的。', copy: [105, 104, 0.9, 1, 0], width: 680 },
    { at: 10.5, id: 'alert', eyebrow: '长通知 / 04 · 消息来了', title: '叮，\n是 Agent。', subtitle: '任务完成，手机上的提醒找到你。', caption: '已启用飞书，并订阅 stop 事件 · 延迟按配置触发', copy: [105, 225, 1, 1, 0], width: 600 },
    { at: 14.1, id: 'message', eyebrow: '长通知 / 05 · 打开看看', title: '难的部分，\n已经做完了。', subtitle: '重构完成，测试通过。等你验收。', caption: '打开飞书，先看清 Agent 的结果摘要。', copy: [105, 250, 0.94, 1, 0], width: 640 },
    { at: 18.1, id: 'return', eyebrow: '长通知 / 06 · 回到电脑', title: '回来，\n刚好验收。', subtitle: '打开变更，检查结果。', caption: '回到电脑，继续对应会话。', copy: [88, 260, 0.93, 1, 0], width: 410 },
    { at: 22.2, id: 'complete', eyebrow: '长通知 / 让等待有个回音', title: '放心离开，\n及时回来。', subtitle: 'cc-notify-hooks', caption: '长通知 · 这一支短片将独立循环', copy: [88, 260, 0.93, 1, 0], width: 440 }
  ];
  const shortShots = [
    { at: 0, id: 'parallel', eyebrow: '短通知 / 01 · 多窗口并行', title: '多开几窗，也能专心做事。', subtitle: 'Claude Code、Codex、dsh，各自推进。', caption: '三个独立窗口，三个独立会话。' },
    { at: 2.4, id: 'notify-api', eyebrow: '短通知 / 02 · 及时提醒', title: '哪个会话需要你，一眼就知道。', subtitle: 'macOS 通知出现在屏幕右上角。', caption: 'Codex 需要确认接口兼容策略。' },
    { at: 4.3, id: 'focus-api', eyebrow: '短通知 / 03 · 切回对应窗口', title: '切回来，答一句。', subtitle: '选择对应窗口，Agent 就能继续。', caption: '手动选择窗口标题栏，继续这段会话。' },
    { at: 6.7, id: 'continue', eyebrow: '短通知 / 04 · 各自继续', title: '回复完，继续眼前的事。', subtitle: '宿主报告会话继续后，后续待发提醒取消。', caption: '已发出的消息保留，取消的是尚未发送的提醒。' },
    { at: 8.2, id: 'notify-tests', eyebrow: '短通知 / 05 · 另一个好消息', title: '测试好了，也会告诉你。', subtitle: '不必在几个窗口之间反复查看。', caption: 'dsh 的回合已结束，86 项测试通过。' },
    { at: 9.7, id: 'focus-tests', eyebrow: '短通知 / 06 · 轮到你验收', title: '切到结果，接着往前。', subtitle: '窗口之间轻轻一换，注意力就位。', caption: '选择 test-suite 窗口，检查测试结果。' },
    { at: 12.2, id: 'short-complete', eyebrow: '短通知 / 让并行更从容', title: '你专注，通知负责提醒。', subtitle: 'cc-notify-hooks', caption: '短通知 · 这一支短片将独立循环' }
  ];

  function applyShot(shots, at) {
    const shot = [...shots].reverse().find((item) => at >= item.at) || shots[0];
    if (currentShot !== shot.id) {
      currentShot = shot.id;
      nodes.film.dataset.shot = shot.id;
      text('shot-eyebrow', shot.eyebrow);
      nodes['shot-title'].replaceChildren(...shot.title.split('\n').flatMap((line, index) => index ? [document.createElement('br'), document.createTextNode(line)] : [document.createTextNode(line)]));
      text('shot-subtitle', shot.subtitle);
      nodes['shot-subtitle'].hidden = !shot.subtitle;
      text('caption-text', shot.caption);
      nodes['story-copy'].style.width = (shot.width || 1400) + 'px';
    }
    const reveal = between(at, shot.at, shot.at + 0.35);
    const base = shot.copy || [100, 70, 1, 1, 0];
    pose('story-copy', [base[0], base[1] + (1 - reveal) * 13, base[2], 0.35 + reveal * 0.65, 0]);
  }

  function renderLong(at) {
    applyShot(longShots, at);
    pose('laptop', sample(at, [
      [0, 535, 155, 0.88, 1, 0], [2.8, 535, 155, 0.88, 1, 0],
      [3.5, 500, 150, 0.92, 1, 0], [4.7, 500, 150, 0.92, 1, 0],
      [5.9, 92, 326, 0.62, 1, 0], [9.9, 92, 326, 0.62, 1, 0],
      [10.9, -70, 490, 0.39, 0, 0], [17.5, -70, 490, 0.39, 0, 0],
      [18.7, 505, 155, 0.9, 1, 0], [24, 505, 155, 0.9, 1, 0]
    ]));
    pose('person', sample(at, [
      [0, 790, 260, 1.4, 0, 0], [4.8, 790, 260, 1.4, 0, 0],
      [5.9, 790, 230, 1.4, 1, 0], [9.9, 790, 230, 1.4, 1, 0],
      [10.9, 605, 445, 0.8, 0.3, 0], [17.5, 605, 445, 0.8, 0.3, 0],
      [18.5, 350, 495, 0.68, 0, 0], [24, 350, 495, 0.68, 0, 0]
    ]));
    const phonePose = sample(at, [
      [0, 1280, 410, 0.62, 0, 0], [5, 1280, 410, 0.62, 0, 0],
      [5.9, 1280, 410, 0.62, 1, 0], [9.9, 1280, 410, 0.62, 1, 0],
      [10.9, 1040, 110, 1.18, 1, 0], [17.5, 1040, 110, 1.18, 1, 0],
      [18.6, 1440, 620, 0.35, 0, 7], [24, 1440, 620, 0.35, 0, 7]
    ]);
    const buzz = windowAt(at, 11.15, 11.6, 0.08) * Math.sin((at - 11.15) * 58);
    phonePose[0] += buzz * 4;
    phonePose[4] += buzz * 1.2;
    pose('phone', phonePose);
    const roomAmount = windowAt(at, 4.9, 18.6, 0.9);
    opacity('table-scene', roomAmount);
    nodes['table-scene'].style.transform = 'translateY(' + (1 - roomAmount) * 30 + 'px)';
    document.querySelector('.room-shelf').style.opacity = '0';
    document.querySelector('.room-plant').style.opacity = roomAmount;
    const dim = between(at, 3.5, 5.1) * (1 - between(at, 18, 18.8));
    opacity('screen-dim', dim * 0.6);

    const prompt = '重构结算模块，补齐回归测试，再检查兼容性。';
    text('task-prompt-text', prompt.slice(0, Math.max(1, Math.floor(clamp((at - 0.35) / 1.65) * prompt.length))));
    opacity('prompt-caret', at < 2.1 ? (Math.sin(at * 12) > 0 ? 1 : 0) : 0);
    display('task-work', at < 18.1);
    display('task-review', at >= 18.1, 'block');
    document.querySelector('.task-prompt').style.visibility = at >= 18.1 ? 'hidden' : 'visible';
    opacity('task-work', between(at, 1.95, 2.4));
    const progress = clamp((at - 2) / 7.7);
    nodes['agent-progress'].style.width = (6 + progress * 94) + '%';
    const checked = Math.floor(progress * 4.01);
    for (let i = 1; i <= 4; i += 1) nodes['check-' + i].className = i <= checked ? 'done' : i === checked + 1 ? 'active' : '';
    const stages = ['正在分析支付链路', '重构模块，保留旧接口', '正在补齐回归测试', '生成变更说明', '工作完成，等你回来'];
    text('work-heading', stages[Math.min(4, checked)]);
    const seconds = Math.floor(2 + progress * 1258);
    text('work-clock', String(Math.floor(seconds / 60)).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0'));
    const scroll = at > 9.7 ? 107 : Math.max(0, (at - 2.3) * 71) % 108;
    nodes['work-log'].style.transform = 'translateY(-' + scroll.toFixed(1) + 'px)';
    text('terminal-status', progress >= 1 ? 'Done · waiting for your review' : 'Working · no need to keep watching');
    opacity('fast-forward', windowAt(at, 2.9, 10.2));
    nodes['review-file'].classList.toggle('opened', at > 20.25);
    opacity('review-done', between(at, 21.6, 22.2));

    // A small sip, blink and continuous game provide visible life between cuts.
    const sip = windowAt(at, 6.5, 9.1, 0.7);
    nodes['coffee-arm'].setAttribute('transform', 'translate(' + (-78 * sip).toFixed(1) + ',' + (-22 * sip).toFixed(1) + ') rotate(' + (-12 * sip).toFixed(1) + ' 300 250)');
    nodes['coffee-steam'].style.opacity = (0.45 + 0.3 * Math.sin(at * 3)).toFixed(3);
    nodes['coffee-steam'].setAttribute('transform', 'translate(0,' + (-3 - Math.sin(at * 2) * 3).toFixed(1) + ')');
    const blinkPhase = at % 3.2;
    const blink = blinkPhase > 2.9 && blinkPhase < 3.08 ? 0.13 : 1;
    nodes['person-eyes'].setAttribute('transform', 'translate(0,' + (151 * (1 - blink)) + ') scale(1,' + blink + ')');
    opacity('break-bubble', windowAt(at, 6, 10.5, 0.4));
    const gameTime = Math.min(at, 14.1);
    const jumpPhase = (gameTime * 0.53) % 1;
    const gameX = 42 + (Math.sin(gameTime * 1.5) + 1) * 49;
    const gameY = 280 - Math.sin(jumpPhase * Math.PI) * 112;
    nodes['game-character'].style.transform = 'translate(' + gameX.toFixed(1) + 'px,' + gameY.toFixed(1) + 'px) rotate(' + (Math.sin(gameTime * 4) * 8).toFixed(1) + 'deg)';
    text('game-score', 240 + Math.floor(gameTime * 1.5) * 10);
    opacity('game-combo', 0.4 + 0.6 * Math.max(0, Math.sin(gameTime * 3)));
    const wallMinutes = 14 * 60 + 32 + Math.round(progress * 21) + Math.round(between(at, 9.7, 10.7) * 5);
    const wallClock = String(Math.floor(wallMinutes / 60)).padStart(2, '0') + ':' + String(wallMinutes % 60).padStart(2, '0');
    text('phone-time', wallClock);
    text('mac-time', 'Mon ' + wallClock);
    const notice = between(at, 11.05, 11.55) * (1 - between(at, 14.1, 14.45));
    nodes['phone-banner'].style.transform = 'translateY(' + ((1 - notice) * -150).toFixed(1) + 'px)';
    opacity('phone-banner', notice);
    const message = between(at, 14.12, 14.6);
    nodes['phone-message'].style.transform = 'translateY(' + ((1 - message) * 90).toFixed(1) + 'px) scale(' + (0.96 + message * 0.04).toFixed(4) + ')';
    opacity('phone-message', message);
    opacity('phone-tap', windowAt(at, 13.7, 14.35, 0.2));
    for (let i = 1; i <= 3; i += 1) {
      const reveal = between(at, 14.6 + i * 0.5, 15 + i * 0.5);
      opacity('message-result-' + i, reveal);
      nodes['message-result-' + i].style.transform = 'translateY(' + (1 - reveal) * 9 + 'px)';
    }
    opacity('time-jump', windowAt(at, 10.7, 14, 0.35));
    opacity('confetti', windowAt(at, 22.05, 24, 0.45));
    nodes.confetti.style.transform = 'translateY(' + (12 - (at - 22) * 12).toFixed(1) + 'px)';
    opacity('focus-ribbon', 0);
    opacity('pending-cancelled', 0);
    opacity('mac-toast', 0);
    cursor(at, [
      [0, 540, 220, 0], [1.4, 620, 160, 1], [2.05, 620, 160, 1], [2.45, 620, 160, 0],
      [18.8, 720, 410, 0], [19.3, 720, 410, 1], [20.2, 480, 264, 1], [20.7, 480, 264, 1],
      [21.6, 640, 438, 1], [22.7, 640, 438, 1], [23.3, 640, 438, 0], [24, 640, 438, 0]
    ], [2.05, 20.25, 21.8]);
  }

  function renderShort(at) {
    applyShot(shortShots, at);
    text('mac-time', 'Mon 14:32');
    pose('laptop', sample(at, [
      [0, 325, 181, 0.88, 1, 0], [2.2, 325, 181, 0.88, 1, 0],
      [2.9, 314, 176, 0.9, 1, 0], [11.8, 314, 176, 0.9, 1, 0],
      [12.6, 325, 181, 0.88, 1, 0], [14, 325, 181, 0.88, 1, 0]
    ]));
    const apiFrames = [
      [0, 36, 49, 0.96, 1, 0], [4.15, 36, 49, 0.96, 1, 0],
      [4.75, 62, 86, 1, 1, 0], [6.7, 62, 86, 1, 1, 0],
      [7.2, 36, 49, 0.96, 1, 0], [9.5, 36, 49, 0.96, 1, 0],
      [10.1, 36, 49, 0.93, 1, 0], [14, 36, 49, 0.93, 1, 0]
    ];
    const testsFrames = [
      [0, 222, 96, 0.97, 1, 0], [4.15, 222, 96, 0.97, 1, 0],
      [4.75, 227, 58, 0.96, 1, 0], [6.7, 227, 58, 0.96, 1, 0],
      [7.2, 222, 96, 0.97, 1, 0], [9.5, 222, 96, 0.97, 1, 0],
      [10.1, 180, 115, 1.04, 1, 0], [14, 180, 115, 1.04, 1, 0]
    ];
    const webFrames = [
      [0, 112, 147, 1, 1, 0], [4.15, 112, 147, 1, 1, 0],
      [4.75, 176, 169, 0.93, 1, 0], [6.7, 176, 169, 0.93, 1, 0],
      [7.2, 112, 147, 1, 1, 0], [9.5, 112, 147, 1, 1, 0],
      [10.1, 85, 158, 0.94, 1, 0], [14, 85, 158, 0.94, 1, 0]
    ];
    pose('api-window', sample(at, apiFrames));
    pose('tests-window', sample(at, testsFrames));
    pose('web-window', sample(at, webFrames));
    const focus = at >= 9.7 ? 'tests' : at >= 4.3 && at < 6.9 ? 'api' : 'web';
    ['api', 'tests', 'web'].forEach((name) => {
      nodes[name + '-window'].style.zIndex = name === focus ? '5' : name === 'web' || (name === 'tests' && focus === 'web') ? '3' : '2';
      nodes[name + '-window'].classList.toggle('is-focused', name === focus);
    });
    const answered = at >= 5.65;
    nodes['api-answer'].classList.toggle('answered', answered);
    nodes['api-footer'].classList.toggle('resumed', answered);
    text('api-heading', at < 2 ? '正在更新接口' : answered ? '已确认，继续更新接口' : '需要你确认一个选择');
    text('api-description', answered ? '保留 /v1，开始实现 /v2 与兼容测试。' : '迁移逻辑已准备好，需要确认兼容策略。');
    text('api-footer', answered ? '✓ 已收到回复，Agent 继续工作' : '等待你的选择');
    const testsDone = at >= 7.8;
    text('tests-count', testsDone ? 86 : Math.min(85, Math.floor(48 + at * 4.7)));
    text('tests-heading', testsDone ? '全部通过，结果已就绪。' : '回归测试运行中');
    text('tests-badge', testsDone ? 'ALL PASSED' : 'RUNNING');
    nodes['tests-badge'].classList.toggle('passed', testsDone);
    text('tests-footer', testsDone ? '✓ 86 项测试通过 · 可以开始验收' : '正在检查剩余异常分支…');
    const webPrompt = at > 6.9 ? '很好，接下来调整移动端间距。' : '标题再简洁一点，让重点更突出。';
    const typing = at > 6.9 ? clamp((at - 6.9) / 1.1) : clamp((at + 0.3) / 1.8);
    text('web-input-text', webPrompt.slice(0, Math.floor(typing * webPrompt.length)));
    document.querySelector('.mini-site-shape').style.transform = 'rotate(' + (11 + Math.sin(at * 2) * 4) + 'deg) translateY(' + (Math.sin(at * 2.5) * 3) + 'px)';
    document.querySelector('.web-input .text-caret').style.opacity = Math.sin(at * 11) > 0 ? '1' : '0';
    const firstToast = windowAt(at, 2.45, 5.1, 0.36);
    const secondToast = windowAt(at, 8.25, 10.7, 0.36);
    const toast = Math.max(firstToast, secondToast);
    opacity('mac-toast', toast);
    nodes['mac-toast'].style.transform = 'translateX(' + ((1 - toast) * 365).toFixed(1) + 'px)';
    text('toast-title', at >= 8 ? 'dsh · 任务完成' : 'Codex · 需要回复');
    text('toast-project', at >= 8 ? '[test-suite] 回归测试已完成' : '[api-service] 确认兼容策略');
    text('toast-message', at >= 8 ? '86 项测试通过，等你检查结果。' : '保留旧版接口，还是直接替换？');
    opacity('pending-cancelled', windowAt(at, 5.9, 7.8, 0.3));
    opacity('focus-ribbon', 0);
    opacity('screen-dim', 0);
    opacity('person', 0);
    opacity('phone', 0);
    opacity('table-scene', 0);
    opacity('time-jump', 0);
    opacity('confetti', windowAt(at, 12.1, 14, 0.4));
    nodes.confetti.style.transform = 'translateY(' + (10 - (at - 12) * 8) + 'px)';
    document.querySelector('.room-shelf').style.opacity = '0';
    document.querySelector('.room-plant').style.opacity = '0';
    cursor(at, [
      [0, 600, 458, 1], [2.8, 612, 458, 1], [3.5, 612, 458, 1],
      [4.15, 265, 64, 1], [4.28, 265, 64, 1], [4.78, 290, 102, 1],
      [5.58, 334, 282, 1], [6.1, 334, 282, 1],
      [6.75, 788, 185, 1], [7.22, 770, 163, 1], [7.7, 600, 455, 1],
      [8.8, 600, 455, 1], [9.5, 400, 111, 1], [9.68, 400, 111, 1],
      [10.1, 363, 132, 1], [10.7, 620, 355, 1], [12, 650, 430, 1],
      [12.8, 650, 430, 0], [14, 650, 430, 0]
    ], [4.25, 5.65, 6.9, 9.68, 11.1]);
  }

  function formatTime(seconds) { return '00:' + String(Math.floor(seconds)).padStart(2, '0'); }
  function canRun() { return playing && !document.hidden && !narrow && !scrubbing; }

  function updateControls() {
    nodes.timeline.max = durations[scene];
    if (!scrubbing) nodes.timeline.value = time.toFixed(2);
    nodes.timeline.setAttribute('aria-valuetext', titles[scene] + '，' + Math.floor(time) + ' 秒，共 ' + durations[scene] + ' 秒');
    text('elapsed', formatTime(time) + ' / ' + formatTime(durations[scene]));
    nodes['play-toggle'].setAttribute('aria-label', playing ? '暂停演示' : '播放演示');
    nodes['play-icon'].setAttribute('href', playing ? '#i-pause' : '#i-play');
    text('playback-state', playing ? titles[scene] + ' · 独立循环' : '已暂停 · ' + titles[scene]);
  }

  function render() {
    nodes.film.dataset.scene = scene;
    if (scene === 'long') renderLong(time); else renderShort(time);
    updateControls();
  }

  function tick(stamp) {
    raf = 0;
    if (!canRun()) { previousStamp = null; return; }
    if (previousStamp !== null) time += Math.min((stamp - previousStamp) / 1000, 0.1);
    previousStamp = stamp;
    if (time >= durations[scene]) { time %= durations[scene]; currentShot = ''; }
    render();
    raf = requestAnimationFrame(tick);
  }

  function synchronizePlayback() {
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
    previousStamp = null;
    updateControls();
    if (canRun()) raf = requestAnimationFrame(tick);
  }

  function announce(message) { text('player-status', message); }
  function togglePlay() {
    playing = !playing;
    if (playing && time >= durations[scene]) time = 0;
    synchronizePlayback();
    announce(playing ? '正在播放' + titles[scene] + '短片' : '演示已暂停');
  }

  function selectScene(next, fromUser = false) {
    scene = next;
    currentShot = '';
    if (fromUser) {
      time = reducedMotion.matches ? (scene === 'long' ? 12 : 3.5) : 0;
      playing = !reducedMotion.matches;
      const url = new URL(location.href);
      url.searchParams.set('scene', scene);
      url.searchParams.delete('t');
      url.searchParams.delete('paused');
      history.replaceState(null, '', url);
      announce('已切换到' + titles[scene] + '独立短片');
    }
    sceneButtons.forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.selectScene === scene)));
    nodes.film.setAttribute('aria-label', titles[scene] + '场景动画');
    text('scene-description', descriptions[scene]);
    render();
    synchronizePlayback();
  }

  function resize() {
    const width = nodes['film-frame'].getBoundingClientRect().width;
    nodes.film.style.setProperty('--film-scale', width / 1600);
    const wasNarrow = narrow;
    narrow = innerWidth < 560 || (innerWidth < 900 && innerWidth / innerHeight < 1.15);
    nodes.player.classList.toggle('is-narrow', narrow);
    if (narrow !== wasNarrow) synchronizePlayback();
  }

  function applyTheme(value, save = false) {
    selectedTheme = ['light', 'dark'].includes(value) ? value : 'system';
    document.documentElement.dataset.theme = selectedTheme === 'system' ? (themeMedia.matches ? 'dark' : 'light') : selectedTheme;
    nodes['theme-select'].value = selectedTheme;
    document.querySelector('meta[name="theme-color"]').content = document.documentElement.dataset.theme === 'dark' ? '#1b2428' : '#f5f3eb';
    if (save) { try { localStorage.setItem('cc-notify-theme', selectedTheme); } catch {} }
  }

  try { selectedTheme = localStorage.getItem('cc-notify-theme') || 'system'; } catch {}
  applyTheme(selectedTheme);
  nodes['theme-select'].addEventListener('change', (event) => applyTheme(event.target.value, true));
  themeMedia.addEventListener('change', () => applyTheme(selectedTheme));
  window.addEventListener('storage', (event) => { if (event.key === 'cc-notify-theme') applyTheme(event.newValue || 'system'); });
  reducedMotion.addEventListener('change', () => {
    if (reducedMotion.matches) { playing = false; synchronizePlayback(); announce('已按系统的减少动态效果设置暂停'); }
  });
  nodes['play-toggle'].addEventListener('click', togglePlay);
  nodes.replay.addEventListener('click', () => { time = 0; currentShot = ''; playing = true; render(); synchronizePlayback(); announce('从头播放' + titles[scene] + '短片'); });
  sceneButtons.forEach((button) => button.addEventListener('click', () => selectScene(button.dataset.selectScene, true)));
  nodes.timeline.addEventListener('pointerdown', () => { scrubbing = true; synchronizePlayback(); });
  window.addEventListener('pointerup', () => { if (scrubbing) { scrubbing = false; synchronizePlayback(); } });
  window.addEventListener('pointercancel', () => { if (scrubbing) { scrubbing = false; synchronizePlayback(); } });
  nodes.timeline.addEventListener('input', () => { time = clamp(Number(nodes.timeline.value), 0, durations[scene]); previousStamp = null; render(); });
  nodes.fullscreen.addEventListener('click', async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else if (nodes.player.requestFullscreen) await nodes.player.requestFullscreen();
      else announce('当前浏览器不支持全屏，短片已铺满页面。');
    } catch { announce('浏览器未进入全屏，短片仍可在当前页面播放。'); }
  });
  document.addEventListener('fullscreenchange', () => { nodes.fullscreen.setAttribute('aria-label', document.fullscreenElement ? '退出全屏' : '进入全屏'); resize(); });
  document.addEventListener('visibilitychange', synchronizePlayback);
  window.addEventListener('resize', resize);
  if ('ResizeObserver' in window) new ResizeObserver(resize).observe(nodes['film-frame']);
  document.addEventListener('keydown', (event) => {
    if (event.target.closest('input,select,button,a,textarea') || event.metaKey || event.ctrlKey || event.altKey) return;
    if (event.code === 'Space') { event.preventDefault(); togglePlay(); }
    if (event.code === 'ArrowLeft' || event.code === 'ArrowRight') {
      event.preventDefault();
      time = clamp(time + (event.code === 'ArrowRight' ? 1 : -1), 0, durations[scene]);
      previousStamp = null;
      render();
    }
  });
  resize();
  selectScene(scene);
})();
