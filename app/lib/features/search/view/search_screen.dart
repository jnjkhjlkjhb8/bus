import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/search_models.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/rail_navigation_request.dart';
import 'package:wheres_the_car/features/rail/view/rail_train_screen.dart';
import 'package:wheres_the_car/features/search/bloc/search_bloc.dart';
import 'package:wheres_the_car/features/search/bloc/search_event.dart';
import 'package:wheres_the_car/features/search/bloc/search_state.dart';
import 'package:wheres_the_car/features/search/genui/view/genui_sheet.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/transport_icon.dart';

part '../widgets/search_ai_button.dart';
part '../widgets/search_result_row.dart';
part '../widgets/recent_searches.dart';

String _todayIso() {
  final now = DateTime.now();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}

void _navigateToResult(BuildContext context, SearchResult result) {
  unawaited(HapticService.instance.lightTap());
  // Persist the selection through the recent-search repository (owned by
  // SearchBloc) so every entry point — result rows, recents, and AI — records
  // history in one place instead of writing storage directly.
  context.read<SearchBloc>().add(SearchResultSelected(result));
  switch (result.type) {
    case SearchResultType.busRoute:
      unawaited(context.push('/bus/route/${result.uid}'));
    case SearchResultType.busStation:
      unawaited(
        context.push(
          '/bus/stop',
          extra: {
            'stopName': result.name,
            'stopId': result.uid,
            'city': result.city,
          },
        ),
      );
    case SearchResultType.bikeStation:
      unawaited(
        context.push('/bike/station', extra: {'stationUid': result.uid}),
      );
    case SearchResultType.mrtStation:
      unawaited(context.push('/metro'));
    case SearchResultType.traStation:
      unawaited(
        context.push(
          '/rail/station',
          extra: {'stationId': result.uid, 'name': result.name},
        ),
      );
    case SearchResultType.thsrStation:
      // THSR has no through-station live board, so route to the O/D query
      // screen with this station preset as the origin (user picks the dest).
      RailNavigationRequest.set(
        stationId: result.uid,
        stationName: result.name,
        system: RailSystem.thsr,
      );
      unawaited(context.push('/rail'));
    case SearchResultType.traTrain:
    case SearchResultType.thsrTrain:
      unawaited(
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RailTrainScreen(
              type: result.type == SearchResultType.traTrain ? '台鐵' : '高鐵',
              trainNo: result.uid,
              date: _todayIso(),
            ),
          ),
        ),
      );
  }
}

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchBloc(),
      child: const _SearchView(),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView();

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    context.read<SearchBloc>().add(SearchQueryChanged(value));
  }

  void _onClear() {
    _controller.clear();
    context.read<SearchBloc>().add(const SearchCleared());
    _focusNode.requestFocus();
  }

  Future<void> _openGenUi() async {
    final result =
        await showGenUiSheet(context, initialQuery: _controller.text);
    if (!mounted || result == null) return;
    switch (result) {
      case GenUiSheetOpen(:final result):
        _navigateToResult(context, result);
      case GenUiSheetQuery(:final query):
        if (query.trim().isEmpty) return;
        _controller.text = query;
        _controller.selection = TextSelection.collapsed(offset: query.length);
        context.read<SearchBloc>().add(SearchQueryChanged(query));
        _focusNode.requestFocus();
    }
  }

  TransportType _transportType(SearchResultType type) => switch (type) {
    SearchResultType.busRoute => TransportType.bus,
    SearchResultType.busStation => TransportType.busStop,
    SearchResultType.bikeStation => TransportType.bike,
    SearchResultType.traStation ||
    SearchResultType.traTrain => TransportType.tra,
    SearchResultType.thsrStation ||
    SearchResultType.thsrTrain => TransportType.thsr,
    SearchResultType.mrtStation => TransportType.mrtBL,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          Container(
            color: cs.surface,
            padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 12),
            child: Row(
              children: [
                Pressable(
                  onTap: () => context.pop(),
                  semanticLabel: '關閉搜尋',
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.brightness == Brightness.light
                          ? Colors.white
                          : cs.surfaceContainerLow,
                      shape: BoxShape.circle,
                      boxShadow: cs.brightness == Brightness.light
                          ? const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 10,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.brightness == Brightness.light
                          ? Colors.white.withValues(alpha: 0.88)
                          : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: cs.brightness == Brightness.light
                          ? const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 10,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: cs.outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            onChanged: _onChanged,
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: cs.onSurface,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: '搜尋路線、站點',
                              hintStyle: AppTextStyles.bodyLarge.copyWith(
                                color: cs.onSurfaceVariant,
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        BlocBuilder<SearchBloc, SearchState>(
                          buildWhen: (p, c) =>
                              p.query.isEmpty != c.query.isEmpty,
                          builder: (context, state) {
                            if (state.query.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Pressable(
                              onTap: _onClear,
                              semanticLabel: '清除搜尋',
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: cs.outline,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (FirebaseGate.enabled) ...[
                  const SizedBox(width: 10),
                  _AiButton(onTap: _openGenUi),
                ],
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<SearchBloc, SearchState>(
              builder: (context, state) {
                if (state.loading) {
                  return Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                if (state.query.isEmpty) {
                  return const _RecentSearches();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      color: cs.surface,
                      child: Text(
                        '搜尋結果',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.04,
                        ),
                      ),
                    ),
                    Expanded(
                      child: state.error != null
                          ? ErrorStateView(
                              error: state.error!,
                              onRetry: () => context.read<SearchBloc>().add(
                                SearchQueryChanged(state.query),
                              ),
                            )
                          : state.results.isEmpty
                          ? Center(
                              child: Text(
                                '找不到結果',
                                style: AppTextStyles.bodyRegular.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.only(bottom: bottomPad + 16),
                              itemCount: state.results.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                thickness: 0.5,
                                color: cs.outlineVariant,
                              ),
                              itemBuilder: (context, index) {
                                final result = state.results[index];
                                return _SearchResultRow(
                                  result: result,
                                  transportType: _transportType(result.type),
                                  onTap: () =>
                                      _navigateToResult(context, result),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
