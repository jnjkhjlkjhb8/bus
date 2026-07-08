import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/features/search/bloc/search_state.dart';
import 'package:wheres_the_car/features/search/genui/bloc/genui_bloc.dart';
import 'package:wheres_the_car/features/search/genui/data/genui_service.dart';
import 'package:wheres_the_car/features/search/genui/view/genui_renderer.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';

/// GenUI sheet 關閉時帶回的結果。
sealed class GenUiSheetResult {
  const GenUiSheetResult();
}

/// 回填搜尋框後執行一般搜尋。
class GenUiSheetQuery extends GenUiSheetResult {
  const GenUiSheetQuery(this.query);
  final String query;
}

/// 直接開啟某筆查詢結果的頁面。
class GenUiSheetOpen extends GenUiSheetResult {
  const GenUiSheetOpen(this.result);
  final SearchResult result;
}

Future<GenUiSheetResult?> showGenUiSheet(
  BuildContext context, {
  String initialQuery = '',
}) {
  return BottomSheetShell.show<GenUiSheetResult>(
    context: context,
    initialOffset: const SheetOffset.proportionalToViewport(0.6),
    minOffset: const SheetOffset.proportionalToViewport(0.3),
    child: BlocProvider(
      create: (_) => GenUiBloc(),
      child: _GenUiSheet(initialQuery: initialQuery),
    ),
  );
}

class _GenUiSheet extends StatefulWidget {
  const _GenUiSheet({required this.initialQuery});
  final String initialQuery;

  @override
  State<_GenUiSheet> createState() => _GenUiSheetState();
}

class _GenUiSheetState extends State<_GenUiSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _submit(widget.initialQuery));
    } else {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focusNode.requestFocus());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    if (context.read<GenUiBloc>().state.status == GenUiStatus.loading) return;
    _focusNode.unfocus();
    context.read<GenUiBloc>().add(GenUiAsked(text));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                '對話框',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _submit,
                    style: TextStyle(fontSize: 15, color: cs.onSurface),
                    decoration: InputDecoration(
                      hintText: '問問看,例如:從台北車站怎麼去淡水',
                      hintStyle:
                          TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                BlocBuilder<GenUiBloc, GenUiState>(
                  buildWhen: (p, c) => p.status != c.status,
                  builder: (context, state) {
                    final loading = state.status == GenUiStatus.loading;
                    return Pressable(
                      onTap: () => loading
                          ? context
                              .read<GenUiBloc>()
                              .add(const GenUiCancelled())
                          : _submit(_controller.text),
                      semanticLabel: loading ? '停止' : '送出',
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          loading
                              ? Icons.stop_rounded
                              : Icons.arrow_upward_rounded,
                          size: 18,
                          color: cs.onPrimary,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: BlocConsumer<GenUiBloc, GenUiState>(
                listenWhen: (p, c) => c.status == GenUiStatus.content,
                listener: (context, state) =>
                    unawaited(HapticService.instance.lightTap()),
                builder: _body,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, GenUiState state) {
    final cs = Theme.of(context).colorScheme;
    switch (state.status) {
      case GenUiStatus.idle:
        return const SizedBox(height: 8);
      case GenUiStatus.loading:
        final label = switch (state.phase) {
          GenUiPhase.thinking => 'AI 思考中…',
          GenUiPhase.searching => '正在查詢「${state.phaseQuery ?? ''}」…',
          GenUiPhase.composing => '整理結果中…',
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotion.short,
                  switchInCurve: AppMotion.easeOut,
                  switchOutCurve: AppMotion.easeOut,
                  child: Text(
                    label,
                    key: ValueKey(label),
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        );
      case GenUiStatus.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.errorKind == GenUiErrorKind.offline
                      ? '沒有網路連線'
                      : 'AI 暫時無法使用',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
              ),
              Pressable(
                onTap: () => context
                    .read<GenUiBloc>()
                    .add(GenUiAsked(state.lastPrompt)),
                semanticLabel: '重試',
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    '重試',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      case GenUiStatus.content:
        if (state.nodes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '沒有可顯示的結果',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          );
        }
        return KeyedSubtree(
          key: ValueKey(identityHashCode(state.nodes)),
          child: GenUiRenderer(
            nodes: state.nodes,
            refs: state.refs,
            onChip: (query) =>
                Navigator.of(context).pop(GenUiSheetQuery(query)),
            onOpen: (result) =>
                Navigator.of(context).pop(GenUiSheetOpen(result)),
          ),
        );
    }
  }
}
