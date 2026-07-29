import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_bus/features/rail/rail_navigation_request.dart';
import 'package:wheres_the_bus/features/rail/view/rail_train_screen.dart';
import 'package:wheres_the_bus/features/rail/widgets/rail_query_sheet.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');

/// The rail query form as hosted inside the home sheet. Unlike the rail screen,
/// which shows results inline, this hands an O/D query off to `/rail` (via
/// [RailNavigationRequest], auto-submitting) and pushes a train query onto the
/// root navigator.
class HomeRailQuerySheet extends StatelessWidget {
  const HomeRailQuerySheet({this.preset, super.key});

  final RailQueryPreset? preset;

  void _onSubmit(BuildContext context, RailQuerySubmission submission) {
    switch (submission) {
      case RailOdQuerySubmission():
        RailNavigationRequest.set(
          RailQueryRequest(
            system: submission.system,
            originName: submission.originName,
            originId: submission.originId,
            destName: submission.destName,
            destId: submission.destId,
            date: submission.date,
            isDeparture: submission.isDeparture,
            autoSubmit: true,
          ),
        );
        unawaited(context.push('/rail'));
      case RailTrainQuerySubmission():
        unawaited(
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => RailTrainScreen(
                type: submission.system == RailSystem.thsr ? '高鐵' : '台鐵',
                trainNo: submission.trainNo,
                date: _dateFormat.format(submission.date),
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RailQuerySheetContent(
      preset: preset,
      onSubmit: (submission) => _onSubmit(context, submission),
      // Pops this form off the sheet's nested navigator, back to the nearby
      // list it was opened from.
      onBack: () => Navigator.of(context).maybePop(),
    );
  }
}
