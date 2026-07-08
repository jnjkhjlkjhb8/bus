import 'package:wheres_the_car/core/firebase/crash_reporter.dart';

/// Creates an arrival reminder on the server and returns its reminder id.
typedef CreateReminder =
    Future<String> Function({
      required String stopKey,
      required String direction,
      required DateTime expiresAt,
    });

/// Cancels a server-side arrival reminder by id.
typedef CancelReminder = Future<void> Function(String reminderId);

/// Mirrors an armed reminder to local persistence (bus keeps a local copy so
/// the bell survives restart; rail does not, and leaves this null).
typedef PersistArm =
    Future<void> Function(
      String stopKey,
      String reminderId,
      DateTime expiresAt,
    );

/// Removes the locally-mirrored reminder for [stopKey].
typedef PersistDisarm = Future<void> Function(String stopKey);

/// The optimistic arrival-reminder toggle choreography, shared by the bus
/// route and rail train blocs. It owns one state machine over a
/// `stopKey -> reminderId` map: toggle on writes a `'pending'` placeholder,
/// awaits the server create,
/// then swaps in the real id (rolling back on failure); toggle off removes the
/// entry, awaits the server cancel, and restores it on failure. A `'pending'`
/// entry guards against a double toggle mid-flight, and `'local:'` ids (issued
/// when Firebase is disabled) skip the server cancel.
///
/// The machine is Bloc-agnostic: the caller supplies the current map, an emit
/// adapter, and an `isDone` guard (the bus/rail `Emitter.isDone`) so a reminder
/// resolved after the handler closed does not emit into a dead emitter.
/// Persistence and telemetry are optional collaborators — bus wires both, rail
/// neither.
class ReminderToggle {
  const ReminderToggle({
    required this.createReminder,
    required this.cancelReminder,
    this.persistArm,
    this.persistDisarm,
    this.onToggled,
    this.reportError = CrashReporter.record,
  });

  final CreateReminder createReminder;
  final CancelReminder cancelReminder;
  final PersistArm? persistArm;
  final PersistDisarm? persistDisarm;

  /// Best-effort side effect (telemetry) after a successful arm/disarm.
  final void Function({required bool enabled})? onToggled;
  final void Function(Object error, StackTrace stack) reportError;

  /// Runs one toggle for [key].
  ///
  /// [readReminders] returns the current map (read fresh each time a new map is
  /// derived); [emit] pushes the next map into state; [isDone] reports whether
  /// the caller's emitter has closed. [direction] is the canonical `'0'`/`'1'`
  /// (or bus direction) passed to create. [armAt] is when the reminder fires
  /// (bus: now + TTL; rail: the stop's scheduled arrival); a null or past
  /// [armAt] makes an arm request a no-op, matching rail's already-departed
  /// guard.
  Future<void> run({
    required Map<String, String> Function() readReminders,
    required void Function(Map<String, String> next) emit,
    required bool Function() isDone,
    required String key,
    required String direction,
    required DateTime? armAt,
  }) async {
    final existing = readReminders()[key];
    if (existing != null) {
      await _disarm(key: key, existing: existing, emit: emit, isDone: isDone,
          readReminders: readReminders);
      return;
    }
    await _arm(
      key: key,
      direction: direction,
      armAt: armAt,
      emit: emit,
      isDone: isDone,
      readReminders: readReminders,
    );
  }

  Future<void> _disarm({
    required String key,
    required String existing,
    required Map<String, String> Function() readReminders,
    required void Function(Map<String, String>) emit,
    required bool Function() isDone,
  }) async {
    // A toggle mid-flight (server create not yet resolved) is ignored so the
    // placeholder isn't cancelled before it becomes a real id.
    if (existing == 'pending') return;
    // Optimistic off; restore on failure.
    emit(Map.of(readReminders())..remove(key));
    try {
      if (!existing.startsWith('local:')) {
        await cancelReminder(existing);
      }
      await persistDisarm?.call(key);
      onToggled?.call(enabled: false);
    } on Object catch (e, s) {
      reportError(e, s);
      if (isDone()) return;
      emit(Map.of(readReminders())..[key] = existing);
    }
  }

  Future<void> _arm({
    required String key,
    required String direction,
    required DateTime? armAt,
    required Map<String, String> Function() readReminders,
    required void Function(Map<String, String>) emit,
    required bool Function() isDone,
  }) async {
    // No usable arm time (unparseable / already departed) — nothing to arm.
    if (armAt == null || !armAt.isAfter(DateTime.now())) return;
    // Optimistic on with a placeholder id; replace it with the server id.
    emit(Map.of(readReminders())..[key] = 'pending');
    try {
      final reminderId = await createReminder(
        stopKey: key,
        direction: direction,
        expiresAt: armAt,
      );
      if (isDone()) return;
      emit(Map.of(readReminders())..[key] = reminderId);
      await persistArm?.call(key, reminderId, armAt);
      onToggled?.call(enabled: true);
    } on Object catch (e, s) {
      reportError(e, s);
      if (isDone()) return;
      emit(Map.of(readReminders())..remove(key));
    }
  }
}
