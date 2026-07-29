part of '../view/metro_screen.dart';

class _MetroPlaceholderSheet extends StatefulWidget {
  const _MetroPlaceholderSheet({
    required this.onStationSelect,
    required this.sheetController,
    super.key,
  });

  final ValueChanged<MetroMapStation> onStationSelect;

  /// Drives the parent `Sheet`'s detent so the search field isn't left
  /// covered by the keyboard (B2) — see `_onSearchFocusChange`.
  final SheetController sheetController;

  @override
  State<_MetroPlaceholderSheet> createState() => _MetroPlaceholderSheetState();
}

class _MetroPlaceholderSheetState extends State<_MetroPlaceholderSheet> {
  late final TextEditingController _searchCtrl;
  late final FocusNode _searchFocus;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _searchFocus = FocusNode()..addListener(_onSearchFocusChange);
  }

  @override
  void dispose() {
    _searchFocus
      ..removeListener(_onSearchFocusChange)
      ..dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Focusing the search field brings up the keyboard, which otherwise covers
  // roughly the bottom third of the sheet at its `half` detent — under two
  // result rows of clearance. Move to `tall` so results have room above the
  // keyboard; the sheet doesn't react to the keyboard on its own (B2).
  void _onSearchFocusChange() {
    // A focus change can still be delivered while an ancestor is being torn
    // down, after this State is defunct — both the MediaQuery lookup and the
    // sheet animation below would throw on a dead element.
    if (!mounted) return;
    if (!_searchFocus.hasFocus) return;
    unawaited(
      widget.sheetController.animateToDetent(
        AppSheetSnap.tall,
        reduced: AppMotion.reduced(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // surfaceContainerHigh and surfaceContainerLow are both pure white in
    // the light scheme and the sheet background is surfaceContainerLow, so
    // the field needs the light-scheme surface tone instead to read as a
    // distinct control (mirrors _SystemPill's brightness split).
    final fieldFill = cs.brightness == Brightness.light
        ? cs.surface
        : cs.surfaceContainerHigh;
    final favIds = context
        .watch<FavoritesBloc>()
        .state
        .items
        .where((f) => f.type == FavoriteType.metroStation)
        .map((f) => f.refId)
        .toSet();

    final searchResults = _query.isEmpty
        ? const <MetroMapStation>[]
        : metroMapStations.where((s) {
            final q = _query.toLowerCase();
            return s.name.toLowerCase().contains(q) ||
                s.id.toLowerCase().contains(q);
          }).toList();

    final favStations = metroMapStations
        .where((s) => favIds.contains(s.id))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            onChanged: (val) => setState(() => _query = val),
            style: AppTextStyles.bodyLarge,
            decoration: InputDecoration(
              hintText: AppI18n.of(context).metroSearchHint,
              prefixIcon: Icon(
                Icons.search_rounded,
                color: cs.onSurfaceVariant,
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              filled: true,
              fillColor: fieldFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _query.isNotEmpty
              ? _buildSearchResults(cs, searchResults)
              : _buildFavoritesList(cs, favStations),
        ),
      ],
    );
  }

  Widget _stationRow(
    ColorScheme cs,
    MetroMapStation station, {
    Widget? trailing,
  }) {
    return Pressable(
      onTap: () {
        FocusScope.of(context).unfocus();
        widget.onStationSelect(station);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            TransportIcon(type: _getTransportType(_lineCode(station.id))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _lineName(AppI18n.of(context), station.id),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme cs, List<MetroMapStation> results) {
    if (results.isEmpty) {
      // The parent Sheet's content box is SheetSize.stretch — full viewport
      // height — while the sheet itself only rests at the `half` detent, so
      // a Center here lands well below the visible sheet area. Top-align
      // instead; don't reintroduce Center/Expanded for this branch.
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppI18n.of(context).metroNoStationMatch(_query),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyRegular.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppI18n.of(context).metroSearchNoMatchHint,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      // Keyboard clearance: the sheet doesn't resize for the keyboard on its
      // own, so without this the last row(s) can sit permanently behind it
      // (B2).
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        32 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      itemCount: results.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
      itemBuilder: (context, index) => _stationRow(cs, results[index]),
    );
  }

  Widget _buildFavoritesList(ColorScheme cs, List<MetroMapStation> favs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              Icon(Icons.bookmark_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                AppI18n.of(context).metroFavoriteStations,
                style: AppTextStyles.bodyRegular.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: favs.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                    child: Text(
                      AppI18n.of(context).metroNoFavoriteStations,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  // Keyboard clearance, same as the search results list (B2).
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    32 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  itemCount: favs.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                  itemBuilder: (context, index) => _stationRow(
                    cs,
                    favs[index],
                    trailing: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
