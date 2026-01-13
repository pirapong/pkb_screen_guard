import 'dart:async';
import 'package:flutter/services.dart';

/// สถานะ overlay ปัจจุบัน
class PkbOverlayStatus {
  final bool hasOverlay;
  final bool touchObscured;

  const PkbOverlayStatus({
    required this.hasOverlay,
    required this.touchObscured,
  });

  @override
  String toString() =>
      'PkbOverlayStatus(hasOverlay: $hasOverlay, touchObscured: $touchObscured)';
}

/// สถานะ Accessibility Service (AAS)
class PkbAasStatus {
  final bool hasSuspiciousAas;
  final List<String> suspiciousPackages;

  const PkbAasStatus({
    required this.hasSuspiciousAas,
    required this.suspiciousPackages,
  });

  @override
  String toString() =>
      'PkbAasStatus(hasSuspiciousAas: $hasSuspiciousAas, suspiciousPackages: $suspiciousPackages)';
}

/// Dart wrapper สำหรับ pkb_screen_guard
class PkbScreenGuard {
  static const MethodChannel _method =
  MethodChannel('pkb_screen_guard/methods');

  static const EventChannel _events =
  EventChannel('pkb_screen_guard/events');

  static Stream<Map<String, dynamic>>? _eventStream;

  // ---------------------------------------------------------------------------
  // ฟีเจอร์เดิม (ไม่แตะ)
  // ---------------------------------------------------------------------------

  static Future<void> enableSecure() async {
    await _method.invokeMethod('enableSecure');
  }

  static Future<void> disableSecure() async {
    await _method.invokeMethod('disableSecure');
  }

  static Future<void> startMonitoring() async {
    await _method.invokeMethod('startMonitoring');
  }

  static Future<void> stopMonitoring() async {
    await _method.invokeMethod('stopMonitoring');
  }

  static Future<void> showOverlay() async {
    await _method.invokeMethod('showOverlay');
  }

  static Future<void> hideOverlay() async {
    await _method.invokeMethod('hideOverlay');
  }

  static Future<bool> checkRooted() async {
    final res = await _method.invokeMethod<bool>('checkRooted');
    return res ?? false;
  }

  static Stream<Map<String, dynamic>> events() {
    _eventStream ??= _events
        .receiveBroadcastStream()
        .map((dynamic e) => Map<String, dynamic>.from(e as Map));
    return _eventStream!;
  }

  static Future<void> enableSecurityGuard() async {
    await _method.invokeMethod('enableSecurityGuard');
  }

  static Future<PkbOverlayStatus> checkOverlayStatus() async {
    final result =
        await _method.invokeMethod<Map<dynamic, dynamic>>(
          'checkOverlayStatus',
        ) ??
            <dynamic, dynamic>{};

    return PkbOverlayStatus(
      hasOverlay: result['hasOverlay'] == true,
      touchObscured: result['touchObscured'] == true,
    );
  }

  static Future<PkbAasStatus> checkAccessibilityServices({
    required List<String> allowedInstallers,
    required List<String> allowedPackages,
  }) async {
    final result =
        await _method.invokeMethod<Map<dynamic, dynamic>>(
          'checkAccessibilityServices',
          {
            'allowedInstallers': allowedInstallers,
            'allowedPackages': allowedPackages,
          },
        ) ??
            <dynamic, dynamic>{};

    return PkbAasStatus(
      hasSuspiciousAas: result['hasSuspiciousAas'] == true,
      suspiciousPackages:
      (result['suspiciousPackages'] as List?)?.cast<String>() ?? const [],
    );
  }

  // ---------------------------------------------------------------------------
  // ✅ เพิ่มใหม่อย่างเดียว: เช็ค AnyDesk / Remote Active
  // ---------------------------------------------------------------------------

  /// ตรวจว่ามีความเป็นไปได้ว่ากำลัง Remote (เช่น AnyDesk)
  ///
  /// return ตัวอย่าง:
  /// {
  ///   remoteActive: true/false,
  ///   anydeskInstalled: true/false,
  ///   anydeskAasEnabled: true/false,
  ///   externalDisplay: true/false
  /// }
  static Future<Map<String, dynamic>> checkRemoteActive() async {
    final res = await _method.invokeMethod<Map<dynamic, dynamic>>(
      'checkRemoteActive',
    );

    return Map<String, dynamic>.from(res ?? {});
  }
}
