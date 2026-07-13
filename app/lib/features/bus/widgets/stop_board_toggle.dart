import 'package:wheres_the_car/features/live_activity/bloc/stop_board_cubit.dart';

/// Pure derivation for the stop screen's Live Activity toggle button. Kept
/// out of the screen widget so it can be unit-tested directly.
///
/// [StopBoardCubit] is a single app-wide instance shared with the
/// journey/track card (only one Live Activity can exist at a time), so its
/// state may reflect a board started from a different stop screen. Matching
/// on [stopName] is how a given stop screen tells "my board is live" from
/// "some other board is live" — the cubit's [StopBoardState] only carries
/// the stop name, not a stable stop key.
bool isStopBoardActive(StopBoardState state, String stopName) =>
    state.active && state.stopName == stopName;
