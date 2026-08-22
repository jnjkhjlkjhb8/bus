class FirebaseGate {
  FirebaseGate._();

  static const appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );
  static const requested = bool.fromEnvironment('FIREBASE_ENABLED');
  static const bool enabled = requested && appEnv != 'dev';
  static const grpcTLS = bool.fromEnvironment('GRPC_TLS');

  /// The App Check debug token non-production flavors attest with. Pinning it
  /// in the flavor file is what keeps one registered token valid across
  /// reinstalls and machines: left empty, the debug provider mints a fresh
  /// token per install, which is unregistered in the console and therefore
  /// rejected — taking every Firebase_Service call (device registration, and
  /// with it every 追蹤 session) down with it.
  static const appCheckDebugToken = String.fromEnvironment(
    'APP_CHECK_DEBUG_TOKEN',
  );

  static void ensureSecureTransport({
    bool firebaseEnabled = enabled,
    bool tlsEnabled = grpcTLS,
  }) {
    if (firebaseEnabled && !tlsEnabled) {
      throw StateError('Firebase requires GRPC_TLS=true');
    }
  }
}
