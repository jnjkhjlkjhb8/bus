import 'package:wheres_the_bus/l10n/app_i18n.dart';

/// The rider's own ticket type, chosen once in Settings and applied to every
/// fare the app quotes — bus, TRA and THSR alike.
///
/// The three operators encode 票種 differently (TRA packs it into a ticket-type
/// string, THSR into a numeric fare class, TDX bus into a FareClass enum), so
/// each axis is expressed here as an ordered list of candidates. The first
/// candidate the data actually carries wins; the list ends at the full fare so
/// a pair that never landed a concession price still quotes *something*. When
/// the match is not the requested type, the resolver reports the type it did
/// match so the UI can label the number honestly instead of passing a full fare
/// off as a concession one.
enum FareType {
  full('full'),
  student('student'),
  child('child'),
  concession('concession');

  const FareType(this.key);

  /// Value persisted through `SettingsRepository.fareType`.
  final String key;

  static FareType fromKey(String? key) =>
      values.firstWhere((e) => e.key == key, orElse: () => full);

  /// Display name — the option label in Settings and the heading every quoted
  /// fare is labelled with.
  String labelOf(AppI18n i18n) => switch (this) {
    FareType.full => i18n.fareFull,
    FareType.student => i18n.fareStudent,
    FareType.child => i18n.fareChild,
    FareType.concession => i18n.fareConcession,
  };

  /// TRA 票種 prefixes to try, in order. TDX packs 票種 and 車種 into one
  /// ticket-type string (成自 / 敬復 / 孩莒 …), so this is only the first
  /// character; `traFareFor` appends the train's class.
  ///
  /// TRA prices no student fare — students ride on 全票 — so [student] resolves
  /// straight to 成 rather than falling back through a type that never exists.
  List<String> get traPrefixes => switch (this) {
    FareType.full || FareType.student => const ['成'],
    FareType.child => const ['孩', '成'],
    FareType.concession => const ['敬', '愛', '成'],
  };

  /// THSR fare classes to try, in order: 1 全票, 9 半票. THSR charges 孩童,
  /// 敬老 and 愛心 the same 半票, so all three collapse to one class.
  List<int> get thsrFareClasses => switch (this) {
    FareType.full || FareType.student => const [1],
    FareType.child || FareType.concession => const [9, 1],
  };

  /// TDX bus FareClass codes to try, in order (see the enum in
  /// `fare_decoder.dart`). Concession walks 敬老 → 愛心 → 半票 because operators
  /// publish the same price under any of the three.
  List<int> get busFareClasses => switch (this) {
    FareType.full => const [1],
    FareType.student => const [2, 1],
    FareType.child => const [7, 10, 1],
    FareType.concession => const [3, 4, 10, 1],
  };

  /// The type to label a resolved fare with, given that it matched
  /// [isFullFare] (the last candidate in every chain).
  ///
  /// Only the full fare is a downgrade worth admitting to. Every other
  /// candidate — 敬老, 愛心 or the shared 半票 — is a genuine concession price,
  /// so it keeps the rider's own label rather than TDX's internal one.
  FareType matchedWhen({required bool isFullFare}) =>
      isFullFare ? FareType.full : this;
}

/// A fare resolved for a requested `FareType`.
///
/// `matched` is the type the price actually belongs to. When it differs from
/// what was asked for, the pair carries no fare for the rider's type and the UI
/// must show that type's label — quoting a full fare under a 敬老票 heading is
/// worse than admitting the concession price is unpublished.
typedef ResolvedFare = ({int price, FareType matched});
