(function () {
  'use strict';

  var CARD_ID = 'xboard-ai-account-store-card';
  var STORE_URL = '__STORE_URL__';
  var STORE_SSO_URL = '__STORE_SSO_URL__';
  var TELEGRAM_URL = '__TELEGRAM_URL__';
  var scheduled = false;

  function isShopPage() {
    return /^#\/shop(?:[/?]|$)/.test(window.location.hash || '');
  }

  function buildCard() {
    var card = document.createElement('a');
    card.id = CARD_ID;
    card.className = 'xboard-ai-store-card xboard-ai-store-float';
    card.href = STORE_URL;
    card.target = '_blank';
    card.rel = 'noopener noreferrer';
    card.setAttribute('aria-label', '进入AI工具和账号商店');
    card.innerHTML = [
      '<span class="xboard-ai-store-icon" aria-hidden="true">',
      '<img src="__STORE_LOGO_URL__" alt="">',
      '</span>',
      '<span class="xboard-ai-store-copy">',
      '<span class="xboard-ai-store-kicker">跨境速云精选服务</span>',
      '<strong>AI工具 / 账号商店</strong>',
      '<small>GPT · Gemini · Telegram · Google</small>',
      '</span>',
      '<span class="xboard-ai-store-action">进入商店',
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"/></svg>',
      '</span>'
    ].join('');

    card.addEventListener('click', function (event) {
      var authData = window.localStorage.getItem('auth_data') || '';
      if (!authData) return;

      event.preventDefault();
      var form = document.createElement('form');
      form.method = 'POST';
      form.action = STORE_SSO_URL;
      form.style.display = 'none';

      var input = document.createElement('input');
      input.type = 'hidden';
      input.name = 'xboard_auth';
      input.value = authData;
      form.appendChild(input);
      document.body.appendChild(form);
      form.submit();
    });
    return card;
  }

  function mountTelegram() {
    if (document.getElementById('xboard-telegram-float')) return;

    var telegram = document.createElement('a');
    telegram.id = 'xboard-telegram-float';
    telegram.href = TELEGRAM_URL;
    telegram.target = '_blank';
    telegram.rel = 'noopener noreferrer';
    telegram.setAttribute('aria-label', '打开 Telegram 客服');
    telegram.innerHTML = [
      '<svg viewBox="0 0 24 24" aria-hidden="true">',
      '<path d="M21 4L3.8 11.1c-.9.35-.88.86-.16 1.08l4.4 1.38 1.7 5.18c.2.56.1.78.68.78.45 0 .65-.2.9-.44l2.12-2.05 4.42 3.27c.82.45 1.4.22 1.6-.76L22.2 5.3C22.48 4.08 21.72 3.53 21 4Z M9.02 13.25l8.58-5.42c.43-.26.82-.12.5.17l-7.08 6.38-.27 2.85-1.73-3.98Z"/>',
      '</svg><span>Telegram 客服</span>'
    ].join('');
    document.body.appendChild(telegram);
  }

  function closeXboardMobileServiceMenu() {
    var menu = document.getElementById('xboard-mobile-service-menu');
    var button = document.getElementById('xboard-mobile-service-nav-item');
    if (menu) menu.classList.remove('is-open');
    if (button) button.classList.remove('is-open');
  }

  function installXboardMobileServiceNav() {
    if (window.innerWidth > 904) return;
    var row = document.querySelector('.slide-tabs-nav');
    if (!row || document.getElementById('xboard-mobile-service-nav-item')) return;

    var button = document.createElement('button');
    button.id = 'xboard-mobile-service-nav-item';
    button.type = 'button';
    button.className = 'nav-item xboard-mobile-service-nav-item';
    button.innerHTML = '<div class="nav-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 14v-3a8 8 0 0 1 16 0v3M6 12H5a2 2 0 0 0-2 2v2a2 2 0 0 0 2 2h1v-6ZM18 12h1a2 2 0 0 1 2 2v2a2 2 0 0 1-2 2h-1v-6Z"/></svg></div><span class="nav-text">客服</span>';
    var indicator = row.querySelector('.indicator-container');
    row.insertBefore(button, indicator || null);

    var staleMenu = document.getElementById('xboard-mobile-service-menu');
    if (staleMenu) staleMenu.remove();
    var menu = document.createElement('div');
    menu.id = 'xboard-mobile-service-menu';
    menu.innerHTML = '<button type="button" class="xboard-mobile-ticket"><svg viewBox="0 0 24 24"><path d="M4 14v-3a8 8 0 0 1 16 0v3M6 12H5a2 2 0 0 0-2 2v2a2 2 0 0 0 2 2h1v-6ZM18 12h1a2 2 0 0 1 2 2v2a2 2 0 0 1-2 2h-1v-6Z"/></svg><span><strong>工单客服</strong><small>提交和查看工单</small></span></button><a href="__TELEGRAM_URL__" target="_blank" rel="noopener noreferrer"><svg viewBox="0 0 24 24"><path d="M21 4L3.8 11.1c-.9.35-.88.86-.16 1.08l4.4 1.38 1.7 5.18c.2.56.1.78.68.78.45 0 .65-.2.9-.44l2.12-2.05 4.42 3.27c.82.45 1.4.22 1.6-.76L22.2 5.3C22.48 4.08 21.72 3.53 21 4Z"/></svg><span><strong>Telegram 客服</strong><small>__TELEGRAM_HANDLE__</small></span></a>';
    document.body.appendChild(menu);

    button.addEventListener('click', function (event) {
      event.preventDefault();
      event.stopPropagation();
      menu.classList.toggle('is-open');
      button.classList.toggle('is-open');
    });
    menu.querySelector('.xboard-mobile-ticket').addEventListener('click', function () {
      closeXboardMobileServiceMenu();
      window.location.hash = '#/mobile/tickets';
    });
    menu.addEventListener('click', function (event) { event.stopPropagation(); });
  }

  function mountCard() {
    scheduled = false;
    mountTelegram();
    installXboardMobileServiceNav();

    var existing = document.getElementById(CARD_ID);
    var oldWelcome = document.querySelector('.welcome-card.xboard-shop-welcome-has-ai');
    if (oldWelcome) oldWelcome.classList.remove('xboard-shop-welcome-has-ai');

    var authData = window.localStorage.getItem('auth_data') || '';
    if (!authData) {
      if (existing) {
        existing.remove();
      }
      return;
    }

    if (existing) return;

    var card = buildCard();
    document.body.appendChild(card);
  }

  function scheduleMount() {
    if (scheduled) return;
    scheduled = true;
    window.requestAnimationFrame(mountCard);
  }

  window.addEventListener('hashchange', scheduleMount);
  window.addEventListener('popstate', scheduleMount);
  window.addEventListener('resize', scheduleMount);
  window.addEventListener('storage', function (event) {
    if (event.key === 'auth_data') scheduleMount();
  });

  var observer = new MutationObserver(scheduleMount);
  observer.observe(document.documentElement, { childList: true, subtree: true });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scheduleMount, { once: true });
  } else {
    scheduleMount();
  }
  document.addEventListener('click', closeXboardMobileServiceMenu);
})();
