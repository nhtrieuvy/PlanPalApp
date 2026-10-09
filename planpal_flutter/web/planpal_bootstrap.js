(function () {
  'use strict';

  var startup = document.getElementById('planpal-startup');
  var message = startup && startup.querySelector('.startup-message');
  var retry = startup && startup.querySelector('.startup-retry');
  var failed = false;

  function hasFlutterView() {
    return Boolean(document.querySelector('flutter-view, flt-glass-pane'));
  }

  function hideStartup() {
    if (!startup || failed) return;
    startup.hidden = true;
  }

  function showStartupError() {
    if (!startup || hasFlutterView()) return;
    failed = true;
    startup.dataset.error = 'true';
    startup.setAttribute('role', 'alert');
    if (message) {
      message.textContent = navigator.language.toLowerCase().startsWith('vi')
        ? 'Không thể tải PlanPal. Vui lòng kiểm tra kết nối và thử lại.'
        : 'PlanPal could not load. Check your connection and try again.';
    }
  }

  var observer = new MutationObserver(function () {
    if (hasFlutterView()) {
      hideStartup();
      observer.disconnect();
    }
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });

  window.addEventListener('error', showStartupError);
  window.addEventListener('unhandledrejection', showStartupError);
  window.setTimeout(function () {
    if (!hasFlutterView()) showStartupError();
  }, 15000);

  if (retry) {
    retry.addEventListener('click', function () {
      window.location.reload();
    });
  }

  // FCM uses a dedicated scope; Flutter owns the root app-shell worker.
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register(
        '/firebase-messaging-sw.js',
        { scope: '/firebase-cloud-messaging-push-scope' }
      ).catch(function () {
        // Push remains optional and must not block application startup.
      });
    });
  }
})();
