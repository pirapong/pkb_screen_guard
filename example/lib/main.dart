import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pkb_screen_guard/pkb_screen_guard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pkb_screen_guard Example',
      theme: ThemeData(useMaterial3: true),
      home: const GuardHomePage(),
    );
  }
}

class GuardHomePage extends StatefulWidget {
  const GuardHomePage({super.key});

  @override
  State<GuardHomePage> createState() => _GuardHomePageState();
}

class _GuardHomePageState extends State<GuardHomePage> {
  bool? _rooted;
  PkbOverlayStatus? _overlayStatus;
  PkbAasStatus? _aasStatus;

  // ✅ เพิ่มตัวแปรสำหรับ AnyDesk Remote
  Map<String, dynamic>? _remoteStatus;

  final List<Map<String, dynamic>> _events = [];
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _initGuard();
  }

  Future<void> _initGuard() async {
    /// 1) ตรวจ Root/JB
    final rooted = await PkbScreenGuard.checkRooted();
    setState(() => _rooted = rooted);

    /// 2) รับ Event จาก Native
    _sub ??= PkbScreenGuard.events().listen((event) async {
      setState(() {
        _events.insert(0, {
          'ts': DateTime.now().toIso8601String(),
          ...event,
        });
      });

      // 🔴 ถ้าตรวจพบ Remote จาก Native
      if (event['event'] == 'remoteAppDetected') {
        // 1) บังจอ
        await PkbScreenGuard.showOverlay();

        // 2) แจ้งเตือน (ถ้าต้องการ)
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: const Text('แจ้งเตือนความปลอดภัย'),
              content: const Text(
                'ตรวจพบการควบคุมหน้าจอจากภายนอก\n'
                    'ไม่อนุญาตให้ใช้งานแอปในขณะนี้',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // 3) ปิดแอป
                    Navigator.of(context).pop();
                  },
                  child: const Text('ตกลง'),
                ),
              ],
            ),
          );
        }

        // 4) ปิดแอป (แนวธนาคาร)
        // SystemNavigator.pop();
      }
    });

    /// 3) เปิด FLAG_SECURE
    await PkbScreenGuard.enableSecure();

    /// 4) เปิดโหมด Security Guard (ป้องกัน Overlay)
    await PkbScreenGuard.enableSecurityGuard();

    /// 5) เริ่ม Monitoring
    await PkbScreenGuard.startMonitoring();

    /// 6) อ่านสถานะ Overlay
    _checkOverlay();

    /// 7) ตรวจ Accessibility Services
    _checkAas();
  }

  Future<void> _checkOverlay() async {
    final status = await PkbScreenGuard.checkOverlayStatus();
    setState(() => _overlayStatus = status);
  }

  Future<void> _checkAas() async {
    final aas = await PkbScreenGuard.checkAccessibilityServices(
      allowedInstallers: [
        'com.android.vending', // Google Play
        'com.android.packageinstaller', // System
      ],
      allowedPackages: [],
    );
    setState(() => _aasStatus = aas);
  }

  // ✅ ฟังก์ชันเช็ค AnyDesk Remote
  Future<void> _checkAnyDeskRemote() async {
    final res = await PkbScreenGuard.checkRemoteActive();
    setState(() => _remoteStatus = res);

    if (res['remoteActive'] == true) {
      await PkbScreenGuard.showOverlay();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------------------
  // UI
  // ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final rootedText = _rooted == null
        ? 'กำลังตรวจสอบ...'
        : (_rooted == true
        ? '⚠ ตรวจพบ Root/Jailbreak'
        : '✔ ไม่พบ Root/Jailbreak');

    final overlayText = _overlayStatus == null
        ? 'กำลังตรวจสอบ...'
        : '''
Draw Over Apps: ${_overlayStatus!.hasOverlay ? "⚠ เปิดอยู่" : "✔ ปิดอยู่"}
Touch Obscured: ${_overlayStatus!.touchObscured ? "⚠ พบการซ้อนทับ" : "✔ ไม่มี"}
''';

    final aasText = _aasStatus == null
        ? 'กำลังตรวจสอบ...'
        : '''
Suspicious AAS: ${_aasStatus!.hasSuspiciousAas ? "⚠ พบ" : "✔ ไม่พบ"}
Packages: ${_aasStatus!.suspiciousPackages.join(", ")}
''';

    return Scaffold(
      appBar: AppBar(
        title: const Text('pkb_screen_guard Example'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "🔐 อุปกรณ์ & ความปลอดภัย",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          // ROOT/JAILBREAK
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text("สถานะ Root / Jailbreak"),
            subtitle: Text(rootedText),
          ),

          const SizedBox(height: 10),

          // OVERLAY STATUS
          ListTile(
            leading: const Icon(Icons.layers),
            title: const Text("สถานะ Overlay Attack"),
            subtitle: Text(overlayText),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _checkOverlay,
            ),
          ),

          const SizedBox(height: 10),

          // AAS STATUS
          ListTile(
            leading: const Icon(Icons.accessibility),
            title: const Text("Accessibility Service ตรวจพบ"),
            subtitle: Text(aasText),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _checkAas,
            ),
          ),

          const Divider(height: 32),

          const Text(
            "🧪 การทดสอบอื่น ๆ",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          ElevatedButton(
            onPressed: () => PkbScreenGuard.showOverlay(),
            child: const Text("Show Black Overlay"),
          ),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.hideOverlay(),
            child: const Text("Hide Black Overlay"),
          ),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.enableSecure(),
            child: const Text("Enable FLAG_SECURE"),
          ),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.disableSecure(),
            child: const Text("Disable FLAG_SECURE"),
          ),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.startMonitoring(),
            child: const Text("Start Monitoring"),
          ),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.stopMonitoring(),
            child: const Text("Stop Monitoring"),
          ),

          const SizedBox(height: 12),

          // ✅ ปุ่มเช็ค AnyDesk
          ElevatedButton(
            onPressed: _checkAnyDeskRemote,
            child: const Text("Check AnyDesk Remote"),
          ),

          if (_remoteStatus != null)
            Card(
              child: ListTile(
                leading: Icon(
                  _remoteStatus!['remoteActive'] == true
                      ? Icons.warning
                      : Icons.check_circle,
                  color: _remoteStatus!['remoteActive'] == true
                      ? Colors.red
                      : Colors.green,
                ),
                title: Text(
                  _remoteStatus!['remoteActive'] == true
                      ? "⚠ ตรวจพบความเป็นไปได้ว่ากำลัง Remote (AnyDesk)"
                      : "✔ ไม่พบการ Remote",
                ),
                subtitle: Text(_remoteStatus.toString()),
              ),
            ),

          const SizedBox(height: 20),
          const Divider(),

          const Text(
            "📡 Events ล่าสุด",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          if (_events.isEmpty)
            const Text(
              "ยังไม่มี event (ลองอัดหน้าจอ / แชร์หน้าจอ / external display)",
            )
          else
            ..._events.take(30).map(_buildEventTile),
        ],
      ),
    );
  }

  Widget _buildEventTile(Map<String, dynamic> e) {
    final ev = e['event'];
    final ts = e['ts'];
    final pkg = e['package'];
    final score = e['score'];

    return Card(
      child: ListTile(
        title: Text('$ev'),
        subtitle: Text(
          "time: $ts"
              "${pkg != null ? "\npackage: $pkg" : ""}"
              "${score != null ? "\nscore: $score" : ""}",
        ),
      ),
    );
  }
}

