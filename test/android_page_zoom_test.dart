import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webspace/services/webview.dart';

void main() {
  test('Android zoom combines viewport and normalized native scale', () {
    final source = File('lib/services/webview.dart').readAsStringSync();
    expect(source, contains('await controller.getZoomScale() ?? 1'));
    expect(source, contains('targetScale / currentScale'));
    expect(source, contains('controller.zoomBy(zoomFactor: relativeFactor)'));
    expect(source, contains("groupName: 'android_page_zoom'"));
    expect(source, contains('AT_DOCUMENT_START'));
    expect(source, contains('forMainFrameOnly: true'));
    expect(source, isNot(contains('settings.initialScale')));
  });

  group('same-origin HTTP download bridge validation', () {
    test('accepts same-origin default ports', () {
      expect(
        isSameHttpOrigin(
          'https://example.com/file',
          'https://example.com/page',
        ),
        isTrue,
      );
      expect(
        isSameHttpOrigin(
          'http://example.com:80/file',
          'http://example.com/page',
        ),
        isTrue,
      );
      expect(
        isSameHttpOrigin(
          'https://example.com/page',
          'https://example.com:443/',
        ),
        isTrue,
      );
    });

    test('rejects mismatched scheme, host, and port', () {
      expect(
        isSameHttpOrigin('http://example.com/file', 'https://example.com/page'),
        isFalse,
      );
      expect(
        isSameHttpOrigin(
          'https://other.example/file',
          'https://example.com/page',
        ),
        isFalse,
      );
      expect(
        isSameHttpOrigin(
          'https://example.com:8443/file',
          'https://example.com/page',
        ),
        isFalse,
      );
    });

    test('rejects malformed and non-http URLs', () {
      expect(
        isSameHttpOrigin('not a URL', 'https://example.com/page'),
        isFalse,
      );
      expect(
        isSameHttpOrigin(
          'blob:https://example.com/id',
          'https://example.com/page',
        ),
        isFalse,
      );
      expect(
        isSameHttpOrigin('file:///tmp/report', 'file:///tmp/page'),
        isFalse,
      );
      expect(
        isSameHttpOrigin('https:///missing-host', 'https://example.com/page'),
        isFalse,
      );
    });
  });

  test(
    'registers the guarded HTTP bridge and reuses the HTTP download funnel',
    () {
      final source = File('lib/services/webview.dart').readAsStringSync();
      expect(source, contains("handlerName: '_webspaceHttpDownloadStart'"));
      expect(source, contains('lastStableUrl ?? controllerUrl'));
      expect(source, contains('isSameHttpOrigin(urlString, liveUrl)'));
      expect(source, contains('await _handleHttpDownload('));
    },
  );
}
