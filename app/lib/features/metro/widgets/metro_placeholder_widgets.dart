part of '../view/metro_screen.dart';

class _MetroPlaceholderSheet extends StatefulWidget {
  const _MetroPlaceholderSheet({
    required this.onStationSelect,
    super.key,
  });

  final ValueChanged<MetroMapStation> onStationSelect;

  @override
  State<_MetroPlaceholderSheet> createState() => _MetroPlaceholderSheetState();
}

class _MetroPlaceholderSheetState extends State<_MetroPlaceholderSheet> {
  late final TextEditingController _searchCtrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            onChanged: (val) => setState(() => _query = val),
            style: AppTextStyles.bodyLarge,
            decoration: InputDecoration(
              hintText: '搜尋捷運車站...',
              prefixIcon: Icon(Icons.search_rounded, color: cs.outline),
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
              fillColor: cs.surfaceContainerHigh,
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
                    _lineName(station.id),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '找不到符合的車站',
            style: AppTextStyles.bodyRegular.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
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
                '我的收藏車站',
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      '尚無收藏的車站\n在地圖上選擇車站後點選右上角 [ 收藏 ] 以新增',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
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
