import 'package:flutter/material.dart';
import 'package:webspace/widgets/page_load_bar.dart';

/// The load progress along the top edge in full screen, where no app bar
/// hosts it. Transparent to pointers: it adds nothing tappable, so a
/// kiosk-locked shell stays sealed (KIOSK-002) and web-app controls in the
/// top corners keep their taps.
class FullscreenLoadBar extends StatelessWidget {
  const FullscreenLoadBar({super.key, required this.progress});

  /// Percent loaded; 0 shows an indeterminate bar.
  final int progress;

  @override
  Widget build(BuildContext context) => Positioned(
    top: MediaQuery.of(context).padding.top,
    left: 0,
    right: 0,
    child: IgnorePointer(
      child: LinearProgressIndicator(
        value: progress > 0 ? progress / 100 : null,
        minHeight: PageLoadBar.height,
        backgroundColor: Colors.transparent,
      ),
    ),
  );
}

/// The invisible target under the status bar that leaves full screen. Only
/// the centered target catches the tap, leaving the top corners to the page.
class FullscreenExitHandle extends StatelessWidget {
  const FullscreenExitHandle({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: topPadding + 20,
      child: Align(
        alignment: Alignment.topCenter,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onExit,
          child: SizedBox(
            width: 96,
            height: topPadding + 20,
          ),
        ),
      ),
    );
  }
}
