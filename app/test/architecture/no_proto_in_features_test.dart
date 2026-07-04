import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no generated proto imports leak into migrated feature directories', () {
    // Scoped to the feature areas migrated behind the repository seam by the
    // Track B/C refactor. Directories are listed explicitly rather than
    // scanning all of lib/features because some areas still import proto:
    //   - lib/features/alerts/bloc is added in Task 6, where alert_bloc drops
    //     its proto import. It still imports alert.pb.dart at the end of this
    //     task, so including it here would fail the green bar.
    // TODO(rail-seam): nearby/map (home/bloc/nearby_bloc.dart, map/bloc/*)
    // still import near.pb.dart; their migration is deferred to a separate
    // tracked task.
    const scoped = [
      'lib/features/bus/bloc',
      'lib/features/bus/view',
      'lib/features/bus/widgets',
      'lib/features/metro/bloc',
      'lib/features/bike/bloc',
      'lib/features/rail/bloc',
    ];
    final offenders = <String>[];
    final pattern = RegExp(r'''import\s+['"][^'"]*data/generated/[^'"]*\.pb''');
    for (final path in scoped) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Generated proto types must not leave data/. Move decoding into a '
          'repository and return a domain type.\n${offenders.join('\n')}',
    );
  });
}
