import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:wheres_the_bus/core/storage/hive_store.dart';

class InstallIdentity {
  InstallIdentity._();

  static const _key = 'install_id';
  static const _secretKey = 'install_secret';
  static const _secureSecretKey = 'firebase_install_secret';

  static Future<String> getOrCreate({Box<dynamic>? settings}) async {
    final box = settings ?? HiveStore.settings;
    final existing = box.get(_key) as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final value = const Uuid().v4();
    await box.put(_key, value);
    return value;
  }

  static Future<String> getOrCreateSecret({
    Box<dynamic>? settings,
    Future<String?> Function(String key)? secureRead,
    Future<void> Function(String key, String value)? secureWrite,
  }) async {
    final box = settings ?? HiveStore.settings;
    const storage = FlutterSecureStorage();
    final read = secureRead ?? (key) => storage.read(key: key);
    final write =
        secureWrite ?? (key, value) => storage.write(key: key, value: value);
    final secured = await read(_secureSecretKey);
    if (secured != null && secured.isNotEmpty) {
      if (box.containsKey(_secretKey)) await box.delete(_secretKey);
      return secured;
    }
    final legacy = box.get(_secretKey) as String?;
    if (legacy != null && legacy.isNotEmpty) {
      await write(_secureSecretKey, legacy);
      await box.delete(_secretKey);
      return legacy;
    }
    final random = Random.secure();
    final value = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    await write(_secureSecretKey, value);
    return value;
  }
}
