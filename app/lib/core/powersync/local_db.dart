/// Read seam over the synced local SQLite database.
///
/// Repositories depend on this narrow interface instead of `PowerSyncService`
/// directly, so their queries can run against an in-memory fake under
/// `flutter test` without initializing PowerSync. Only the read shape used by
/// repositories is exposed; writes stay owned by PowerSync's sync loop.
///
// A single-method interface is intentional: it must be implementable by both
// PowerSyncService and test fakes, which a function typedef cannot express.
// ignore: one_member_abstracts
abstract interface class LocalDb {
  /// Runs a read-only query and returns each row as a column-keyed map.
  Future<List<Map<String, dynamic>>> getAll(
    String sql, [
    List<Object?> parameters,
  ]);
}
