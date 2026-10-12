import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webspace/services/webview_downloads.dart';

void main() {
  test('Android zoom combines viewport and normalized native scale', () {
    final webview = File('lib/services/webview.dart').readAsStringSync();
    expect(webview, contains('await controller.getZoomScale() ?? 1'));
    expect(webview, contains('targetScale / currentScale'));
    expect(webview, contains('controller.zoomBy(zoomFactor: relativeFactor)'));
    expect(webview, isNot(contains('settings.initialScale')));

    final scripts = File('lib/services/page_scripts.dart').readAsStringSync();
    expect(scripts, contains('buildPageZoomViewportShim('));
    expect(scripts, contains("pageShim('page_zoom'"));
    final shim = File('lib/services/page_shim.dart').readAsStringSync();
    expect(
      shim,
      contains(
        'ShimTime.start => inapp.UserScriptInjectionTime.AT_DOCUMENT_START',
      ),
    );
  });

  group('same-origin HTTP download bridge validation', () {
    test('accepts same-origin default ports', () {
      expect(
        WebViewDownloads.isSameHttpOrigin(
          'https://example.com/file',
          current: 'https://example.com/page',
        ),
        isTrue,
      );
      expect(
        WebViewDownloads.isSameHttpOrigin(
          'http://example.com:80/file',
          current: 'http://example.com/page',
        ),
        isTrue,
      );
      expect(
        WebViewDownloads.isSameHttpOrigin(
          'https://example.com/page',
          current: 'https://example.com:443/',
        ),
        isTrue,
      );
    });

    test('rejects mismatched scheme, host, and port', () {
      expect(
        WebViewDownloads.isSameHttpOrigin(
          'http://example.com/file',
          current: 'https://example.com/page',
        ),
        isFalse,
      );
      expect(
        WebViewDownloads.isSameHttpOrigin(
          'https://other.example/file',
          current: 'https://example.com/page',
        ),
        isFalse,
      );
      expect(
        WebViewDownloads.isSameHttpOrigin(
          'https://example.com:8443/file',
          current: 'https://example.com/page',
        ),
        isFalse,
      );
    });

    test('rejects malformed and non-http URLs', () {
      expect(
        WebViewDownloads.isSameHttpOrigin(
          'not a URL',
          current: 'https://example.com/page',
        ),
        isFalse,
      );
      expect(
        WebViewDownloads.isSameHttpOrigin(
          'blob:https://example.com/id',
          current: 'https://example.com/page',
        ),
        isFalse,
      );
      expect(
        WebViewDownloads.isSameHttpOrigin(
          'file:///tmp/report',
          current: 'file:///tmp/page',
        ),
        isFalse,
      );
      expect(
        WebViewDownloads.isSameHttpOrigin(
          'https:///missing-host',
          current: 'https://example.com/page',
        ),
        isFalse,
      );
    });
  });

  test('registers the guarded HTTP bridge and native fallback', () {
    final source = File('lib/services/page_handlers.dart').readAsStringSync();
    final webview = File('lib/services/webview.dart').readAsStringSync();
    expect(source, contains("handlerName: '_webspaceHttpDownloadStart'"));
    expect(source, contains('sourceUrl() ?? (await controller.getUrl())'));
    expect(source, contains('isSameHttpOrigin(url, current: liveUrl)'));
    expect(source, contains('WebViewDownloads.handleHttpDownloadFromAnchor('));
    expect(
      webview,
      contains('sourceUrl: () => lastStableUrl ?? lastLoadStartUrl'),
    );
  });

  test('Android HTTP downloads fall back after internal failures', () {
    final downloads = File(
      'lib/services/webview_downloads.dart',
    ).readAsStringSync();
    final bindings = [
      File('lib/web_view_model.dart').readAsStringSync(),
      File('lib/screens/inappbrowser.dart').readAsStringSync(),
    ].join().replaceAll(RegExp(r'\s+'), ' ');

    expect(downloads, contains('webViewController: controller'));
    expect(downloads, contains('Internal cookie read failed'));
    expect(
      downloads,
      contains("await handOffToBrowser('Internal cookie read failed')"),
    );
    expect(downloads, contains('on DownloadException catch (e)'));
    expect(
      downloads,
      contains("await handOffToBrowser('Internal download failed')"),
    );
    expect(downloads, contains('DownloadsService.instance.cancel(task.id);'));
    expect(
      downloads,
      contains('final savedPath = await saveViaPicker(result);'),
    );
    expect(downloads, contains("case 'data':"));
    expect(downloads, contains("case 'blob':"));
    expect(downloads, contains('cookieHeaderFor: (uri) async'));
    expect(
      RegExp(
        'onHttpDownload: hostIsAndroid '
        r'\? launchUrlInSystemBrowser : null,',
      ).allMatches(bindings),
      hasLength(2),
    );
  });
}
