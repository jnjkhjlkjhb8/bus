import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no generated proto imports leak outside data/', () {
    // The seam rule (CONTEXT.md): generated proto types never leave
    // app/lib/data/. Features and shared widgets consume validated domain
    // types from repositories/decoders. This scans everything under lib/
    // except data/ itself; data/generated is the only place proto may live.
    final root = Directory('lib');
    final offenders = <String>[];
    final pattern = RegExp(r'''import\s+['"][^'"]*data/generated/[^'"]*\.pb''');
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // data/ owns the proto boundary; skip it wholesale (generated code,
      // decoders, and repositories all legitimately touch proto there).
      // core/grpc/ is the transport seam that holds the generated gRPC service
      // stubs; it is the one sanctioned proto touchpoint outside data/.
      final normalized = entity.path.replaceAll(r'\', '/');
      if (normalized.startsWith('lib/data/')) continue;
      if (normalized.startsWith('lib/core/grpc/')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Generated proto types must not leave data/. Move decoding into a '
          'repository or decoder and return a domain type.\n'
          '${offenders.join('\n')}',
    );
  });
}
