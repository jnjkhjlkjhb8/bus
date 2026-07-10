import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_state.dart';
import 'package:wheres_the_car/shared/widgets/status_banner.dart';

/// Shown while the app is serving cached data. Shares [StatusBanner] with the
/// maintenance notice so the two read as one vocabulary, not two dialects.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocSelector<AlertBloc, AlertState, bool>(
        selector: (state) => state.error is OfflineError,
        builder: (context, offline) => StatusBanner(
          severity: StatusSeverity.neutral,
          message: offline ? '目前離線，顯示快取資料。' : null,
        ),
      );
}
