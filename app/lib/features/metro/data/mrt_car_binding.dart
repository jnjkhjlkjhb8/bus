/// Derives the GetTrainInfo carID the backend binds a metro 追蹤 session by,
/// from the congestion feed's CN1 carriage pair (ADR-0015): position digit `1`
/// prepended to the first half of the `/`-split pair, **leading zeros
/// preserved** (`021/022` → `1021`). Every valid carID of a train returns the
/// same trip reading, so this one derived value suffices.
///
/// Returns the empty string when [cn1] has no usable first half, which the
/// setup sheet reads as "fall back to manual car-number entry".
String deriveCarIdFromCn1(String cn1) {
  final first = cn1.split('/').first.trim();
  if (first.isEmpty) return '';
  return '1$first';
}
