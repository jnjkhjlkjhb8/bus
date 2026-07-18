import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/data/repositories/place_recent_repository.dart';
import 'package:wheres_the_car/data/repositories/places_repository.dart';
import 'package:wheres_the_car/data/repositories/saved_place_repository.dart';
import 'package:wheres_the_car/features/go/model/planned_place.dart';
import 'package:wheres_the_car/features/go/model/saved_place_icons.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';
import 'package:wheres_the_car/shared/widgets/app_dialog.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_car/shared/widgets/app_spinner.dart';

Future<PlannedPlace> resolveCurrentPlace() async {
  final pos = await LocationService.instance.currentPosition();
  return PlannedPlace(
    name: '目前位置',
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

/// The shared place-search body: current location, saved places, recent
/// searches, and autocomplete-on-type — reused inline by the plan-entry page
/// (input hidden, picking sets the destination) and by [PlaceSearchScreen]
/// (input active, picking pops the page). It never navigates itself; picking a
/// place only calls [onPicked].
class PlaceSearchView extends StatefulWidget {
  const PlaceSearchView({
    required this.onPicked,
    this.showInput = false,
    this.autofocus = false,
    this.fieldLabel = '搜尋地點',
    this.allowCurrentLocation = true,
    this.emptyHint,
    this.footer,
    this.onBack,
    super.key,
  });

  final ValueChanged<PlannedPlace> onPicked;
  final bool showInput;
  final bool autofocus;
  final String fieldLabel;
  final bool allowCurrentLocation;

  /// Shown (once) when there are no saved places and no recents to fill the
  /// list — a quiet prompt rather than a blank surface. Used by the plan-entry
  /// host; null on the search page (where the keyboard is already up).
  final String? emptyHint;

  /// Appended below the shortcut list while the query is empty (hidden during
  /// autocomplete). The plan-entry host uses it for the 路線箱 saved-routes
  /// section; the search page leaves it null.
  final Widget? footer;

  /// When set, a leading back button is shown in the input row.
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
    if (widget.showInput && widget.autofocus) {
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
      final place = await resolveCurrentPlace();
      if (!mounted) return;
      widget.onPicked(place);
      if (mounted) setState(() => _resolvingLocation = false);
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _resolvingLocation = false);
      AppSnackbar.show(context, '無法取得目前位置', type: SnackType.error);
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
      AppSnackbar.show(context, '無法取得地點資訊', type: SnackType.error);
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
      '已移除搜尋紀錄',
      action: '復原',
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
    AppSnackbar.show(context, '已儲存地點', type: SnackType.success);
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
      AppSnackbar.show(context, '無法取得地點資訊', type: SnackType.error);
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
      '已移除儲存地點',
      action: '復原',
      onAction: () async {
        await SavedPlaceRepository.instance.add(place);
        if (!mounted) return;
        setState(() => _saved = SavedPlaceRepository.instance.all());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showInput) _buildInputRow(context),
        Expanded(child: _buildList(context)),
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
              semanticLabel: '返回',
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
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: cs.onSurface,
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
                      semanticLabel: '清除',
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (!_empty) {
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
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (widget.allowCurrentLocation)
          _CurrentLocationRow(
            loading: _resolvingLocation,
            onTap: _useCurrentLocation,
          ),
        if (_saved.isEmpty && _recents.isEmpty && widget.emptyHint != null)
          _EmptyHint(widget.emptyHint!),
        if (_saved.isNotEmpty) ...[
          const _SectionDivider(),
          const _SectionLabel('儲存地點'),
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
          const _SectionDivider(),
          const _SectionLabel('最近搜尋'),
          for (final place in _recents)
            _RecentPlaceRow(
              key: ValueKey('recent-${_placeKey(place)}'),
              place: place,
              onTap: () => _pickPlace(place),
              onSave: () => _saveFrom(place),
              onRemove: () => _removeRecent(place),
            ),
        ],
        if (widget.footer != null) widget.footer!,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
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

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(height: 8, color: cs.surfaceContainerHigh);
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
      semanticLabel: '使用目前位置',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.my_location_rounded, size: 22, color: cs.primary),
            const SizedBox(width: 14),
            Text(
              '目前位置',
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

// A row whose right-swipe reveals a neutral "儲存" affordance and whose
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
                    '儲存',
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            leading,
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  width: 160,
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  ),
                ),
              ],
            ),
          ),
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
            '找不到符合的地點',
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
      title: '儲存地點',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '名稱',
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
            '圖示',
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
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: '儲存',
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
