(function () {
  'use strict';

  var ORDER_API = 'https://go.laowu.life/sso/orders';
  var selectedOrderId = '';
  var cachedOrders = null;
  var loadingOrders = null;
  var MAX_MEDIA = 4;
  var MAX_MEDIA_BYTES = 20 * 1024 * 1024;

  function statusLabel(status) {
    var labels = {
      pending: '寰呭鐞?, unpaid: '寰呮敮浠?, paid: '宸叉敮浠?, processing: '澶勭悊涓?,
      delivered: '宸蹭氦浠?, completed: '宸插畬鎴?, canceled: '宸插彇娑?, cancelled: '宸插彇娑?,
      refunded: '宸查€€娆?, failed: '澶辫触'
    };
    return labels[String(status || '').toLowerCase()] || status || '鏈煡鐘舵€?;
  }

  function getAuth() {
    return window.localStorage.getItem('auth_data') || '';
  }

  function loadOrders() {
    if (cachedOrders) return Promise.resolve(cachedOrders);
    if (loadingOrders) return loadingOrders;
    var auth = getAuth();
    if (!auth) return Promise.resolve([]);
    loadingOrders = window.fetch(ORDER_API, {
      method: 'POST',
      mode: 'cors',
      credentials: 'omit',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ xboard_auth: auth })
    }).then(function (response) {
      if (!response.ok) throw new Error('order lookup failed');
      return response.json();
    }).then(function (payload) {
      cachedOrders = payload && payload.ok && Array.isArray(payload.orders) ? payload.orders : [];
      return cachedOrders;
    }).catch(function () {
      return [];
    }).finally(function () {
      loadingOrders = null;
    });
    return loadingOrders;
  }

  function ticketDialog() {
    var candidates = document.querySelectorAll('[role="dialog"], [aria-modal="true"], .n-modal, .n-card, .modal');
    for (var i = 0; i < candidates.length; i += 1) {
      if (!candidates[i].getClientRects().length) continue;
      var text = candidates[i].textContent || '';
      if (text.indexOf('鏂扮殑宸ュ崟') !== -1 || text.indexOf('鏂板缓宸ュ崟') !== -1 || text.indexOf('鍒涘缓宸ュ崟') !== -1 || text.indexOf('My Tickets') !== -1) return candidates[i];
    }
    var subject = document.querySelector('input[placeholder*="宸ュ崟涓婚"], input[placeholder*="ticket subject" i]');
    if (subject && subject.getClientRects().length) {
      var parent = subject.parentElement;
      for (var depth = 0; parent && depth < 8; depth += 1, parent = parent.parentElement) {
        var parentText = parent.textContent || '';
        if (parentText.indexOf('鏂板缓宸ュ崟') !== -1 || parentText.indexOf('鍒涘缓宸ュ崟') !== -1 || parentText.indexOf('鏂扮殑宸ュ崟') !== -1) return parent;
      }
    }
    return null;
  }

  function renderPicker(wrapper) {
    var preview = wrapper.querySelector('.ticket-media-preview');
    preview.innerHTML = '';
    (wrapper.__ticketFiles || []).forEach(function (file, index) {
      var item = document.createElement('div');
      item.className = 'ticket-media-preview-item';
      var url = URL.createObjectURL(file);
      var media = file.type.indexOf('video/') === 0 ? document.createElement('video') : document.createElement('img');
      media.src = url;
      if (media.tagName === 'VIDEO') media.muted = true;
      media.onload = media.onloadedmetadata = function () { URL.revokeObjectURL(url); };
      var remove = document.createElement('button');
      remove.type = 'button';
      remove.textContent = '脳';
      remove.setAttribute('aria-label', '绉婚櫎闄勪欢');
      remove.addEventListener('click', function () {
        wrapper.__ticketFiles.splice(index, 1);
        renderPicker(wrapper);
      });
      item.appendChild(media);
      item.appendChild(remove);
      preview.appendChild(item);
    });
  }

  function mountMediaPicker(textarea) {
    if (!textarea || textarea.dataset.ticketMediaMounted) return;
    textarea.dataset.ticketMediaMounted = '1';
    var wrapper = document.createElement('div');
    wrapper.className = 'ticket-media-picker';
    wrapper.__ticketFiles = [];
    wrapper.innerHTML = '<button type="button" class="ticket-media-choose">锛?鍥剧墖 / 琛ㄦ儏鍖?/ 瑙嗛</button>' +
      '<input class="ticket-media-input" type="file" accept="image/jpeg,image/png,image/gif,image/webp,video/mp4,video/webm,video/quicktime" multiple hidden>' +
      '<small>鏈€澶?涓紝鍗曚釜涓嶈秴杩?0MB</small><div class="ticket-media-preview"></div>';
    var input = wrapper.querySelector('input');
    wrapper.querySelector('.ticket-media-choose').addEventListener('click', function () { input.click(); });
    input.addEventListener('change', function () {
      var files = Array.prototype.slice.call(input.files || []);
      files.forEach(function (file) {
        if (wrapper.__ticketFiles.length >= MAX_MEDIA) return;
        if (file.size > MAX_MEDIA_BYTES) {
          window.alert(file.name + ' 瓒呰繃20MB锛屾湭娣诲姞');
          return;
        }
        if (!/^(image\/(jpeg|png|gif|webp)|video\/(mp4|webm|quicktime))$/i.test(file.type)) {
          window.alert(file.name + ' 鏍煎紡涓嶆敮鎸?);
          return;
        }
        wrapper.__ticketFiles.push(file);
      });
      input.value = '';
      renderPicker(wrapper);
    });
    var container = textarea.parentElement;
    if (container && container.parentNode) container.parentNode.insertBefore(wrapper, container);
  }

  function mountMediaPickers(dialog, ticketPage) {
    var root = dialog || (ticketPage ? document : null);
    if (!root) return;
    var textareas = root.querySelectorAll('textarea');
    for (var i = 0; i < textareas.length; i += 1) {
      if (textareas[i].getClientRects().length) mountMediaPicker(textareas[i]);
    }
  }

  function mountOrderSelect() {
    var dialog = ticketDialog();
    var ticketPage = /(?:^|\/)tickets?(?:[/?]|$)/i.test((window.location.hash || '').replace(/^#\/?/, ''));
    var active = document.activeElement;
    var editorFocused = !!(ticketPage && active && active.matches && active.matches('input, textarea, select, [contenteditable="true"]'));
    if (document.body) document.body.classList.toggle('ai-store-ticket-modal-open', !!dialog);
    if (document.body) document.body.classList.toggle('ai-store-ticket-page', ticketPage);
    if (document.body) document.body.classList.toggle('ai-store-ticket-editor-focused', editorFocused);
    var mobileNavRow = document.querySelector('.slide-tabs-nav');
    var mobileNav = mobileNavRow ? (mobileNavRow.closest('nav') || mobileNavRow.parentElement) : null;
    var hiddenNavs = document.querySelectorAll('.ai-store-ticket-bottom-nav-hidden');
    for (var navIndex = 0; navIndex < hiddenNavs.length; navIndex += 1) {
      if ((!dialog && !editorFocused) || hiddenNavs[navIndex] !== mobileNav) hiddenNavs[navIndex].classList.remove('ai-store-ticket-bottom-nav-hidden');
    }
    if ((dialog || editorFocused) && mobileNav) mobileNav.classList.add('ai-store-ticket-bottom-nav-hidden');
    if (!ticketPage) return;
    if (dialog) dialog.classList.add('ai-store-ticket-dialog');
    mountMediaPickers(dialog, ticketPage);
    renderMediaMarkers(document);
    if (!dialog) return;
    return;

    var wrapper = document.createElement('div');
    wrapper.id = 'ai-store-ticket-order';
    wrapper.innerHTML = '<label for="ai-store-ticket-order-select">闇€瑕佸叧鑱斿摢绗旇喘涔拌褰曪紵 <small>锛堝彲閫夛級</small></label>' +
      '<select id="ai-store-ticket-order-select" disabled><option value="">姝ｅ湪璇诲彇褰撳墠璐﹀彿璁㈠崟鈥?/option></select>' +
      '<p>鎵句笉鍒板搴旇鍗曚篃娌″叧绯伙紱绯荤粺浼氳嚜鍔ㄩ檮甯﹀綋鍓嶈处鍙峰拰鑺傜偣濂楅淇℃伅銆?/p>';

    var labels = dialog.querySelectorAll('label');
    var messageContainer = null;
    for (var i = 0; i < labels.length; i += 1) {
      var labelText = labels[i].textContent || '';
      if (labelText.indexOf('娑堟伅') !== -1 || labelText.indexOf('鍐呭') !== -1 || labelText.indexOf('Message') !== -1) {
        messageContainer = labels[i].parentElement;
        break;
      }
    }
    if (!messageContainer) {
      var textarea = dialog.querySelector('textarea[placeholder*="鎻忚堪"], textarea');
      if (textarea) messageContainer = textarea.parentElement;
    }
    if (messageContainer && messageContainer.parentNode) messageContainer.parentNode.insertBefore(wrapper, messageContainer);
    else dialog.appendChild(wrapper);

    var select = wrapper.querySelector('select');
    select.addEventListener('change', function () { selectedOrderId = select.value || ''; });
    loadOrders().then(function (orders) {
      if (!document.body.contains(select)) return;
      select.innerHTML = '<option value="">涓嶉€夋嫨锛岀洿鎺ユ彁浜?/option>';
      orders.forEach(function (order) {
        var option = document.createElement('option');
        option.value = String(order.id);
        option.textContent = order.order_no + ' 路 ' + (order.products || []).join('銆?) + ' 路 ' + order.amount + ' ' + order.currency + ' 路 ' + statusLabel(order.status);
        select.appendChild(option);
      });
      select.disabled = false;
      if (!orders.length) select.options[0].textContent = '褰撳墠璐﹀彿鏆傛棤鍙叧鑱旇鍗?;
    });
  }

  function addOrderToBody(body) {
    if (!selectedOrderId) return body;
    if (typeof body === 'string') {
      try {
        var json = JSON.parse(body);
        json.go_order_id = Number(selectedOrderId);
        return JSON.stringify(json);
      } catch (_) {
        var params = new URLSearchParams(body);
        params.set('go_order_id', selectedOrderId);
        return params.toString();
      }
    }
    if (body instanceof FormData || body instanceof URLSearchParams) body.set('go_order_id', selectedOrderId);
    return body;
  }

  function addMediaToBody(body, ids) {
    if (!ids || !ids.length) return body;
    if (typeof body === 'string') {
      try {
        var json = JSON.parse(body);
        json.media_ids = ids;
        return JSON.stringify(json);
      } catch (_) {
        var params = new URLSearchParams(body);
        ids.forEach(function (id) { params.append('media_ids[]', id); });
        return params.toString();
      }
    }
    if (body instanceof FormData || body instanceof URLSearchParams) {
      ids.forEach(function (id) { body.append('media_ids[]', id); });
    }
    return body;
  }

  function pendingMediaFiles() {
    var wrappers = document.querySelectorAll('.ticket-media-picker');
    var files = [];
    for (var i = 0; i < wrappers.length; i += 1) {
      if (!wrappers[i].getClientRects().length) continue;
      files = files.concat(wrappers[i].__ticketFiles || []);
    }
    return files.slice(0, MAX_MEDIA);
  }

  function clearPendingMedia() {
    document.querySelectorAll('.ticket-media-picker').forEach(function (wrapper) {
      wrapper.__ticketFiles = [];
      renderPicker(wrapper);
    });
  }

  function uploadMediaFiles(files) {
    return Promise.all(files.map(function (file) {
      var form = new FormData();
      form.append('file', file, file.name);
      return originalFetch('/api/v1/user/ticket/media/upload', {
        method: 'POST',
        headers: { Authorization: getAuth() },
        body: form
      }).then(function (response) {
        if (!response.ok) throw new Error('涓婁紶澶辫触锛? + file.name);
        return response.json();
      }).then(function (payload) {
        var id = payload && payload.data && payload.data.id;
        if (!id) throw new Error('涓婁紶杩斿洖寮傚父锛? + file.name);
        return id;
      });
    }));
  }

  function renderMediaMarkers(root) {
    if (!root || !window.NodeFilter) return;
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    var nodes = [];
    var node;
    while ((node = walker.nextNode())) {
      if (node.nodeValue && node.nodeValue.indexOf('[[ticket-media:') !== -1) nodes.push(node);
    }
    nodes.forEach(function (textNode) {
      var parent = textNode.parentElement;
      if (!parent || /^(SCRIPT|STYLE|TEXTAREA)$/i.test(parent.tagName)) return;
      var value = textNode.nodeValue;
      var regex = /\[\[ticket-media:([0-9a-f-]{36}):(image|sticker|video)\]\]/ig;
      var match;
      var last = 0;
      var fragment = document.createDocumentFragment();
      while ((match = regex.exec(value))) {
        fragment.appendChild(document.createTextNode(value.slice(last, match.index)));
        var holder = document.createElement('span');
        holder.className = 'ticket-media-render';
        holder.dataset.mediaId = match[1];
        holder.dataset.mediaKind = match[2].toLowerCase();
        holder.textContent = '姝ｅ湪鍔犺浇濯掍綋鈥?;
        fragment.appendChild(holder);
        loadRenderedMedia(holder);
        last = regex.lastIndex;
      }
      if (last) {
        fragment.appendChild(document.createTextNode(value.slice(last)));
        textNode.parentNode.replaceChild(fragment, textNode);
      }
    });
  }

  function loadRenderedMedia(holder) {
    originalFetch('/api/v1/user/ticket/media/' + encodeURIComponent(holder.dataset.mediaId), {
      headers: { Authorization: getAuth() }
    }).then(function (response) {
      if (!response.ok) throw new Error('load failed');
      return response.blob();
    }).then(function (blob) {
      var url = URL.createObjectURL(blob);
      var media = blob.type.indexOf('video/') === 0 ? document.createElement('video') : document.createElement('img');
      media.src = url;
      media.className = 'ticket-message-media';
      if (media.tagName === 'VIDEO') {
        media.controls = true;
        media.playsInline = true;
        media.preload = 'metadata';
      }
      holder.textContent = '';
      holder.appendChild(media);
    }).catch(function () {
      holder.textContent = '濯掍綋鍔犺浇澶辫触';
      holder.classList.add('ticket-media-error');
    });
  }

  var originalOpen = XMLHttpRequest.prototype.open;
  var originalSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__aiStoreTicketUrl = String(url || '');
    return originalOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function (body) {
    var isSave = this.__aiStoreTicketUrl.indexOf('/user/ticket/save') !== -1;
    var isReply = this.__aiStoreTicketUrl.indexOf('/user/ticket/reply') !== -1;
    if (isSave) body = addOrderToBody(body);
    if (!isSave && !isReply) return originalSend.call(this, body);
    var xhr = this;
    var files = pendingMediaFiles();
    if (!files.length) return originalSend.call(xhr, body);
    uploadMediaFiles(files).then(function (ids) {
      clearPendingMedia();
      originalSend.call(xhr, addMediaToBody(body, ids));
    }).catch(function (error) {
      window.alert(error.message || '濯掍綋涓婁紶澶辫触');
    });
  };

  var originalFetch = window.fetch.bind(window);
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    var isSave = url.indexOf('/user/ticket/save') !== -1;
    var isReply = url.indexOf('/user/ticket/reply') !== -1;
    if (isSave && init && init.body) init = Object.assign({}, init, { body: addOrderToBody(init.body) });
    if ((!isSave && !isReply) || !init || !init.body) return originalFetch(input, init);
    var files = pendingMediaFiles();
    if (!files.length) return originalFetch(input, init);
    return uploadMediaFiles(files).then(function (ids) {
      clearPendingMedia();
      var nextInit = Object.assign({}, init, { body: addMediaToBody(init.body, ids) });
      return originalFetch(input, nextInit);
    });
  };

  new MutationObserver(mountOrderSelect).observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener('hashchange', function () { selectedOrderId = ''; mountOrderSelect(); });
  document.addEventListener('focusin', mountOrderSelect);
  document.addEventListener('focusout', function () { window.setTimeout(mountOrderSelect, 0); });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mountOrderSelect, { once: true });
  else mountOrderSelect();
})();
