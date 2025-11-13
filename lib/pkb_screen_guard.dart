import 'dart:async';
import 'package:flutter/services.dart';

/// Dart wrapper สำหรับ pkb_screen_guard
class PkbScreenGuard {
  // ช่องคุยกับ native
  static const MethodChannel _method =
  MethodChannel('pkb_screen_guard/methods');

  // ช่องรับ event จาก native
  static const EventChannel _events =
  EventChannel('pkb_screen_guard/events');

  static Stream<Map<String, dynamic>>? _eventStream;

  /// Android: เปิด FLAG_SECURE (ห้าม screenshot + recent preview)
  /// iOS: ไม่มีผล (ignored)
  static Future<void> enableSecure() async {
    await _method.invokeMethod('enableSecure');
  }

  /// Android: ปิด FLAG_SECURE
  /// iOS: ไม่มีผล
  static Future<void> disableSecure() async {
    await _method.invokeMethod('disableSecure');
  }

  /// เริ่ม monitoring (Android + iOS)
  /// - Android: เริ่มตรวจ root / hook / remote app / external display ฯลฯ
  /// - iOS: เรา auto-start อยู่แล้ว แต่เรียกได้ซ้ำ
  static Future<void> startMonitoring() async {
    await _method.invokeMethod('startMonitoring');
  }

  /// หยุด monitoring
  static Future<void> stopMonitoring() async {
    await _method.invokeMethod('stopMonitoring');
  }

  /// แสดง overlay ปิดหน้าจอ (จอดำ + ข้อความเตือน)
  static Future<void> showOverlay() async {
    await _method.invokeMethod('showOverlay');
  }

  /// ซ่อน overlay
  static Future<void> hideOverlay() async {
    await _method.invokeMethod('hideOverlay');
  }

  /// ตรวจ rooted/jailbroken ครั้งเดียว
  /// - Android: heuristic root detection
  /// - iOS: heuristic jailbreak detection (simulator จะคืน false)
  static Future<bool> checkRooted() async {
    final res = await _method.invokeMethod<bool>('checkRooted');
    return res ?? false;
  }

  /// Stream ของ event จาก native
  ///
  /// event ที่เป็นไปได้ เช่น:
  /// - screenCaptured
  /// - screenCapturingStopped
  /// - externalDisplayAttached / externalDisplayDetached
  /// - rootDetected / rootCleared
  /// - hookDetected
  /// - remoteAppDetected (มี field package)
  static Stream<Map<String, dynamic>> events() {
    _eventStream ??= _events
        .receiveBroadcastStream()
        .map((dynamic e) => Map<String, dynamic>.from(e as Map));
    return _eventStream!;
  }
}
