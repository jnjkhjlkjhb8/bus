import 'package:wheres_the_bus/features/live_activity/bloc/stop_board_state.dart';

/// Pure derivation for the stop screen's Live Activity toggle button. Kept
/// out of the screen widget so it can be unit-tested directly.
///
/// [StopBoardState] comes from a single app-wide `StopBoardBloc` instance
/// shared with the journey/track card (only one Live Activity can exist at
/// a time), so its state may reflect a board started from a different stop
/// screen. Matching on [stopName] is how a given stop screen tells "my
/// board is live" from "some other board is live" — the state only carries
/// the stop name, not a stable stop key.
bool isStopBoardActive(StopBoardState state, String stopName) =>
    state.active && state.stopName == stopName;
