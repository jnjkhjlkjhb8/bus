import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_bus/app/router/app_routes.dart';
import 'package:wheres_the_bus/app/theme/app_shadows.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/core/haptics/haptic_service.dart';
import 'package:wheres_the_bus/data/models/city_names.dart';
import 'package:wheres_the_bus/data/models/search_models.dart';
import 'package:wheres_the_bus/features/rail/view/rail_train_screen.dart';
import 'package:wheres_the_bus/features/search/bloc/search_bloc.dart';
import 'package:wheres_the_bus/features/search/bloc/search_event.dart';
import 'package:wheres_the_bus/features/search/bloc/search_state.dart';
import 'package:wheres_the_bus/features/search/genui/bloc/genui_bloc.dart';
import 'package:wheres_the_bus/features/search/genui/view/genui_ask_lane.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_bus/shared/widgets/error_state_view.dart';
import 'package:wheres_the_bus/shared/widgets/filter_chip_group.dart';
import 'package:wheres_the_bus/shared/widgets/transport_icon.dart';

part '../widgets/search_result_row.dart';
part '../widgets/recent_searches.dart';
part '../widgets/city_filter_rail.dart';

/// Platform minimum for a touch target (Android 48dp / Apple HIG 44pt).
/// Applied as the hit area; the painted control stays whatever size the
/// layout calls for.
const double _minTouchTarget = 48;

/// No stop or route name comes close to this. The cap exists so a pasted
/// wall of text can't be fired at the router on every keystroke.
const int _maxQueryLength = 50;

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
      unawaited(context.push(AppRoutes.busRoute(result.uid)));
    case SearchResultType.busStation:
      unawaited(
        context.push(
          AppRoutes.busStopLocation(
            stopName: result.name,
            stopId: result.uid,
            city: result.city,
            lat: result.lat,
            lon: result.lon,
          ),
        ),
      );
    case SearchResultType.bikeStation:
      unawaited(
        context.push(
          AppRoutes.bikeStationLocation(
            stationUid: result.uid,
            name: result.name,
            lat: result.lat,
            lon: result.lon,
          ),
        ),
      );
    case SearchResultType.mrtStation:
      // Land on the picked station, not the bare map. Matched by name (the
      // search uid and the map's station ids use different code schemes).
      unawaited(context.push(AppRoutes.metro, extra: result.name));
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
  const SearchScreen({super.key, this.bloc});

  /// Test seam. The screen owns its bloc in the app — nothing routes to it
  /// with one — but a widget test has no Hive box or router behind the
  /// default, and this screen's states (results, filtered, empty) are worth
  /// rendering rather than only asserting on in the bloc.
  final SearchBloc? bloc;

  @override
  Widget build(BuildContext context) {
    final bloc = this.bloc;
    return MultiBlocProvider(
      providers: [
        if (bloc == null)
          BlocProvider(create: (_) => SearchBloc())
        else
          BlocProvider.value(value: bloc),
        // Lives with the screen, not with a sheet: opening a result and
        // coming back has to land on the answer that sent you there.
        BlocProvider(create: (_) => GenUiBloc()),
      ],
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

  /// The debounce means the in-flight query may lag what's on screen; an
  /// explicit submit skips the wait and dismisses the keyboard so the results
  /// aren't left hidden behind it.
  void _onSubmitted(String value) {
    _focusNode.unfocus();
    context.read<SearchBloc>().add(SearchQueryChanged(value));
  }

  void _onClear() {
    _controller.clear();
    context.read<SearchBloc>().add(const SearchCleared());
    _focusNode.requestFocus();
  }

  /// Runs a question through the ask lane. The field is the single input for
  /// both lanes, so a chip or an example asking something else has to move the
  /// field with it — otherwise the keyword results below would keep answering
  /// the previous question.
  void _ask(String prompt) {
    final text = prompt.trim();
    if (text.isEmpty) return;
    if (_controller.text.trim() != text) {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
      context.read<SearchBloc>().add(SearchQueryChanged(text));
    }
    _focusNode.unfocus();
    askGenUi(context, text);
  }

  TransportType _transportType(SearchResultType type) => switch (type) {
    SearchResultType.busRoute => TransportType.bus,
    SearchResultType.busStation => TransportType.busStop,
    SearchResultType.bikeStation => TransportType.bike,
    SearchResultType.traTrain => TransportType.tra,
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
                  semanticLabel: AppI18n.of(context).searchCloseSemantics,
                  // 40pt visual, 48dp touch target: the circle stays the size
                  // the layout wants while the hit area meets the platform
                  // minimum (Pressable hit-tests the whole opaque box).
                  child: SizedBox(
                    width: _minTouchTarget,
                    height: _minTouchTarget,
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          shape: BoxShape.circle,
                          boxShadow: AppShadows.cardFor(cs.brightness),
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
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    // minHeight, not a fixed height: at large text scales the
                    // field has to grow with its content instead of clipping
                    // it (Settings offers a large-text mode).
                    constraints: const BoxConstraints(
                      minHeight: _minTouchTarget,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppShadows.cardFor(cs.brightness),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            onChanged: _onChanged,
                            onSubmitted: _onSubmitted,
                            textInputAction: TextInputAction.search,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(
                                _maxQueryLength,
                              ),
                            ],
                            style: AppTextStyles.bodyRegular.copyWith(
                              color: cs.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: AppI18n.of(context).searchHint,
                              hintStyle: AppTextStyles.bodyRegular.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
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
                              semanticLabel: AppI18n.of(
                                context,
                              ).searchClearSemantics,
                              child: SizedBox(
                                width: _minTouchTarget,
                                height: _minTouchTarget,
                                child: Center(
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      // onSurfaceVariant, not outline: this is
                                      // a control, so it owes 3:1 against its
                                      // background (WCAG 1.4.11). outline
                                      // (#BFBFBF) manages 1.84:1.
                                      color: cs.onSurfaceVariant,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 12,
                                      color: cs.surfaceContainerLow,
                                    ),
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
              ],
            ),
          ),
          // Above the switcher, not inside it: the answer has to survive the
          // body swapping between recents, results, and empty as the field
          // changes under it.
          BlocBuilder<SearchBloc, SearchState>(
            buildWhen: (p, c) => p.query != c.query,
            builder: (context, state) => GenUiAskLane(
              query: state.query,
              onAsk: _ask,
              onOpen: (result) => _navigateToResult(context, result),
            ),
          ),
          Expanded(
            child: BlocBuilder<SearchBloc, SearchState>(
              builder: (context, state) {
                final body = _buildBody(context, state, cs, bottomPad);
                final reduceMotion = MediaQuery.disableAnimationsOf(context);
                return AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : AppMotion.short,
                  switchInCurve: AppMotion.easeOut,
                  switchOutCurve: AppMotion.easeOut,
                  child: KeyedSubtree(
                    key: ValueKey(_bodyKey(state)),
                    child: body,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Distinguishes the body states for the AnimatedSwitcher. A query that is
  // still loading but already has results to show (from a previous query)
  // keeps the 'results' key — see F1: the full-screen spinner only replaces
  // the body when there is nothing to show yet, otherwise stale results
  // stay on screen (with scroll position) while a thin progress bar overlays
  // them. The 'results' key is intentionally constant across queries so a
  // new results list replaces the old one in place without a crossfade —
  // only state-kind changes animate.
  String _bodyKey(SearchState state) {
    if (state.loading &&
        state.results.isEmpty &&
        state.cityOptions.length < 2) {
      return 'loading';
    }
    if (state.query.isEmpty) return 'recents';
    // With a chip row on screen the chrome is identical across loading,
    // empty, and results, so those share a key: the switcher swaps the list
    // underneath instead of crossfading the chips against themselves.
    if (state.cityOptions.length >= 2 && state.error == null) return 'results';
    if (state.error != null) return 'error';
    if (state.results.isEmpty) return 'empty';
    return 'results';
  }

  Widget _buildBody(
    BuildContext context,
    SearchState state,
    ColorScheme cs,
    double bottomPad,
  ) {
    // Skeleton, not a spinner: the row structure is fixed, so showing it
    // keeps the layout from jumping when results land. It replaces the whole
    // body only while there is no chip row — once there is one, a city toggle
    // would otherwise take the chips away under the finger that just tapped
    // them, and the skeleton goes under the chrome instead (below).
    if (state.loading &&
        state.results.isEmpty &&
        state.cityOptions.length < 2) {
      return const _ResultsSkeleton();
    }

    if (state.query.isEmpty) {
      return const _RecentSearches();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: AppI18n.of(context).searchResults,
          count: state.error == null ? state.results.length : null,
        ),
        _CityFilterRail(
          options: state.cityOptions,
          selected: state.city,
          onToggle: (code) {
            unawaited(HapticService.instance.selectionClick());
            context.read<SearchBloc>().add(SearchCityToggled(code));
          },
        ),
        if (state.loading)
          SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
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
              : state.loading && state.results.isEmpty
              // Reloading under a new city filter: "no match" is not the
              // answer yet, so the rows stay skeletal until it is.
              ? const _SkeletonRows()
              : state.results.isEmpty
              ? _NoResults(query: state.query)
              : ListView.separated(
                  // Results sit behind the keyboard on a phone; dragging the
                  // list is the reflex for getting it out of the way.
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                      onTap: () => _navigateToResult(context, result),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Shared header for the recents and results lists, so the two read as one
/// vocabulary rather than two near-identical inline `Text`s.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.count, this.trailing});

  final String label;

  /// Rendered as "(n)" beside the label. Null hides it — an unknown count
  /// (error, still loading) shouldn't render as zero.
  final int? count;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = count;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
      color: cs.surface,
      child: Row(
        children: [
          Expanded(
            child: Text(
              n == null ? label : '$label（$n）',
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Empty result state. Names the query back to the user and points at what
/// actually works, rather than dead-ending on "找不到結果".
class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            AppI18n.of(context).searchNoMatch(query),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            AppI18n.of(context).searchNoMatchHint,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// First-load placeholder. Mirrors the result row's metrics so the list
/// doesn't reflow when the real rows arrive.
class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: AppI18n.of(context).searchResults),
        const Expanded(child: _SkeletonRows()),
      ],
    );
  }
}

/// The placeholder rows alone, for the case where the header and the city
/// chips are already on screen and only the list is being replaced.
class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: 6,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          thickness: 0.5,
          color: cs.outlineVariant,
        ),
        itemBuilder: (_, _) => Container(
          height: 62,
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          color: cs.surfaceContainerLow,
          child: Row(
            children: [
              _SkeletonBox(width: 34, height: 34, radius: 9, cs: cs),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBox(width: 72, height: 13, radius: 4, cs: cs),
                  const SizedBox(height: 7),
                  _SkeletonBox(width: 148, height: 11, radius: 4, cs: cs),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.cs,
  });

  final double width;
  final double height;
  final double radius;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
