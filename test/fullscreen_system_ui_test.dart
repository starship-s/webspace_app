import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webspace/main.dart' show fullscreenSystemUiMode;

void main() {
  test('selects the fullscreen system UI mode by platform', () {
    expect(
      fullscreenSystemUiMode(TargetPlatform.android),
      SystemUiMode.edgeToEdge,
    );
    expect(
      fullscreenSystemUiMode(TargetPlatform.iOS),
      SystemUiMode.immersiveSticky,
    );
  });
}
