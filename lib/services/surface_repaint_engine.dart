/// Pure-Dart model of the Android surface-repaint nudge (PAUSE-015/017/018),
/// the runtime counterpart of `formal/kernel.tla`'s repaint machine. Every
/// (re)attach of the visible hybrid-composition SurfaceView owes a repaint
/// (activate, resume, a fresh controller, back/forward from bfcache, reload,
/// first visible commit, a route returning, go home, renderer rebuild:
/// PAUSE-015/017/018/021/024/031); going to the background does not. That
/// coverage is gated in test/js/surface_repaint_funnel.test.js. This class owns
/// the coalescing tick loop that drives native repaint requests and the repaint
/// owed after an attach, with no side effects: the host supplies the clock
/// (`Future.delayed`) and native call. It
/// never imports Flutter, so it is unit- and interleaving-testable. See
/// test/surface_repaint_engine_test.dart.
library;

/// Whether the host should stop the tick loop after this native repaint.
class RepaintTick {
  final bool done;
  const RepaintTick({required this.done});
}

class SurfaceRepaintEngine {
  /// Number of repaint requests per nudge. Spread across frames because a
  /// freshly-attached surface may not be composited on the first frame.
  static const int ticksPerRequest = 6;

  int _ticksRemaining = 0;
  bool _looping = false;
  bool _owed = false;

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

  bool _commitPending = false;

  /// How long the host holds the commit latch open after an issue
  /// (PAUSE-027). Long enough to outlast a slow recommit, short enough that
  /// an unrelated navigation minutes later does not inherit a repaint.
  static const Duration commitWindow = Duration(seconds: 15);

  /// Whether a document has been issued whose commit onto the visible surface
  /// has not yet settled.
  bool get commitPending => _commitPending;

  /// A document was issued for the visible webview whose commit will land an
  /// unbounded time later. Unlike every other transition here, the surface
  /// does not go blank when the *call* is made: the old frame is discarded now
  /// and the replacement commits later (network, parse, script), so the
  /// one-shot nudge fired at issue time can drain before the commit lands —
  /// the same ordering `formal/warmstart.tla` model-checks for the warm-start
  /// resume. This latch carries the debt across that gap; [noteLoadSettled]
  /// pays it.
  ///
  /// Callers arm it: a reload, a re-issued load, and a freshly-attached
  /// surface whose *first* document has not committed yet (PAUSE-021/025).
  ///
  /// Arming opens a *window*, not a one-shot ticket, and the host closes it
  /// with [closeCommitWindow] after [commitWindow] (PAUSE-027). One issue can
  /// settle more than once — a redirect chain commits an interstitial first —
  /// and a reload issued while another is still in flight settles twice: the
  /// aborted load's settle first, the replacement's after. Disarming on the
  /// first settle spends the repaint on a document that is already gone and
  /// leaves the one the user is looking at blank, which is the rapid-refresh
  /// white screen.
  void noteCommitPending() {
    _commitPending = true;
  }

  /// Close the commit window: later loads settle without a repaint. Driven by
  /// the host's bounded timer, restarted on every [noteCommitPending].
  void closeCommitWindow() {
    _commitPending = false;
  }

  /// A main-frame load settled on the visible webview. Returns true iff the
  /// commit window is open, in which case the host MUST nudge: the commit is
  /// the document's real surface attach. Does not close the window — see
  /// [noteCommitPending].
  bool noteLoadSettled() {
    if (!_commitPending) return false;
    attach();
    return true;
  }

  /// Request a nudge. Refills the tick budget and returns whether the host
  /// should START the tick loop (true), or an already-running loop absorbed
  /// the request (false). Coalescing: concurrent callers never start two loops.
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
    // A native repaint request recomposites whatever surface is currently
    // attached, so it clears any owed repaint. A late attach with no later
    // request is the warm-start defect (formal/warmstart.tla, Fix="none").
    _owed = false;
    return const RepaintTick(done: false);
  }

  /// Abort the loop with no further ticks (host unmounted mid-loop).
  void abort() {
    _ticksRemaining = 0;
    _looping = false;
  }
}
