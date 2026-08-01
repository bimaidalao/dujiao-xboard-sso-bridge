(function () {
  'use strict';

  var SSO_ENDPOINT = '__PANEL_SSO_URL__';
  var LOGIN_URL = '/auth/login';

  function getToken() {
    return window.localStorage.getItem('user_token') || '';
  }

  function startSso(redirect) {
    var token = getToken();
    if (!token) {
      window.location.href = LOGIN_URL;
      return;
    }

    var form = document.createElement('form');
    form.method = 'POST';
    form.action = SSO_ENDPOINT;
    form.style.display = 'none';

    var tokenInput = document.createElement('input');
    tokenInput.type = 'hidden';
    tokenInput.name = 'go_token';
    tokenInput.value = token;
    form.appendChild(tokenInput);

    var redirectInput = document.createElement('input');
    redirectInput.type = 'hidden';
    redirectInput.name = 'redirect';
    redirectInput.value = redirect || 'dashboard';
    form.appendChild(redirectInput);

    document.body.appendChild(form);
    form.submit();
  }

  function icon(path) {
    return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="' + path + '"></path></svg>';
  }

  function closeMobileServiceMenu() {
    var menu = document.getElementById('go-mobile-service-menu');
    var button = document.getElementById('go-mobile-service-nav-item');
    if (menu) menu.classList.remove('is-open');
    if (button) button.classList.remove('is-open');
  }

  function enhanceRegisterEntry() {
    if (window.location.pathname !== '/auth/login') return;
    var links = document.querySelectorAll('a[href="/auth/register"]');
    for (var i = 0; i < links.length; i += 1) {
      if (links[i].classList.contains('go-register-cta')) continue;
      links[i].classList.add('go-register-cta');
      links[i].setAttribute('aria-label', '免费注册新账号');
      links[i].innerHTML = '<span class="go-register-cta-badge">新用户入口</span><span class="go-register-cta-hint">还没有商城账号？</span><strong>立即免费注册</strong><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"></path></svg>';
    }
  }

  function installMobileServiceNav() {
    if (window.innerWidth >= 1024) return;
    var navs = document.querySelectorAll('nav');
    var nav = null;
    for (var i = 0; i < navs.length; i += 1) {
      if (navs[i].classList.contains('lg:hidden') && navs[i].classList.contains('bottom-0')) {
        nav = navs[i];
        break;
      }
    }
    if (!nav) return;

    var row = nav.firstElementChild;
    if (!row || document.getElementById('go-mobile-service-nav-item')) return;

    var button = document.createElement('button');
    button.id = 'go-mobile-service-nav-item';
    button.type = 'button';
    button.setAttribute('aria-label', '打开客服菜单');
    button.innerHTML = icon('M4 14v-3a8 8 0 0 1 16 0v3M6 12H5a2 2 0 0 0-2 2v2a2 2 0 0 0 2 2h1v-6ZM18 12h1a2 2 0 0 1 2 2v2a2 2 0 0 1-2 2h-1v-6Z') + '<span>客服</span>';
    row.appendChild(button);

    var staleMenu = document.getElementById('go-mobile-service-menu');
    if (staleMenu) staleMenu.remove();
    var menu = document.createElement('div');
    menu.id = 'go-mobile-service-menu';
    menu.innerHTML = '<button type="button" class="go-mobile-service-ticket">' + icon('M4 14v-3a8 8 0 0 1 16 0v3M6 12H5a2 2 0 0 0-2 2v2a2 2 0 0 0 2 2h1v-6ZM18 12h1a2 2 0 0 1 2 2v2a2 2 0 0 1-2 2h-1v-6Z') + '<span><strong>工单客服</strong><small>提交和查看工单</small></span></button><a href="__TELEGRAM_URL__" target="_blank" rel="noopener noreferrer">' + icon('M21 4L3.8 11.1c-.9.35-.88.86-.16 1.08l4.4 1.38 1.7 5.18c.2.56.1.78.68.78.45 0 .65-.2.9-.44l2.12-2.05 4.42 3.27c.82.45 1.4.22 1.6-.76L22.2 5.3C22.48 4.08 21.72 3.53 21 4Z') + '<span><strong>Telegram 客服</strong><small>__TELEGRAM_HANDLE__</small></span></a>';
    document.body.appendChild(menu);

    button.addEventListener('click', function (event) {
      event.stopPropagation();
      menu.classList.toggle('is-open');
      button.classList.toggle('is-open');
    });
    menu.querySelector('.go-mobile-service-ticket').addEventListener('click', function () {
      closeMobileServiceMenu();
      startSso('mobile/tickets');
    });
    menu.addEventListener('click', function (event) { event.stopPropagation(); });
  }

  function createBridge() {
    if (document.getElementById('go-service-bridge')) return;

    var bridge = document.createElement('div');
    bridge.id = 'go-service-bridge';
    bridge.setAttribute('aria-label', '跨境速云快捷入口');

    var dashboardButton = document.createElement('button');
    dashboardButton.type = 'button';
    dashboardButton.className = 'go-bridge-dashboard';
    dashboardButton.innerHTML = '<img class="go-bridge-site-logo" src="__PANEL_LOGO_URL__" alt="跨境速云">' + '<span><strong>进入跨境速云</strong><small>AI专用加速器VPN节点</small></span>';
    dashboardButton.addEventListener('click', function () { startSso('dashboard'); });
    bridge.appendChild(dashboardButton);

    var ticketButton = document.createElement('button');
    ticketButton.type = 'button';
    ticketButton.className = 'go-bridge-ticket';
    ticketButton.setAttribute('aria-label', '打开工单客服');
    ticketButton.innerHTML = icon('M4 14v-3a8 8 0 0 1 16 0v3M6 12H5a2 2 0 0 0-2 2v2a2 2 0 0 0 2 2h1v-6ZM18 12h1a2 2 0 0 1 2 2v2a2 2 0 0 1-2 2h-1v-6ZM18 19c0 1.1-2.7 2-6 2') + '<span>工单客服</span>';
    ticketButton.addEventListener('click', function () { startSso(window.innerWidth < 905 ? 'mobile/tickets' : 'tickets'); });
    bridge.appendChild(ticketButton);

    var telegramButton = document.createElement('a');
    telegramButton.className = 'go-bridge-telegram';
    telegramButton.href = '__TELEGRAM_URL__';
    telegramButton.target = '_blank';
    telegramButton.rel = 'noopener noreferrer';
    telegramButton.setAttribute('aria-label', '打开 Telegram 客服');
    telegramButton.innerHTML = icon('M21 4L3.8 11.1c-.9.35-.88.86-.16 1.08l4.4 1.38 1.7 5.18c.2.56.1.78.68.78.45 0 .65-.2.9-.44l2.12-2.05 4.42 3.27c.82.45 1.4.22 1.6-.76L22.2 5.3C22.48 4.08 21.72 3.53 21 4Z M9.02 13.25l8.58-5.42c.43-.26.82-.12.5.17l-7.08 6.38-.27 2.85-1.73-3.98Z') + '<span>Telegram 客服</span>';
    bridge.appendChild(telegramButton);

    document.body.appendChild(bridge);
    enhanceRegisterEntry();
    installMobileServiceNav();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', createBridge, { once: true });
  } else {
    createBridge();
  }

  window.addEventListener('storage', function (event) {
    if (event.key !== 'user_token') return;
    var bridge = document.getElementById('go-service-bridge');
    if (bridge) bridge.remove();
    createBridge();
  });

  document.addEventListener('click', closeMobileServiceMenu);
  window.addEventListener('resize', installMobileServiceNav);
  new MutationObserver(function () {
    enhanceRegisterEntry();
    installMobileServiceNav();
  }).observe(document.documentElement, { childList: true, subtree: true });
})();
