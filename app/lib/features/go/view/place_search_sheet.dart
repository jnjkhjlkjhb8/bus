import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/features/go/model/planned_place.dart';
import 'package:wheres_the_car/features/search/bloc/search_bloc.dart';
import 'package:wheres_the_car/features/search/bloc/search_event.dart';
import 'package:wheres_the_car/features/search/bloc/search_state.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';

Future<PlannedPlace> resolveCurrentPlace() async {
  final pos = await LocationService.instance.currentPosition();
  return PlannedPlace(
    name: '目前位置',
    latLng: LatLng(pos.latitude, pos.longitude),
    isCurrentLocation: true,
  );
}

Future<PlannedPlace?> showPlaceSearchSheet(
  BuildContext context, {
  required String fieldLabel,
  bool allowCurrentLocation = true,
}) {
  return showModalBottomSheet<PlannedPlace>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider(
      create: (_) => SearchBloc(),
      child: _PlaceSearchSheet(
        fieldLabel: fieldLabel,
        allowCurrentLocation: allowCurrentLocation,
      ),
    ),
  );
}

class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet({
    required this.fieldLabel,
    required this.allowCurrentLocation,
  });

  final String fieldLabel;
  final bool allowCurrentLocation;

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _resolvingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    unawaited(HapticService.instance.lightTap());
    setState(() => _resolvingLocation = true);
    try {
      final pos = await LocationService.instance.currentPosition();
      if (!mounted) return;
      Navigator.of(context).pop(
        PlannedPlace(
          name: '目前位置',
          latLng: LatLng(pos.latitude, pos.longitude),
          isCurrentLocation: true,
        ),
      );
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _resolvingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('無法取得目前位置'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _pick(SearchResult result) {
    if (result.lat == null || result.lon == null) return;
    unawaited(HapticService.instance.lightTap());
    Navigator.of(context).pop(
      PlannedPlace(
        name: result.name,
        latLng: LatLng(result.lat!, result.lon!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        height: media.size.height * 0.86,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusBottomSheet),
          ),
        ),
        child: Column(
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusCard,
                        ),
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
                              onChanged: (v) => context.read<SearchBloc>().add(
                                SearchQueryChanged(v),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: () => Navigator.of(context).pop(),
                    semanticLabel: '取消',
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(
                          '取消',
                          style: AppTextStyles.bodyRegular.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<SearchBloc, SearchState>(
                builder: (context, state) {
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (widget.allowCurrentLocation &&
                          _controller.text.isEmpty)
                        _CurrentLocationRow(
                          loading: _resolvingLocation,
                          onTap: _useCurrentLocation,
                        ),
                      if (state.loading && state.results.isEmpty)
                        const _PlaceSkeleton()
                      else if (state.query.isNotEmpty && state.results.isEmpty)
                        const _PlaceEmpty()
                      else
                        for (final r in state.results)
                          _PlaceResultRow(
                            result: r,
                            enabled: r.lat != null && r.lon != null,
                            onTap: () => _pick(r),
                          ),
                    ],
                  );
                },
              ),
            ),
          ],
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
      semanticLabel: '使用目前位置',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.my_location_rounded, size: 22, color: cs.primary),
            const SizedBox(width: 14),
            Text(
              '目前位置',
              style: AppTextStyles.bodyLarge.copyWith(color: cs.onSurface),
            ),
            const Spacer(),
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceResultRow extends StatelessWidget {
  const _PlaceResultRow({
    required this.result,
    required this.enabled,
    required this.onTap,
  });

  final SearchResult result;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Pressable(
        onTap: enabled ? onTap : null,
        semanticLabel: result.name,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    if (result.subtitle.isNotEmpty)
                      Text(
                        result.subtitle,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
