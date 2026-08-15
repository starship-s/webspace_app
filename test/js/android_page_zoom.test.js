// Behavioural tests for the Android document-start viewport contract
// (lib/services/webview.dart#buildAndroidPageZoomScript).

const test = require('node:test');
const assert = require('node:assert/strict');
const { makeDom, readFixture, runInDom } = require('./helpers/load_shim');

function boot(fixture, html) {
  const dom = makeDom({ html });
  Object.defineProperty(dom.window.screen, 'width', {
    configurable: true,
    value: 360,
  });
  runInDom(dom, readFixture(`android_page_zoom/${fixture}.js`));
  return dom;
}

function settle() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

test('80% uses the CSS screen-width formula', () => {
  const dom = boot('80', '<!doctype html><html><head></head><body></body></html>');
  const meta = dom.window.document.querySelector('meta[name="viewport"]');
  assert.ok(meta);
  assert.equal(meta.getAttribute('content'), 'width=450, initial-scale=0.8');
});

test('125% uses the CSS screen-width formula', () => {
  const dom = boot('125', '<!doctype html><html><head></head><body></body></html>');
  const meta = dom.window.document.querySelector('meta[name="viewport"]');
  assert.ok(meta);
  assert.equal(meta.getAttribute('content'), 'width=288, initial-scale=1.25');
});

test('rewrites only zoom directives and preserves accessibility/site directives', () => {
  const dom = boot(
    '80',
    '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, interactive-widget=resizes-content, user-scalable=no, minimum-scale=0.5, maximum-scale=2"></head><body></body></html>',
  );
  const metas = dom.window.document.querySelectorAll('meta[name="viewport"]');
  const content = metas[0].getAttribute('content');
  assert.equal(metas.length, 1);
  assert.match(content, /width=450/);
  assert.match(content, /initial-scale=0\.8/);
  assert.match(content, /viewport-fit=cover/);
  assert.match(content, /interactive-widget=resizes-content/);
  assert.match(content, /user-scalable=no/);
  assert.doesNotMatch(content, /(?:minimum|max)imum-scale=/);
});

test('late viewport metadata is adopted without duplicate tags or observer recursion', async () => {
  const dom = boot('80', '<!doctype html><html><head></head><body></body></html>');
  const late = dom.window.document.createElement('meta');
  late.name = 'viewport';
  late.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
  dom.window.document.head.appendChild(late);
  await settle();
  const metas = dom.window.document.querySelectorAll('meta[name="viewport"]');
  assert.equal(metas.length, 1);
  assert.equal(metas[0].getAttribute('content'),
    'width=450, initial-scale=0.8, viewport-fit=cover');
});
