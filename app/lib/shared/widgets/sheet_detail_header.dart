import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_event.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';

/// Shared header for a second-layer station-detail sheet: a drag handle on
/// top (matching the root sheet), then a row of `[back] title [favorite]`.
/// Back pops the enclosing navigator (the sheet's nested navigator in the home
/// flow, or the route in a standalone screen). Provide [favorite] for the
/// standard bookmark toggle, or [trailing] for a custom trailing action.
class SheetDetailHeader extends StatelessWidget {
  const SheetDetailHeader({
    required this.title,
    this.subtitle,
    this.favorite,
    this.trailing,
    super.key,
  }) : assert(
         favorite == null || trailing == null,
         'Pass favorite or trailing, not both.',
       );

  final String title;

  /// Secondary line under the title (e.g. a freshness timestamp), so metadata
  /// shares the header row instead of costing its own row of sheet height.
  final Widget? subtitle;

  /// Standard bookmark toggle target. When set, renders the favorite button.
  final Favorite? favorite;

  /// Custom trailing widget, used when the favorite is non-standard.
  final Widget? trailing;

  void _back(BuildContext context) {
    unawaited(HapticService.instance.lightTap());
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetDragHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 12, 4),
          child: Row(
            children: [
              Pressable(
                onTap: () => _back(context),
                semanticLabel: '返回',
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: AppTextStyles.heading2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ?subtitle,
                  ],
                ),
              ),
              if (favorite != null) FavoriteToggleButton(favorite: favorite!),
              // Mutually exclusive with favorite (see assert): when a favorite
              // is set, trailing is null and this adds nothing.
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}

/// Bookmark toggle for a [Favorite]: filled when saved, with an undo snackbar.
/// Reused by [SheetDetailHeader] and by full-page detail app bars. Requires a
/// [FavoritesBloc] above it in the tree.
class FavoriteToggleButton extends StatelessWidget {
  const FavoriteToggleButton({required this.favorite, super.key});

  final Favorite favorite;

  void _toggle(BuildContext context) {
    unawaited(HapticService.instance.lightTap());
    final wasSaved = context.read<FavoritesBloc>().state.contains(favorite.id);
    context.read<FavoritesBloc>().add(FavoriteToggled(favorite));
    AppSnackbar.show(
      context,
      wasSaved ? '已取消收藏' : '已加入收藏',
      action: '復原',
      onAction: () => _toggle(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<FavoritesBloc, FavoritesState>(
      buildWhen: (p, n) => p.contains(favorite.id) != n.contains(favorite.id),
      builder: (context, state) {
        final saved = state.contains(favorite.id);
        return Pressable(
          onTap: () => _toggle(context),
          semanticLabel: saved ? '取消收藏' : '收藏',
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              size: 22,
              color: cs.onSurface,
            ),
          ),
        );
      },
    );
  }
}
