(() => {
  "use strict";

  const film = document.getElementById("film");
  const seek = document.getElementById("seek");
  const playToggle = document.getElementById("play-toggle");
  const playIcon = playToggle.querySelector("use");
  const timeDisplay = document.getElementById("time-display");
  const sceneLabel = document.getElementById("scene-label");
  const sceneTitle = document.getElementById("scene-title");
  const captionStep = document.getElementById("caption-step");
  const captionText = document.getElementById("caption-text");
  const captionKind = document.getElementById("caption-kind");
  const chapters = [...document.querySelectorAll("[data-chapter]")];
  const fullscreenToggle = document.getElementById("fullscreen-toggle");
  const fullscreenNote = document.getElementById("fullscreen-note");
  const motionNote = document.getElementById("motion-note");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const darkScheme = window.matchMedia("(prefers-color-scheme: dark)");
  const narrowViewport = window.matchMedia("(max-width: 640px), (max-width: 900px) and (orientation: portrait)");
  const params = new URLSearchParams(window.location.search);
  const duration = 40;
  const clamp = (value) => Math.min(duration - 0.1, Math.max(0, Number.isFinite(value) ? value : 0));
  const phases = [
    { start: 0, name: "desktop-busy", step: "01 — 01", text: "你在处理另一件事。三个会话，各自向前。" },
    { start: 4, name: "desktop-notice", step: "01 — 02", text: "右上角的一条提醒，让你知道谁在等你。" },
    { start: 8, name: "desktop-switch", step: "01 — 03", text: "看到项目与摘要，切回对应会话。" },
    { start: 9.5, name: "desktop-review", step: "01 — 03", text: "看到项目与摘要，切回对应会话。" },
    { start: 13, name: "desktop-settled", step: "01 — 04", text: "继续输入后，取消这个会话尚未发送的提醒。" },
    { start: 18, name: "away-running", step: "02 — 01", text: "长任务交给 Agent，你可以先离开电脑。" },
    { start: 23, name: "phone-notice", step: "02 — 02", text: "回合结束后 5 分钟仍未响应，飞书送达手机。" },
    { start: 27, name: "phone-open", step: "02 — 03", text: "打开消息，看清是哪个项目、完成了什么。" },
    { start: 33, name: "return-review", step: "02 — 04", text: "回到电脑，直接开始验收。" },
  ];

  let time = clamp(Number(params.get("t") || (params.get("scene") === "away" ? 18 : 0)));
  let wantsPlay = !reducedMotion.matches && !params.has("paused");
  let parentVisible = true;
  let lastFrame = null;
  let frameRequest = null;
  let currentPhase = "";
  let instantRequest = null;
  let themeMode = "system";
  const themeToggle = document.getElementById("theme-toggle");
  const themes = ["system", "light", "dark"];
  const themeLabels = { system: "跟随系统", light: "浅色", dark: "深色" };

  function applyTheme(mode) {
    themeMode = themes.includes(mode) ? mode : "system";
    document.documentElement.dataset.theme = themeMode === "system" ? (darkScheme.matches ? "dark" : "light") : themeMode;
    const next = themes[(themes.indexOf(themeMode) + 1) % themes.length];
    const label = `主题：${themeLabels[themeMode]}。点击切换为${themeLabels[next]}`;
    themeToggle.setAttribute("aria-label", label);
    themeToggle.title = label;
  }

  try { applyTheme(localStorage.getItem("cc-notify-theme") || "system"); }
  catch (_) { applyTheme("system"); }

  themeToggle.addEventListener("click", () => {
    applyTheme(themes[(themes.indexOf(themeMode) + 1) % themes.length]);
    try { localStorage.setItem("cc-notify-theme", themeMode); } catch (_) { /* Preferences remain usable in memory. */ }
  });
  darkScheme.addEventListener("change", () => { if (themeMode === "system") applyTheme("system"); });
  window.addEventListener("storage", (event) => {
    if (event.key === "cc-notify-theme" || event.key === null) applyTheme(event.newValue || "system");
  });

  if (params.get("embed") === "1") document.body.classList.add("embedded");
  motionNote.hidden = !reducedMotion.matches || params.has("paused");

  function isPlaying() {
    return wantsPlay && !document.hidden && !narrowViewport.matches && parentVisible;
  }

  function render() {
    let phase = phases[0];
    for (const candidate of phases) {
      if (time >= candidate.start) phase = candidate;
      else break;
    }
    const away = time >= 18;
    if (currentPhase !== phase.name) {
      currentPhase = phase.name;
      film.dataset.phase = phase.name;
      film.dataset.scene = away ? "away" : "desktop";
      sceneLabel.textContent = away ? "02 / 离开电脑后" : "01 / 在电脑前";
      sceneTitle.textContent = away ? "你可以走开。需要验收时，消息会找到你。" : "专注眼前这一件，其他会话也不会错过。";
      captionStep.textContent = phase.step;
      captionText.textContent = phase.text;
      captionKind.textContent = away ? "分钟级 · 异步提醒" : "秒级 · 桌面提醒";
      chapters.forEach((button, index) => button.setAttribute("aria-pressed", String(index === (away ? 1 : 0))));
    }
    seek.value = String(time);
    seek.style.setProperty("--progress", `${(time / duration) * 100}%`);
    seek.setAttribute("aria-valuetext", `${Math.floor(time)} 秒，共 ${duration} 秒。${away ? "离开电脑后" : "多会话并行"}。${phase.text}`);
    timeDisplay.textContent = `00:${String(Math.floor(time)).padStart(2, "0")} / 00:40`;
    film.dataset.time = time.toFixed(1);
  }

  function frame(now) {
    frameRequest = null;
    if (!isPlaying()) {
      lastFrame = null;
      return;
    }
    if (lastFrame !== null) time = (time + Math.min((now - lastFrame) / 1000, 0.2)) % duration;
    lastFrame = now;
    render();
    frameRequest = requestAnimationFrame(frame);
  }

  function syncPlayback() {
    const playing = isPlaying();
    film.dataset.playing = String(playing);
    film.dataset.narrow = String(narrowViewport.matches);
    playToggle.setAttribute("aria-label", wantsPlay ? "暂停演示" : "播放演示");
    playIcon.setAttribute("href", wantsPlay ? "#i-pause" : "#i-play");
    if (frameRequest !== null) cancelAnimationFrame(frameRequest);
    frameRequest = null;
    lastFrame = null;
    if (playing) frameRequest = requestAnimationFrame(frame);
  }

  function startPlayback() {
    wantsPlay = true;
    film.dataset.motionOptIn = "true";
    motionNote.hidden = true;
    syncPlayback();
  }

  function jumpTo(value) {
    time = clamp(value);
    film.dataset.instant = "true";
    if (instantRequest !== null) cancelAnimationFrame(instantRequest);
    render();
    // Flush the selected state without animating across unrelated scenes.
    film.getBoundingClientRect();
    instantRequest = requestAnimationFrame(() => {
      delete film.dataset.instant;
      instantRequest = null;
    });
    lastFrame = null;
  }

  playToggle.addEventListener("click", () => {
    if (wantsPlay) {
      wantsPlay = false;
      syncPlayback();
    } else startPlayback();
  });

  document.getElementById("motion-play").addEventListener("click", startPlayback);
  document.getElementById("replay").addEventListener("click", () => {
    jumpTo(0);
    startPlayback();
  });

  chapters.forEach((button) => {
    button.addEventListener("click", () => {
      jumpTo(Number(button.dataset.chapter));
      // Chapter selection preserves a user's pause or reduced-motion preference.
      syncPlayback();
    });
  });

  seek.addEventListener("input", () => jumpTo(Number(seek.value)));
  document.addEventListener("visibilitychange", syncPlayback);
  narrowViewport.addEventListener("change", syncPlayback);
  reducedMotion.addEventListener("change", () => {
    if (reducedMotion.matches) {
      wantsPlay = false;
      delete film.dataset.motionOptIn;
      motionNote.hidden = false;
    } else motionNote.hidden = true;
    syncPlayback();
  });

  // A same-origin parent can pause the embedded film when it scrolls offscreen.
  window.addEventListener("message", (event) => {
    if (event.source !== window.parent || event.origin !== window.location.origin) return;
    if (event.data?.type === "cc-notify:theme") {
      applyTheme(event.data.theme);
      return;
    }
    if (event.data?.type !== "cc-notify:visibility" || typeof event.data.visible !== "boolean") return;
    parentVisible = event.data.visible;
    syncPlayback();
  });

  fullscreenToggle.addEventListener("click", async () => {
    fullscreenNote.hidden = true;
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else if (document.documentElement.requestFullscreen) await document.documentElement.requestFullscreen();
      else throw new Error("Fullscreen is unavailable");
    } catch (_) {
      document.getElementById("fullscreen-status").textContent = "此浏览器未启用全屏。";
      fullscreenNote.hidden = false;
    }
  });
  document.addEventListener("fullscreenchange", () => {
    fullscreenToggle.setAttribute("aria-label", document.fullscreenElement ? "退出全屏" : "全屏观看");
  });
  document.getElementById("dismiss-fullscreen-note").addEventListener("click", () => { fullscreenNote.hidden = true; });

  // Query parameters also allow reviewers to open a particular paused frame.
  jumpTo(time);
  syncPlayback();
  if (window.parent !== window) window.parent.postMessage({ type: "cc-notify:ready" }, window.location.origin === "null" ? "*" : window.location.origin);
})();
