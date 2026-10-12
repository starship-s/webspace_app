import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webspace/services/fullscreen_system_ui.dart'
    show fullscreenSystemUiMode;

void main() {
  test('selects the fullscreen system UI mode by platform', () {
    expect(
      fullscreenSystemUiMode(
        platform: TargetPlatform.android,
        tabStripInFullscreen: false,
        tabBarButton: false,
        kioskLocked: false,
      ),
      SystemUiMode.edgeToEdge,
    );
    expect(
      fullscreenSystemUiMode(
        platform: TargetPlatform.iOS,
        tabStripInFullscreen: false,
        tabBarButton: false,
        kioskLocked: false,
      ),
      SystemUiMode.immersiveSticky,
    );
  });
}
