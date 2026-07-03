import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_event.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_car/features/favorites/favorite_actions.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/transport_icon.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<FavoritesBloc, FavoritesState>(
        builder: (context, state) {
          final items = state.items;
          final pinnedCount = state.pinned.length;
          return Column(
            children: [
              DetailAppBar(
                title: '我的收藏',
                subtitle: items.isEmpty
                    ? null
                    : '${items.length} 個收藏 · $pinnedCount 已釘選',
              ),
              Expanded(
                child: items.isEmpty
                    ? const _FavoritesEmpty()
                    : _FavoritesList(items: items),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FavoritesList extends StatelessWidget {
  const _FavoritesList({required this.items});

  final List<Favorite> items;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: items.length,
      onReorderStart: (_) => unawaited(HapticService.instance.lightTap()),
      onReorderItem: (oldIndex, newIndex) {
        final next = [...items];
        next.insert(newIndex, next.removeAt(oldIndex));
        context.read<FavoritesBloc>().add(FavoritesReordered(next));
      },
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        child: child,
      ),
      itemBuilder: (context, index) {
        final fav = items[index];
        return _FavoriteListRow(
          key: ValueKey(fav.id),
          fav: fav,
          index: index,
        );
      },
    );
  }
}

class _FavoriteListRow extends StatelessWidget {
  const _FavoriteListRow({
    required this.fav,
    required this.index,
    super.key,
  });

  final Favorite fav;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('dismiss-${fav.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        unawaited(HapticService.instance.lightTap());
        context.read<FavoritesBloc>().add(FavoriteRemoved(fav.id));
      },
      background: Container(
        color: cs.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(
          Symbols.delete_rounded,
          color: cs.onErrorContainer,
          size: 22,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Pressable(
          onTap: () {
            unawaited(HapticService.instance.lightTap());
            openFavorite(context, fav);
          },
          semanticLabel: fav.title,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
              child: Row(
                children: [
                  TransportIcon(type: transportTypeForFavorite(fav)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fav.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (fav.subtitle.isNotEmpty)
                          Text(
                            fav.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _PinButton(fav: fav),
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Symbols.drag_handle_rounded,
                        size: 22,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({required this.fav});

  final Favorite fav;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: fav.pinned ? '取消釘選' : '釘選至首頁',
      child: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(
          Symbols.keep_rounded,
          fill: fav.pinned ? 1 : 0,
          size: 22,
          color: fav.pinned ? cs.onSurface : cs.onSurfaceVariant,
        ),
        onPressed: () {
          unawaited(HapticService.instance.lightTap());
          context.read<FavoritesBloc>().add(
            FavoritePinChanged(fav.id, pinned: !fav.pinned),
          );
        },
      ),
    );
  }
}

class _FavoritesEmpty extends StatelessWidget {
  const _FavoritesEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.bookmark_rounded, size: 44, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              '尚無收藏',
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '在站牌或路線頁點收藏即可加入，釘選後會顯示在首頁',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
