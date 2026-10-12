import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webspace/services/fullscreen_system_ui.dart';
import 'package:webspace/web_view_model.dart';

import 'helpers/real_app.dart';

/// Android fullscreen keeps the OS bars visible, including when app controls
/// are available. The content and any retained tab strip stay within their
/// reported safe-area insets.
void main() {
  group('fullscreenSystemUiMode', () {
    test('Android keeps system bars visible with or without app controls', () {
      for (final withControls in [false, true]) {
        expect(
          fullscreenSystemUiMode(
            platform: TargetPlatform.android,
            tabStripInFullscreen: withControls,
            tabBarButton: withControls,
            kioskLocked: false,
          ),
          SystemUiMode.edgeToEdge,
        );
      }
    });

    test('other platforms retain the fullscreen controls policy', () {
      expect(
        fullscreenSystemUiMode(
          platform: TargetPlatform.iOS,
          tabStripInFullscreen: false,
          tabBarButton: false,
          kioskLocked: false,
        ),
        SystemUiMode.immersiveSticky,
      );
      expect(
        fullscreenSystemUiMode(
          platform: TargetPlatform.iOS,
          tabStripInFullscreen: true,
          tabBarButton: false,
          kioskLocked: false,
        ),
        SystemUiMode.immersive,
      );
    });
  });

  group('in the Android app', () {
    const navBar = 48.0;
    late List<String> modes;

    setUp(() {
      modes = [];
    });

    Future<void> enterFullscreenOn(WidgetTester tester,
        {required Map<String, Object> prefs}) async {
      final dpr = tester.view.devicePixelRatio;
      tester.view.padding = FakeViewPadding(bottom: navBar * dpr);
      tester.view.viewPadding = FakeViewPadding(bottom: navBar * dpr);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            modes.add(call.arguments as String);
          }
          return null;
        },
      );
      final site = WebViewModel(
        initUrl: 'https://example.com',
        name: 'Example',
        fullscreenMode: true,
      );
      await pumpRealApp(tester, sites: [site], prefs: prefs);
      await openWebspace(tester, name: 'All');
      await openSiteFromDrawer(tester, name: 'Example');
    }

    testWidgets('a kept tab strip stays above the visible navigation bar', (tester) async {
      addTearDown(tester.view.reset);
      await enterFullscreenOn(tester, prefs: {
        'showTabStrip': true,
        'tabStripInFullscreen': true,
      });
      expect(find.byTooltip('Open navigation menu'), findsNothing,
          reason: 'the site opened in full screen');
      expect(modes.last, 'SystemUiMode.edgeToEdge');

      final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final chip = find.text('Example');
      expect(tester.getRect(chip).bottom, lessThanOrEqualTo(height - navBar),
          reason: 'the strip stays above the visible system navigation bar');
    });

    testWidgets('fullscreen without app controls also keeps system bars visible', (tester) async {
      addTearDown(tester.view.reset);
      await enterFullscreenOn(tester, prefs: {'showTabStrip': true});
      expect(find.byTooltip('Open navigation menu'), findsNothing);
      expect(modes.last, 'SystemUiMode.edgeToEdge');
    });
  });
}
