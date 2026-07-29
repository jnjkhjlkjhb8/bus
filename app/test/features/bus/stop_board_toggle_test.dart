import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/features/bus/widgets/stop_board_toggle.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/stop_board_state.dart';

void main() {
  test(
    'inactive state → not active for any stop',
    () => expect(
      isStopBoardActive(const StopBoardState(), '大安森林公園站'),
      isFalse,
    ),
  );

  test(
    'active state for this stop → active',
    () => expect(
      isStopBoardActive(
        const StopBoardState(active: true, stopName: '大安森林公園站'),
        '大安森林公園站',
      ),
      isTrue,
    ),
  );

  test(
    'active state for a different stop → not active here (shared bloc '
    'is broadcasting elsewhere)',
    () => expect(
      isStopBoardActive(
        const StopBoardState(active: true, stopName: '公館站'),
        '大安森林公園站',
      ),
      isFalse,
    ),
  );
}
