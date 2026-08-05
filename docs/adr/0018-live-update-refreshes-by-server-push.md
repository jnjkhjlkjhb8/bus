# 0018 Live Update Refreshes Move To Server Push, Metro First

## Status

Accepted (metro leg implemented, FDPL-64), builds on 0007 and 0015

## Context

The alight-tracking card is computed in Dart (`_content` in
`journey_session_bloc.dart`) and handed to each platform over one MethodChannel
payload (`AlightTrackContent.toArgs()`). Both native sides only ever redraw when
Dart hands them something new, so the card is exactly as live as the Dart
isolate:

- iOS suspends within seconds of leaving the screen. The only background mode
  the app ships is `remote-notification`; there is no `location` mode and no
  `ACCESS_BACKGROUND_LOCATION` on Android, so nothing keeps the isolate awake.
- Android keeps a cached process for a while and then does not. A killed
  process used to leave an un-swipeable ongoing card frozen mid-ride.

Both platforms therefore degrade rather than stay true: iOS marks the card
stale on a per-mode `staleDate`, Android retires it on a matching
`setTimeoutAfter` window. Honest, but a rider mid-ride still loses the reading
they opened the card for.

gRPC streaming cannot close this gap — a suspended app holds no sockets, and
live feeds are now deliberately dropped while backgrounded (`AppForeground`).
Push is the only transport that reaches a card whose app is not running.

Where the numbers already live decides how far push can go:

| Mode | Source of 剩 N 站 | Server-derivable |
|---|---|---|
| Metro | server session (`reminders` `route_type='mrt'`, `mrt_track.go`) | yes, already computed |
| TRA / THSR | carried timetable + live delay | yes, pure arithmetic |
| Bus, pinned plate | the vehicle feed's own stops-remaining | yes |
| Bus, unpinned, riding | phone GPS matched to the nearest upcoming stop | no |

Metro is already all the way there: a 15s scan advances each session,
`publishState` writes it, and `notify.Dispatcher` already sends this rider a
data message for the 提前站數 vibration (ADR-0015).

## Decision

- **Card refreshes become server-pushed, metro first.** Local updates stay the
  path while the app is foregrounded; push is additive and arbitrated by the
  existing `AlightTrackChannel` lease, so two writers cannot fight over one
  card.
- **The payload contract does not change.** The server emits the field set
  `AlightTrackContent.toArgs()` already defines, because both native builders
  (`buildTrack`, `contentState(from:)`) parse exactly that map. No new renderer,
  no per-transport card vocabulary — the reason ADR-0007 collapsed four cards
  into one applies to the transport too.

  **Amended at implementation:** true on Android, not on iOS. A remote Live
  Activity push is decoded by ActivityKit straight into `ContentState` with no
  app code in the loop, so `contentState(from:)` is never reached and the wire
  shape is `ContentState`'s own field names. Worse, a `Date` there decodes with
  `JSONDecoder`'s default strategy — seconds since 2001 — so a server sending
  unix epoch would be 31 years out with nothing to catch it. `etaDate`/`asOf`
  therefore became `etaUnix`/`asOfUnix`, and a Go test reads the field list back
  out of the Swift source so a rename cannot silently stop a card updating.
- **Push only when the data moves, never on a timer.** The card's numbers may
  not change without data behind them (`ContentState.etaDate`,
  `AlightTrackContent.etaMinutes` both exist for this reason), which also keeps
  volume inside APNs' Live Activity budget: about one push per station hop.
- **Android:** a Kotlin-side FCM data path rebuilds the notification through the
  existing builder. `buildTrack` splits out of the channel plumbing so it needs
  only a `Context` — today `LiveActivityPlugin`'s constructor demands an
  Activity-bound `NotificationPermissionCoordinator`, which no FCM callback can
  supply. Messages go out `priority: high` or Doze holds them.
- **iOS:** `Activity.request(pushType: .token)`, the ActivityKit push token
  travels up through `upsertDevice` (new field), and the server pushes over
  APNs directly with `apns-push-type: liveactivity`. FCM carries no such push
  type, so `services/functions/notify/` grows a small APNs sender (p8 key,
  ES256 JWT, HTTP/2 POST) beside `firebase_admin.go`. The app declares
  `NSSupportsLiveActivitiesFrequentUpdates`.

  **Amended at implementation:** the token does not go on the device row. It is
  issued per activity and dies with the card, so a device column would need a
  migration and an explicit clear at session end. It lives beside the session's
  Redis state instead (`shared.MrtTrackPushTokenKey`, written by a new
  `SetTrackPushToken` RPC), where it expires with the session that owns it and
  there is nothing to clean up. It is also a stream, not a one-shot read:
  `pushTokenUpdates` reissues, and a card refreshed against a superseded token
  silently stops updating.
- **An unpinned bus ride stays device-only.** Its progress exists only on the
  phone, and a foreground service to keep GPS alive in the background is
  refused: one case does not justify a permanent notification, a
  background-location permission and a store-review conversation on both
  platforms. That ride keeps degrading to stale/retired as it does today.
- **Push-to-start is out of scope.** `Activity.pushToStartTokenUpdates`
  (iOS 17.2) would let the server open a card with the app closed; it is a
  separate decision with its own consent questions.

## Consequences

- APNs credentials become new optional config (`APNS_KEY_ID`, `APNS_TEAM_ID`,
  `APNS_P8`, `APNS_TOPIC`). Empty means iOS push is disabled — the same
  empty-credential-skips shape as TDX, TRTC and Sentry, so no environment is
  forced to hold them.
- The proto change is wire-breaking: backend and app ship together.
- Two ways into one card means writes have to be ordered. **Amended at
  implementation:** the Dart lease cannot do it — a remote Live Activity push
  bypasses the app entirely, so there is no interception point on iOS at all,
  and the two writers' timestamps come from two machines whose clocks are not
  the same. Android orders them on stops remaining instead, which only ever
  moves one way, and drops a reading less far along than the one on screen
  (`TrackNotification.post`). On iOS the ordering is APNs' own `timestamp`
  between pushes, and nothing between a push and a local update: pushing only
  when the data moves bounds that window to one station hop. A platform
  ceiling, not an unfinished seam.
- Bus and rail need a server-side session table before they can be pushed;
  `createArrivalReminder` is a one-shot trigger, not a session. Deferred.
- A device that blocks push keeps today's behavior exactly, on both platforms.
- The Android push arrives on a `com.google.android.c2dm.intent.RECEIVE`
  receiver rather than a `FirebaseMessagingService`: firebase_messaging already
  declares that service and only one may win, so taking it would break the Dart
  background handler the 下車提醒 vibration rides on. Receivers do not compete,
  and a broadcast starts a process the system has already killed.
- 取消追蹤 on a card whose process is gone is answered by `TrackCancelReceiver`
  (manifest-registered): it takes the card down, then posts the session id to
  `POST /api/track/cancel` so the session actually ends and its remaining buzzes
  do not fire (FDPL-65). That endpoint takes the track id and nothing else — a
  bare receiver can reach neither the install id (a Hive box) nor the install
  secret (EncryptedSharedPreferences), and has no gRPC stack — so the id, a
  server-minted UUIDv4 that only ever travelled to the owning device, *is* the
  credential. It grants exactly one minor act, ending your own reminder, and
  answers identically whether or not the session existed. While an engine is
  alive the receiver stands down (`LiveActivityPlugin.dartIsListening`) and the
  install-bound gRPC CancelTrack remains the path.
