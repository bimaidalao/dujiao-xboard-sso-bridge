(function () {
  'use strict';

  function isTicketPage() {
    return /(?:^|\/)tickets?(?:[/?]|$)/i.test((location.hash || '').replace(/^#\/?/, ''));
  }

  function ticketDialog() {
    var candidates = document.querySelectorAll('[role="dialog"],[aria-modal="true"],.n-modal,.n-card,.modal');
    for (var i = 0; i < candidates.length; i += 1) {
      if (!candidates[i].getClientRects().length) continue;
      var text = candidates[i].textContent || '';
      if (/新的工单|新建工单|创建工单|My Tickets/i.test(text)) return candidates[i];
    }
    var subject = document.querySelector('input[placeholder*="工单主题"],input[placeholder*="ticket subject" i]');
    if (!subject || !subject.getClientRects().length) return null;
    var parent = subject.parentElement;
    for (var depth = 0; parent && depth < 8; depth += 1, parent = parent.parentElement) {
      if (/新的工单|新建工单|创建工单/i.test(parent.textContent || '')) return parent;
    }
    return null;
  }

  function mobileNav() {
    var row = document.querySelector('.slide-tabs-nav');
    return row ? (row.closest('nav') || row.parentElement) : null;
  }

  function refreshTicketLayout() {
    if (!document.body) return;
    var ticketPage = isTicketPage();
    var dialog = ticketPage ? ticketDialog() : null;
    var active = document.activeElement;
    var editorFocused = !!(ticketPage && active && active.matches && active.matches('input,textarea,select,[contenteditable="true"]'));
    var nav = mobileNav();

    document.body.classList.toggle('ai-store-ticket-page', ticketPage);
    document.body.classList.toggle('ai-store-ticket-modal-open', !!dialog);
    document.body.classList.toggle('ai-store-ticket-editor-focused', editorFocused);
    document.querySelectorAll('.ai-store-ticket-bottom-nav-hidden').forEach(function (element) {
      if ((!dialog && !editorFocused) || element !== nav) element.classList.remove('ai-store-ticket-bottom-nav-hidden');
    });
    if ((dialog || editorFocused) && nav) nav.classList.add('ai-store-ticket-bottom-nav-hidden');
    if (dialog) dialog.classList.add('ai-store-ticket-dialog');
  }

  new MutationObserver(refreshTicketLayout).observe(document.documentElement, {childList:true,subtree:true});
  addEventListener('hashchange', refreshTicketLayout);
  document.addEventListener('focusin', refreshTicketLayout);
  document.addEventListener('focusout', function () { setTimeout(refreshTicketLayout, 0); });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', refreshTicketLayout, {once:true});
  else refreshTicketLayout();
})();
