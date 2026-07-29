part of '../home_screen.dart';

class _SearchBar extends StatelessWidget {
  const _SearchBar({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: AppI18n.of(context).homeSearchHint,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        alignment: Alignment.center,
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppI18n.of(context).homeSearchHint,
                style: AppTextStyles.bodyRegular.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FavoritesBloc, FavoritesState>(
      buildWhen: (p, c) => p.pinned != c.pinned,
      builder: (context, state) {
        final pinned = state.pinned;
        if (pinned.isEmpty) {
          return const _FavoritesEmpty();
        }
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ...pinned.map((fav) => FavoriteTile(fav: fav)),
            _SeeMoreButton(),
          ],
        );
      },
    );
  }
}

class _SeeMoreButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () {
        unawaited(context.push('/favorites'));
      },
      semanticLabel: AppI18n.of(context).homeSeeAllFavorites,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppI18n.of(context).homeSeeAllFavorites,
              style: AppTextStyles.bodyRegular.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesEmpty extends StatelessWidget {
  const _FavoritesEmpty();

  @override
  Widget build(BuildContext context) {
    return _EmptyState(
      icon: Icons.push_pin_outlined,
      heading: AppI18n.of(context).homeNoPinned,
      body: AppI18n.of(context).homeNoPinnedBody,
      actionLabel: AppI18n.of(context).homeGoToFavorites,
      onAction: () {
        unawaited(context.push('/favorites'));
      },
    );
  }
}

/// Shared shape for every empty state inside this sheet: icon, heading,
/// body, and an optional hug-width CTA. Anchored to the upper third rather
/// than centred — on the full detent, a centred empty state reads as
/// content that failed to load. Kept private to this file (and its sibling
/// part files, which share the library) rather than promoted to a public
/// widget, since only the two sheet tabs need it.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.heading,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String heading;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: const Alignment(0, -0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              heading,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              Pressable(
                onTap: onAction,
                semanticLabel: actionLabel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(
                      AppTheme.radiusButton,
                    ),
                  ),
                  child: Text(
                    actionLabel!,
                    style: AppTextStyles.bodyRegular.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
