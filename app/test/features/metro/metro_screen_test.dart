import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/repositories/favorites_repository.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/metro/view/metro_screen.dart';

void main() {
  testWidgets('metro sheet no longer hosts the time/fare sliding segment', (
    tester,
  ) async {
    final favorites = FavoritesBloc(
      _FakeFavoritesRepository(),
      ValueNotifier(true),
    );
    addTearDown(favorites.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BlocProvider<FavoritesBloc>.value(
          value: favorites,
          child: const MetroScreen(),
        ),
      ),
    );
    // One frame is enough to build the sheet; avoid settling on the map's
    // raster future and deferred hit-target timer.
    await tester.pump();

    // The mode switch moved to a floating map chip; the sliding segment that
    // used to sit atop the sheet is gone.
    expect(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('AppSlidingSegment'),
      ),
      findsNothing,
    );
    // '旅途時間' was the segment's label and is unique to it.
    expect(find.text('旅途時間'), findsNothing);
  });
}

class _FakeFavoritesRepository implements FavoritesRepository {
  @override
  bool get isReady => true;

  @override
  Stream<BoxEvent> watch() => const Stream.empty();

  @override
  Stream<void> changes() => const Stream.empty();

  @override
  List<Favorite> all() => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
