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

  test('registers the guarded HTTP bridge and native fallback', () {
    final source = File('lib/services/webview.dart').readAsStringSync();
    expect(source, contains("handlerName: '_webspaceHttpDownloadStart'"));
    expect(source, contains('lastStableUrl ?? controllerUrl'));
    expect(source, contains('isSameHttpOrigin(urlString, liveUrl)'));
    expect(source, contains('await _handleHttpDownload('));
  });

  test('Android HTTP downloads fall back after internal failures', () {
    final source = File('lib/services/webview.dart').readAsStringSync();
    final bindings = [
      File('lib/web_view_model.dart').readAsStringSync(),
      File('lib/screens/inappbrowser.dart').readAsStringSync(),
    ].join().replaceAll(RegExp(r'\s+'), ' ');

    expect(source, contains('webViewController: controller'));
    expect(source, contains('Internal cookie read failed'));
    expect(
      source,
      contains("await handOffToBrowser('Internal cookie read failed')"),
    );
    expect(source, contains('on DownloadException catch (e)'));
    expect(
      source,
      contains("await handOffToBrowser('Internal download failed')"),
    );
    expect(source, contains('DownloadsService.instance.cancel(task.id);'));
    expect(source, contains('final savedPath = await _saveViaPicker(result);'));
    expect(source, contains("case 'data':"));
    expect(source, contains("case 'blob':"));
    expect(
      source,
      contains('await _handleHttpDownload(\n          controller,'),
    );
    expect(
      RegExp(
        'onHttpDownload: hostIsAndroid '
        r'\? launchUrlInSystemBrowser : null,',
      ).allMatches(bindings),
      hasLength(2),
    );
  });
}
