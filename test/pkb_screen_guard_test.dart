// import 'package:flutter_test/flutter_test.dart';
// import 'package:pkbscreenguard/pkbscreenguard.dart';
// import 'package:pkbscreenguard/pkb_screen_guard_platform_interface.dart';
// import 'package:pkbscreenguard/pkb_screen_guard_method_channel.dart';
// import 'package:plugin_platform_interface/plugin_platform_interface.dart';
//
// class MockPkbScreenGuardPlatform
//     with MockPlatformInterfaceMixin
//     implements PkbScreenGuardPlatform {
//
//   @override
//   Future<String?> getPlatformVersion() => Future.value('42');
// }
//
// void main() {
//   final PkbScreenGuardPlatform initialPlatform = PkbScreenGuardPlatform.instance;
//
//   test('$MethodChannelPkbScreenGuard is the default instance', () {
//     expect(initialPlatform, isInstanceOf<MethodChannelPkbScreenGuard>());
//   });
//
//   test('getPlatformVersion', () async {
//     PkbScreenGuard pkbScreenGuardPlugin = PkbScreenGuard();
//     MockPkbScreenGuardPlatform fakePlatform = MockPkbScreenGuardPlatform();
//     PkbScreenGuardPlatform.instance = fakePlatform;
//
//     expect(await pkbScreenGuardPlugin.getPlatformVersion(), '42');
//   });
// }
