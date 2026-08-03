import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/shared/widgets/bottom_sheet_shell.dart';

/// The home sheet interpolates two things off `SheetController` metrics: the
/// filter row's reveal fraction and the status-bar inset above the drag
/// handle. Both divide by the sheet's viewport height, which measures 0 on
/// the frames before the sheet is laid out.
///
/// That divide yields NaN (or infinity). `num.clamp` happens to normalise
/// both to its upper limit, so nothing throws — but the upper limit is the
/// wrong answer here: it would show the filter row fully revealed and the
/// status-bar inset fully applied for a frame, before the sheet has been
/// measured at all. The guards make an unmeasured sheet read as collapsed.
void main() {
  // Mirrors _NearbyStationsTabState._buildFilterRow.
  double? filterReveal({required double viewport, required double offset}) {
    if (viewport <= 0) return null;
    final peekPx = viewport * AppSheetSnap.peekFrac;
    final halfPx = viewport * AppSheetSnap.halfFrac;
    return ((offset - peekPx) / (halfPx - peekPx)).clamp(0.0, 1.0);
  }

  // Mirrors _HomeScreenScaffold._buildSheetRoot's safe-area ramp.
  double safeAreaProgress({required double viewport, required double offset}) {
    if (viewport <= 0) return 0;
    return ((offset / viewport - AppSheetSnap.tallFrac) /
            (AppSheetSnap.fullFrac - AppSheetSnap.tallFrac))
        .clamp(0.0, 1.0);
  }

  group('unmeasured viewport reads as collapsed', () {
    test('filter row stays hidden', () {
      expect(filterReveal(viewport: 0, offset: 0), isNull);
    });

    test('safe-area inset stays off', () {
      expect(safeAreaProgress(viewport: 0, offset: 0), 0);
    });

    test('without the guard it would read as fully open instead', () {
      // Documents why the guards exist: clamp() normalises the 0/0 NaN to its
      // upper limit, which is exactly the wrong end of the range.
      expect((0.0 / 0.0).clamp(0.0, 1.0), 1.0);
      expect((1.0 / 0.0).clamp(0.0, 1.0), 1.0);
    });
  });

  group('measured viewport still interpolates', () {
    test('filter row is collapsed at the peek detent', () {
      expect(filterReveal(viewport: 800, offset: 800 * 0.25), 0);
    });

    test('filter row is fully revealed at the half detent', () {
      expect(filterReveal(viewport: 800, offset: 800 * 0.5), 1);
    });

    test('safe-area inset is off below the tall detent', () {
      expect(safeAreaProgress(viewport: 800, offset: 800 * 0.5), 0);
    });

    test('safe-area inset is fully applied at the full detent', () {
      expect(safeAreaProgress(viewport: 800, offset: 800), 1);
    });
  });
}
