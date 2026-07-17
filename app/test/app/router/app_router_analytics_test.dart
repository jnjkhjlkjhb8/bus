import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/app/router/app_router.dart';

void main() {
  test('route graph builds before Firebase core has initialized', () {
    expect(
      () => buildAppRoutes(includeDebugRoutes: false, firebaseEnabled: true),
      returnsNormally,
    );
  });
}
