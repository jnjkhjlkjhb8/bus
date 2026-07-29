import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/haptics/haptic_service.dart';
import 'package:wheres_the_bus/core/location/location_service.dart';
import 'package:wheres_the_bus/data/repositories/place_recent_repository.dart';
import 'package:wheres_the_bus/data/repositories/places_repository.dart';
import 'package:wheres_the_bus/data/repositories/saved_place_repository.dart';
import 'package:wheres_the_bus/features/go/model/planned_place.dart';
import 'package:wheres_the_bus/features/go/model/saved_place_icons.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/widgets/app_button.dart';
import 'package:wheres_the_bus/shared/widgets/app_dialog.dart';
import 'package:wheres_the_bus/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_bus/shared/widgets/app_spinner.dart';
import 'package:wheres_the_bus/shared/widgets/state_cards.dart';

Future<PlannedPlace> resolveCurrentPlace(AppI18n i18n) async {
  // A granted permission still fails here when the fix times out (indoors,
  // cold GPS). The OS cached fix is accurate enough for an origin, so fall
  // back to it and only report "no location" when that is missing too — which
  // is also the case for a real denial, since lastKnownPosition returns null
  // without permission.
  Position pos;
  try {
    pos = await LocationService.instance.currentPosition();
  } on Object {
    final cached = await LocationService.instance.lastKnownPosition();
    if (cached == null) rethrow;
    pos = cached;
  }
  return PlannedPlace(
    name: i18n.goCurrentLocation,
    latLng: LatLng(pos.latitude, pos.longitude),
    isCurrentLocation: true,
  );
}

/// Pushes the full-page place search and returns the picked place (or null on
/// back). Replaces the former modal bottom sheet; the planner's field-edit path
/// and the plan-entry fields both route here.
Future<PlannedPlace?> showPlaceSearchPage(
  BuildContext context, {
  required String fieldLabel,
  bool allowCurrentLocation = true,
}) {
  return Navigator.of(context).push<PlannedPlace>(
    MaterialPageRoute(
      builder: (_) => PlaceSearchScreen(
        fieldLabel: fieldLabel,
        allowCurrentLocation: allowCurrentLocation,
      ),
    ),
  );
}

/// The pushed search page: a plain [Scaffold] hosting [PlaceSearchView] with
/// its input active. Picking a place pops the page with it.
class PlaceSearchScreen extends StatelessWidget {
  const PlaceSearchScreen({
    required this.fieldLabel,
    this.allowCurrentLocation = true,
    super.key,
  });

  final String fieldLabel;
  final bool allowCurrentLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: PlaceSearchView(
          showInput: true,
          autofocus: true,
          fieldLabel: fieldLabel,
          allowCurrentLocation: allowCurrentLocation,
          onBack: () => Navigator.of(context).maybePop(),
          onPicked: (place) => Navigator.of(context).pop(place),
        ),
      ),
    );
  }
}

/// Builds the surface hosting the search field. [input] is the wired text field
/// (with its own clear button); the builder decides where it sits — the
/// plan-entry page drops it into the destination row of its origin/destination
/// block, so typing happens on the same screen the planner opens at.
typedef PlaceSearchHeaderBuilder =
    Widget Function(BuildContext context, Widget input);

/// The shared place-search body: current location, saved places, recent
/// searches, and autocomplete-on-type — reused inline by the plan-entry page
/// (its own header hosts the field, picking sets the destination) and by
/// [PlaceSearchScreen] (plain input row, picking pops the page). It never
/// navigates itself; picking a place only calls [onPicked].
class PlaceSearchView extends StatefulWidget {
  const PlaceSearchView({
    required this.onPicked,
    this.showInput = false,
    this.autofocus = false,
    this.fieldLabel,
    this.allowCurrentLocation = true,
    this.emptyHint,
    this.header,
    this.headerBuilder,
    this.onBack,
    super.key,
  });

  final ValueChanged<PlannedPlace> onPicked;

  /// Whether the built-in input row is shown. Ignored when [headerBuilder] is
  /// set — the host is then responsible for placing the field.
  final bool showInput;
  final bool autofocus;

  /// Null takes the standard placeholder, which needs a locale to resolve —
  /// and a const default has no context to resolve it with.
  final String? fieldLabel;
  final bool allowCurrentLocation;

  /// Shown when there are no saved places and no recents to fill the list — a
  /// quiet prompt rather than a blank surface.
  final String? emptyHint;

  /// Sits above the shortcut list while the query is empty (hidden during
  /// autocomplete). The plan-entry host uses it for the 路線箱 saved routes:
  /// a saved route is a whole answer in one tap, so it outranks the places
  /// below it.
  final Widget? header;

  /// Replaces the built-in input row, handing back the wired text field for the
  /// host to place. When set, the field is focused on first frame.
  final PlaceSearchHeaderBuilder? headerBuilder;

  /// When set, a leading back button is shown in the built-in input row.
  final VoidCallback? onBack;

  @override
  State<PlaceSearchView> createState() => _PlaceSearchViewState();
}

class _PlaceSearchViewState extends State<PlaceSearchView> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<PlaceSuggestion> _results = const [];
  List<PlannedPlace> _recents = const [];
  List<PlannedPlace> _saved = const [];
  bool _loading = false;
  bool _resolvingLocation = false;
  // The placeId currently resolving a Places `details()` fetch (from either
  // a tap-to-pick or a swipe-to-save), so only that row shows a busy state
  // instead of the whole list.
  String? _pickingId;

  @override
  void initState() {
    super.initState();
    _recents = PlaceRecentRepository.instance.all();
    _saved = SavedPlaceRepository.instance.all();
    // A hosted field is the reason the screen exists, so it always takes focus.
    // Deferred a frame: requesting focus during the route transition drops
    // frames of the push the rider is watching.
    final hosted = widget.headerBuilder != null;
    if (hosted || (widget.showInput && widget.autofocus)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusNode.requestFocus(),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _empty => _controller.text.trim().isEmpty;

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    try {
      final results = await PlacesRepository.instance.autocomplete(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    unawaited(HapticService.instance.lightTap());
    setState(() => _resolvingLocation = true);
    try {
      final place = await resolveCurrentPlace(AppI18n.of(context));
      if (!mounted) return;
      widget.onPicked(place);
      if (mounted) setState(() => _resolvingLocation = false);
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _resolvingLocation = false);
      AppSnackbar.show(
        context,
        AppI18n.of(context).goLocationUnavailable,
        type: SnackType.error,
      );
    }
  }

  Future<void> _pickResult(PlaceSuggestion suggestion) async {
    if (_pickingId != null) return;
    unawaited(HapticService.instance.lightTap());
    setState(() => _pickingId = suggestion.placeId);
    try {
      final place = await PlacesRepository.instance.details(suggestion.placeId);
      await PlaceRecentRepository.instance.add(place);
      if (!mounted) return;
      widget.onPicked(place);
      if (mounted) setState(() => _pickingId = null);
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _pickingId = null);
      AppSnackbar.show(
        context,
        AppI18n.of(context).goPlaceUnavailable,
        type: SnackType.error,
      );
    }
  }

  // A recent/saved place already carries coordinates, so it returns straight
  // away without a fresh Places details lookup.
  void _pickPlace(PlannedPlace place) {
    unawaited(HapticService.instance.lightTap());
    widget.onPicked(place);
  }

  Future<void> _removeRecent(PlannedPlace place) async {
    unawaited(HapticService.instance.lightTap());
    await PlaceRecentRepository.instance.remove(place);
    if (!mounted) return;
    setState(() => _recents = PlaceRecentRepository.instance.all());
    AppSnackbar.show(
      context,
      AppI18n.of(context).goRecentRemoved,
      action: AppI18n.of(context).commonUndo,
      onAction: () async {
        await PlaceRecentRepository.instance.add(place);
        if (!mounted) return;
        setState(() => _recents = PlaceRecentRepository.instance.all());
      },
    );
  }

  // Right-swipe on a result or recent opens the save dialog prefilled with the
  // place's own name; on confirm it is pinned to saved places.
  Future<void> _saveFrom(PlannedPlace place) async {
    final result = await showSavePlaceDialog(context, initialName: place.name);
    if (result == null || !mounted) return;
    await SavedPlaceRepository.instance.add(
      place.copyWith(name: result.name, iconKey: result.iconKey),
    );
    if (!mounted) return;
    setState(() => _saved = SavedPlaceRepository.instance.all());
    AppSnackbar.show(
      context,
      AppI18n.of(context).goPlaceSaved,
      type: SnackType.success,
    );
  }

  // A search result carries no coordinates, so resolve its details before
  // opening the save dialog — otherwise the pin would be stored at (0, 0).
  Future<void> _saveFromResult(PlaceSuggestion suggestion) async {
    if (_pickingId != null) return;
    setState(() => _pickingId = suggestion.placeId);
    PlannedPlace place;
    try {
      place = await PlacesRepository.instance.details(suggestion.placeId);
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _pickingId = null);
      AppSnackbar.show(
        context,
        AppI18n.of(context).goPlaceUnavailable,
        type: SnackType.error,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _pickingId = null);
    await _saveFrom(place);
  }

  Future<void> _editSaved(PlannedPlace place) async {
    final result = await showSavePlaceDialog(
      context,
      initialName: place.name,
      initialIcon: place.iconKey,
    );
    if (result == null || !mounted) return;
    await SavedPlaceRepository.instance.add(
      place.copyWith(name: result.name, iconKey: result.iconKey),
    );
    if (!mounted) return;
    setState(() => _saved = SavedPlaceRepository.instance.all());
  }

  Future<void> _removeSaved(PlannedPlace place) async {
    unawaited(HapticService.instance.lightTap());
    await SavedPlaceRepository.instance.remove(place);
    if (!mounted) return;
    setState(() => _saved = SavedPlaceRepository.instance.all());
    AppSnackbar.show(
      context,
      AppI18n.of(context).goSavedPlaceRemoved,
      action: AppI18n.of(context).commonUndo,
      onAction: () async {
        await SavedPlaceRepository.instance.add(place);
        if (!mounted) return;
        setState(() => _saved = SavedPlaceRepository.instance.all());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final headerBuilder = widget.headerBuilder;
    return Column(
      children: [
        if (headerBuilder != null)
          headerBuilder(context, _buildInput(context))
        else if (widget.showInput)
          _buildInputRow(context),
        Expanded(child: _buildList(context)),
      ],
    );
  }

  /// The text field itself plus its clear button — everything the host needs to
  /// drop the search into a row of its own design.
  Widget _buildInput(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            style: AppTextStyles.bodyLarge.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: widget.fieldLabel,
              hintStyle: AppTextStyles.bodyLarge.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        if (!_empty)
          Pressable(
            onTap: () {
              _controller.clear();
              _onQueryChanged('');
            },
            semanticLabel: AppI18n.of(context).commonClear,
            minTapSize: 44,
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildInputRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 16, 12),
      child: Row(
        children: [
          if (widget.onBack != null)
            Pressable(
              onTap: widget.onBack,
              semanticLabel: AppI18n.of(context).commonBack,
              child: SizedBox(
                width: 40,
                height: 44,
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 22,
                  color: cs.onSurface,
                ),
              ),
            ),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _buildInput(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    // Shortcuts and autocomplete are two readings of the same column, so they
    // cross-fade rather than hard-swapping. Keyed by which list is showing, not
    // by its contents: re-fading on every keystroke would strobe.
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : AppMotion.micro,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.01),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: _empty
          ? _buildShortcuts(context)
          : KeyedSubtree(
              key: const ValueKey('results'),
              child: _buildResults(context),
            ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_loading && _results.isEmpty) return const _PlaceSkeleton();
    if (_results.isEmpty) return const _PlaceEmpty();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _results.length,
      itemBuilder: (context, i) => _ResultRow(
        result: _results[i],
        loading: _pickingId == _results[i].placeId,
        onTap: () => _pickResult(_results[i]),
        onSave: () => _saveFromResult(_results[i]),
      ),
    );
  }

  Widget _buildShortcuts(BuildContext context) {
    return ListView(
      key: const ValueKey('shortcuts'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (widget.header != null) widget.header!,
        if (widget.allowCurrentLocation)
          _CurrentLocationRow(
            loading: _resolvingLocation,
            onTap: _useCurrentLocation,
          ),
        if (_saved.isEmpty && _recents.isEmpty && widget.emptyHint != null)
          _EmptyHint(widget.emptyHint!),
        if (_saved.isNotEmpty) ...[
          _SectionLabel(AppI18n.of(context).goSavedPlaces),
          for (final place in _saved)
            _SavedPlaceRow(
              key: ValueKey('saved-${_placeKey(place)}'),
              place: place,
              onTap: () => _pickPlace(place),
              onEdit: () => _editSaved(place),
              onRemove: () => _removeSaved(place),
            ),
        ],
        if (_recents.isNotEmpty) ...[
          _SectionLabel(AppI18n.of(context).searchRecent),
          for (final place in _recents)
            _RecentPlaceRow(
              key: ValueKey('recent-${_placeKey(place)}'),
              place: place,
              onTap: () => _pickPlace(place),
              onSave: () => _saveFrom(place),
              onRemove: () => _removeRecent(place),
            ),
        ],
      ],
    );
  }

  String _placeKey(PlannedPlace p) =>
      '${p.name}-${p.latLng.latitude}-${p.latLng.longitude}';
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyRegular.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Inset-grouped section header: a quiet label with air above it, in place of
/// the full-bleed grey slab this list used to separate sections with.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CurrentLocationRow extends StatelessWidget {
  const _CurrentLocationRow({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: loading ? null : onTap,
      semanticLabel: AppI18n.of(context).goUseCurrentLocation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.my_location_rounded, size: 22, color: cs.primary),
            const SizedBox(width: 14),
            Text(
              AppI18n.of(context).goCurrentLocation,
              style: AppTextStyles.bodyLarge.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (loading)
              AppSpinner(size: 18, strokeWidth: 2, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// A row whose right-swipe reveals a neutral AppI18n.of(context).commonSave affordance and whose
// left-swipe reveals a destructive action; a colored background is data here,
// not decoration, so it stays within the achromatic UI (error red is the one
// permitted semantic exception, used only for delete).
class _SwipeRow extends StatelessWidget {
  const _SwipeRow({
    required this.dismissKey,
    required this.child,
    this.onSaveSwipe,
    this.onDestructiveSwipe,
    this.destructiveIcon = Icons.delete_rounded,
  });

  final Key dismissKey;
  final Widget child;
  // Right-swipe (startToEnd). Shows the save affordance; returns without
  // dismissing the row.
  final VoidCallback? onSaveSwipe;
  // Left-swipe (endToStart). Removes the row.
  final VoidCallback? onDestructiveSwipe;
  final IconData destructiveIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final directions = <DismissDirection>{
      if (onSaveSwipe != null) DismissDirection.startToEnd,
      if (onDestructiveSwipe != null) DismissDirection.endToStart,
    };
    if (directions.isEmpty) return child;
    final direction = directions.length == 2
        ? DismissDirection.horizontal
        : directions.first;
    return Dismissible(
      key: dismissKey,
      direction: direction,
      background: onSaveSwipe == null
          ? null
          : Container(
              color: cs.surfaceContainerHigh,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bookmark_add_rounded,
                    color: cs.onSurface,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppI18n.of(context).commonSave,
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
      secondaryBackground: onDestructiveSwipe == null
          ? null
          : Container(
              color: cs.errorContainer,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Icon(
                destructiveIcon,
                color: cs.onErrorContainer,
                size: 22,
              ),
            ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onSaveSwipe?.call();
          return false; // save/edit: snap back, don't remove the row
        }
        return true; // destructive: confirm here, remove in onDismissed
      },
      onDismissed: (dir) {
        if (dir == DismissDirection.endToStart) onDestructiveSwipe?.call();
      },
      child: child,
    );
  }
}

class _RecentPlaceRow extends StatelessWidget {
  const _RecentPlaceRow({
    required this.place,
    required this.onTap,
    required this.onSave,
    required this.onRemove,
    super.key,
  });

  final PlannedPlace place;
  final VoidCallback onTap;
  final VoidCallback onSave;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SwipeRow(
      dismissKey: ValueKey(
        'dismiss-recent-${place.name}-'
        '${place.latLng.latitude}-${place.latLng.longitude}',
      ),
      onSaveSwipe: onSave,
      onDestructiveSwipe: onRemove,
      child: _PlaceRow(
        leading: Icon(
          Icons.access_time_rounded,
          size: 22,
          color: cs.onSurfaceVariant,
        ),
        title: place.name,
        onTap: onTap,
      ),
    );
  }
}

class _SavedPlaceRow extends StatelessWidget {
  const _SavedPlaceRow({
    required this.place,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
    super.key,
  });

  final PlannedPlace place;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SwipeRow(
      dismissKey: ValueKey(
        'dismiss-saved-${place.name}-'
        '${place.latLng.latitude}-${place.latLng.longitude}',
      ),
      onSaveSwipe: onEdit,
      onDestructiveSwipe: onRemove,
      destructiveIcon: Icons.bookmark_remove_rounded,
      child: _PlaceRow(
        leading: Icon(
          SavedPlaceIcons.resolve(place.iconKey),
          size: 22,
          color: cs.onSurface,
        ),
        title: place.name,
        onTap: onTap,
        onLongPress: onEdit,
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.result,
    required this.onTap,
    required this.onSave,
    this.loading = false,
  });

  final PlaceSuggestion result;
  final VoidCallback onTap;
  final VoidCallback onSave;

  /// True while this row's Places `details()` fetch (from a tap or a
  /// swipe-to-save) is in flight — shows a spinner in place of the leading
  /// icon instead of leaving the tap with no visible busy state.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SwipeRow(
      dismissKey: ValueKey('dismiss-result-${result.placeId}'),
      onSaveSwipe: loading ? null : onSave,
      child: _PlaceRow(
        leading: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: AppSpinner(
                  size: 18,
                  strokeWidth: 2,
                  color: cs.onSurfaceVariant,
                ),
              )
            : Icon(
                Icons.place_outlined,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
        title: result.primaryText,
        subtitle: result.secondaryText.isEmpty ? null : result.secondaryText,
        onTap: loading ? null : onTap,
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.onLongPress,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: title,
      child: Container(
        color: cs.surface,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 22, child: Center(child: leading)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceSkeleton extends StatelessWidget {
  const _PlaceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 5; i++) const ShimmerRow(height: 36),
      ],
    );
  }
}

class _PlaceEmpty extends StatelessWidget {
  const _PlaceEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            AppI18n.of(context).goNoPlaceMatch,
            style: AppTextStyles.bodyRegular.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered modal to name a saved place and pick its icon. Returns the chosen
/// `(name, iconKey)` on 儲存, or null on cancel/dismiss.
Future<({String name, String iconKey})?> showSavePlaceDialog(
  BuildContext context, {
  required String initialName,
  String? initialIcon,
}) {
  return showDialog<({String name, String iconKey})>(
    context: context,
    builder: (_) =>
        _SavePlaceDialog(initialName: initialName, initialIcon: initialIcon),
  );
}

class _SavePlaceDialog extends StatefulWidget {
  const _SavePlaceDialog({required this.initialName, this.initialIcon});

  final String initialName;
  final String? initialIcon;

  @override
  State<_SavePlaceDialog> createState() => _SavePlaceDialogState();
}

class _SavePlaceDialogState extends State<_SavePlaceDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late String _icon = widget.initialIcon ?? SavedPlaceIcons.keys.first;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  // Rebuilds only to toggle the 儲存 button's enabled state as the name
  // field crosses the empty/non-empty boundary.
  void _onNameChanged() => setState(() {});

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    unawaited(HapticService.instance.lightTap());
    Navigator.of(context).pop((name: name, iconKey: _icon));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppDialog(
      title: AppI18n.of(context).goSavedPlaces,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppI18n.of(context).commonName,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: AppTextStyles.bodyLarge.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                borderSide: BorderSide(color: cs.onSurface, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            AppI18n.of(context).commonIcon,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _IconGrid(
            selected: _icon,
            onSelect: (key) => setState(() => _icon = key),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: AppButton.outlined(
                  label: AppI18n.of(context).commonCancel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: AppI18n.of(context).commonSave,
                  onPressed: _name.text.trim().isEmpty ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final key in SavedPlaceIcons.keys)
          Pressable(
            onTap: () => onSelect(key),
            semanticLabel: key,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: key == selected
                    ? cs.surface
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(
                  color: key == selected ? cs.onSurface : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                SavedPlaceIcons.resolve(key),
                size: 22,
                color: key == selected ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
