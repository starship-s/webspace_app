/// Pure-Dart model of the Android surface-repaint nudge (PAUSE-015/017/018),
/// the runtime counterpart of `formal/kernel.tla`'s repaint machine. It owns
/// two decisions and no side effects: (1) which transitions re-attach the
/// visible hybrid-composition SurfaceView and therefore owe a repaint, and
/// (2) the coalescing tick loop that drives `_nudgeSurfaceRepaint`. The host
/// supplies the clock (`Future.delayed`) and native repaint side effect; this
/// class never imports Flutter, so it is unit- and interleaving-testable. See
/// test/surface_repaint_engine_test.dart.
library;

/// Surface lifecycle transitions on the visible site. Every value except
/// [appBackground] (re)attaches the SurfaceView and must be followed by a
/// repaint nudge — that is the coverage contract behind BUG-001. A new
/// surface-attach path MUST be added here and routed through the host nudge.
enum SurfaceTransition {
  activate, // _setCurrentIndex (PAUSE-015)
  resume, // _onResumed (PAUSE-015)
  controllerAttach, // fresh controller mounts a new SurfaceView (PAUSE-017)
  back, // bfcache restore reuses the controller (PAUSE-018)
  forward, // bfcache restore reuses the controller (PAUSE-018)
  reload, // reload discards the painted frame, recommits later (PAUSE-021)
  goHome, // dispose + rebuild at initUrl (PAUSE-017)
  rendererRebuilt, // renderer-gone recovery rebuild (PAUSE-017)
  appBackground, // app going to background: no attach, no repaint owed
}

/// The action the host applies for one tick, then schedules the next tick
/// unless [done].
class RepaintTick {
  final bool done;
  const RepaintTick({required this.done});
}

class SurfaceRepaintEngine {
  /// Number of native repaint requests per nudge. Spread across frames because
  /// a freshly-attached surface may not be composited on the first frame.
  static const int ticksPerRequest = 6;

  int _ticksRemaining = 0;
  bool _looping = false;
  bool _owed = false;

  /// Whether a tick loop is currently running.
  bool get isLooping => _looping;

  /// Whether a blank-surface (re)attach is still owed a repaint. Mirrors
  /// `owed` in formal/kernel.tla and formal/warmstart.tla: [attach] sets it,
  /// a nudge [tick] clears it. The warm-start bug (BUG-001 Attempt 8 /
  /// PAUSE-020) is precisely an [attach] that lands after the triggering
  /// event's one-shot loop has drained, so no tick runs against it and this
  /// stays true; see test/surface_repaint_engine_test.dart.
  bool get owed => _owed;

  /// A blank hybrid-composition SurfaceView (re)attached: a repaint is owed
  /// until a nudge tick runs against it. The visible-surface counterpart of
  /// `Attach` in the formal models. Idempotent.
  void attach() {
    _owed = true;
  }

  /// True iff [t] re-attaches the visible surface and so must be followed by a
  /// repaint. The complete set is the contract; mirrors `Attach` in kernel.tla.
  static bool mustRepaint(SurfaceTransition t) =>
      t != SurfaceTransition.appBackground;

  bool _reloadPending = false;

  /// Whether a reload has been issued whose new document has not yet settled.
  bool get reloadPending => _reloadPending;

  /// A reload was issued on the visible webview (PAUSE-021). Unlike every
  /// other transition here, the surface does not go blank when the *call* is
  /// made: the reload discards the painted frame and the new document commits
  /// onto the surface some unbounded time later, so the one-shot nudge fired
  /// at issue time can drain before the recommit lands — the same ordering
  /// `formal/warmstart.tla` model-checks for the warm-start resume. This latch
  /// carries the debt across that gap; [consumeLoadSettled] pays it.
  void reloadIssued() {
    _reloadPending = true;
  }

  /// A main-frame load settled on the visible webview. Returns true iff it
  /// completes a pending reload, in which case the host MUST nudge: the
  /// recommit is the reload's real surface attach. Consumes the latch, so a
  /// later unrelated navigation does not nudge.
  bool consumeLoadSettled() {
    if (!_reloadPending) return false;
    _reloadPending = false;
    attach();
    return true;
  }

  /// Request a nudge. Refills the tick budget and returns whether the host
  /// should START the tick loop (true), or an already-running loop absorbed
  /// the request (false). Coalescing: concurrent callers never start two
  /// loops.
  bool request() {
    _ticksRemaining = ticksPerRequest;
    if (_looping) return false;
    _looping = true;
    return true;
  }

  /// Advance one tick until the budget drains.
  RepaintTick tick() {
    if (_ticksRemaining <= 0) {
      _looping = false;
      return const RepaintTick(done: true);
    }
    _ticksRemaining--;
    // A repaint tick recomposites whatever surface is currently attached, so it
    // clears any owed repaint. A late attach with no subsequent tick is the
    // warm-start defect: `owed` stays true (formal/warmstart.tla, Fix="none").
    _owed = false;
    return const RepaintTick(done: false);
  }

  /// Abort the loop with no further ticks (host unmounted or its controller
  /// disappeared mid-loop).
  void abort() {
    _ticksRemaining = 0;
    _looping = false;
  }
}
