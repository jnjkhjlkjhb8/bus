/// File generated from the checked-in Firebase platform config.
// Regenerate with:
// `flutterfire configure --project=mybus-32985 --platforms=android,ios`.
// ignore_for_file: type=lint

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase options are not configured for web.');
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      TargetPlatform.macOS => throw UnsupportedError(
        'Firebase options are not configured for macOS.',
      ),
      TargetPlatform.windows => throw UnsupportedError(
        'Firebase options are not configured for Windows.',
      ),
      TargetPlatform.linux => throw UnsupportedError(
        'Firebase options are not configured for Linux.',
      ),
      TargetPlatform.fuchsia => throw UnsupportedError(
        'Firebase options are not configured for Fuchsia.',
      ),
    };
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCmGMEt6KuiaExuu9GXG4ucv3Qen0cxeTs',
    appId: '1:286997226441:android:5b40adc141814bf5253e18',
    messagingSenderId: '286997226441',
    projectId: 'mybus-32985',
    storageBucket: 'mybus-32985.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBLNIbc4k9MtX3UpUsaSD0VsEUFa7zCgmg',
    appId: '1:286997226441:ios:3845a240b9fb0eb8253e18',
    messagingSenderId: '286997226441',
    projectId: 'mybus-32985',
    storageBucket: 'mybus-32985.firebasestorage.app',
    iosBundleId: 'com.wheres.bus',
  );
}
