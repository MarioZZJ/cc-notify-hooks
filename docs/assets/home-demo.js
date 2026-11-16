(() => {
  'use strict';

  const demo = document.querySelector('.home-demo');
  const toggle = document.getElementById('home-motion-toggle');
  if (!demo || !toggle) return;

  const label = toggle.querySelector('.motion-label');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let wantsPlay = !reducedMotion.matches;
  let animated = wantsPlay;
  let userChosePlayback = false;
  let inView = !('IntersectionObserver' in window);

  function updatePlayback() {
    demo.dataset.animated = String(animated);
    demo.dataset.wantsPlay = String(wantsPlay);
    demo.dataset.playing = String(wantsPlay && inView && !document.hidden);
    label.textContent = wantsPlay ? '暂停动画' : '播放动画';
    toggle.setAttribute('aria-label', wantsPlay ? '暂停首页动画' : '播放首页动画');
  }

  toggle.hidden = false;
  toggle.addEventListener('click', () => {
    userChosePlayback = true;
    wantsPlay = !wantsPlay;
    if (wantsPlay) animated = true;
    updatePlayback();
  });

  // Keep the static illustration for reduced motion unless the visitor asks to play.
  reducedMotion.addEventListener('change', event => {
    if (event.matches) {
      wantsPlay = false;
      animated = false;
    } else if (!userChosePlayback) {
      wantsPlay = true;
      animated = true;
    }
    updatePlayback();
  });

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      inView = entries[0].isIntersecting;
      updatePlayback();
    }, { threshold: 0 });
    observer.observe(demo.querySelector('.notice-pair'));
  }
  document.addEventListener('visibilitychange', updatePlayback);
  updatePlayback();
})();
