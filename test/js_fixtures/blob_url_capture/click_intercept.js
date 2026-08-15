(function() {
  if (window.__webspaceBlobClickHooked) return;
  window.__webspaceBlobClickHooked = true;
  try {
    function asNative(fn, name) {
      try {
        var stubs = window.__wsFnStubs;
        if (stubs && typeof stubs.set === 'function') {
          stubs.set(fn, 'function ' + name + '() { [native code] }');
        }
      } catch (_) {}
      return fn;
    }
    function downloadHref(el) {
      if (!el || el.tagName !== 'A') return '';
      if (!el.hasAttribute || !el.hasAttribute('download')) return '';
      var href = '';
      try { href = el.href || el.getAttribute('href') || ''; } catch (_) {}
      return typeof href === 'string' ? href : '';
    }
    function isBlobDownloadAnchor(el) {
      return downloadHref(el).indexOf('blob:') === 0;
    }
    function isHttpDownloadAnchor(el) {
      var href = downloadHref(el);
      return href.indexOf('http:') === 0 || href.indexOf('https:') === 0;
    }
    function isSameOriginHttpDownloadAnchor(el) {
      if (!isHttpDownloadAnchor(el)) return false;
      try {
        return new URL(downloadHref(el), document.baseURI).origin ===
          window.location.origin;
      } catch (_) {
        return false;
      }
    }
    function removeDownloadAttribute(el) {
      try { el.removeAttribute('download'); } catch (_) {}
    }
    function dispatchDownload(el) {
      var href = downloadHref(el);
      var name = '';
      try { name = el.getAttribute('download') || ''; } catch (_) {}
      try {
        window.flutter_inappwebview.callHandler(
          '_webspaceBlobDownloadStart', href, name);
      } catch (_) {}
    }
    function dispatchHttpDownload(el) {
      var href = downloadHref(el);
      var name = '';
      try { name = el.getAttribute('download') || ''; } catch (_) {}
      try {
        window.flutter_inappwebview.callHandler(
          '_webspaceHttpDownloadStart', href, name);
      } catch (_) {}
    }
    var listener = function(e) {
      var el = e.target;
      // Bubble up through composed path so a click on a child of the
      // anchor (e.g. an icon inside <a download>) still resolves.
      while (el && el !== document && !downloadHref(el)) {
        el = el.parentNode;
      }
      if (el && el !== document) {
        if (isBlobDownloadAnchor(el)) {
          try { e.preventDefault(); } catch (_) {}
          try { e.stopPropagation(); } catch (_) {}
          dispatchDownload(el);
        } else if (isSameOriginHttpDownloadAnchor(el)) {
          try { e.preventDefault(); } catch (_) {}
          try { e.stopPropagation(); } catch (_) {}
          dispatchHttpDownload(el);
        } else if (isHttpDownloadAnchor(el)) {
          removeDownloadAttribute(el);
        }
      }
    };
    document.addEventListener('click', listener, true);
    if (typeof HTMLAnchorElement !== 'undefined' &&
        HTMLAnchorElement.prototype &&
        typeof HTMLAnchorElement.prototype.click === 'function') {
      var origClick = HTMLAnchorElement.prototype.click;
      var patched = function click() {
        if (isBlobDownloadAnchor(this)) {
          dispatchDownload(this);
          return;
        }
        if (isSameOriginHttpDownloadAnchor(this)) {
          dispatchHttpDownload(this);
          return;
        }
        if (isHttpDownloadAnchor(this)) {
          removeDownloadAttribute(this);
        }
        return origClick.apply(this, arguments);
      };
      asNative(patched, 'click');
      try { HTMLAnchorElement.prototype.click = patched; } catch (_) {}
    }
  } catch (_) {}
})();
