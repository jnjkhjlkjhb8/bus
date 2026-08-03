import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/haptics/haptic_service.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';

/// The single source of truth for bottom-sheet snap heights.
///
/// Every draggable sheet in the app snaps to detents drawn from this one set,
/// so switching between pages never lands the sheet at an unfamiliar height.
/// Pages pick which detent they *open* at (`peek`/`half`/`tall`) and which
/// subset they snap to; the physical stops are always identical, which is what
/// removes the jump.
abstract final class AppSheetSnap {
  /// Viewport fractions backing each detent — also the clamp bounds a page
  /// hands to [carriedSheetOffset].
  static const peekFrac = 0.25;
  static const halfFrac = 0.5;
  static const tallFrac = 0.85;
  static const fullFrac = 1.0;

  /// Map/list glancing height — the resting detent for map-front pages, and
  /// the floor of every grid: the sheet never gets smaller than this.
  static const peek = SheetOffset.proportionalToViewport(peekFrac);

  /// The default open height for content-led pages.
  static const half = SheetOffset.proportionalToViewport(halfFrac);

  /// Tall-but-not-full: forms and detail views that open large, and metro's
  /// capped max (keeps the line map peeking above the sheet).
  static const tall = SheetOffset.proportionalToViewport(tallFrac);

  /// Full-height read.
  static const full = SheetOffset.proportionalToViewport(fullFrac);

  /// The release speed (logical px/s) at or above which a drag is read as a
  /// flick and throws the sheet a whole detent, rather than settling at the
  /// detent nearest where the rider left it.
  ///
  /// smooth_sheets defaults to `kMinFlingVelocity` (50 px/s), which is below
  /// the residual speed a finger still carries at the end of a deliberate,
  /// unhurried drag — so nearly every release counted as a flick and the sheet
  /// dropped a full detent from under a rider who meant to place it. 600 px/s
  /// is a flick that has to be meant.
  static const flingSpeed = 600.0;

  /// The standard three-detent grid used by every page.
  static const grid = SheetSnapGrid(
    snaps: [peek, half, full],
    minFlingSpeed: flingSpeed,
  );
}

/// The one way a page moves its own sheet by code.
///
/// A detent change the app makes on the rider's behalf has to read the same
/// on every page, so the tempo lives here instead of at each call site — the
/// pages that spelled it out locally had drifted onto a different duration and
/// a much steeper curve than the home sheet they sit next to.
///
/// The curve is smooth_sheets' own [Curves.easeInOut], left unspecified: it is
/// gentler than [AppMotion.easeInOut], whose near-vertical middle is tuned for
/// content-sized transitions and reads as a yank across a whole viewport of
/// travel. It is what the home sheet has always moved on.
///
/// Reduce-motion collapses the travel instead of animating it. One millisecond
/// rather than zero: smooth_sheets asserts on a zero-length animation.
extension SheetControllerMotion on SheetController {
  Future<void> animateToDetent(SheetOffset to, {required bool reduced}) =>
      animateTo(
        to,
        duration: reduced ? const Duration(milliseconds: 1) : AppMotion.sheet,
      );
}

/// The settle the sheet runs after a drag release, on [AppMotion.spring]
/// rather than smooth_sheets' own spring: the package default responds in
/// ~0.44s, slow enough that the sheet reads as arriving after the finger
/// instead of with it. Hoisted out of `build` because the sheet rebuilds every
/// drag frame and the physics is the same object each time.
final _sheetSpring = ClampingSheetPhysics(spring: AppMotion.spring);

/// The viewport fraction a sibling sheet should open at to continue where a
/// live sheet currently sits, clamped into [min]..[max]; [fallback] when the
/// sheet has no metrics yet (first build). Pure so it is unit-testable.
///
/// This is scoped per page: a page reads its own sheet's height when opening
/// a sibling sheet, so heights stay continuous *within* a page while different
/// pages remain independent.
double carriedFraction({
  required double offset,
  required double viewportHeight,
  required double min,
  required double max,
  required double fallback,
}) {
  if (viewportHeight <= 0) return fallback.clamp(min, max);
  return (offset / viewportHeight).clamp(min, max);
}

/// [carriedFraction] read from a live [controller], as a [SheetOffset] ready
/// to hand to a sibling sheet's `initialOffset`.
SheetOffset carriedSheetOffset(
  SheetController? controller, {
  required double min,
  required double max,
  required double fallback,
}) {
  final metrics = controller?.metrics;
  return SheetOffset.proportionalToViewport(
    carriedFraction(
      offset: metrics?.offset ?? 0,
      viewportHeight: metrics?.viewportSize.height ?? 0,
      min: min,
      max: max,
      fallback: fallback,
    ),
  );
}

/// Carries the sheet's height *backwards* across a pop inside a [PagedSheet].
///
/// smooth_sheets stores a height per route and restores it when that route is
/// uncovered, so a rider who opens a stop from the nearby list, pulls the sheet
/// up to half and then goes back lands at whatever the list was left at — the
/// sheet drops under a gesture that only asked to go back. Height is a property
/// of the sheet here, not of the page inside it: forward is already continuous
/// ([carriedSheetOffset] at the push), and this is that same fact on the way
/// back out.
///
/// One object is both the navigator's observer — it notices the pop and reads
/// the height — and the underlying route's [SheetSnapGrid] — it answers with
/// that height while the pop runs. The two halves are the same fact, and
/// splitting them would mean keeping them in sync.
///
/// Wired up by the home page only. Every other sheet in the app pushes pages
/// that own their height (a picker opens at its own detent, a detail page at
/// [AppSheetSnap.peek]), and carrying a height back into those would undo the
/// height they asked for.
class CarryBackSnapGrid extends NavigatorObserver implements SheetSnapGrid {
  CarryBackSnapGrid({required this.controller, this.base = AppSheetSnap.grid});

  final SheetController controller;

  /// The grid the carried height is snapped against — the page's usual detents.
  final SheetSnapGrid base;

  /// Sheet offset (px) read when the running pop started, or null when no pop
  /// is in flight — which is what leaves every ordinary drag alone, since those
  /// already pass the live offset.
  double? _carried;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _carried = null;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final offset = controller.metrics?.offset;
    final animation = route is TransitionRoute ? route.animation : null;
    if (offset == null || animation == null) return;
    _carried = offset;
    // Dropped once the popped route's animation comes to rest: dismissed for a
    // pop that ran through, completed for a back-swipe the rider let go of with
    // the route still there. Anything still moving is the pop being carried.
    void clearWhenSettled(AnimationStatus status) {
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.reverse) {
        return;
      }
      animation.removeStatusListener(clearWhenSettled);
      _carried = null;
    }

    animation.addStatusListener(clearWhenSettled);
  }

  @override
  SheetOffset getSnapOffset(
    ViewportLayout layout,
    double offset,
    double velocity,
  ) => base.getSnapOffset(layout, _carried ?? offset, velocity);

  @override
  (SheetOffset, SheetOffset) getBoundaries(ViewportLayout layout) =>
      base.getBoundaries(layout);
}

/// Sheet-offset ticks for a sheet page, muted while another page covers it.
///
/// A covered page stays alive with its scrollables still attached to the
/// sheet's scroll controller, sitting idle. Any offset-driven re-layout there
/// resizes that idle scroll view, and Flutter answers a dimension change on an
/// idle scroll position with `goBallistic(0)`; smooth_sheets routes that to the
/// sheet without checking which position sent it, so the sheet snaps to the
/// nearest detent in the middle of the drag the user is running on the page
/// above — the sheet springs back to full instead of following the finger.
/// Muting the ticks keeps the covered page's layout still, which it can afford:
/// nothing of it is on screen.
class CurrentPageSheetTicks extends ChangeNotifier {
  CurrentPageSheetTicks({required this.source, required this.isCurrent}) {
    source.addListener(_onTick);
  }

  /// Usually the page's [SheetController].
  final Listenable source;

  /// Whether the page these ticks drive is the visible one.
  final ValueGetter<bool> isCurrent;

  void _onTick() {
    if (isCurrent()) notifyListeners();
  }

  @override
  void dispose() {
    source.removeListener(_onTick);
    super.dispose();
  }
}

/// The standard chrome every draggable in-page sheet wears: the viewport, the
/// edge give, the drag haptics, and the physics/decoration that
/// give the sheet its feel.
///
/// Pages supply only what genuinely differs — the detents they snap to, the
/// controller they read, the content. Everything a rider feels while dragging
/// is fixed here so no two sheets in the app move differently, including the
/// status-bar alignment described on [statusBarPadding].
class AppSheet extends StatefulWidget {
  const AppSheet({
    required this.child,
    this.controller,
    this.initialOffset = AppSheetSnap.half,
    this.snapGrid = AppSheetSnap.grid,
    this.color,
    this.padStatusBar = true,
    super.key,
  }) : navigator = null;

  /// The multi-page variant: the sheet hosts its own [Navigator] and each
  /// [PagedSheetRoute] carries its own detents, so [initialOffset] and
  /// [snapGrid] are the routes' business rather than this widget's.
  ///
  /// Its pages also pad themselves: re-padding the shared sheet per frame
  /// would resize the idle scroll views of the pages stacked underneath the
  /// visible one, which hijacks the drag (see [CurrentPageSheetTicks]). Pages
  /// call [statusBarPadding] through their own ticks instead.
  const AppSheet.paged({
    required Navigator this.navigator,
    this.controller,
    this.color,
    super.key,
  }) : child = const SizedBox.shrink(),
       initialOffset = AppSheetSnap.half,
       snapGrid = AppSheetSnap.grid,
       padStatusBar = true;

  /// The top padding a sheet sitting [offset] tall needs for its content to
  /// stop at the status bar instead of sliding under it.
  ///
  /// Ramps across the whole [AppSheetSnap.half]-to-[AppSheetSnap.full] stretch
  /// rather than over the last few pixels of travel: the content should drift
  /// clear of the status bar as the rider pulls, so that arriving at full is
  /// the end of a movement already underway. Waiting until the sheet's top
  /// edge actually reaches the status bar is geometrically exact but reads as
  /// the content being yanked up after the sheet has already settled. Detents
  /// at or below half keep their full content height.
  ///
  /// Applied through the sheet's own `padding` rather than a [Padding] widget
  /// so the blank space doesn't inflate the content's measured size (see
  /// `BareSheet.padding` upstream).
  static double statusBarPadding({
    required double offset,
    required double viewportHeight,
    required double topInset,
  }) {
    // A sheet that hasn't been laid out yet reports a zero viewport; dividing
    // through it yields a NaN that survives clamp() and reaches EdgeInsets as
    // an invalid value.
    if (viewportHeight <= 0) return 0;
    final progress =
        ((offset / viewportHeight - AppSheetSnap.halfFrac) /
                (AppSheetSnap.fullFrac - AppSheetSnap.halfFrac))
            .clamp(0.0, 1.0);
    // Whole logical pixels only. The sheet lays its content out at
    // (viewport - padding) and then re-inflates the measured size by the same
    // padding; with a fractional padding that round-trip lands one ULP above
    // the viewport, which reaches BoxConstraints as minHeight > maxHeight and
    // trips the non-normalized assert. Integer padding subtracts and adds
    // back exactly, and a 1px quantum is invisible on a ramp this long.
    return (topInset * progress).roundToDouble();
  }

  final Widget child;

  final SheetController? controller;
  final SheetOffset initialOffset;
  final SheetSnapGrid snapGrid;

  /// Defaults to `surfaceContainerLow`; pages override only when the sheet
  /// sits on a surface that would otherwise blend into it.
  final Color? color;

  /// Whether the sheet ramps in top padding as it nears `full` (see
  /// [statusBarPadding]). Off on pages whose max detent sits below `full` —
  /// metro is capped at `tall`, and the ramp is keyed to `full`, so it never
  /// finishes closing and leaves a permanent gap above the drag handle.
  final bool padStatusBar;

  final Navigator? navigator;

  @override
  State<AppSheet> createState() => _AppSheetState();
}

/// The arrival note a sheet plays when it lands on its minimum detent.
class _SheetEdgeHaptics {
  /// Null until the first notification: a sheet that opens *at* its minimum
  /// (the home root opens at peek, which is its minimum) would otherwise buzz
  /// on the frame it first reports its position.
  bool? _atEdge;

  void observe(SheetMetrics metrics) {
    // Half a pixel of slack: the settle animation lands on the end offset by
    // arbitrarily small increments and would otherwise never read as arrived.
    final atEdge = metrics.offset <= metrics.minOffset + 0.5;
    if (_atEdge == false && atEdge) {
      unawaited(HapticService.instance.mediumTap());
    }
    _atEdge = atEdge;
  }
}

class _AppSheetState extends State<AppSheet> {
  final _edgeHaptics = _SheetEdgeHaptics();

  /// Only created when the page didn't bring its own: the offset drives the
  /// status-bar padding, so this widget always needs a controller to read.
  SheetController? _ownController;

  SheetController get _controller =>
      widget.controller ?? (_ownController ??= SheetController());

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  bool _onNotification(SheetNotification notification) {
    _edgeHaptics.observe(notification.metrics);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final decoration = MaterialSheetDecoration(
      size: SheetSize.stretch,
      color: widget.color ?? cs.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusBottomSheet),
      ),
      clipBehavior: Clip.antiAlias,
    );
    final navigator = widget.navigator;
    return _AppSheetScope(
      controller: _controller,
      child: NotificationListener<SheetNotification>(
        onNotification: _onNotification,
        child: SheetViewport(
          child: SheetEdgeGestureDetector(
            child: navigator == null
                // Rebuilds per drag frame to re-pad the sheet, with the content
                // passed through untouched so only the padding recomputes.
                ? ValueListenableBuilder<double?>(
                    valueListenable: _controller,
                    child: widget.child,
                    builder: (context, offset, content) => Sheet(
                      controller: _controller,
                      initialOffset: widget.initialOffset,
                      snapGrid: widget.snapGrid,
                      padding: EdgeInsets.only(
                        top: widget.padStatusBar
                            ? AppSheet.statusBarPadding(
                                offset: offset ?? 0,
                                viewportHeight: MediaQuery.sizeOf(
                                  context,
                                ).height,
                                topInset: MediaQuery.paddingOf(context).top,
                              )
                            : 0,
                      ),
                      // No bounce past the end detents: the sheet is the page's
                      // primary surface, and overshoot there reads as the page
                      // itself coming loose.
                      physics: _sheetSpring,
                      scrollConfiguration: const SheetScrollConfiguration(),
                      decoration: decoration,
                      child: content!,
                    ),
                  )
                : PagedSheet(
                    controller: _controller,
                    physics: _sheetSpring,
                    decoration: decoration,
                    navigator: navigator,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Hands the live sheet controller to [SheetPageTopInset] on the pages inside.
class _AppSheetScope extends InheritedWidget {
  const _AppSheetScope({required this.controller, required super.child});

  final SheetController controller;

  @override
  bool updateShouldNotify(_AppSheetScope oldWidget) =>
      controller != oldWidget.controller;
}

/// [AppSheet.statusBarPadding] for one page of an [AppSheet.paged], applied by
/// the page instead of the sheet.
///
/// The shared sheet can't pad these itself: the inset resizes the page's list,
/// and resizing the pages stacked *under* the visible one hijacks the drag the
/// rider is running on top (see [CurrentPageSheetTicks], which is what keeps a
/// covered page still here). Outside a sheet it pads nothing, so a view that
/// doubles as a standalone screen can carry it unconditionally.
class SheetPageTopInset extends StatefulWidget {
  const SheetPageTopInset({required this.child, super.key});

  final Widget child;

  @override
  State<SheetPageTopInset> createState() => _SheetPageTopInsetState();
}

class _SheetPageTopInsetState extends State<SheetPageTopInset> {
  SheetController? _controller;
  CurrentPageSheetTicks? _ticks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context
        .dependOnInheritedWidgetOfExactType<_AppSheetScope>()
        ?.controller;
    if (controller == _controller) return;
    _ticks?.dispose();
    _controller = controller;
    _ticks = controller == null
        ? null
        : CurrentPageSheetTicks(
            source: controller,
            isCurrent: () => ModalRoute.of(context)?.isCurrent ?? true,
          );
  }

  @override
  void dispose() {
    _ticks?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticks = _ticks;
    if (ticks == null) return widget.child;
    return AnimatedBuilder(
      animation: ticks,
      child: widget.child,
      builder: (context, child) {
        final metrics = _controller?.metrics;
        final viewport =
            metrics?.viewportSize.height ?? MediaQuery.sizeOf(context).height;
        return Padding(
          padding: EdgeInsets.only(
            top: AppSheet.statusBarPadding(
              offset: metrics?.offset ?? 0,
              viewportHeight: viewport,
              topInset: MediaQuery.paddingOf(context).top,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// The modal counterpart of [AppSheet], pushed over the whole app rather than
/// living inside a page.
///
/// It shares [AppSheet.statusBarPadding] and, like a page sheet, cannot be
/// dragged away: the way out is the scrim, the back gesture, or the sheet's
/// own control.
class BottomSheetShell extends StatefulWidget {
  const BottomSheetShell({
    required this.child,
    this.initialOffset = AppSheetSnap.half,
    this.minOffset = AppSheetSnap.peek,
    this.maxOffset = AppSheetSnap.full,
    super.key,
  });

  final Widget child;
  final SheetOffset initialOffset;
  final SheetOffset minOffset;
  final SheetOffset maxOffset;

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    SheetOffset initialOffset = AppSheetSnap.half,
    SheetOffset minOffset = AppSheetSnap.peek,
    SheetOffset maxOffset = AppSheetSnap.full,
  }) {
    return Navigator.of(context).push(
      // `swipeDismissible` left off: dragging a sheet down never dismisses it
      // anywhere in the app (see [SheetEdgeGestureDetector]), and a modal is
      // not the place to make that gesture mean something else. The scrim tap
      // (`barrierDismissible`, on by default) and the back gesture are the
      // ways out, alongside whatever control the sheet carries itself.
      ModalSheetRoute<T>(
        builder: (_) => BottomSheetShell(
          initialOffset: initialOffset,
          minOffset: minOffset,
          maxOffset: maxOffset,
          child: child,
        ),
      ),
    );
  }

  @override
  State<BottomSheetShell> createState() => _BottomSheetShellState();
}

class _BottomSheetShellState extends State<BottomSheetShell> {
  late final SheetController _controller = SheetController();

  /// A modal keeps its own dismiss gesture, but arriving at a detent should
  /// feel the same here as it does in an [AppSheet].
  final _edgeHaptics = _SheetEdgeHaptics();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onNotification(SheetNotification notification) {
    _edgeHaptics.observe(notification.metrics);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NotificationListener<SheetNotification>(
      onNotification: _onNotification,
      child: _buildSheet(context, cs),
    );
  }

  Widget _buildSheet(BuildContext context, ColorScheme cs) {
    return ValueListenableBuilder<double?>(
      valueListenable: _controller,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const SheetDragHandle(), widget.child],
      ),
      builder: (context, offset, content) => Sheet(
        controller: _controller,
        initialOffset: widget.initialOffset,
        snapGrid: SheetSnapGrid(
          snaps: [widget.minOffset, widget.initialOffset, widget.maxOffset],
          minFlingSpeed: AppSheetSnap.flingSpeed,
        ),
        padding: EdgeInsets.only(
          top: AppSheet.statusBarPadding(
            offset: offset ?? 0,
            viewportHeight: MediaQuery.sizeOf(context).height,
            topInset: MediaQuery.paddingOf(context).top,
          ),
        ),
        physics: _sheetSpring,
        scrollConfiguration: const SheetScrollConfiguration(),
        decoration: MaterialSheetDecoration(
          size: SheetSize.stretch,
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusBottomSheet),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        child: content!,
      ),
    );
  }
}

class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key});

  /// How far the handle spreads and flattens at full floor load: 32×4 squashed
  /// to 40×3.
  ///
  /// The rubber-band give says the sheet is being resisted; this says what it
  /// is being resisted *by*. It reads on the one element the gesture is already
  /// about, so the answer arrives where the rider is looking — and it is a
  /// deformation under load rather than a signal that lights up, which is why
  /// it can be this quiet and still land.
  static const _squash = 0.25;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final load = _SheetFloorScope.of(context);
    return Semantics(
      label: AppI18n.of(context).commonDragToResize,
      child: SizedBox(
        width: double.infinity,
        height: 28,
        child: Center(
          // Scaled rather than resized: the handle deforms on every frame of
          // the pull, and a transform keeps that off the layout path.
          child: Transform.scale(
            scaleX: 1 + _squash * load,
            scaleY: 1 - _squash * load,
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                // cs.outline is too low-contrast against the dark sheet
                // surface (~1.45:1); onSurfaceVariant at partial opacity keeps
                // the handle restrained while staying visible in both themes.
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pulling a sheet down past its lowest detent finds a floor: the sheet gives
/// a little, resists progressively, and springs back.
///
/// It never commits to anything. A sheet leaves through the back button in its
/// own chrome, never through a drag — a gesture that sometimes shrinks the
/// sheet and sometimes throws the page away is not one a rider can spend
/// without looking. The floor still answers the pull, because a boundary that
/// does nothing reads as a frozen app rather than as an end of travel.
///
/// The top edge is left to the sheet's own clamping physics: it simply stops.
/// The give there used to be the telegraph of a hold-to-exit that no longer
/// exists, and on its own it is motion in place of information — 1.5% of scale
/// on a stretched sheet also opens a strip of map down both sides, which reads
/// as the surface coming loose rather than as resistance.
class SheetEdgeGestureDetector extends StatefulWidget {
  const SheetEdgeGestureDetector({required this.child, super.key});

  final Widget child;

  @override
  State<SheetEdgeGestureDetector> createState() =>
      _SheetEdgeGestureDetectorState();
}

class _SheetEdgeGestureDetectorState extends State<SheetEdgeGestureDetector>
    with SingleTickerProviderStateMixin {
  /// How far past the lowest detent the rider has pulled, in px, springing
  /// back to zero when they let go.
  ///
  /// [SheetOverflowNotification.overflow] reports the delta the sheet refused
  /// *this frame*, not a running total, so the pull is summed here. Reading the
  /// raw per-frame value instead would make the give track drag speed and
  /// collapse to nothing the moment the finger stopped — exactly when the pull
  /// is at its most deliberate.
  ///
  /// An [AnimationController] rather than a plain field behind `setState`: it
  /// is written on every drag frame, and on release it has to *settle* rather
  /// than snap. The release is the whole gesture.
  late final AnimationController _overflow = AnimationController.unbounded(
    vsync: this,
  );

  /// Whether the sheet is currently held against its floor by a live pull;
  /// false once the rider lets go, so the spring-back does not read as more
  /// pull.
  bool _onFloor = false;

  /// Whether the rider's finger is still on the sheet. The give belongs to a
  /// live drag, so a cancelled one — the arena can take the gesture away
  /// mid-pull — hands the sheet straight back to its spring.
  bool _dragging = false;

  /// How far the sheet can be pushed below its lowest detent, however hard the
  /// rider pulls. Deep enough to read as ground given rather than as a jitter,
  /// shallow enough that the sheet plainly is not going anywhere.
  static const _maxFloorGivePx = 28.0;

  /// The share of the finger the sheet follows in the *first* pixels past the
  /// bottom detent, before the resistance builds. Apple's rubber-band constant.
  static const _floorResistance = 0.55;

  /// Below this the give is invisible, so it is treated as settled rather than
  /// re-sprung: a spring lands arbitrarily close to zero, never exactly on it.
  static const _settledPx = 0.5;

  /// Apple's rubber-band curve. The give starts out following the finger at
  /// [_floorResistance] and bends asymptotically toward [_maxFloorGivePx], so
  /// the sheet slows to a stop instead of hitting a wall — and no amount of
  /// extra pull buys any more travel.
  static double _rubberBand(double overshoot) =>
      (overshoot * _maxFloorGivePx * _floorResistance) /
      (_maxFloorGivePx + _floorResistance * overshoot);

  /// Whether [overflow] is the sheet refusing to go any lower. Overflow is
  /// signed — positive past the top detent, negative past the bottom one — and
  /// only the bottom is this widget's business.
  bool _isFloor(SheetMetrics metrics, double overflow) =>
      overflow < 0 && (metrics.offset - metrics.minOffset).abs() < 1.0;

  void _onFloorOverflow(double overflow) {
    // Assigning `value` also stops a spring-back still in flight, which is
    // what lets the rider catch the sheet on its way home and keep pulling
    // from where it is.
    final from = _onFloor ? _overflow.value : 0.0;
    _overflow.value = from + overflow.abs();
    _onFloor = true;
  }

  /// Ends the pull: hands the give back to a spring.
  ///
  /// [velocity] is the give's own rate of change, so the sheet leaves the
  /// finger at exactly the speed the finger left it — no seam between the drag
  /// and the settle.
  void _cleanup({double velocity = 0}) {
    _onFloor = false;
    // Guarded on `isAnimating` because a drag past a detent reports "no
    // overflow" on every frame it is back within bounds; restarting the spring
    // on each of those would freeze it at its first frame.
    if (_overflow.value > _settledPx && !_overflow.isAnimating) {
      unawaited(
        _overflow.animateWith(
          SpringSimulation(AppMotion.spring, _overflow.value, 0, velocity),
        ),
      );
    }
  }

  @override
  void dispose() {
    _overflow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The give is positional, so reduce-motion drops it (see AppMotion.reduced)
    // and leaves the arrival haptic alone — the honest translation: there is
    // nothing to warn about down there, only a fact to state.
    final reduced = AppMotion.reduced(context);
    return NotificationListener<SheetNotification>(
      onNotification: (notification) {
        switch (notification) {
          case SheetDragStartNotification():
            _dragging = true;
          // Cancel matters as much as end: a drag the gesture arena takes away
          // mid-pull would otherwise leave the sheet held off its detent.
          case SheetDragEndNotification(:final dragDetails):
            _dragging = false;
            // The give grows as the sheet is pushed *down* past its lowest
            // detent, so its rate is the finger's vertical velocity inverted.
            _cleanup(velocity: -dragDetails.velocityY);
          case SheetDragCancelNotification():
            _dragging = false;
            _cleanup();
          case SheetOverflowNotification(:final overflow, :final metrics):
            if (_dragging && _isFloor(metrics, overflow)) {
              _onFloorOverflow(overflow);
            } else {
              _cleanup();
            }
          default:
            break;
        }
        return false;
      },
      child: AnimatedBuilder(
        animation: _overflow,
        // Passed through untouched: the give is a transform, so the sheet's
        // content never rebuilds for it.
        child: widget.child,
        builder: (context, child) {
          // The sheet is *moved*, not scaled: shrinking it opened a gap around
          // the surface that let the map show through, which reads as the
          // sheet going translucent rather than as resistance. Sliding a
          // stretched sheet down pushes its far edge off screen instead,
          // leaving nothing to see through.
          final floorPx = reduced ? 0.0 : _rubberBand(_overflow.value);
          return Transform.translate(
            offset: Offset(0, floorPx),
            child: _SheetFloorScope(
              load: floorPx / _maxFloorGivePx,
              child: child!,
            ),
          );
        },
      ),
    );
  }
}

/// How hard the sheet above is being held against its lowest detent, 0..1, for
/// the chrome that shows it.
///
/// Zero outside a [SheetEdgeGestureDetector] — a modal has no floor, so its
/// handle simply never takes any load.
class _SheetFloorScope extends InheritedWidget {
  const _SheetFloorScope({required this.load, required super.child});

  final double load;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetFloorScope>()?.load ?? 0;

  @override
  bool updateShouldNotify(_SheetFloorScope oldWidget) => oldWidget.load != load;
}
