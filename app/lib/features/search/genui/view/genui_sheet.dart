import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/features/search/genui/bloc/genui_bloc.dart';
import 'package:wheres_the_car/features/search/genui/view/genui_renderer.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';

Future<String?> showGenUiSheet(
  BuildContext context, {
  String initialQuery = '',
}) {
  return BottomSheetShell.show<String>(
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
                'AI 助理',
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
                Pressable(
                  onTap: () => _submit(_controller.text),
                  semanticLabel: '送出',
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: cs.onPrimary,
                    ),
                  ),
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
              Text(
                'AI 思考中…',
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      case GenUiStatus.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'AI 暫時無法使用',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
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
        return GenUiRenderer(
          nodes: state.nodes,
          onChip: (query) => Navigator.of(context).pop(query),
        );
    }
  }
}
