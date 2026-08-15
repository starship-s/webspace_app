import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main-site cookie policy stays native', () {
    final modelSource = File('lib/web_view_model.dart').readAsStringSync();
    expect(modelSource, isNot(contains('removeThirdPartyCookies')));
    expect(modelSource, isNot(contains('document.cookie')));

    final webviewSource = File('lib/services/webview.dart').readAsStringSync();
    expect(
      webviewSource,
      contains('..thirdPartyCookiesEnabled = config.thirdPartyCookiesEnabled'),
    );
  });
}
