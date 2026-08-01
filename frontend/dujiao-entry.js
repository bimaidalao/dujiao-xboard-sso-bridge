(function () {
  'use strict';
  var config = window.DujiaoXboardBridge || {};
  if (!config.xboardSsoUrl) return;

  var button = document.createElement('button');
  button.className = 'dx-bridge-entry';
  button.type = 'button';
  button.innerHTML = '<strong>' + (config.panelLabel || 'Open dashboard') + '</strong><small>Single sign-on</small>';
  button.addEventListener('click', function () {
    var token = localStorage.getItem('user_token') || '';
    if (!token) {
      location.href = config.dujiaoLoginUrl || '/auth/login';
      return;
    }
    var form = document.createElement('form');
    form.method = 'POST';
    form.action = config.xboardSsoUrl;
    form.hidden = true;
    var tokenInput = document.createElement('input');
    tokenInput.name = 'dujiao_token';
    tokenInput.value = token;
    form.appendChild(tokenInput);
    var redirectInput = document.createElement('input');
    redirectInput.name = 'redirect';
    redirectInput.value = 'dashboard';
    form.appendChild(redirectInput);
    document.body.appendChild(form);
    form.submit();
  });
  document.body.appendChild(button);
})();

