(function () {
  'use strict';

  var ORDER_API = '__STORE_ORDER_API__';
  var selectedOrderId = '';
  var cachedOrders = null;
  var loadingOrders = null;

  function statusLabel(status) {
    var labels = {pending:'待处理',unpaid:'待支付',paid:'已支付',processing:'处理中',delivered:'已交付',completed:'已完成',canceled:'已取消',cancelled:'已取消',refunded:'已退款',failed:'失败'};
    return labels[String(status || '').toLowerCase()] || status || '未知状态';
  }

  function getAuth() { return localStorage.getItem('auth_data') || ''; }

  function loadOrders() {
    if (cachedOrders) return Promise.resolve(cachedOrders);
    if (loadingOrders) return loadingOrders;
    var auth = getAuth();
    if (!auth) return Promise.resolve([]);
    loadingOrders = fetch(ORDER_API, {
      method:'POST', mode:'cors', credentials:'omit',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({xboard_auth:auth})
    }).then(function (response) {
      if (!response.ok) throw new Error('order lookup failed');
      return response.json();
    }).then(function (payload) {
      cachedOrders = payload && payload.ok && Array.isArray(payload.orders) ? payload.orders : [];
      return cachedOrders;
    }).catch(function () { return []; }).finally(function () { loadingOrders = null; });
    return loadingOrders;
  }

  function ticketDialog() {
    var candidates = document.querySelectorAll('[role="dialog"],[aria-modal="true"],.n-modal,.n-card,.modal');
    for (var i = 0; i < candidates.length; i += 1) {
      if (!candidates[i].getClientRects().length) continue;
      var text = candidates[i].textContent || '';
      if (text.indexOf('新的工单') !== -1 || text.indexOf('新建工单') !== -1 || text.indexOf('创建工单') !== -1 || text.indexOf('My Tickets') !== -1) return candidates[i];
    }
    var subject = document.querySelector('input[placeholder*="工单主题"],input[placeholder*="ticket subject" i]');
    if (subject && subject.getClientRects().length) {
      var parent = subject.parentElement;
      for (var depth = 0; parent && depth < 8; depth += 1, parent = parent.parentElement) {
        var parentText = parent.textContent || '';
        if (parentText.indexOf('新建工单') !== -1 || parentText.indexOf('创建工单') !== -1 || parentText.indexOf('新的工单') !== -1) return parent;
      }
    }
    return null;
  }

  function updateMobileLayers(dialog) {
    document.body.classList.toggle('ai-store-ticket-modal-open', !!dialog);
    var row = document.querySelector('.slide-tabs-nav');
    var nav = row ? (row.closest('nav') || row.parentElement) : null;
    var hidden = document.querySelectorAll('.ai-store-ticket-bottom-nav-hidden');
    for (var i = 0; i < hidden.length; i += 1) {
      if (!dialog || hidden[i] !== nav) hidden[i].classList.remove('ai-store-ticket-bottom-nav-hidden');
    }
    if (dialog && nav) nav.classList.add('ai-store-ticket-bottom-nav-hidden');
  }

  function mountOrderSelect() {
    var dialog = ticketDialog();
    var ticketPage = /(?:^|\/)tickets?(?:[/?]|$)/i.test((location.hash || '').replace(/^#\/?/, ''));
    var active = document.activeElement;
    var editorFocused = !!(ticketPage && active && active.matches && active.matches('input, textarea, select, [contenteditable="true"]'));
    document.body.classList.toggle('ai-store-ticket-page', ticketPage);
    document.body.classList.toggle('ai-store-ticket-editor-focused', editorFocused);
    updateMobileLayers(dialog || editorFocused);
    if (!ticketPage) return;
    if (!dialog || dialog.querySelector('#ai-store-ticket-order')) return;
    dialog.classList.add('ai-store-ticket-dialog');

    var wrapper = document.createElement('div');
    wrapper.id = 'ai-store-ticket-order';
    wrapper.innerHTML = '<label for="ai-store-ticket-order-select">关联 AI 工具商店订单 <small>（可选）</small></label><select id="ai-store-ticket-order-select" disabled><option value="">正在读取当前账号订单…</option></select><p>节点套餐信息仍会自动附带；此处只追加所选商城订单的订单号、商品、金额、状态和时间，不读取卡密或交付内容。</p>';
    var labels = dialog.querySelectorAll('label');
    var messageContainer = null;
    for (var i = 0; i < labels.length; i += 1) {
      var labelText = labels[i].textContent || '';
      if (labelText.indexOf('消息') !== -1 || labelText.indexOf('内容') !== -1 || labelText.indexOf('Message') !== -1) {
        messageContainer = labels[i].parentElement;
        break;
      }
    }
    if (!messageContainer) {
      var textarea = dialog.querySelector('textarea[placeholder*="描述"],textarea');
      if (textarea) messageContainer = textarea.parentElement;
    }
    if (messageContainer && messageContainer.parentNode) messageContainer.parentNode.insertBefore(wrapper, messageContainer);
    else dialog.appendChild(wrapper);

    var select = wrapper.querySelector('select');
    select.addEventListener('change', function () { selectedOrderId = select.value || ''; });
    loadOrders().then(function (orders) {
      if (!document.body.contains(select)) return;
      select.innerHTML = '<option value="">不关联商城订单</option>';
      orders.forEach(function (order) {
        var option = document.createElement('option');
        option.value = String(order.id);
        option.textContent = order.order_no + ' · ' + (order.products || []).join('、') + ' · ' + order.amount + ' ' + order.currency + ' · ' + statusLabel(order.status);
        select.appendChild(option);
      });
      select.disabled = false;
      if (!orders.length) select.options[0].textContent = '当前账号暂无可关联订单';
    });
  }

  function addOrderToBody(body) {
    if (!selectedOrderId) return body;
    if (typeof body === 'string') {
      try {
        var json = JSON.parse(body); json.go_order_id = Number(selectedOrderId); return JSON.stringify(json);
      } catch (_) {
        var params = new URLSearchParams(body); params.set('go_order_id', selectedOrderId); return params.toString();
      }
    }
    if (body instanceof FormData || body instanceof URLSearchParams) body.set('go_order_id', selectedOrderId);
    return body;
  }

  var originalOpen = XMLHttpRequest.prototype.open;
  var originalSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) { this.__storeTicketUrl = String(url || ''); return originalOpen.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function (body) {
    if (this.__storeTicketUrl.indexOf('/user/ticket/save') !== -1) body = addOrderToBody(body);
    return originalSend.call(this, body);
  };
  var originalFetch = window.fetch.bind(window);
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    if (url.indexOf('/user/ticket/save') !== -1 && init && init.body) init = Object.assign({}, init, {body:addOrderToBody(init.body)});
    return originalFetch(input, init);
  };

  new MutationObserver(mountOrderSelect).observe(document.documentElement, {childList:true,subtree:true});
  addEventListener('hashchange', function () { selectedOrderId = ''; mountOrderSelect(); });
  document.addEventListener('focusin', mountOrderSelect);
  document.addEventListener('focusout', function () { setTimeout(mountOrderSelect, 0); });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mountOrderSelect, {once:true});
  else mountOrderSelect();
})();
