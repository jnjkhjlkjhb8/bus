part of '../view/search_screen.dart';

class _RecentSearches extends StatelessWidget {
  const _RecentSearches();

  void _remove(BuildContext context, SearchResult result, int index) {
    unawaited(HapticService.instance.lightTap());
    final bloc = context.read<SearchBloc>()..add(SearchRecentRemoved(result));
    AppSnackbar.show(
      context,
      AppI18n.of(context).searchRecentRemoved(result.name),
      action: AppI18n.of(context).commonUndo,
      // Restores at the original index. Re-adding would promote the entry to
      // the top of the list, which isn't what AppI18n.of(context).commonUndo claims to do.
      onAction: () => bloc.add(SearchRecentRestored(result, index)),
    );
  }

  Future<void> _clearAll(BuildContext context) async {
    final bloc = context.read<SearchBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppI18n.of(context).searchRecentClearTitle),
        content: Text(AppI18n.of(context).searchRecentClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppI18n.of(context).searchRecentKeep),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppI18n.of(context).searchRecentClear),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      unawaited(HapticService.instance.lightTap());
      bloc.add(const SearchRecentsCleared());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final recentItems = context.select<SearchBloc, List<SearchResult>>(
      (bloc) => bloc.state.recentResults,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: AppI18n.of(context).searchRecent,
          trailing: recentItems.isEmpty
              ? null
              : Pressable(
                  onTap: () => unawaited(_clearAll(context)),
                  semanticLabel: AppI18n.of(context).searchRecentClearSemantics,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: _minTouchTarget,
                      // 44 not 48: this is what sets the header band's height.
                      // Still at the HIG minimum.
                      minHeight: 44,
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      AppI18n.of(context).commonClear,
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(
          child: recentItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      AppI18n.of(context).searchRecentEmpty,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyRegular.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.zero,
                  itemCount: recentItems.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    thickness: 0.5,
                    color: cs.outlineVariant,
                  ),
                  itemBuilder: (context, index) {
                    final result = recentItems[index];
                    return Dismissible(
                      key: ValueKey('recent-${result.type.name}-${result.uid}'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _remove(context, result, index),
                      background: Container(
                        color: cs.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Icon(
                          Icons.delete_rounded,
                          color: cs.onErrorContainer,
                          size: 22,
                        ),
                      ),
                      child: Semantics(
                        // Swiping is the only way to delete for a sighted
                        // user; a screen reader needs an equivalent it can
                        // actually reach, so the same action is exposed here
                        // and on long-press.
                        customSemanticsActions: {
                          CustomSemanticsAction(
                            label: AppI18n.of(context).searchRecentRemoveOne,
                          ): () =>
                              _remove(context, result, index),
                        },
                        child: Pressable(
                          onTap: () => _navigateToResult(context, result),
                          onLongPress: () => _remove(context, result, index),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 56),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: cs.surface,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.access_time_rounded,
                                      size: 16,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        result.name,
                                        style: AppTextStyles.bodyRegular
                                            .copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSurface,
                                              height: 1.3,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        result.subtitle,
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: cs.onSurfaceVariant,
                                          height: 1.3,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 24,
                                  color: cs.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
