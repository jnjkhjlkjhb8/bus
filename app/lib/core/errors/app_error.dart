import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:grpc/grpc.dart';

sealed class AppError {
  const AppError();

  factory AppError.from(Object e) {
    if (e is AppError) return e;
    if (e is SocketException) return const OfflineError();
    if (e is TimeoutException) return const TimeoutError();
    if (e is GrpcError) {
      return switch (e.code) {
        StatusCode.unavailable => const OfflineError(),
        StatusCode.deadlineExceeded => const TimeoutError(),
        StatusCode.notFound => const NotFoundError(),
        _ => ServerError(e.code),
      };
    }
    return const UnknownError();
  }

  String get title;
  String get hint;
  IconData get icon;
}

class OfflineError extends AppError {
  const OfflineError();

  @override
  String get title => '目前無法取得即時資訊';

  @override
  String get hint => '已離線,連上網路後可重新整理';

  @override
  IconData get icon => Icons.cloud_off_rounded;
}

class TimeoutError extends AppError {
  const TimeoutError();

  @override
  String get title => '連線逾時';

  @override
  String get hint => '網路回應太慢,請稍後再試';

  @override
  IconData get icon => Icons.hourglass_empty_rounded;
}

class NotFoundError extends AppError {
  const NotFoundError();

  @override
  String get title => '查無資料';

  @override
  String get hint => '目前沒有可顯示的內容';

  @override
  IconData get icon => Icons.search_off_rounded;
}

class ServerError extends AppError {
  const ServerError(this.code);

  final int code;

  @override
  String get title => '服務暫時無法使用';

  @override
  String get hint => '我們正在處理,請稍後再試';

  @override
  IconData get icon => Icons.error_outline_rounded;
}

class UnknownError extends AppError {
  const UnknownError();

  @override
  String get title => '發生未預期的錯誤';

  @override
  String get hint => '請稍後再試';

  @override
  IconData get icon => Icons.error_outline_rounded;
}
