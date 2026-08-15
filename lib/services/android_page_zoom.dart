/// Build Android's first-layout page zoom contract. Android WebView ignores
/// its native scale setting on modern viewport pages, so the scale belongs in
/// the page's own viewport metadata before layout begins.
String buildAndroidPageZoomScript(int zoomPercent) =>
    r'''
(function() {
  if (window.__webspaceAndroidPageZoom) return;
  window.__webspaceAndroidPageZoom = true;
  var zoomPercent = __ZOOM_PERCENT__;
  var targetScale = zoomPercent / 100;
  var targetWidth = screen.width * 100 / zoomPercent;
  var widthDirective = 'width=' + String(targetWidth);
  var scaleDirective = 'initial-scale=' + String(targetScale);
  var managedMeta = null;
  var updating = false;

  function viewportMetas() {
    var all = document.getElementsByTagName('meta');
    var out = [];
    for (var i = 0; i < all.length; i++) {
      var name = all[i].getAttribute('name');
      if (name && name.toLowerCase() === 'viewport') out.push(all[i]);
    }
    return out;
  }

  function normalizeContent(content) {
    var parts = String(content || '').split(',');
    var next = [];
    var widthSeen = false;
    var scaleSeen = false;
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i].trim();
      if (!part) continue;
      if (/^width\s*=/i.test(part)) {
        if (!widthSeen) next.push(widthDirective);
        widthSeen = true;
      } else if (/^initial-scale\s*=/i.test(part)) {
        if (!scaleSeen) next.push(scaleDirective);
        scaleSeen = true;
      } else if (/^(?:minimum-scale|maximum-scale)\s*=/i.test(part)) {
        // These directives could clamp the configured initial scale. Keep
        // user-scalable untouched so accessibility behavior remains theirs.
      } else {
        next.push(part);
      }
    }
    if (!widthSeen) next.unshift(widthDirective);
    if (!scaleSeen) next.push(scaleDirective);
    return next.join(', ');
  }

  function containsViewport(node) {
    if (!node || node.nodeType !== 1) return false;
    var name = node.getAttribute && node.getAttribute('name');
    if (node.tagName === 'META' && name &&
        name.toLowerCase() === 'viewport') return true;
    var metas = node.getElementsByTagName && node.getElementsByTagName('meta');
    if (!metas) return false;
    for (var i = 0; i < metas.length; i++) {
      var n = metas[i].getAttribute('name');
      if (n && n.toLowerCase() === 'viewport') return true;
    }
    return false;
  }

  function ensure() {
    if (updating || !document.documentElement) return;
    updating = true;
    try {
      var metas = viewportMetas();
      if (!managedMeta || !managedMeta.parentNode) {
        managedMeta = metas.length ? metas[0] : document.createElement('meta');
        if (!metas.length) {
          managedMeta.setAttribute('name', 'viewport');
          var parent = document.head || document.documentElement;
          parent.insertBefore(managedMeta, parent.firstChild);
        }
      }
      if (document.head && managedMeta.parentNode !== document.head) {
        document.head.insertBefore(managedMeta, document.head.firstChild);
      }
      metas = viewportMetas();
      for (var i = 0; i < metas.length; i++) {
        var meta = metas[i];
        if (meta === managedMeta) continue;
        managedMeta.setAttribute('content', meta.getAttribute('content') || '');
        if (meta.parentNode) meta.parentNode.removeChild(meta);
      }
      var content = managedMeta.getAttribute('content') || '';
      var normalized = normalizeContent(content);
      if (content !== normalized) managedMeta.setAttribute('content', normalized);
    } catch (_) {} finally {
      updating = false;
    }
  }

  ensure();
  if (typeof MutationObserver !== 'undefined') {
    try {
      var observer = new MutationObserver(function(mutations) {
        var relevant = !managedMeta || !managedMeta.parentNode ||
            (document.head && managedMeta.parentNode !== document.head);
        for (var i = 0; i < mutations.length && !relevant; i++) {
          var mutation = mutations[i];
          if (mutation.type === 'attributes') {
            var target = mutation.target;
            var name = target && target.getAttribute &&
                target.getAttribute('name');
            relevant = target && target.tagName === 'META' && name &&
                name.toLowerCase() === 'viewport';
          } else {
            var added = mutation.addedNodes;
            for (var j = 0; j < added.length; j++) {
              if (containsViewport(added[j]) ||
                  (added[j].nodeType === 1 && added[j].tagName === 'HEAD')) {
                relevant = true;
                break;
              }
            }
          }
        }
        if (relevant) ensure();
      });
      observer.observe(document, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['name', 'content'],
      });
    } catch (_) {}
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', ensure);
  }
})();'''
        .replaceAll('__ZOOM_PERCENT__', zoomPercent.toString());
