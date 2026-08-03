import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/firebase/firebase_gate.dart';
import 'package:wheres_the_bus/core/firebase/remote_config.dart';
import 'package:wheres_the_bus/data/models/search_models.dart';
import 'package:wheres_the_bus/features/search/genui/bloc/genui_bloc.dart';
import 'package:wheres_the_bus/features/search/genui/data/genui_service.dart';
import 'package:wheres_the_bus/features/search/genui/view/genui_renderer.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/widgets/app_spinner.dart';

/// The conversational lane inside the search results.
///
/// It replaces the modal sheet the feature shipped with: one search field, and
/// an answer that opens in place above the keyword results instead of covering
/// them. Keyword search is instant and offline; the question is a second lane
/// beside it, never a gate in front of it.
class GenUiAskLane extends StatelessWidget {
  const GenUiAskLane({
    required this.query,
    required this.onAsk,
    required this.onOpen,
    super.key,
  });

  /// Whatever is in the search field right now.
  final String query;

  /// Runs a question. The host owns the search field, so it syncs the text
  /// before dispatching — a chip re-asks without the field going stale.
  final ValueChanged<String> onAsk;

  final ValueChanged<SearchResult> onOpen;

  /// Off when Firebase is (dev/test flavor), and killable from Remote Config
  /// without a release.
  static bool get enabled =>
      FirebaseGate.enabled && AppConfig.getBool(AppConfig.genUiEnabledKey);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppConfig.version,
      builder: (context, _, _) => enabled
          ? GenUiLane(query: query, onAsk: onAsk, onOpen: onOpen)
          : const SizedBox.shrink(),
    );
  }
}

/// The lane itself, with no availability gate — [GenUiAskLane] owns that.
/// Split out so the states below can be rendered without a Firebase build.
class GenUiLane extends StatelessWidget {
  const GenUiLane({
    required this.query,
    required this.onAsk,
    required this.onOpen,
    super.key,
  });

  final String query;
  final ValueChanged<String> onAsk;
  final ValueChanged<SearchResult> onOpen;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<GenUiBloc, GenUiState>(builder: _lane);

  Widget _lane(BuildContext context, GenUiState state) {
    final q = query.trim();
    final idle = state.status == GenUiStatus.idle;
    // Idle means nothing is on screen, so the offer always comes back — a
    // stopped request that never produced an answer has to leave a way to ask
    // again. Otherwise the offer returns only once the field has moved on from
    // the question the answer above belongs to, which is what lets an answer
    // survive the rider typing something else instead of forcing a collapse.
    final canAskNew =
        q.isNotEmpty &&
        (idle ||
            (state.status != GenUiStatus.loading && q != state.lastPrompt));

    final lane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (idle && q.isEmpty)
          _Invite(onAsk: onAsk)
        else if (canAskNew)
          _AskRow(query: q, onAsk: onAsk),
        if (!idle) ...[
          if (canAskNew) const SizedBox(height: 8),
          _Answered(state: state, onAsk: onAsk, onOpen: onOpen),
        ],
      ],
    );

    // The lane sits above the results rather than inside their scroll, so a
    // long answer is capped and scrolls in place instead of pushing the
    // keyword results — the thing that is always right and always instant —
    // off the screen. Short answers still shrink-wrap.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: lane,
      ),
    );
  }
}

/// The lane hangs on the same 16px gutter as the search field above it, so
/// every block and card in it shares one left edge with the field rather than
/// floating on a third column of its own.
const _laneInset = EdgeInsets.fromLTRB(16, 6, 16, 6);

class _Block extends StatelessWidget {
  const _Block({required this.child, this.onTap, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: child,
    );
    return Padding(
      padding: _laneInset,
      child: onTap == null
          ? box
          : Pressable(onTap: onTap, semanticLabel: semanticLabel, child: box),
    );
  }
}

class _Spark extends StatelessWidget {
  const _Spark();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.auto_awesome_rounded,
    size: 16,
    color: Theme.of(context).colorScheme.onSurface,
  );
}

/// The empty-query state: what this can be asked, in its own words. The
/// feature used to open on a blank field, which taught nobody anything.
class _Invite extends StatelessWidget {
  const _Invite({required this.onAsk});

  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i18n = AppI18n.of(context);
    final examples = [i18n.genuiAskExample1, i18n.genuiAskExample2];
    return _Block(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _Spark(),
              const SizedBox(width: 9),
              Text(
                i18n.genuiAskInvite,
                style: AppTextStyles.bodyRegular.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final example in examples)
                Pressable(
                  onTap: () => onAsk(example),
                  semanticLabel: example,
                  minTapSize: 44,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusStadium,
                      ),
                      border: Border.all(color: cs.outlineVariant, width: 0.5),
                    ),
                    child: Text(
                      example,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row offering to ask what is already in the search field.
class _AskRow extends StatelessWidget {
  const _AskRow({required this.query, required this.onAsk});

  final String query;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = AppI18n.of(context).genuiAskQuery(query);
    return _Block(
      onTap: () => onAsk(query),
      semanticLabel: label,
      child: Row(
        children: [
          const _Spark(),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyRegular.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          Icon(
            Icons.arrow_forward_rounded,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// Everything after a question has been asked: the question itself, then
/// whichever of waiting / answer / failure is true right now.
class _Answered extends StatelessWidget {
  const _Answered({
    required this.state,
    required this.onAsk,
    required this.onOpen,
  });

  final GenUiState state;
  final ValueChanged<String> onAsk;
  final ValueChanged<SearchResult> onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i18n = AppI18n.of(context);
    final loading = state.status == GenUiStatus.loading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _Spark(),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      state.lastPrompt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyRegular.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TrailingAction(loading: loading),
                ],
              ),
              if (loading) ...[
                const SizedBox(height: 8),
                _PhaseLine(state: state),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: switch (state.status) {
            GenUiStatus.loading => const _AnswerSkeleton(),
            GenUiStatus.error => _ErrorRow(state: state, onAsk: onAsk),
            GenUiStatus.content when state.nodes.isEmpty => _NothingToShow(
              i18n: i18n,
            ),
            GenUiStatus.content => KeyedSubtree(
              // Keyed by the prompt that produced this content, so the
              // stagger-in only replays for a genuinely new answer.
              key: ValueKey(state.lastPrompt),
              child: GenUiRenderer(
                nodes: state.nodes,
                refs: state.refs,
                onAsk: onAsk,
                onOpen: onOpen,
              ),
            ),
            GenUiStatus.idle => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

/// Stop while a request is in flight, collapse once there is an answer. Stop
/// no longer discards what is already on screen.
class _TrailingAction extends StatelessWidget {
  const _TrailingAction({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i18n = AppI18n.of(context);
    final label = loading ? i18n.genuiStop : i18n.genuiCollapse;
    return Pressable(
      onTap: () => context.read<GenUiBloc>().add(
        loading ? const GenUiCancelled() : const GenUiDismissed(),
      ),
      semanticLabel: label,
      minTapSize: 44,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: loading ? cs.surfaceContainerLow : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          border: loading
              ? Border.all(color: cs.outlineVariant, width: 0.5)
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: loading ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Elapsed stage, not progress: the model reports which tool it is in, and
/// nothing here invents a percentage.
class _PhaseLine extends StatelessWidget {
  const _PhaseLine({required this.state});

  final GenUiState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i18n = AppI18n.of(context);
    final label = switch (state.phase) {
      GenUiPhase.thinking => i18n.genuiThinking,
      GenUiPhase.searching => i18n.genuiSearching(state.phaseQuery ?? ''),
      GenUiPhase.composing => i18n.genuiComposing,
    };
    return Row(
      children: [
        const AppSpinner(size: 14, strokeWidth: 2),
        const SizedBox(width: 9),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.reduced(context)
                ? AppMotion.instant
                : AppMotion.short,
            switchInCurve: AppMotion.easeOut,
            switchOutCurve: AppMotion.easeOut,
            child: Text(
              label,
              key: ValueKey(label),
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two card outlines, so the answer lands without the list reflowing under
/// the reader's thumb. Skeleton over spinner is the house rule for content.
class _AnswerSkeleton extends StatelessWidget {
  const _AnswerSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A fraction of the card's own width rather than a fixed pixel count —
    // the card is full-bleed (matching _RouteCard), so a hardcoded width
    // would sit at an arbitrary, screen-size-dependent fraction of it instead
    // of the varied-but-proportional line lengths this is meant to suggest.
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusChip),
        ),
      ),
    );
    return ExcludeSemantics(
      child: Column(
        // Stretched to match _RouteCard's width: double.infinity — otherwise
        // these shrink-wrap to their bar width and the real card snaps wider
        // the moment content replaces the skeleton.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 2; i++)
            Container(
              margin: EdgeInsets.only(bottom: i == 0 ? 10 : 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(color: cs.outlineVariant, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(i == 0 ? 0.48 : 0.6, 12),
                  const SizedBox(height: 8),
                  bar(i == 0 ? 0.3 : 0.36, 10),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.state, required this.onAsk});

  final GenUiState state;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i18n = AppI18n.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              state.errorKind == GenUiErrorKind.offline
                  ? i18n.genuiOffline
                  : i18n.genuiUnavailable,
              style: AppTextStyles.bodySmall.copyWith(color: cs.onSurface),
            ),
          ),
          Pressable(
            onTap: () => onAsk(state.lastPrompt),
            semanticLabel: i18n.commonRetryShort,
            minTapSize: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                i18n.commonRetryShort,
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An answer with nothing in it names the limit and points back at what does
/// work, instead of dead-ending on "no results".
class _NothingToShow extends StatelessWidget {
  const _NothingToShow({required this.i18n});

  final AppI18n i18n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.genuiNoResults,
            style: AppTextStyles.bodyRegular.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            i18n.genuiNoResultsHint,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dispatches a question to the assistant.
void askGenUi(BuildContext context, String prompt) {
  final text = prompt.trim();
  if (text.isEmpty) return;
  context.read<GenUiBloc>().add(GenUiAsked(text));
}
