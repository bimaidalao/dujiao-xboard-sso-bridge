(function () {
  'use strict';
  var config = window.DujiaoXboardBridge || {};
  if (!config.dujiaoSsoUrl) return;

  var button = document.createElement('button');
  button.className = 'dx-bridge-entry';
  button.type = 'button';
  button.innerHTML = '<strong>' + (config.storeLabel || 'Open store') + '</strong><small>Single sign-on</small>';
  button.addEventListener('click', function () {
    var authData = localStorage.getItem('auth_data') || '';
    if (!authData) {
      location.href = config.xboardLoginUrl || '#/login';
      return;
    }
    var form = document.createElement('form');
    form.method = 'POST';
    form.action = config.dujiaoSsoUrl;
    form.hidden = true;
    var input = document.createElement('input');
    input.name = 'xboard_auth';
    input.value = authData;
    form.appendChild(input);
    document.body.appendChild(form);
    form.submit();
  });
  document.body.appendChild(button);
})();

