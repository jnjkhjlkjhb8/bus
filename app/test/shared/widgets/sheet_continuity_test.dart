import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/shared/widgets/bottom_sheet_shell.dart';

void main() {
  group('carriedFraction', () {
    test('returns the current height as a viewport fraction', () {
      expect(
        carriedFraction(
          offset: 300,
          viewportHeight: 1000,
          min: 0.25,
          max: 1,
          fallback: 0.5,
        ),
        0.3,
      );
    });

    test('clamps to the target sheet range (e.g. metro cap)', () {
      expect(
        carriedFraction(
          offset: 950,
          viewportHeight: 1000,
          min: 0.25,
          max: 0.85,
          fallback: 0.5,
        ),
        0.85,
      );
      expect(
        carriedFraction(
          offset: 100,
          viewportHeight: 1000,
          min: 0.25,
          max: 1,
          fallback: 0.5,
        ),
        0.25,
      );
    });

    test('falls back (clamped) when the sheet has no metrics yet', () {
      expect(
        carriedFraction(
          offset: 0,
          viewportHeight: 0,
          min: 0.25,
          max: 1,
          fallback: 0.5,
        ),
        0.5,
      );
      expect(
        carriedFraction(
          offset: 0,
          viewportHeight: 0,
          min: 0.25,
          max: 1,
          fallback: 0.1,
        ),
        0.25,
      );
    });
  });

  group('AppSheet.statusBarPadding', () {
    double padAt(double offset) => AppSheet.statusBarPadding(
      offset: offset,
      viewportHeight: 1000,
      topInset: 60,
    );

    test('is zero at and below the half detent', () {
      expect(padAt(250), 0); // peek
      expect(padAt(500), 0); // half
    });

    test('ramps across the whole half-to-full stretch', () {
      expect(padAt(625), 15); // a quarter of the way up
      expect(padAt(750), 30);
      expect(padAt(1000), 60); // full: content clears the status bar
    });

    test('never exceeds the inset, even past the full detent', () {
      expect(padAt(1200), 60);
    });

    test('survives the sheet layout round-trip at every offset', () {
      // smooth_sheets lays the content out at (viewport - padding) and then
      // re-inflates the measured size by that same padding to size the sheet.
      // A fractional padding makes the round-trip land one ULP above the
      // viewport, which reaches BoxConstraints as minHeight > maxHeight and
      // trips the non-normalized assert in _RenderSheetSkelton.performLayout.
      const viewport = 914.2857142857143; // a 2400px screen at dpr 2.625
      for (var step = 0; step <= 1000; step++) {
        final pad = AppSheet.statusBarPadding(
          offset: viewport * (step / 1000),
          viewportHeight: viewport,
          topInset: 24,
        );
        expect(
          (viewport - pad) + pad,
          lessThanOrEqualTo(viewport),
          reason: 'padding $pad at step $step inflates past the viewport',
        );
      }
    });

    test('is zero before the sheet has been measured', () {
      expect(
        AppSheet.statusBarPadding(
          offset: 0,
          viewportHeight: 0,
          topInset: 60,
        ),
        0,
      );
    });
  });
}
