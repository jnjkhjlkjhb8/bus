# Project Context

## Domain Language

| Term | Meaning |
|---|---|
| stop | A physical boarding point from source data, usually keyed by StationID or StationUID. |
| station | The user-facing place name around one or more nearby stops. |
| station group | The first-layer bus station entity shown in search and nearby flows; it can contain multiple stop IDs. |
| TDX subroute UID | The subroute identifier as emitted by TDX. City buses share one UID across both directions; InterCity (THB) encodes direction in a UID suffix, so one route variant arrives as two UIDs. |
| canonical subroute | The direction-merged subroute identity the app, Redis ETA keys, and environment schemas use. Derived from TDX subroute UIDs during load; TDX-native UIDs never leave the ingestion boundary. |
| ETA | Real-time arrival estimate streamed through Redis and gRPC. |
| arrival instant | The absolute wall-clock moment a vehicle is expected to arrive — the canonical bus ETA value. Remaining-seconds/minutes shown in UI are derived from it at render time; a cached arrival instant stays valid, a cached seconds-remaining decays. |
| static data | Route, stop, station, schedule, fare, and geometry data persisted in PostgreSQL and synced where useful. |
| live data | ETA and alert data that comes from TDX polling or MQTT and is cached or published through Redis. |
| raw landing | The verbatim TDX static payload written into the shared `raw_tdx` schema by `ROLE=ingestor`, partitioned by city/system/date. Fetched once; serves every environment. |
| load | Transforming raw-landing rows into one environment's schema (`public`, `staging`, or local test). Loads never call TDX. |
| live job | One realtime dataset's recipe — TDX live endpoints, transform, Redis key patterns, and cadence — run by the shared live runner in `services/functions`. The live counterpart of a load: the TDX source and Redis sink are adapters, so tests replay recorded fixtures instead of calling TDX. The runner owns the 304→TTL-refresh rule for every live job. |
| coming-soon highlight | A static visual state for the most imminent arrival; it is not a separate fake card or animation. |
| arrival feed | The deep live-arrival module in the app's data layer and the single live-stream seam over gRPC: `watch` (stream of arrival lists) hides reconnect, decay ticking, merge policy, and sorting; `passthrough` is the identity policy for lone non-arrival values (bike availability, alerts, delay maps) — resilience without arrival semantics. Bus stop, bus route, metro, and the TRA departure board use arrival policies; bike/alerts/delays use passthrough. |
| load sink | The write seam every load transform receives (`services/functions/load_sink.go`). `copyUpsert` owns the temp-table COPY→upsert skeleton; six semantic operations own bus operators, bus city assembly, bus daily timetable, MRT journey matrix, MRT travel time, and THSR stations. The production adapter privately owns PostgreSQL and Redis; tests use an in-memory fake without raw-client access. |
| dataset registry | The single ordered table of raw_tdx dataset recipes (`services/functions/dataset.go`) from which the ingestor fetch loop, the raw-landing whitelist/target map, and the loader registry all derive. Intentional asymmetries are explicit fields (`landOnly`, `foldedInto`, `loadParts`), and load order (bus_operator before bus) is structural. |
| nearby discovery | The router module that queries station groups, bike, metro, TRA, and THSR concurrently within a radius, enriches results with walking metrics, preserves partial database success, and falls back to geodesic estimates when routing is unavailable. Station-group responses are keyed by `group_uid`. |
| reminder toggle | The shared optimistic arrival-reminder state machine (`lib/data/reminders/reminder_toggle.dart`): pending guard, optimistic on/off, placeholder-id swap, rollback on failure. Bus and rail blocs wire it with their own create/cancel, persistence, and telemetry collaborators. |
| 追蹤 (arrival tracking) | A standalone, self-ending countdown to one target stop for an approaching vehicle, surfaced in-app and on the iOS Live Activity / Android Live Update. Ends when the vehicle passes the target. Distinct from 到站提醒: 追蹤 is the live countdown *surface*; 到站提醒 is the one-shot *alert*. A 追蹤 session carries an optional 指定車輛 binding. |
| 目標站 (target stop) | The single stop a 追蹤 session counts down to. When 追蹤 is started from a stop it is that stop (the next bus is followed); when started from a vehicle it is the rider's alight stop (下車站). One field regardless of entry point — the board/alight distinction is user intent, not a separate concept. |
| 指定車輛 (pinned vehicle) | An optional binding on a 追蹤 session that narrows the ETA source from "next bus to the 目標站" to one specific plate. Unpinned 追蹤 follows whichever bus is next; pinned 追蹤 follows one vehicle and ends when that plate passes the 目標站. The pinned card is also the surface a MaaS navigation *riding* leg renders — a boarded bus heading to its alight 目標站 is a pinned 追蹤 — so standalone vehicle tracking and riding share one card. Only the pre-board (waiting) card stays MaaS-specific. |
| 提前站數 (reminder lead) | The stops-based lead of a 到站提醒 on a 指定車輛 追蹤: the alert fires when that plate is that many stops before the 目標站. Defined **only** when a vehicle is pinned — stops-remaining is deterministic for one plate. Unpinned 站點 ETA reminders keep the existing time-based (分鐘) lead; the two lead units never mix. |
| 站點 ETA (stop board) | The live, persisting board for one stop: every route calling at that stop with its ETA to that stop, soonest first. Surfaced in-app (the 站牌 screen) and as a Live Activity / Android Live Update. Unlike 追蹤 it has no single 目標站 and does not self-end — it is a watch-a-stop glance. Any row can arm a 到站提醒. |
| arrival display | The small contract the shared arrival tile renders (label, status, highlight rank). Each mode maps its own domain model to it; the tile owns the rendering invariants (mono time values, static coming-soon highlight). |
| rail timetable query | One user-selected TRA or THSR origin-destination-date lookup. The module resolves missing station IDs, selects the rail adapter, loads the timetable, and attaches TRA delay updates from one caller intent with no event-order requirement. |
| MaaS navigation | The lifecycle of a selected MaaS plan through start, section advancement, arrival, or cancellation. Plan navigation and the transit-only journey session advance independently while the coordinator owns their start/end and PiP synchronization; the UI owns camera and snackbar rendering. |
| walk path | The OSRM foot route resolved at plan time for every walk section (first mile, transfer, last mile): real duration, street geometry, and walk steps from one `/route` call. A pure enhancement — on any OSRM failure the section keeps the TDX duration, straight-line rendering, and no steps; the plan never fails, and there is no retry (the 90 s plan cache paces re-attempts). |
| walk step | One turn-by-turn instruction inside a walk path: a server-composed Chinese sentence plus the raw OSRM maneuver type/modifier (for iconography) and the maneuver location. Step advancement during navigation is display-only; leg advancement stays owned by the arrival-radius rule. |
| plan preview | The Go planner phase between plan results and MaaS navigation: one selected plan shown as a full itinerary on the same map-and-sheet screen. Selecting a plan (from a card or a map line) always enters preview; MaaS navigation can only start from preview, never directly from a result. The fastest plan is the default selection. |
| plan entry | The first Go planner phase, before plan results: a full-page, map-less surface (no `GoogleMap` mounted) with the origin/destination fields and a shortcut list (current location, saved places, recent places, then the 路線箱 saved-routes section as a footer). The planner is always entered here — `/go` is opened with no destination — so this is the primary planner surface, not an edge case. Choosing a destination leaves plan entry for plan results; opening a saved route jumps straight to that plan. |
| place search | The pushed full page (not a bottom sheet) that a plan-entry field opens for typing. Hosts one shared body — current location, saved places, recent places, then autocomplete-on-type — reused by the field-edit path on the map/results view. Returns a `PlannedPlace` to the field that opened it. |
| saved place | A user-pinned planner location with an arbitrary label and icon, stored by `SavedPlaceRepository` (a `PlannedPlace` whose `name` is the label, plus an `iconKey`). Saved by swiping a search result/recent right into the name-and-icon dialog. Distinct from a saved route (a whole plan) and a recent place (auto-remembered, transient). |
| recent place | An auto-remembered planner destination, capped and transient, stored by `PlaceRecentRepository`. Only user-picked places are kept (never the current-location pseudo-place). Distinct from a saved place. |
| saved route | A whole A→B plan pinned in 路線箱 (`state.savedRoutes`); a saved *plan*, not a location. Distinct from a saved place. |

## Module Map

| Area | Location |
|---|---|
| Flutter app entry | `app/lib/main.dart` |
| Flutter routing shell | `app/lib/app/router/app_router.dart`, `app/lib/shared/widgets/main_scaffold.dart` |
| Flutter repositories | `app/lib/data/repositories/` |
| gRPC source of truth | `models/*.proto` |
| Router binary | `services/router/` |
| Ingestion binary | `services/functions/` |
| Redis key conventions | `docs/redis.md` |
| PostgreSQL schema | `docs/storage.md` |
| Deployment | `docker-compose.yaml`, `docs/architecture.md` |

## Operating Rules

- Generated protobuf files are not edited by hand.
- Bus station search and nearby first-layer UI use station-group semantics.
- Live ETA matching must preserve the backend key contract; do not patch only the UI when backend identifiers are wrong.
- Firebase is auxiliary infrastructure; Go, PostgreSQL, Redis, and PowerSync remain the data plane.
- Generated proto types never leave `app/lib/data/`; features consume validated domain types from repositories.
- ETA display rounds seconds up to minutes (ceil) in every transit mode — never round or floor.
- A TDX 304 Not-Modified means the cached live data is still valid: refresh its Redis TTL instead of letting it expire.
