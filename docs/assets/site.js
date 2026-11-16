(() => {
  'use strict';

  const themeButton = document.getElementById('theme-toggle');
  const themeLabel = document.getElementById('theme-label');
  const themes = ['system', 'light', 'dark'];
  const themeLabels = { system: '自动', light: '浅色', dark: '深色' };
  const themeNames = { system: '跟随系统', light: '浅色', dark: '深色' };
  let theme = 'system';
  try {
    const stored = localStorage.getItem('cc-notify-theme');
    if (themes.includes(stored)) theme = stored;
  } catch { /* Storage is optional. */ }

  function applyTheme() {
    if (theme === 'system') delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = theme;
    themeLabel.textContent = themeLabels[theme];
    const next = themes[(themes.indexOf(theme) + 1) % themes.length];
    themeButton.setAttribute('aria-label', `切换主题，当前${themeNames[theme]}，切换为${themeNames[next]}`);
    themeButton.title = `当前${themeNames[theme]} · 点击切换为${themeNames[next]}`;
  }

  themeButton.hidden = false;
  themeButton.addEventListener('click', () => {
    theme = themes[(themes.indexOf(theme) + 1) % themes.length];
    try { localStorage.setItem('cc-notify-theme', theme); } catch { /* Keep the in-page choice. */ }
    applyTheme();
  });
  window.addEventListener('storage', event => {
    if (event.key !== 'cc-notify-theme') return;
    theme = themes.includes(event.newValue) ? event.newValue : 'system';
    applyTheme();
  });
  applyTheme();

  const tabList = document.getElementById('install-tabs');
  const tabs = [...tabList.querySelectorAll('[role="tab"]')];
  const panels = tabs.map(tab => document.getElementById(tab.getAttribute('aria-controls')));
  const copyStatus = document.getElementById('copy-status');

  function selectTab(index, moveFocus = false) {
    tabs.forEach((tab, current) => {
      const selected = current === index;
      tab.setAttribute('aria-selected', String(selected));
      tab.tabIndex = selected ? 0 : -1;
      panels[current].hidden = !selected;
    });
    copyStatus.textContent = '';
    if (moveFocus) tabs[index].focus();
  }
  tabs.forEach((tab, index) => {
    panels[index].setAttribute('role', 'tabpanel');
    panels[index].setAttribute('aria-labelledby', tab.id);
    panels[index].tabIndex = 0;
    tab.addEventListener('click', () => selectTab(index));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      else if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tabs.length - 1;
      else return;
      event.preventDefault();
      selectTab(next, true);
    });
  });
  selectTab(0);
  tabList.hidden = false;

  document.querySelectorAll('[data-copy]').forEach(button => {
    button.hidden = false;
    const initialLabel = button.textContent;
    let resetLabel;
    button.addEventListener('click', async () => {
      const code = document.getElementById(button.dataset.copy);
      const text = code.textContent;
      const command = button.closest('.command');
      copyStatus.textContent = '';
      try {
        if (!window.isSecureContext || !navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
        await navigator.clipboard.writeText(text);
        button.textContent = '已复制 ✓';
        clearTimeout(resetLabel);
        resetLabel = setTimeout(() => { button.textContent = initialLabel; }, 2500);
        const fallback = command.querySelector('.copy-fallback');
        if (fallback) fallback.hidden = true;
        copyStatus.textContent = '已复制到剪贴板。';
      } catch {
        let fallback = command.querySelector('.copy-fallback');
        if (!fallback) {
          fallback = document.createElement('div');
          fallback.className = 'copy-fallback';
          const label = document.createElement('label');
          const textarea = document.createElement('textarea');
          textarea.id = `${code.id}-manual`;
          textarea.readOnly = true;
          textarea.spellcheck = false;
          textarea.rows = Math.max(3, Math.min(8, text.split('\n').length + 1));
          label.htmlFor = textarea.id;
          label.textContent = '自动复制不可用。请按 Ctrl+C / ⌘C，或长按复制下方内容。';
          fallback.append(label, textarea);
          command.append(fallback);
        }
        fallback.hidden = false;
        const textarea = fallback.querySelector('textarea');
        textarea.value = text;
        if (!command.closest('[hidden]')) {
          textarea.focus();
          textarea.select();
          copyStatus.textContent = '已选中命令，可手动复制。';
        }
      }
    });
  });
})();
